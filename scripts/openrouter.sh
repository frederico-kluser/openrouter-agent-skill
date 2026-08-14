#!/usr/bin/env bash
# ============================================================================
# openrouter.sh — CLI para a API do OpenRouter (https://openrouter.ai/api/v1)
#
# Dependências: curl + jq (se jq faltar, usa python3 como fallback de
# formatação; se ambos faltarem, exibe o JSON cru com um aviso).
#
# Autenticação: a chave vem EXCLUSIVAMENTE da variável de ambiente
# OPENROUTER_API_KEY (nunca de argumento, nunca hardcoded). Sem chave,
# TODOS os comandos entram em modo dry-run por padrão: imprimem o curl
# exato que seria executado (chave como placeholder) e saem com código 0.
# Endpoints públicos (models/providers/prices/tps/suggest) podem funcionar
# sem chave; use --live para forçar a execução real, ou --dry-run para
# forçar a simulação. Com chave definida, os comandos executam de verdade
# (--dry-run ainda simula).
#
# Fontes factuais: docs/research/openrouter-api.md e
# docs/research/openrouter-routing-config.md (verificadas 2026-08-14).
# ============================================================================
set -euo pipefail

API_BASE="https://openrouter.ai/api/v1"
FLAG_JSON=0
FLAG_DRY=0
FLAG_LIVE=0
TMP="$(mktemp)"
TMP_HDR="$(mktemp)"
trap 'rm -f "$TMP" "$TMP_HDR"' EXIT

# ---------------------------------------------------------------------------
# Utilidades de mensagem
# ---------------------------------------------------------------------------
warn() { printf 'Aviso: %s\n' "$*" >&2; }
die()  { printf 'Erro: %s\n' "$*" >&2; exit 1; }

# Lê o valor do próximo argumento. Chamado com "$@" dentro do case ($1 é o
# próprio flag, $2 é o valor). Morre com mensagem acionável se valor ausente.
# Uso: --flag) var=$(val "$@"); shift 2;;
val() {
  [[ $# -ge 2 ]] || die "$1: valor ausente (veja --help)."
  printf '%s' "$2"
}

ensure_jq() {
  if ! command -v jq >/dev/null 2>&1 && ! command -v python3 >/dev/null 2>&1; then
    die "$1: precisa de jq (ou python3 como fallback) para formatar a saída."
  fi
}

# ---------------------------------------------------------------------------
# Ajuda
# ---------------------------------------------------------------------------
usage() {
  cat <<'EOF'
openrouter.sh — CLI para a API do OpenRouter (https://openrouter.ai/api/v1)

Uso:
  openrouter.sh <comando> [opções]

Comandos:
  models    [--query TEXTO] [--sort VALOR] [--min-price N] [--max-price N]
            [--limit N] [--offset N] [--json] [--dry-run] [--live]
      Lista modelos (GET /api/v1/models) com filtros reais.
      --sort: most-popular | newest | top-weekly | pricing-low-to-high |
              pricing-high-to-low | context-high-to-low | throughput-high-to-low |
              latency-low-to-high | intelligence-high-to-low | coding-high-to-low |
              agentic-high-to-low | design-arena-elo-high-to-low
      --min-price / --max-price: preço por 1M tokens, em USD (mesma convenção
              de provider.max_price). --limit 0 = lista completa (default 100).

  providers <modelo> [--json] [--dry-run] [--live]
      Providers que servem o modelo (GET /api/v1/models/<modelo>/endpoints).
      Tabela: tag, quantização, TPS (throughput_last_30m.p50), latência
      (latency_last_30m.p50, em segundos), preços prompt/completion por 1M,
      status, uptime. O identificador de provider é o campo `tag`.

  prices <modelo> [--dry-run] [--live]
      Ranking dos providers por preço de prompt (menor -> maior).

  tps <modelo> [--dry-run] [--live]
      Top 10 providers por throughput (tokens/s, p50 da janela de 30 min).

  suggest "<tarefa>" [--provider P] [--force] [--dry-run] [--live]
      Monta um payload JSON de exemplo para /chat/completions (modelo
      sugerido por heurística sobre a tarefa + provider + plugins).
      --force: provider={only:[P], allow_fallbacks:false}.
      Sem OPENROUTER_API_KEY (ou com --dry-run): só imprime o payload e o
      curl que seria executado. Com chave ou --live e sem --dry-run: envia
      a requisição (custa créditos).

  chat --model M [--provider P] [--message "..."] [--stream] [--dry-run] [--live]
      Chat real via POST /api/v1/chat/completions (requer OPENROUTER_API_KEY).
      --provider P força provider={only:[P], allow_fallbacks:false}.
      --stream: saída SSE crua (data: [DONE] encerra; usage no último chunk).

  key [--dry-run] [--live]
      Limites da chave atual (GET /api/v1/key): limit, limit_remaining,
      is_free_tier, usage_daily/weekly/monthly, limit_reset.

  credits [--dry-run] [--live]
      Créditos comprados/usados (GET /api/v1/credits). Requer MANAGEMENT key
      (criada em https://openrouter.ai/keys com o tipo Management).

  --help | -h
      Mostra esta ajuda.

Autenticação:
  A chave vem APENAS da variável de ambiente OPENROUTER_API_KEY. Sem chave,
  TODOS os comandos entram em modo dry-run por padrão: imprimem o curl
  exato que seria executado (chave como placeholder) e saem com código 0.
  Endpoints públicos (models/providers/prices/tps/suggest) podem funcionar
  sem chave; use --live para executar de verdade mesmo sem chave, ou
  --dry-run para forçar a simulação. Com chave definida, os comandos
  executam de verdade e --dry-run ainda simula.

Saída:
  Tabelas em texto puro por padrão; --json devolve o JSON bruto da API.

Exemplos:
  openrouter.sh models --query gpt-4o --sort pricing-low-to-high --limit 10
  openrouter.sh models --min-price 0 --max-price 1 --limit 20 --json
  openrouter.sh providers openai/gpt-4o
  openrouter.sh prices anthropic/claude-3.5-sonnet
  openrouter.sh tps meta-llama/llama-3.2-3b-instruct:free
  openrouter.sh suggest "extraia os campos do contrato em JSON" --force
  OPENROUTER_API_KEY=sk-or-v1-... openrouter.sh chat --model openai/gpt-4o \
      --message "Olá, OpenRouter!"
  OPENROUTER_API_KEY=sk-or-v1-... openrouter.sh chat --model openai/gpt-4o --stream
  OPENROUTER_API_KEY=sk-or-v1-... openrouter.sh key
  OPENROUTER_API_KEY=sk-or-v1-... openrouter.sh credits
EOF
}

# ---------------------------------------------------------------------------
# Curl: dry-run, execução e tratamento de erro
# ---------------------------------------------------------------------------
# Imprime o curl que seria executado (chave sempre como placeholder) e sai 0.
dry_run_exit() {
  warn "Modo dry-run — nada foi enviado."
  if [[ -z "${OPENROUTER_API_KEY:-}" ]]; then
    warn "Sem OPENROUTER_API_KEY — modo dry-run. Endpoints públicos podem funcionar sem chave; use --live para executar de verdade."
    warn "Para executar de verdade, exporte sua chave (crie em https://openrouter.ai/keys):"
    warn '  export OPENROUTER_API_KEY=sk-or-v1-...'
  fi
  echo "Curl que seria executado (chave mostrada como placeholder):"
  printf '  curl '
  printf '%q ' "$@"
  echo
  exit 0
}

# Mensagens específicas por código HTTP usando o error_type do envelope.
# Sempre retorna 1 (erro).
or_handle_error() {
  local code="$1"
  local et msg
  et=$(jq -r '.error.metadata.error_type // "desconhecido"' "$TMP" 2>/dev/null || echo "desconhecido")
  msg=$(jq -r '.error.message // "sem mensagem no envelope"' "$TMP" 2>/dev/null || echo "resposta não é JSON")
  case "$code" in
    400) printf 'Erro 400 — requisição inválida.\n' >&2 ;;
    401) printf 'Erro 401 — chave inválida, ausente ou revogada.\n' >&2
         printf '  Resolva em https://openrouter.ai/settings/keys (gere outra chave).\n' >&2 ;;
    402) printf 'Erro 402 — créditos insuficientes.\n' >&2
         printf '  Adicione créditos em https://openrouter.ai/settings/credits e tente de novo.\n' >&2 ;;
    403) printf 'Erro 403 — permissão negada.\n' >&2
         printf '  /credits exige MANAGEMENT key; guardrails/moderação também retornam 403.\n' >&2 ;;
    404) printf 'Erro 404 — recurso não encontrado (modelo inexistente ou nenhum provider atende as restrições).\n' >&2
         printf '  Confira o slug (ex.: openai/gpt-4o) ou relaxe provider/models.\n' >&2 ;;
    408) printf 'Erro 408 — a requisição expirou.\n' >&2 ;;
    413) printf 'Erro 413 — payload grande demais.\n' >&2 ;;
    422) printf 'Erro 422 — requisição não processável.\n' >&2 ;;
    429) printf 'Erro 429 — rate limit (plataforma ou provider).\n' >&2
         printf '  Respeite o header Retry-After e tente com backoff exponencial.\n' >&2 ;;
    500) printf 'Erro 500 — erro interno do servidor (mensagem upstream mascarada).\n' >&2 ;;
    502) printf 'Erro 502 — o modelo/provider escolhido está fora do ar ou devolveu resposta inválida.\n' >&2
         printf '  O fallback de provider (allow_fallbacks) pode resolver.\n' >&2 ;;
    503) printf 'Erro 503 — nenhum provider disponível para as restrições de roteamento.\n' >&2
         printf '  Relaxe provider (only/order/max_price/quantizations) ou adicione fallbacks via models[].\n' >&2 ;;
    504) printf 'Erro 504 — gateway timeout (o provider não respondeu a tempo).\n' >&2 ;;
    *)   printf 'Erro HTTP %s — não mapeado.\n' "$code" >&2 ;;
  esac
  printf '  error_type: %s\n  mensagem:   %s\n' "$et" "$msg" >&2
  return 1
}

# Executa o curl (ou entra em dry-run).
# Uso: run_or_dry <label> <need_auth:0|1> [args do curl...]
# O corpo da resposta fica em $TMP e os headers em $TMP_HDR.
run_or_dry() {
  local label="$1" need_auth="$2"; shift 2
  local -a cargs=("$@")
  # --dry-run explícito sempre simula (mesmo com chave definida).
  if [[ "$FLAG_DRY" == "1" ]]; then
    local -a disp=("$@")
    if [[ -n "${OPENROUTER_API_KEY:-}" || "$need_auth" == "1" ]]; then
      disp+=(-H "Authorization: Bearer <OPENROUTER_API_KEY>")
    fi
    dry_run_exit -sS --max-time 120 "${disp[@]}"
  fi
  if [[ -z "${OPENROUTER_API_KEY:-}" ]]; then
    if [[ "$FLAG_LIVE" == "1" ]]; then
      warn "Sem OPENROUTER_API_KEY, mas --live ativo — executando a requisição real SEM chave (endpoints públicos; autenticados responderão 401)."
    else
      local -a disp=("$@")
      [[ "$need_auth" == "1" ]] && disp+=(-H "Authorization: Bearer <OPENROUTER_API_KEY>")
      dry_run_exit -sS --max-time 120 "${disp[@]}"
    fi
  else
    cargs+=(-H "Authorization: Bearer $OPENROUTER_API_KEY")
  fi
  curl -sS --max-time 120 "${cargs[@]}" -D "$TMP_HDR" -o "$TMP" \
    || die "falha de rede ao chamar $label."
  local code
  code=$(awk 'NR==1{print $2}' "$TMP_HDR")
  if [[ "$code" != "200" ]]; then
    or_handle_error "$code"
    return 1
  fi
  return 0
}

# ---------------------------------------------------------------------------
# Formatação
# ---------------------------------------------------------------------------
# Renderiza uma tabela: filtro jq + formatação awk. Sem jq, tenta python3
# (json.tool) e, como último recurso, exibe o JSON cru — sempre com aviso.
render_table() {
  local filter="$1" awkprog="$2" file="${3:-$TMP}"
  if command -v jq >/dev/null 2>&1; then
    jq -r "$filter" "$file" | awk -F'\t' "$awkprog"
  elif command -v python3 >/dev/null 2>&1; then
    warn "jq não encontrado — exibindo JSON cru formatado com python3 (a tabela precisa de jq)."
    python3 -m json.tool "$file" 2>/dev/null || cat "$file"
  else
    warn "jq e python3 não encontrados — exibindo JSON cru."
    cat "$file"
  fi
}

pretty_json() {
  local file="${1:-$TMP}"
  if command -v jq >/dev/null 2>&1; then
    jq . "$file"
  elif command -v python3 >/dev/null 2>&1; then
    python3 -m json.tool "$file" 2>/dev/null || cat "$file"
  else
    cat "$file"
  fi
}

# JSON bonito a partir de uma string (payloads construídos em memória).
pretty_payload() {
  local payload="$1"
  if command -v jq >/dev/null 2>&1; then
    jq . <<<"$payload"
  elif command -v python3 >/dev/null 2>&1; then
    python3 -c 'import json,sys; print(json.dumps(json.load(sys.stdin), indent=2, ensure_ascii=False))' <<<"$payload" 2>/dev/null || echo "$payload"
  else
    echo "$payload"
  fi
}

# Constrói um payload de chat completions com segurança JSON (jq ou python3).
build_payload() { # $1=model $2=message $3=provider_json (ou "null")
  local model="$1" msg="$2" pj="${3:-null}"
  if command -v jq >/dev/null 2>&1; then
    local f='{model: $m, messages: [{role: "user", content: $c}]}'
    [[ "$pj" != "null" ]] && f='{model: $m, messages: [{role: "user", content: $c}], provider: $p}'
    jq -cn --arg m "$model" --arg c "$msg" --argjson p "$pj" "$f"
  elif command -v python3 >/dev/null 2>&1; then
    python3 - "$model" "$msg" "$pj" <<'PYEOF'
import json, sys
model, msg, pj = sys.argv[1], sys.argv[2], sys.argv[3]
body = {"model": model, "messages": [{"role": "user", "content": msg}]}
if pj and pj != "null":
    body["provider"] = json.loads(pj)
print(json.dumps(body, ensure_ascii=False))
PYEOF
  else
    die "não é possível montar o payload sem jq ou python3."
  fi
}

# Lê o header X-Generation-Id salvo em $TMP_HDR (presente em toda resposta).
gen_id_from_headers() {
  awk 'tolower($1)=="x-generation-id:" {gsub("\r","",$2); print $2}' "$TMP_HDR" | tail -1
}

# ---------------------------------------------------------------------------
# Comando: models
# ---------------------------------------------------------------------------
cmd_models() {
  local q="" sort="" minp="" maxp="" limit="100" offset="0"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --query)     q=$(val "$@"); shift 2;;
      --sort)      sort=$(val "$@"); shift 2;;
      --min-price) minp=$(val "$@"); shift 2;;
      --max-price) maxp=$(val "$@"); shift 2;;
      --limit)     limit=$(val "$@"); shift 2;;
      --offset)    offset=$(val "$@"); shift 2;;
      --json)      FLAG_JSON=1; shift;;
      --dry-run)   FLAG_DRY=1; shift;;
      --live)      FLAG_LIVE=1; shift;;
      *) die "models: opção desconhecida '$1' (veja --help).";;
    esac
  done
  ensure_jq "models"
  local -a qa=()
  [[ -n "$q" ]]     && qa+=(--data-urlencode "q=$q")
  [[ -n "$sort" ]]  && qa+=(--data-urlencode "sort=$sort")
  [[ -n "$minp" ]]  && qa+=(--data-urlencode "min_price=$minp")
  [[ -n "$maxp" ]]  && qa+=(--data-urlencode "max_price=$maxp")
  [[ "$limit" != "0" ]] && qa+=(--data-urlencode "limit=$limit")
  [[ "$offset" != "0" ]] && qa+=(--data-urlencode "offset=$offset")
  run_or_dry "GET /models" 0 -G "$API_BASE/models" "${qa[@]}" || return 1
  if [[ "$FLAG_JSON" == "1" ]]; then pretty_json; return 0; fi
  render_table \
    '.data[] | [.id, (.context_length // 0), (.pricing.prompt // "0"), (.pricing.completion // "0")] | @tsv' \
    'function hctx(n) {
       if (n >= 1000000) return sprintf("%.1fM", n/1000000);
       if (n >= 1000)    return sprintf("%.0fK", n/1000);
       return sprintf("%d", n);
     }
     function usd(v) { if (v == 0) return "$0"; return sprintf("$%.2f", v); }
     NR==1 { printf "%-48s %8s %14s %14s\n", "ID", "CTX", "PROMPT/1M", "COMPL/1M" }
     { printf "%-48s %8s %14s %14s\n", $1, hctx($2), usd($3*1000000), usd($4*1000000) }'
  if command -v jq >/dev/null 2>&1; then
    local total shown
    total=$(jq -r '.total_count // (.data | length)' "$TMP" 2>/dev/null || echo "?")
    shown="$limit"; [[ "$limit" == "0" ]] && shown="todos"
    printf '(exibidos %s de %s modelos; use --offset/--limit para paginar)\n' "$shown" "$total"
  fi
  return 0
}

# ---------------------------------------------------------------------------
# Busca comum dos comandos de endpoints (providers/prices/tps)
# ---------------------------------------------------------------------------
endpoints_fetch() { # $1=modelo → 0 ok / 1 erro (resposta em $TMP)
  ensure_jq "providers/prices/tps"
  run_or_dry "GET /models/$1/endpoints" 0 -G "$API_BASE/models/$1/endpoints" || return 1
  if command -v jq >/dev/null 2>&1; then
    local n
    n=$(jq -r '.data.endpoints | length' "$TMP" 2>/dev/null || echo 0)
    if [[ "$n" == "0" ]]; then
      warn "o modelo '$1' não tem endpoints ativos no momento (pode ter sido aposentado). Confira com: models --query '$1'."
    fi
  fi
  return 0
}

# ---------------------------------------------------------------------------
# Comando: providers
# ---------------------------------------------------------------------------
cmd_providers() {
  local model="${1:-}"
  [[ -z "$model" ]] && die "providers: informe o modelo (ex.: openai/gpt-4o). Veja --help."
  shift || true
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --json)    FLAG_JSON=1; shift;;
      --dry-run) FLAG_DRY=1; shift;;
      --live)    FLAG_LIVE=1; shift;;
      *) die "providers: opção desconhecida '$1' (veja --help).";;
    esac
  done
  endpoints_fetch "$model" || return 1
  if [[ "$FLAG_JSON" == "1" ]]; then pretty_json; return 0; fi
  render_table \
    '.data.endpoints[] |
     [.tag,
      (.quantization // ""),
      (.throughput_last_30m.p50 // ""),
      (.latency_last_30m.p50 // ""),
      (.pricing.prompt // "0"),
      (.pricing.completion // "0"),
      (.status // ""),
      (.uptime_last_1d // "")] | @tsv' \
    'function usd(v) { if (v == 0) return "$0"; return sprintf("$%.2f", v); }
     NR==1 { printf "%-26s %-9s %-10s %-11s %14s %14s %7s %9s\n",
       "TAG", "QUANT", "TPS", "LAT", "PROMPT/1M", "COMPL/1M", "STATUS", "UPTIME" }
     {
       tps = ($3 == "") ? "-" : (($3 < 100) ? sprintf("%.1f", $3) : sprintf("%.0f", $3));
       lat = ($4 == "") ? "-" : sprintf("%.3fs", $4);
       printf "%-26s %-9s %-10s %-11s %14s %14s %7s %9s\n",
              $1, ($2 == "") ? "-" : $2, tps, lat,
              usd($5*1000000), usd($6*1000000),
              ($7 == "") ? "-" : $7,
              ($8 == "") ? "-" : sprintf("%.2f%%", $8);
     }'
  echo "(preços por 1M tokens, USD. TPS = throughput_last_30m.p50; LAT = latency_last_30m.p50 em segundos; o identificador de provider é a coluna TAG — não existe campo provider_id na API.)"
  return 0
}

# ---------------------------------------------------------------------------
# Comando: prices
# ---------------------------------------------------------------------------
cmd_prices() {
  local model="${1:-}"
  [[ -z "$model" ]] && die "prices: informe o modelo (ex.: openai/gpt-4o). Veja --help."
  shift || true
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run) FLAG_DRY=1; shift;;
      --live)    FLAG_LIVE=1; shift;;
      *) die "prices: opção desconhecida '$1' (veja --help).";;
    esac
  done
  endpoints_fetch "$model" || return 1
  render_table \
    '.data.endpoints |
     sort_by((.pricing.prompt // "0") | tonumber) |
     to_entries[] | [(.key + 1), .value.tag,
     (.value.pricing.prompt // "0"), (.value.pricing.completion // "0")] | @tsv' \
    'function usd(v) { if (v == 0) return "$0"; return sprintf("$%.2f", v); }
     NR==1 { printf "%4s %-26s %14s %14s\n", "#", "TAG", "PROMPT/1M", "COMPL/1M" }
     { printf "%4d %-26s %14s %14s\n", $1, $2, usd($3*1000000), usd($4*1000000) }'
  echo "(ranking por preço de prompt, menor -> maior; USD por 1M tokens)"
  return 0
}

# ---------------------------------------------------------------------------
# Comando: tps
# ---------------------------------------------------------------------------
cmd_tps() {
  local model="${1:-}"
  [[ -z "$model" ]] && die "tps: informe o modelo (ex.: openai/gpt-4o). Veja --help."
  shift || true
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run) FLAG_DRY=1; shift;;
      --live)    FLAG_LIVE=1; shift;;
      *) die "tps: opção desconhecida '$1' (veja --help).";;
    esac
  done
  endpoints_fetch "$model" || return 1
  render_table \
    '.data.endpoints |
     sort_by(-(.throughput_last_30m.p50 // 0)) | .[0:10] |
     to_entries[] | [(.key + 1), .value.tag,
     (.value.throughput_last_30m.p50 // ""), (.value.latency_last_30m.p50 // ""),
     (.value.pricing.prompt // "0")] | @tsv' \
    'function usd(v) { if (v == 0) return "$0"; return sprintf("$%.2f", v); }
     NR==1 { printf "%4s %-26s %10s %11s %14s\n", "#", "TAG", "TPS", "LAT", "PROMPT/1M" }
     {
       tps = ($3 == "") ? "-" : (($3 < 100) ? sprintf("%.1f", $3) : sprintf("%.0f", $3));
       lat = ($4 == "") ? "-" : sprintf("%.3fs", $4);
       printf "%4d %-26s %10s %11s %14s\n", $1, $2, tps, lat, usd($5*1000000);
     }'
  echo "(top 10 por throughput_last_30m.p50, tokens/s; '-' = sem dados na janela de 30 min)"
  return 0
}

# ---------------------------------------------------------------------------
# Comando: suggest
# ---------------------------------------------------------------------------
# Constrói pequenos objetos JSON com jq (ou python3 como fallback).
suggest_provider_json() { # $1=mode: force|order|default  $2=provider (opcional)
  local mode="$1" p="${2:-}"
  if command -v jq >/dev/null 2>&1; then
    case "$mode" in
      force)   jq -cn --arg p "$p" '{only: [$p], allow_fallbacks: false}' ;;
      order)   jq -cn --arg p "$p" '{order: ([$p, "openai", "anthropic"] | reduce .[] as $x ([]; if index($x) then . else . + [$x] end)), allow_fallbacks: true}' ;;
      default) jq -cn '{allow_fallbacks: true}' ;;
    esac
  else
    case "$mode" in
      force)   python3 -c 'import json,sys; print(json.dumps({"only":[sys.argv[1]],"allow_fallbacks":False}, ensure_ascii=False))' "$p" ;;
      order)   python3 -c 'import json,sys; p=sys.argv[1]; print(json.dumps({"order":list(dict.fromkeys([p,"openai","anthropic"])),"allow_fallbacks":True}, ensure_ascii=False))' "$p" ;;
      default) python3 -c 'import json; print(json.dumps({"allow_fallbacks":True}))' ;;
    esac
  fi
}

suggest_plugins_append() { # $1=plugins_json (não-null) → adiciona context-compression
  if command -v jq >/dev/null 2>&1; then
    jq -cn --argjson a "$1" '$a + [{"id": "context-compression"}]'
  else
    python3 -c 'import json,sys; a=json.loads(sys.argv[1]); a.append({"id":"context-compression"}); print(json.dumps(a, ensure_ascii=False))' "$1"
  fi
}

suggest_payload() { # $1=model $2=tarefa $3=provider_json $4=plugins_json $5=rf_json (null quando ausentes)
  if command -v jq >/dev/null 2>&1; then
    jq -cn --arg m "$1" --arg c "$2" --argjson p "$3" --argjson pl "$4" --argjson rf "$5" \
      '{model: $m, provider: $p, plugins: $pl, response_format: $rf,
        messages: [{role: "user", content: $c}]} | del(.. | nulls)'
  else
    python3 - "$1" "$2" "$3" "$4" "$5" <<'PYEOF'
import json, sys
model, task, pj, pl, rf = sys.argv[1:6]
body = {"model": model, "messages": [{"role": "user", "content": task}]}
if pj != "null":
    body["provider"] = json.loads(pj)
if pl != "null":
    body["plugins"] = json.loads(pl)
if rf != "null":
    body["response_format"] = json.loads(rf)
print(json.dumps(body, ensure_ascii=False))
PYEOF
  fi
}

# Heurística simples de sugestão de modelo (IDs verificados na pesquisa;
# o usuário deve confirmar com `models --query`).
suggest_model() {
  local t; t=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  case "$t" in
    *json*|*extract*|*estrutur*|*schema*|*parse*|*csv*|*tabela*|*tabel*)
      echo "openai/gpt-4o" ;;
    *código*|*codigo*|*code*|*bug*|*refactor*|*funç*|*func*|*api*|*shell*|*bash*|*script*)
      echo "anthropic/claude-3.5-sonnet" ;;
    *math*|*raciocín*|*raciocin*|*lógica*|*logica*|*proof*|*prova*)
      echo "deepseek/deepseek-r1" ;;
    *grátis*|*gratis*|*free*|*barato*|*teste*|*test*)
      echo "meta-llama/llama-3.2-3b-instruct:free" ;;
    *)
      echo "openai/gpt-4o" ;;
  esac
}

cmd_suggest() {
  local task="${1:-}"
  [[ -z "$task" ]] && die "suggest: informe a tarefa entre aspas (ex.: suggest \"extraia os campos do contrato em JSON\")."
  shift || true
  local prov="" force=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --provider) prov=$(val "$@"); shift 2;;
      --force)    force=1; shift;;
      --dry-run)  FLAG_DRY=1; shift;;
      --live)     FLAG_LIVE=1; shift;;
      *) die "suggest: opção desconhecida '$1' (veja --help).";;
    esac
  done
  ensure_jq "suggest"

  local model; model=$(suggest_model "$task")

  # provider: --force → only + sem fallbacks; --provider → order + fallbacks;
  # nenhum → só allow_fallbacks: true (comportamento default da API).
  local pj
  if [[ "$force" == "1" ]]; then
    pj=$(suggest_provider_json force "${prov:-openai}")
  elif [[ -n "$prov" ]]; then
    pj=$(suggest_provider_json order "$prov")
  else
    pj=$(suggest_provider_json default)
  fi

  # plugins + response_format conforme o tipo de tarefa (heurística).
  local pl="null" rf="null"
  case "$task" in
    *[Jj][Ss][Oo][Nn]*|*extract*|*estrutur*|*schema*|*parse*|*[Cc][Ss][Vv]*)
      pl='[{"id":"response-healing"}]'
      rf='{"type":"json_object"}'
      ;;
  esac
  case "$task" in
    *long*|*documento*|*contexto*|*[Pp][Dd][Ff]*)
      if [[ "$pl" == "null" ]]; then
        pl='[{"id":"context-compression"}]'
      else
        pl=$(suggest_plugins_append "$pl")
      fi
      ;;
  esac

  local payload
  payload=$(suggest_payload "$model" "$task" "$pj" "$pl" "$rf")

  echo "== Payload sugerido para POST /api/v1/chat/completions =="
  echo "(modelo por heurística — confirme com: openrouter.sh models --query '$model')"
  pretty_payload "$payload"
  echo

  if [[ "$FLAG_DRY" == "0" && ( -n "${OPENROUTER_API_KEY:-}" || "$FLAG_LIVE" == "1" ) ]]; then
    echo "== Enviando a requisição (use --dry-run para só montar) =="
    run_or_dry "POST /chat/completions (suggest)" 1 \
      "$API_BASE/chat/completions" -H "Content-Type: application/json" -d "$payload" || return 1
    render_chat_response
  else
    echo "(payload não enviado. Com OPENROUTER_API_KEY ou --live e sem --dry-run, esta requisição seria feita — custa créditos.)"
    run_or_dry "POST /chat/completions (suggest)" 1 \
      "$API_BASE/chat/completions" -H "Content-Type: application/json" -d "$payload"
  fi
  return 0
}

# ---------------------------------------------------------------------------
# Comando: chat
# ---------------------------------------------------------------------------
# Exibe o conteúdo da resposta + bloco de usage (cost, reasoning_tokens,
# cost_details) + X-Generation-Id. Espera a resposta em $TMP.
render_chat_response() {
  if jq -e '.error' "$TMP" >/dev/null 2>&1; then
    local et msg
    et=$(jq -r '.error.metadata.error_type // "desconhecido"' "$TMP")
    msg=$(jq -r '.error.message // "-"' "$TMP")
    warn "a resposta veio com erro (HTTP 200): $et — $msg"
    return 1
  fi
  local content
  content=$(jq -r '.choices[0].message.content // ""' "$TMP")
  if [[ -z "$content" ]]; then
    local fr
    fr=$(jq -r '.choices[0].finish_reason // "?"' "$TMP")
    printf '[resposta vazia — finish_reason=%s]\n' "$fr"
  else
    printf '%s\n' "$content"
  fi
  echo
  local p c t r cost
  p=$(jq -r '.usage.prompt_tokens // "?"' "$TMP")
  c=$(jq -r '.usage.completion_tokens // "?"' "$TMP")
  t=$(jq -r '.usage.total_tokens // "?"' "$TMP")
  r=$(jq -r '.usage.completion_tokens_details.reasoning_tokens // 0' "$TMP")
  cost=$(jq -r '.usage.cost // "?"' "$TMP")
  printf 'usage: prompt=%s completion=%s (reasoning=%s) total=%s | cost=$%s\n' \
    "$p" "$c" "$r" "$t" "$cost"
  jq -c '.usage.cost_details // null' "$TMP" 2>/dev/null \
    | sed 's/^/cost_details: /' || true
  local gid
  gid=$(gen_id_from_headers)
  if [[ -n "$gid" ]]; then
    echo "X-Generation-Id: $gid  (estatísticas em GET /api/v1/generation?id=$gid)"
  fi
  return 0
}

cmd_chat() {
  local model="" prov="" msg="Explique, em até 3 frases, o que é o OpenRouter." stream=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --model)    model=$(val "$@"); shift 2;;
      --provider) prov=$(val "$@"); shift 2;;
      --message)  msg=$(val "$@"); shift 2;;
      --stream)   stream=1; shift;;
      --dry-run)  FLAG_DRY=1; shift;;
      --live)     FLAG_LIVE=1; shift;;
      *) die "chat: opção desconhecida '$1' (veja --help).";;
    esac
  done
  [[ -z "$model" ]] && die "chat: informe --model (ex.: --model openai/gpt-4o). Veja --help."
  ensure_jq "chat"

  local pj="null"
  if [[ -n "$prov" ]]; then
    if command -v jq >/dev/null 2>&1; then
      pj=$(jq -cn --arg p "$prov" '{only: [$p], allow_fallbacks: false}')
    else
      pj=$(python3 -c 'import json,sys; print(json.dumps({"only":[sys.argv[1]],"allow_fallbacks":False}, ensure_ascii=False))' "$prov")
    fi
  fi
  local payload
  payload=$(build_payload "$model" "$msg" "$pj")

  if [[ "$stream" == "1" ]]; then
    # Streaming: passa o SSE cru ao terminal; usage chega no último chunk
    # com dados, antes de 'data: [DONE]'.
    if [[ "$FLAG_DRY" == "1" || ( -z "${OPENROUTER_API_KEY:-}" && "$FLAG_LIVE" != "1" ) ]]; then
      dry_run_exit -sS -N --max-time 300 "$API_BASE/chat/completions" \
        -H "Authorization: Bearer <OPENROUTER_API_KEY>" \
        -H "Content-Type: application/json" \
        -d "$payload"
    fi
    if [[ -z "${OPENROUTER_API_KEY:-}" ]]; then
      warn "Sem OPENROUTER_API_KEY, mas --live ativo — executando o streaming real SEM chave (responderá 401)."
    fi
    echo "== SSE cru (streaming). Linhas ':' são comentários do servidor; 'data: [DONE]' encerra. =="
    if ! curl -sS -N --max-time 300 "$API_BASE/chat/completions" \
        -H "Authorization: Bearer $OPENROUTER_API_KEY" \
        -H "Content-Type: application/json" \
        -D "$TMP_HDR" -d "$payload" | tee "$TMP"; then
      die "falha de rede no streaming."
    fi
    echo
    local last
    last=$(grep '^data: ' "$TMP" | grep -v '\[DONE\]' | tail -1 | sed 's/^data: //')
    if [[ -n "$last" ]]; then
      printf '%s' "$last" \
        | jq -r 'select(.usage != null) | .usage
                 | "usage: prompt_tokens=\(.prompt_tokens // "?") completion_tokens=\(.completion_tokens // "?") cost=$\(.cost // "?")"' \
        2>/dev/null || true
      printf '%s' "$last" | jq -r 'select(.error != null) | "erro no stream: \(.error.metadata.error_type // "?") — \(.error.message // "-")"' 2>/dev/null || true
    fi
    local gid
    gid=$(gen_id_from_headers)
    [[ -n "$gid" ]] && echo "X-Generation-Id: $gid"
    return 0
  fi

  run_or_dry "POST /chat/completions" 1 \
    "$API_BASE/chat/completions" -H "Content-Type: application/json" -d "$payload" || return 1
  render_chat_response
}

# ---------------------------------------------------------------------------
# Comando: key
# ---------------------------------------------------------------------------
cmd_key() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run) FLAG_DRY=1; shift;;
      --live)    FLAG_LIVE=1; shift;;
      *) die "key: opção desconhecida '$1' (veja --help).";;
    esac
  done
  ensure_jq "key"
  run_or_dry "GET /key" 1 -G "$API_BASE/key" || return 1
  # Aceita resposta com ou sem wrapper `data`.
  jq -c 'if .data then .data else . end' "$TMP" \
    | jq -r '
      [ ["label",                (.label // "-")],
        ["limit (USD)",          (.limit // "-")],
        ["limit_remaining (USD)",(.limit_remaining // "-")],
        ["limit_reset",          (.limit_reset // "-")],
        ["is_free_tier",         (.is_free_tier // "-")],
        ["is_management_key",    (.is_management_key // "-")],
        ["usage (USD)",          (.usage // "-")],
        ["usage_daily (USD)",    (.usage_daily // "-")],
        ["usage_weekly (USD)",   (.usage_weekly // "-")],
        ["usage_monthly (USD)",  (.usage_monthly // "-")],
        ["expires_at",           (.expires_at // "-")] ] | .[] | @tsv' \
    | awk -F'\t' '{ printf "%-22s %s\n", $1, $2 }'
  echo "(monitore consumo: usage_monthly vs limit — cf. GET /api/v1/key)"
  return 0
}

# ---------------------------------------------------------------------------
# Comando: credits
# ---------------------------------------------------------------------------
cmd_credits() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run) FLAG_DRY=1; shift;;
      --live)    FLAG_LIVE=1; shift;;
      *) die "credits: opção desconhecida '$1' (veja --help).";;
    esac
  done
  ensure_jq "credits"
  run_or_dry "GET /credits" 1 -G "$API_BASE/credits" || {
    warn "Dica: GET /api/v1/credits requer uma MANAGEMENT key (crie em https://openrouter.ai/keys escolhendo o tipo 'Management')."
    return 1
  }
  local tc tu
  tc=$(jq -r '.data.total_credits // 0' "$TMP")
  tu=$(jq -r '.data.total_usage // 0' "$TMP")
  printf 'total_credits: $%.2f\n' "$tc"
  printf 'total_usage:   $%.2f\n' "$tu"
  printf 'restante:      $%.2f\n' "$(awk -v a="$tc" -v b="$tu" 'BEGIN{printf "%.2f", a-b}')"
  return 0
}

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------
main() {
  local cmd="${1:-}"
  shift || true
  case "$cmd" in
    ""|-h|--help|help) usage; exit 0 ;;
    models)    cmd_models "$@" ;;
    providers) cmd_providers "$@" ;;
    prices)    cmd_prices "$@" ;;
    tps)       cmd_tps "$@" ;;
    suggest)   cmd_suggest "$@" ;;
    chat)      cmd_chat "$@" ;;
    key)       cmd_key "$@" ;;
    credits)   cmd_credits "$@" ;;
    *) die "comando desconhecido '$cmd'. Veja --help." ;;
  esac
}

main "$@"
