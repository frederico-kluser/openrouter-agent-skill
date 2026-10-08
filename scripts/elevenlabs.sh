#!/usr/bin/env bash
# ============================================================================
# elevenlabs.sh — ElevenLabs via OpenRouter, TUDO em terminal
#
# Sistema de CREDENCIAIS + áudio:
#   check    Verifica na "memória" (stores de credenciais) se temos o login
#            de cada conta (OpenRouter / ElevenLabs) e como puxar os dados.
#   setup    Configuração GUIADA: pede as chaves (input oculto), valida o
#            formato, testa o login real e SALVA as variáveis de ambiente
#            em ~/.secrets (chmod 600) + export via ~/.zshenv (idempotente).
#   account  PUXA os dados das contas (plano, créditos, uso, vozes) no terminal.
#   models   Tabela de modelos TTS/STT da ElevenLabs.
#   tts      Sintetiza texto → arquivo de áudio (mp3/pcm) com validação de
#            Content-Type + X-Generation-Id (evita corrupção binária).
#   stt      Transcreve arquivo local (Scribe v2) com diarização/opções.
#   voices   Lista as vozes nativas da conta ElevenLabs (inclui clones).
#
# Autenticação: chaves EXCLUSIVAMENTE de variáveis de ambiente (nunca em
# argumento, nunca hardcoded). Ver `check` para a cadeia de busca completa.
#
# Dependências: curl + (jq ou python3).
# Fonte factual: references/audio-elevenlabs.md.
# ============================================================================
set -euo pipefail

OR_API_BASE="https://openrouter.ai/api/v1"
EL_API_BASE="https://api.elevenlabs.io/v1"

FLAG_JSON=0
FLAG_LIVE=0
FLAG_DRY=0

# ---------------------------------------------------------------------------
# Utilidades
# ---------------------------------------------------------------------------
warn() { printf 'Aviso: %s\n' "$*" >&2; }
die()  { printf 'Erro: %s\n' "$*" >&2; exit 1; }
ok()   { printf '✓ %s\n' "$*"; }
info() { printf '· %s\n' "$*"; }

have_jq() { command -v jq >/dev/null 2>&1; }
have_py() { command -v python3 >/dev/null 2>&1; }

need_curl() { command -v curl >/dev/null 2>&1 || die "curl é obrigatório."; }

jsonfmt() {
  if have_jq; then jq . "${1:-/dev/stdin}" 2>/dev/null || cat "${1:-/dev/stdin}"
  elif have_py; then python3 -m json.tool "${1:-/dev/stdin}" 2>/dev/null || cat "${1:-/dev/stdin}"
  else cat "${1:-/dev/stdin}"; fi
}

# Mascara um segredo: mostra prefixo + últimos 4 caracteres.
mask() {
  local v="${1:-}"
  if [[ ${#v} -le 8 ]]; then printf '********'; else printf '%s…%s' "${v:0:6}" "${v: -4}"; fi
}

val() {
  [[ $# -ge 2 ]] || die "$1: valor ausente (veja --help)."
  printf '%s' "$2"
}

# ---------------------------------------------------------------------------
# "Memória" de credenciais — cadeia de busca (primeiro hit vence)
#   1. variável do processo atual
#   2. ./.env do projeto
#   3. ~/.secrets            (fonte canônica desta máquina, chmod 600)
#   4. ~/.zshenv             (export em todo shell zsh)
#   5. ~/.dsh/.credentials.yaml (refs: do credential store DSH, hot reload)
# ---------------------------------------------------------------------------
GLOB_SRC=""   # fonte do último lookup_var
GLOB_VAL=""   # valor do último lookup_var

_lookup_file() {
  # $1=arquivo $2=VAR $3=nome-da-fonte
  local file="$1" var="$2" src="$3" line value
  [[ -f "$file" && -r "$file" ]] || return 1
  line="$(grep -E "^[[:space:]]*(export[[:space:]]+)?${var}=" "$file" 2>/dev/null | tail -n1 || true)"
  [[ -n "$line" ]] || return 1
  value="${line#*=}"
  value="${value%\"}"; value="${value#\"}"
  value="${value%\'}"; value="${value#\'}"
  GLOB_SRC="$src"; GLOB_VAL="$value"
  return 0
}

_lookup_env() {
  local var="$1" value=""
  value="$(printenv "$var" 2>/dev/null || true)"
  [[ -n "$value" ]] || return 1
  GLOB_SRC="ambiente (processo atual)"; GLOB_VAL="$value"
  return 0
}

_lookup_dsh() {
  local var="$1" file="$HOME/.dsh/.credentials.yaml" line value
  [[ -f "$file" && -r "$file" ]] || return 1
  line="$(grep -E "^[[:space:]]+${var}:" "$file" 2>/dev/null | head -n1 || true)"
  [[ -n "$line" ]] || return 1
  value="$(printf '%s' "$line" | sed -E 's/^[^:]+:[[:space:]]*//; s/[[:space:]]*$//; s/^["'\'']//; s/["'\'']$//')"
  [[ -n "$value" ]] || return 1
  GLOB_SRC="~/.dsh/.credentials.yaml (refs)"; GLOB_VAL="$value"
  return 0
}

# Procura VAR na cadeia inteira. Retorna 0 se achou (GLOB_SRC/GLOB_VAL preenchidos).
lookup_var() {
  local var="$1"
  _lookup_env "$var" && return 0
  _lookup_file "./.env" "$var" "./.env do projeto" && return 0
  _lookup_file "$HOME/.secrets" "$var" "~/.secrets" && return 0
  _lookup_file "$HOME/.zshenv" "$var" "~/.zshenv" && return 0
  _lookup_dsh "$var" && return 0
  return 1
}

# Comando para "puxar" a variável a partir da fonte encontrada.
pull_cmd_for() {
  case "$1" in
    "~/.secrets") printf 'source ~/.secrets' ;;
    "~/.zshenv")  printf 'source ~/.zshenv' ;;
    "./.env do projeto") printf 'set -a; source ./.env; set +a' ;;
    "~/.dsh/.credentials.yaml (refs)") printf "export VAR=\$(grep -A1 '  ${2}:' ~/.dsh/.credentials.yaml | awk '{print \$2}')" ;;
    *) printf 'já disponível neste shell' ;;
  esac
}

# Varredura da memória CoALA do projeto (.agents/*/memory/coala.sqlite)
coala_scan() {
  local kw="$1" found=0 f
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    if have_py; then
      local n
      n="$(python3 - "$f" "$kw" <<'PY' 2>/dev/null || echo 0
import sqlite3, sys
path, kw = sys.argv[1], sys.argv[2].lower()
try:
    con = sqlite3.connect(f"file:{path}?mode=ro", uri=True)
    cur = con.cursor()
    hits = 0
    for (t,) in cur.execute("SELECT name FROM sqlite_master WHERE type='table'").fetchall():
        try:
            for row in cur.execute(f'SELECT * FROM "{t}" LIMIT 500').fetchall():
                blob = " ".join(str(c).lower() for c in row if c is not None)
                if kw in blob:
                    hits += 1
        except Exception:
            pass
    print(hits)
except Exception:
    print(0)
PY
)"
      if [[ "${n:-0}" -gt 0 ]]; then
        info "memória CoALA: $n registo(s) mencionando '$kw' em $f"
        found=1
      fi
    fi
  done < <(find . -maxdepth 5 -path '*/.agents/*/memory/coala.sqlite' -type f 2>/dev/null | sort)
  return 0
}

# ---------------------------------------------------------------------------
# Comando: check — verificar em memória se temos o login de cada conta
# ---------------------------------------------------------------------------
cmd_check() {
  local var label status
  local -a rows=()
  for spec in \
    "OPENROUTER_API_KEY|conta OpenRouter (roteador/agregador)" \
    "ELEVENLABS_API_KEY|conta ElevenLabs (clonagem/BYOK; alias ELEVENLABS_NATIVE_API_KEY)" \
  ; do
    var="${spec%%|*}"; label="${spec#*|}"
    if lookup_var "$var"; then
      status="PRESENTE"
    elif [[ "$var" == "ELEVENLABS_API_KEY" ]] && lookup_var "ELEVENLABS_NATIVE_API_KEY"; then
      var="ELEVENLABS_NATIVE_API_KEY"; status="PRESENTE (alias)"
    else
      status="AUSENTE"; GLOB_SRC="—"; GLOB_VAL=""
    fi
    rows+=("$var|$label|$status|$GLOB_SRC|$GLOB_VAL")
  done

  if [[ $FLAG_JSON -eq 1 ]]; then
    printf '['
    local first=1 r p
    for r in "${rows[@]}"; do
      IFS='|' read -r var label status src value <<<"$r"
      [[ $first -eq 1 ]] || printf ','
      first=0
      printf '{"var":"%s","label":"%s","status":"%s","source":"%s","masked":"%s"}' \
        "$var" "$label" "$status" "$src" "$(mask "$value")"
    done
    printf ']\n'
  else
    printf '── Credenciais em memória (cadeia: ambiente → ./.env → ~/.secrets → ~/.zshenv → ~/.dsh/.credentials.yaml) ──\n'
    printf '%-24s %-16s %-38s %-12s %s\n' "VAR" "STATUS" "FONTE" "VALOR" "COMO PUXAR"
    local r
    for r in "${rows[@]}"; do
      IFS='|' read -r var label status src value <<<"$r"
      local pull="scripts/elevenlabs.sh setup"
      [[ "$status" == AUSENTE* ]] || pull="$(pull_cmd_for "$src" "$var")"
      printf '%-24s %-16s %-38s %-12s %s\n' "$var" "$status" "$src" "$( [[ "$status" == AUSENTE* ]] && echo '—' || mask "$value" )" "$pull"
    done
    printf '\n'
    for r in "${rows[@]}"; do
      IFS='|' read -r var label status src value <<<"$r"
      info "$var — $label"
    done
  fi

  # Memória CoALA: registos de conta/login guardados pelo projeto
  coala_scan "elevenlabs"
  coala_scan "openrouter"

  if [[ $FLAG_LIVE -eq 1 ]]; then
    printf '\n── Validação de login ao vivo ──\n'
    cmd_account
    return 0
  fi

  # Diagnóstico de completude (só texto)
  if [[ $FLAG_JSON -eq 0 ]]; then
    local missing=0
    for r in "${rows[@]}"; do
      IFS='|' read -r var label status src value <<<"$r"
      [[ "$status" == AUSENTE* ]] && missing=1
    done
    if [[ $missing -eq 1 ]]; then
      printf '\nFalta(m) credencial(is). Faça o setup guiado (salva as variáveis de ambiente):\n  scripts/elevenlabs.sh setup\n'
    else
      printf '\nTodas as credenciais estão em memória. Puxe os dados da conta com:\n  scripts/elevenlabs.sh account\n'
    fi
  fi
}

# ---------------------------------------------------------------------------
# Comando: setup — configuração guiada que SALVA as variáveis de ambiente
# ---------------------------------------------------------------------------
save_secret() {
  # Grava/atualiza VAR em ~/.secrets (idempotente, chmod 600) e garante o
  # export via ~/.zshenv (linha de sourcing do ~/.secrets).
  local var="$1" value="$2" secrets="$HOME/.secrets" zshenv="$HOME/.zshenv"
  touch "$secrets"; chmod 600 "$secrets"
  if grep -qE "^[[:space:]]*(export[[:space:]]+)?${var}=" "$secrets" 2>/dev/null; then
    # substitui a linha existente preservando o resto do ficheiro
    local tmp
    tmp="$(mktemp "${TMPDIR:-/dev/shm}/secrets.XXXXXX")"
    awk -v var="$var" -v val="$value" '
      BEGIN { done=0 }
      { if ($0 ~ "^[[:space:]]*(export[[:space:]]+)?" var "=") {
          if (!done) { print "export " var "=\x27" val "\x27"; done=1 }
        } else print }
      END { if (!done) print "export " var "=\x27" val "\x27" }
    ' "$secrets" > "$tmp"
    cat "$tmp" > "$secrets"; rm -f "$tmp"
  else
    {
      printf '\n# ── %s (openrouter-agent-skill · %s) ──\n' "$var" "$(date +%F)"
      printf "export %s='%s'\n" "$var" "$value"
    } >> "$secrets"
  fi
  chmod 600 "$secrets"

  if [[ -f "$zshenv" ]] && grep -vE '^[[:space:]]*#' "$zshenv" | grep -qE '(^|[;&|[:space:]])(\.|source)[[:space:]]+[^;]*\.secrets'; then
    : # já sourceia ~/.secrets — nada a fazer
  elif [[ -f "$zshenv" ]]; then
    {
      printf '\n# openrouter-agent-skill: exportar segredos salvos em ~/.secrets\n'
      printf '[ -f ~/.secrets ] && . ~/.secrets\n'
    } >> "$zshenv"
    info "Adicionado sourcing de ~/.secrets em ~/.zshenv"
  fi
}

prompt_key() {
  # $1=VAR $2=descrição $3=obrigatória?(1/0) $4=formato-de-exemplo
  # ATENÇÃO: chamado em $( ) — só o VALOR vai para stdout; mensagens vão para stderr.
  local var="$1" desc="$2" req="${3:-1}" hint="${4:-}" cur value
  if lookup_var "$var"; then cur="$GLOB_VAL"; else cur=""; fi
  printf '\n── %s ──\n' "$var" >&2
  info "$desc" >&2
  [[ -n "$hint" ]] && info "formato esperado: $hint" >&2
  if [[ -n "$cur" ]]; then
    info "já está em memória ($(mask "$cur")) via $GLOB_SRC" >&2
    printf 'Enter mantém o valor atual, ou digite um novo: ' >&2
  else
    printf 'Cole a chave (entrada oculta): ' >&2
  fi
  read -r -s value; printf '\n' >&2
  if [[ -z "$value" ]]; then
    if [[ -n "$cur" ]]; then
      ok "$var mantido ($(mask "$cur"))" >&2
      printf '%s' "$cur"; return 0
    elif [[ "$req" == "1" ]]; then
      die "$var é obrigatório para esta operação. Crie a chave e rode o setup de novo."
    else
      info "$var ignorado (opcional)" >&2; printf ''; return 0
    fi
  fi
  # validações de formato
  case "$var" in
    OPENROUTER_API_KEY)
      [[ "$value" == sk-or-v1-* ]] || warn "chave não parece do OpenRouter (esperado sk-or-v1-...); seguindo assim mesmo" ;;
    ELEVENLABS_API_KEY)
      [[ "$value" =~ ^[A-Za-z0-9_-]{16,}$ ]] || warn "chave ElevenLabs fora do formato usual (32 chars alfanuméricos)" ;;
  esac
  printf '%s' "$value"
}

cmd_setup() {
  need_curl
  printf '══ Configuração guiada de credenciais (salva variáveis de ambiente) ══\n'
  info "As chaves são gravadas em ~/.secrets (chmod 600) e exportadas via ~/.zshenv."
  info "Nada é commitado; valores nunca aparecem na tela (entrada oculta)."

  local or_key el_key
  or_key="$(prompt_key OPENROUTER_API_KEY "Conta OpenRouter — https://openrouter.ai/keys (usada em todas as chamadas da skill)." 1 "sk-or-v1-...")"
  el_key="$(prompt_key ELEVENLABS_API_KEY "Conta ElevenLabs — https://elevenlabs.io/api-keys (necessária para clonagem de voz e BYOK)." 0 "32 caracteres alfanuméricos")"

  save_secret OPENROUTER_API_KEY "$or_key"
  ok "OPENROUTER_API_KEY salva em ~/.secrets"
  if [[ -n "$el_key" ]]; then
    save_secret ELEVENLABS_API_KEY "$el_key"
    ok "ELEVENLABS_API_KEY salva em ~/.secrets"
  fi

  # Teste de login real (valida que o "login da conta" funciona)
  export OPENROUTER_API_KEY="$or_key"
  [[ -n "$el_key" ]] && export ELEVENLABS_API_KEY="$el_key"
  printf '\n── Testando o login das contas ──\n'
  cmd_account || warn "o teste de login falhou — confira as chaves"

  cat <<'EOF'

Próximos passos:
  1. Abra um NOVO shell (ou rode: source ~/.secrets) para carregar as variáveis.
  2. Puxe os dados da conta:    scripts/elevenlabs.sh account
  3. Para clonagem de voz:      configure o BYOK em https://openrouter.ai/settings/keys
     → "Provider Keys" → ElevenLabs → cole a chave nativa (guarde o voice_id do clone).
  4. Primeiro áudio de teste:   scripts/elevenlabs.sh tts "Olá mundo" --out teste.mp3
EOF
}

# ---------------------------------------------------------------------------
# Comando: account — puxar os dados das contas
# ---------------------------------------------------------------------------
cmd_account() {
  need_curl
  local or_key el_key
  if lookup_var OPENROUTER_API_KEY; then or_key="$GLOB_VAL"; else or_key=""; fi
  if lookup_var ELEVENLABS_API_KEY; then el_key="$GLOB_VAL"
  elif lookup_var ELEVENLABS_NATIVE_API_KEY; then el_key="$GLOB_VAL"; else el_key=""; fi

  if [[ -z "$or_key" && -z "$el_key" ]]; then
    die "nenhuma credencial em memória — rode: scripts/elevenlabs.sh check && scripts/elevenlabs.sh setup"
  fi

  if [[ $FLAG_DRY -eq 1 ]]; then
    [[ -n "$or_key" ]] && printf 'DRY-RUN> curl -sS %s/key -H "Authorization: Bearer $OPENROUTER_API_KEY"\n' "$OR_API_BASE"
    [[ -n "$or_key" ]] && printf 'DRY-RUN> curl -sS %s/credits -H "Authorization: Bearer $OPENROUTER_API_KEY"\n' "$OR_API_BASE"
    [[ -n "$el_key" ]] && printf 'DRY-RUN> curl -sS %s/user -H "xi-api-key: $ELEVENLABS_API_KEY"\n' "$EL_API_BASE"
    return 0
  fi

  if [[ -n "$or_key" ]]; then
    printf '\n══ Conta OpenRouter ══\n'
    local body
    body="$(curl -sS "$OR_API_BASE/key" -H "Authorization: Bearer $or_key" || true)"
    if [[ $FLAG_JSON -eq 1 ]]; then
      printf '%s' "$body" | jsonfmt
    else
      if have_jq && printf '%s' "$body" | jq -e '.data' >/dev/null 2>&1; then
        printf '%s' "$body" | jq -r '.data | "  label...........: \(.label // "-")\n  limit...........: \(.limit // "sem teto")\n  limit_remaining.: \(.limit_remaining // "-")\n  usage_monthly...: \(.usage_monthly // 0)\n  is_free_tier....: \(.is_free_tier // false)"'
      else
        printf '%s' "$body" | jsonfmt
      fi
    fi
    # créditos (pode exigir management key — falha é tolerada)
    local credits
    credits="$(curl -sS "$OR_API_BASE/credits" -H "Authorization: Bearer $or_key" 2>/dev/null || true)"
    if have_jq && printf '%s' "$credits" | jq -e '.data.total_credits' >/dev/null 2>&1; then
      printf '%s' "$credits" | jq -r '"  total_credits...: \(.data.total_credits) | total_usage: \(.data.total_usage)"'
    else
      info "créditos: endpoint /credits indisponível para esta chave (ok — é opcional)"
    fi
  else
    info "OPENROUTER_API_KEY ausente — pulando conta OpenRouter"
  fi

  if [[ -n "$el_key" ]]; then
    printf '\n══ Conta ElevenLabs ══\n'
    local body
    body="$(curl -sS "$EL_API_BASE/user" -H "xi-api-key: $el_key" || true)"
    if [[ $FLAG_JSON -eq 1 ]]; then
      printf '%s' "$body" | jsonfmt
    elif have_jq && printf '%s' "$body" | jq -e '.subscription' >/dev/null 2>&1; then
      printf '%s' "$body" | jq -r '"  tier............: \(.subscription.tier // "-")\n  caracteres usados: \(.subscription.character_count // 0) / \(.subscription.character_limit // "?")\n  próxima cobrança.: \(.subscription.next_character_count_reset_unix // "-")\n  voice slots.....: \(.subscription.max_voice_add_edit // "-")"'
      local voices
      voices="$(curl -sS "$EL_API_BASE/voices" -H "xi-api-key: $el_key" 2>/dev/null || true)"
      if have_jq && printf '%s' "$voices" | jq -e '.voices' >/dev/null 2>&1; then
        printf '%s' "$voices" | jq -r '"  vozes na conta..: \(.voices | length) (use: scripts/elevenlabs.sh voices)"'
      fi
    else
      printf '%s' "$body" | jsonfmt
    fi
  else
    info "ELEVENLABS_API_KEY ausente — pulando conta ElevenLabs (necessária para clonagem/BYOK)"
  fi

  # BYOK: dica de configuração quando as duas contas existem
  if [[ -n "$or_key" && -n "$el_key" && $FLAG_JSON -eq 0 ]]; then
    printf '\n'
    info "BYOK: para usar vozes clonadas via OpenRouter, vincule a chave ElevenLabs em"
    info "https://openrouter.ai/settings/keys → Provider Keys → ElevenLabs (ver references/audio-elevenlabs.md §9)."
  fi
}

# ---------------------------------------------------------------------------
# Comando: models — tabelas de modelos
# ---------------------------------------------------------------------------
cmd_models() {
  cat <<'EOF'
── TTS (Text-to-Speech) — preço por MILHÃO de caracteres ─────────────────
model                                nome                     limite/req   preço   uso
elevenlabs/eleven-v4                 Eleven v4                10.000       $40     topo de gama, 90+ idiomas, audio tags, clone HD
elevenlabs/eleven-v4-turbo           Eleven v4 Turbo          10.000       $20     v4 rápido, agentes conversacionais
elevenlabs/eleven-v3                 Eleven v3                 5.000       $40     emoção rica, não-verbais, 70+ idiomas
elevenlabs/eleven-v3-conversational  Eleven v3 Conversational  5.000       $20     ritmo de diálogo
elevenlabs/eleven-flash-v2.5         Eleven Flash v2.5        40.000       $20     TTFT ~75ms, 32 idiomas, alto volume
elevenlabs/eleven-turbo-v2.5         Eleven Turbo v2.5        40.000       $20     velocidade × qualidade multilíngue
elevenlabs/eleven-flash-v2           Eleven Flash v2          30.000       $20     SOMENTE inglês, tempo real
elevenlabs/eleven-multilingual-v2    Eleven Multilingual v2   10.000       $40     long-form (audiolivros), suporta speed 0.7–1.2

── STT (Speech-to-Text) — preço por SEGUNDO de áudio ─────────────────────
model                          nome                  especialização
elevenlabs/scribe-v2           Scribe v2             90+ idiomas, timestamps por palavra, diarização, eventos acústicos   $0.000031/s
elevenlabs/scribe-v2-medical   Scribe v2 Medical     terminologia clínica (−35% de erro em áudios médicos)               $0.000031/s

Notas: default de response_format é PCM (não mp3) — declare sempre explicitamente.
speed só em multilingual-v2/flash (0.7–1.2); eleven-v4 rejeita speed com HTTP 400.
Detalhes: references/audio-elevenlabs.md
EOF
}

# ---------------------------------------------------------------------------
# Comando: tts — sintetizar texto em áudio
# ---------------------------------------------------------------------------
cmd_tts() {
  need_curl
  local model="elevenlabs/eleven-v4-turbo" voice="george" fmt="mp3" out="" text="" text_file=""
  local stability="" similarity="" seed="" prev="" next="" speed="" lang=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --model)    model=$(val "$@"); shift 2 ;;
      --voice)    voice=$(val "$@"); shift 2 ;;
      --voice-id) voice=$(val "$@"); shift 2 ;;   # clone: entra no mesmo campo voice
      --format)   fmt=$(val "$@"); shift 2 ;;
      --out|-o)   out=$(val "$@"); shift 2 ;;
      --file)     text_file=$(val "$@"); shift 2 ;;
      --stability)   stability=$(val "$@"); shift 2 ;;
      --similarity)  similarity=$(val "$@"); shift 2 ;;
      --seed)        seed=$(val "$@"); shift 2 ;;
      --previous-text) prev=$(val "$@"); shift 2 ;;
      --next-text)     next=$(val "$@"); shift 2 ;;
      --speed)    speed=$(val "$@"); shift 2 ;;
      --language) lang=$(val "$@"); shift 2 ;;
      --dry-run)  FLAG_DRY=1; shift ;;
      --json)     FLAG_JSON=1; shift ;;
      -h|--help)  usage; exit 0 ;;
      -*)         die "opção desconhecida: $1 (veja --help)" ;;
      *)          text="$1"; shift ;;
    esac
  done

  if [[ -n "$text_file" ]]; then
    [[ -f "$text_file" ]] || die "arquivo não encontrado: $text_file"
    text="$(cat "$text_file")"
  fi
  [[ -n "$text" ]] || die 'tts: informe o texto (argumento) ou --file <arquivo>.'
  [[ "$fmt" == "mp3" || "$fmt" == "pcm" ]] || die "--format aceita apenas mp3 ou pcm"
  if [[ -n "$speed" ]]; then
    case "$model" in
      *eleven-v4*) warn "eleven-v4* rejeita 'speed' (HTTP 400) — use audio tags ([rushed]/[drawn out]) ou remova --speed" ;;
    esac
  fi
  [[ -n "$out" ]] || out="tts-$(date +%Y%m%d-%H%M%S).$fmt"

  local or_key=""
  if lookup_var OPENROUTER_API_KEY; then or_key="$GLOB_VAL"; fi

  # Monta o payload (python3)
  local payload
  payload="$(python3 - "$model" "$voice" "$fmt" "$text" "$stability" "$similarity" "$seed" "$prev" "$next" "$speed" "$lang" <<'PY'
import json, sys
model, voice, fmt, text = sys.argv[1:5]
stability, similarity, seed, prev, nxt, speed, lang = sys.argv[5:12]
p = {"model": model, "input": text, "voice": voice, "response_format": fmt}
opts = {}
if stability: opts.setdefault("voice_settings", {})["stability"] = float(stability)
if similarity: opts.setdefault("voice_settings", {})["similarity_boost"] = float(similarity)
if seed: opts["seed"] = int(seed)
if prev: opts["previous_text"] = prev
if nxt: opts["next_text"] = nxt
if lang: opts["language_code"] = lang
if opts: p["provider"] = {"options": {"elevenlabs": opts}}
print(json.dumps(p, ensure_ascii=False))
PY
)"

  if [[ $FLAG_DRY -eq 1 ]]; then
    printf 'DRY-RUN> POST %s/audio/speech  (→ %s)\n' "$OR_API_BASE" "$out"
    printf '%s\n' "$payload"
    return 0
  fi
  [[ -n "$or_key" ]] || die "OPENROUTER_API_KEY ausente em memória — rode: scripts/elevenlabs.sh setup"

  local hdrs code
  hdrs="$(mktemp "${TMPDIR:-/dev/shm}/tts-hdrs.XXXXXX")"
  code="$(curl -sS -X POST "$OR_API_BASE/audio/speech" \
    -H "Authorization: Bearer $or_key" \
    -H "Content-Type: application/json" \
    -d "$payload" \
    -D "$hdrs" -o "$out" -w '%{http_code}' || echo 000)"

  local ctype gen
  ctype="$(grep -i '^content-type:' "$hdrs" | tail -n1 | tr -d '\r' | cut -d' ' -f2- || true)"
  gen="$(grep -i '^x-generation-id:' "$hdrs" | tail -n1 | tr -d '\r' | cut -d' ' -f2- || true)"
  rm -f "$hdrs"

  # Guarda contra corrupção binária silenciosa (§10 da referência)
  if [[ "$code" != 2* ]] || [[ "$ctype" != audio/* ]]; then
    warn "a resposta NÃO é áudio (HTTP $code, Content-Type: ${ctype:-vazio}) — corpo de erro:"
    cat "$out" >&2 || true
    printf '\n' >&2
    rm -f "$out"
    die "síntese falhou (provável erro ZodError/payload — ver references/audio-elevenlabs.md §10)"
  fi

  ok "áudio gravado em $out ($(wc -c <"$out" | tr -d ' ') bytes, $ctype)"
  info "X-Generation-Id: ${gen:-indisponível}  (auditar: GET $OR_API_BASE/generation?id=$gen)"
}

# ---------------------------------------------------------------------------
# Comando: stt — transcrever arquivo de áudio
# ---------------------------------------------------------------------------
cmd_stt() {
  need_curl
  local model="elevenlabs/scribe-v2" file="" fmt="" lang="" speakers="" threshold=""
  local diarize="false" tag_events="false" no_verbatim="false" granularity="word"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --model)     model=$(val "$@"); shift 2 ;;
      --format)    fmt=$(val "$@"); shift 2 ;;
      --language)  lang=$(val "$@"); shift 2 ;;
      --speakers)  speakers=$(val "$@"); shift 2 ;;
      --threshold) threshold=$(val "$@"); shift 2 ;;
      --diarize)   diarize="true"; shift ;;
      --tag-events) tag_events="true"; shift ;;
      --no-verbatim) no_verbatim="true"; shift ;;
      --granularity) granularity=$(val "$@"); shift 2 ;;
      --dry-run)   FLAG_DRY=1; shift ;;
      --json)      FLAG_JSON=1; shift ;;
      -h|--help)   usage; exit 0 ;;
      -*)          die "opção desconhecida: $1 (veja --help)" ;;
      *)           file="$1"; shift ;;
    esac
  done
  [[ -n "$file" ]] || die 'stt: informe o caminho do arquivo de áudio.'
  [[ -f "$file" ]] || die "arquivo não encontrado: $file"
  [[ -z "$speakers" || -z "$threshold" ]] || die "use --speakers OU --threshold (a API aceita apenas um dos dois)"
  if [[ -z "$fmt" ]]; then
    case "${file##*.}" in
      mp3) fmt="mp3" ;; wav) fmt="wav" ;; m4a|mp4) fmt="m4a" ;; ogg) fmt="ogg" ;; flac) fmt="flac" ;; pcm|raw) fmt="pcm" ;;
      *) fmt="mp3"; warn "extensão não reconhecida — assumindo format=mp3" ;;
    esac
  fi
  local size
  size="$(wc -c <"$file" | tr -d ' ')"
  [[ "$size" -le 26214400 ]] || die "arquivo de ${size} bytes excede o limite de 25 MB — fatie antes (ver §8 da referência)"

  local or_key=""
  if lookup_var OPENROUTER_API_KEY; then or_key="$GLOB_VAL"; fi

  local payload
  payload="$(python3 - "$file" "$model" "$fmt" "$granularity" "$lang" "$speakers" "$threshold" "$diarize" "$tag_events" "$no_verbatim" <<'PY'
import base64, json, sys
path, model, fmt, gran, lang, speakers, threshold, diarize, tag_events, no_verbatim = sys.argv[1:11]
with open(path, "rb") as f:
    b64 = base64.b64encode(f.read()).decode("utf-8")   # bytes brutos, SEM prefixo data:
p = {
    "model": model,
    "response_format": "verbose_json",
    "timestamp_granularities[]": gran,
    "input_audio": {"data": b64, "format": fmt},
}
opts = {"diarize": diarize == "true", "tag_audio_events": tag_events == "true", "no_verbatim": no_verbatim == "true"}
if lang: opts["language"] = lang
if speakers: opts["num_speakers"] = int(speakers)
if threshold: opts["diarization_threshold"] = float(threshold)
p["provider"] = {"options": {"elevenlabs": opts}}
print(json.dumps(p, ensure_ascii=False))
PY
)"

  if [[ $FLAG_DRY -eq 1 ]]; then
    printf 'DRY-RUN> POST %s/audio/transcriptions  (input: %s, payload de %s bytes com base64)\n' \
      "$OR_API_BASE" "$file" "$(printf '%s' "$payload" | wc -c | tr -d ' ')"
    printf '%s\n' "$payload" | python3 -c 'import json,sys; d=json.load(sys.stdin); d["input_audio"]["data"]="<base64 omitted>"; print(json.dumps(d, indent=2, ensure_ascii=False))'
    return 0
  fi
  [[ -n "$or_key" ]] || die "OPENROUTER_API_KEY ausente em memória — rode: scripts/elevenlabs.sh setup"

  local resp
  resp="$(curl -sS -X POST "$OR_API_BASE/audio/transcriptions" \
    -H "Authorization: Bearer $or_key" \
    -H "Content-Type: application/json" \
    -d "$payload" || true)"

  if [[ $FLAG_JSON -eq 1 ]]; then
    printf '%s' "$resp" | jsonfmt
    return 0
  fi
  if have_jq && printf '%s' "$resp" | jq -e '.text' >/dev/null 2>&1; then
    printf '── Transcrição ──\n'
    printf '%s\n\n' "$(printf '%s' "$resp" | jq -r '.text')"
    printf '%s' "$resp" | jq -r '"custo reportado (usage.cost): $\(.usage.cost // "n/d")"'
    printf '%s' "$resp" | jq -r 'if .words then "palavras com timestamp: \(.words | length)" else empty end'
  else
    printf '%s' "$resp" | jsonfmt
    die "resposta sem .text — verifique o payload/limite (25 MB, timeout 60 s)"
  fi
}

# ---------------------------------------------------------------------------
# Comando: voices — vozes da conta ElevenLabs (nativas + clones)
# ---------------------------------------------------------------------------
cmd_voices() {
  need_curl
  if [[ $FLAG_DRY -eq 1 ]]; then
    printf 'DRY-RUN> curl -sS %s/voices -H "xi-api-key: $ELEVENLABS_API_KEY"\n' "$EL_API_BASE"
    return 0
  fi
  local el_key=""
  if lookup_var ELEVENLABS_API_KEY; then el_key="$GLOB_VAL"
  elif lookup_var ELEVENLABS_NATIVE_API_KEY; then el_key="$GLOB_VAL"; else
    die "ELEVENLABS_API_KEY ausente em memória — rode: scripts/elevenlabs.sh setup"
  fi
  local body
  body="$(curl -sS "$EL_API_BASE/voices" -H "xi-api-key: $el_key" || true)"
  if [[ $FLAG_JSON -eq 1 ]]; then printf '%s' "$body" | jsonfmt; return 0; fi
  if have_jq && printf '%s' "$body" | jq -e '.voices' >/dev/null 2>&1; then
    printf '%-28s %-24s %-14s %s\n' "NOME" "VOICE_ID" "CATEGORIA" "PREVIEW"
    printf '%s' "$body" | jq -r '.voices[] | "\(.name)\t\(.voice_id)\t\(.category // "-")\t\(.preview_url // "-")"' |
      while IFS=$'\t' read -r n id c p; do printf '%-28s %-24s %-14s %s\n' "$n" "$id" "$c" "$p"; done
    printf '\nUse o voice_id (ou o nome das 21 vozes embutidas) em: scripts/elevenlabs.sh tts "..." --voice <id>\n'
  else
    printf '%s' "$body" | jsonfmt
  fi
}

# ---------------------------------------------------------------------------
# Ajuda
# ---------------------------------------------------------------------------
usage() {
  cat <<'EOF'
elevenlabs.sh — ElevenLabs via OpenRouter, 100% em terminal

Uso:
  elevenlabs.sh <comando> [opções]

Comandos:
  check [--json] [--live]    Verifica na MEMÓRIA (ambiente → ./.env → ~/.secrets →
                             ~/.zshenv → ~/.dsh/.credentials.yaml → memória CoALA)
                             se temos o login de cada conta, com o comando para
                             puxar cada variável. --live também consulta as APIs.
  setup [--no-validate]      Configuração GUIADA: pede as chaves (oculto), valida,
                             testa o login e SALVA em ~/.secrets (600) + export via
                             ~/.zshenv. Variáveis: OPENROUTER_API_KEY,
                             ELEVENLABS_API_KEY (clonagem/BYOK).
  account [--json] [--dry-run]
                             Puxa os dados das contas: OpenRouter (limit/usage/
                             créditos) e ElevenLabs (tier, caracteres, vozes).
  models                     Tabela de modelos TTS/STT, limites e preços.
  tts <texto> [opções]       Sintetiza áudio (POST /audio/speech).
                               --file <f>            texto vindo de arquivo
                               --model <slug>        default: elevenlabs/eleven-v4-turbo
                               --voice <nome|id>     default: george (--voice-id = clone)
                               --format mp3|pcm      default: mp3 (a API default é pcm!)
                               --out/-o <arquivo>    default: tts-<timestamp>.<format>
                               --stability --similarity --seed --language
                               --previous-text --next-text   (contexto de chunking)
                               --speed <0.7-1.2>     só multilingual-v2/flash
  stt <arquivo> [opções]     Transcreve áudio (POST /audio/transcriptions).
                               --model scribe-v2|scribe-v2-medical
                               --diarize --speakers N | --threshold X
                               --tag-events --no-verbatim --language <en|pt>
                               --granularity word|segment
  voices [--json]            Lista vozes da conta ElevenLabs (nativas + clones).

Globais: --json (saída estruturada), --dry-run (imprime a chamada sem executar).

Fluxo recomendado:
  scripts/elevenlabs.sh check      → temos o login?
  scripts/elevenlabs.sh setup      → configurar + salvar variáveis de ambiente
  scripts/elevenlabs.sh account    → puxar dados da conta
  scripts/elevenlabs.sh tts "Olá" --out ola.mp3

Referência completa: references/audio-elevenlabs.md
EOF
}

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------
main() {
  [[ $# -ge 1 ]] || { usage; exit 0; }
  local cmd="$1"; shift
  # Flags globais (--json/--live/--dry-run) são consumidos aqui; o resto
  # segue para o parser do comando.
  local -a rest=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --json)    FLAG_JSON=1; shift ;;
      --dry-run) FLAG_DRY=1; shift ;;
      --live)    FLAG_LIVE=1; shift ;;
      *)         rest+=("$1"); shift ;;
    esac
  done
  set -- ${rest[@]+"${rest[@]}"}
  case "$cmd" in
    check)   cmd_check "$@" ;;
    setup)   cmd_setup "$@" ;;
    account) cmd_account "$@" ;;
    models)  cmd_models "$@" ;;
    tts)     cmd_tts "$@" ;;
    stt)     cmd_stt "$@" ;;
    voices)  cmd_voices "$@" ;;
    help|-h|--help) usage ;;
    *) die "comando desconhecido: $cmd (veja --help)" ;;
  esac
}

main "$@"
