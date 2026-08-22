#!/usr/bin/env bash
# ============================================================================
# tests/smoke.sh — smoke tests da skill openrouter-agent-skill
#
# Cobre:
#   1. bash -n em todos os .sh (scripts/ + examples/ + este próprio script)
#   2. python3 -m py_compile em examples/quickstart.py
#   3. jq -e . em examples/router-example.json
#   4. dry-run de TODOS os comandos da CLI (models, providers, prices, tps,
#      suggest, chat, key, credits, --help e sem argumentos) SEM chave:
#      exit 0, aviso de dry-run + linha do curl impressa (nada enviado) e
#      nenhum vazamento de chave na saída
#   5. exit 1 com mensagem acionável: comando desconhecido, providers sem
#      modelo, chat sem --model
#   6. suggest --dry-run imprime payload JSON válido (jq -e)
#   7. (opcional, só se a rede estiver disponível) models --live --limit 1
#      sem chave → exit 0 com tabela
#   8. (sempre roda, sem rede) models --dry-run --limit 1 COM uma chave
#      FICTÍCIA no ambiente: dry-run explícito ainda simula com chave
#      definida — exit 0, chave mascarada (placeholder) e aviso de dry-run
#
# Dependências: bash, curl, jq, python3 (nada mais).
# A chave OPENROUTER_API_KEY do ambiente do SUITE (se existir) é usada
# apenas para assegurar que ela não vaza na saída de nenhum comando testado
# e nunca é impressa. Os subtests da CLI rodam SEM chave (env -u
# OPENROUTER_API_KEY); o subteste 8 usa uma chave FICTÍCIA local (nunca a
# real). Sem chave no ambiente do suite, um aviso é impresso e a detecção
# de vazamento por regex permanece ativa.
#
# Uso (sem env -u — a checagem de vazamento contra a chave real depende da
# chave estar no ambiente do suite):
#   bash tests/smoke.sh        (ou ./tests/smoke.sh)
#
# Saída: "N testes, N falhas" no final. Exit 0 se tudo passou, 1 se falhou.
# ============================================================================
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$TESTS_DIR/.." && pwd)"
CLI="$ROOT/scripts/openrouter.sh"
SMOKE="$TESTS_DIR/$(basename "${BASH_SOURCE[0]}")"

# Valor da chave do ambiente (se existir) — usado APENAS para assegurar que
# ele não vaza na saída de nenhum comando testado. Nunca é impresso.
AMB_KEY="${OPENROUTER_API_KEY:-}"
if [[ -z "$AMB_KEY" ]]; then
  printf 'Aviso: chave do ambiente ausente — checagem de vazamento contra a chave real desativada (detecção por regex permanece ativa)\n'
fi

PASS=0; FAIL=0; SKIP=0

ok()   { PASS=$((PASS + 1)); printf 'ok   %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n' "$1"; }
skip() { SKIP=$((SKIP + 1)); printf 'skip %s\n' "$1"; }

# Roda a CLI SEM chave. Deixa OUT (stdout+stderr) e RC globais.
run_cli() {
  OUT="$(env -u OPENROUTER_API_KEY "$CLI" "$@" 2>&1)"
  RC=$?
}

# 1 se o texto não contém chave real nem o valor da chave do ambiente.
# Obs.: a própria CLI imprime o PLACEHOLDER literal "sk-or-v1-..." (usage e
# aviso de dry-run). O 1º caractere após o prefixo "sk-or-v1-" de uma chave
# real é base64 (letra, dígito, "-", "_", "+" ou "/"); o "..." do placeholder
# não casa o 1º caractere. As checagens são POR LINHA (grep) — padrão case
# com "*" cruzaria newlines.
KEY_REGEX='sk-or-v1-[A-Za-z0-9_+/-]'
no_key_leak() {
  local t="$1"
  if printf '%s\n' "$t" | grep -Eq "$KEY_REGEX"; then
    return 1
  fi
  if [[ -n "$AMB_KEY" ]] && printf '%s\n' "$t" | grep -Fq "$AMB_KEY"; then
    return 1
  fi
  return 0
}

# Validação inline do KEY_REGEX: o placeholder "sk-or-v1-..." NÃO pode casar;
# o 1º caractere base64 possível (alfanumérico, "_" ou "-") DEVE casar.
t_leak_regex() {
  local ph=0 ab=0 us=0 da=0
  printf '%s\n' 'sk-or-v1-...'     | grep -Eq "$KEY_REGEX" || ph=1
  printf '%s\n' 'sk-or-v1-AbCd...' | grep -Eq "$KEY_REGEX" && ab=1
  printf '%s\n' 'sk-or-v1-_XyZ...' | grep -Eq "$KEY_REGEX" && us=1
  printf '%s\n' 'sk-or-v1--XyZ...' | grep -Eq "$KEY_REGEX" && da=1
  if [[ $ph -eq 1 && $ab -eq 1 && $us -eq 1 && $da -eq 1 ]]; then
    ok "regex de detecção de chave (placeholder não casa; 1º char base64 casa: alfanumérico, _, -)"
  else
    fail "regex de detecção de chave (placeholder-ok=$ph alfanum=$ab underscore=$us dash=$da)"
  fi
}

# ---------------------------------------------------------------------------
# 1. bash -n em todos os .sh
# ---------------------------------------------------------------------------
t_syntax() {
  local f rc=0 msg=""
  for f in "$ROOT"/scripts/*.sh "$ROOT"/examples/*.sh "$SMOKE"; do
    [[ -f "$f" ]] || continue
    if err="$(bash -n "$f" 2>&1)"; then
      msg+="  ok   bash -n $f\n"
    else
      rc=1
      msg+="  FAIL bash -n $f\n$err\n"
    fi
  done
  if [[ $rc -eq 0 ]]; then
    ok "bash -n em todos os .sh"
    printf '%b' "$msg"
  else
    fail "bash -n em todos os .sh"
    printf '%b' "$msg"
  fi
}

# ---------------------------------------------------------------------------
# 2. python3 -m py_compile em examples/quickstart.py
# ---------------------------------------------------------------------------
t_pycompile() {
  # PYTHONPYCACHEPREFIX: grava o .pyc fora da worktree (o __pycache__/
  # existente é versionado; não queremos sujar o git status).
  local cache
  cache="$(mktemp -d)"
  if PYTHONPYCACHEPREFIX="$cache" python3 -m py_compile "$ROOT/examples/quickstart.py" 2>&1; then
    ok "python3 -m py_compile examples/quickstart.py"
  else
    fail "python3 -m py_compile examples/quickstart.py"
  fi
  rm -rf "$cache"
}

# ---------------------------------------------------------------------------
# 3. jq -e . em examples/router-example.json
# ---------------------------------------------------------------------------
t_json() {
  if jq -e . "$ROOT/examples/router-example.json" >/dev/null 2>&1; then
    ok "jq -e . examples/router-example.json"
  else
    fail "jq -e . examples/router-example.json"
  fi
}

# ---------------------------------------------------------------------------
# 4. dry-run de cada comando, sem chave e sem --dry-run
#    (saída deve ter aviso de dry-run + linha do curl = nada foi enviado)
# ---------------------------------------------------------------------------
dry_case() {
  local name="$1"; shift
  run_cli "$name" "$@"
  local t="dry-run sem chave: $name${*:+ }$*"
  if [[ $RC -ne 0 ]]; then
    fail "$t (exit $RC, esperado 0)"
    printf '%s\n' "$OUT" | head -3
    return
  fi
  if [[ "$OUT" != *"Modo dry-run"* || "$OUT" != *"  curl "* ]]; then
    fail "$t (saída sem aviso de dry-run ou sem a linha do curl)"
    printf '%s\n' "$OUT" | head -5
    return
  fi
  if ! no_key_leak "$OUT"; then
    fail "$t (VAZOU chave na saída!)"
    return
  fi
  ok "$t"
}

# ---------------------------------------------------------------------------
# 4b. --help e sem argumentos (usage; nada de dry-run/curl)
# ---------------------------------------------------------------------------
usage_case() {
  local mode="$1"
  if [[ "$mode" == "help" ]]; then
    run_cli --help
    local t="--help (usage)"
  else
    run_cli
    local t="sem argumentos (usage)"
  fi
  if [[ $RC -ne 0 ]]; then
    fail "$t (exit $RC, esperado 0)"
    return
  fi
  if [[ "$OUT" != *"Uso:"* || "$OUT" == *"Curl que seria executado"* ]]; then
    fail "$t (saída não é o usage, ou entrou em dry-run de rede)"
    printf '%s\n' "$OUT" | head -3
    return
  fi
  if ! no_key_leak "$OUT"; then
    fail "$t (VAZOU chave na saída!)"
    return
  fi
  ok "$t"
}

# ---------------------------------------------------------------------------
# 5. exit 1 com mensagem acionável
# ---------------------------------------------------------------------------
err_case() {
  local desc="$1" needle="$2"; shift 2
  run_cli "$@"
  local t="exit 1: $desc"
  if [[ $RC -eq 1 && "$OUT" == *"$needle"* ]]; then
    ok "$t"
  else
    fail "$t (exit=$RC, saída não contém '$needle')"
    printf '%s\n' "$OUT" | head -3
  fi
}

# ---------------------------------------------------------------------------
# 6. suggest --dry-run → payload JSON válido (extrair e jq -e)
# ---------------------------------------------------------------------------
t_suggest_json() {
  run_cli suggest "extraia os campos do contrato em JSON" --dry-run
  if [[ $RC -ne 0 ]]; then
    fail "suggest --dry-run imprime payload JSON válido (exit $RC)"
    return
  fi
  if ! no_key_leak "$OUT"; then
    fail "suggest --dry-run imprime payload JSON válido (VAZOU chave!)"
    return
  fi
  # Extrai o bloco entre a linha "== Payload sugerido ..." e o marcador
  # seguinte ("(payload não enviado..." ou "== Enviando..."). A linha
  # "(modelo por heurística ..." vem antes do JSON e é ignorada.
  local payload
  payload="$(printf '%s\n' "$OUT" \
    | awk '/^== Payload sugerido/{f=1; next}
           f && /^\(modelo por heurística/{next}
           f && /^\(payload não enviado|^== Enviando/{f=0}
           f' \
    | grep -v '^$')"
  if [[ -z "$payload" ]]; then
    fail "suggest --dry-run imprime payload JSON válido (não consegui extrair o payload)"
    printf '%s\n' "$OUT" | head -8
    return
  fi
  if printf '%s\n' "$payload" | jq -e . >/dev/null 2>&1 \
     && printf '%s\n' "$payload" | jq -e 'has("model") and has("messages")' >/dev/null 2>&1; then
    ok "suggest --dry-run imprime payload JSON válido (jq -e)"
  else
    fail "suggest --dry-run imprime payload JSON válido (payload extraído não passa no jq -e)"
    printf '%s\n' "$payload" | head -8
  fi
}

# ---------------------------------------------------------------------------
# 7. (opcional) models --live --limit 1 sem chave → exit 0 com tabela
#    Só roda se a rede estiver disponível; offline = SKIP, não falha.
# ---------------------------------------------------------------------------
t_live() {
  local probe rc
  probe="$(curl -sS --max-time 8 -o /dev/null -w '%{http_code}' \
    https://openrouter.ai/api/v1/models 2>/dev/null)"
  rc=$?
  if [[ $rc -ne 0 || -z "$probe" ]]; then
    skip "models --live --limit 1 sem chave (rede indisponível)"
    return
  fi
  run_cli models --live --limit 1
  local t="models --live --limit 1 sem chave (rede ok)"
  if [[ $RC -eq 0 && "$OUT" == *"ID"* && "$OUT" == *"(exibidos"* ]]; then
    ok "$t"
  else
    fail "$t (exit=$RC; sem tabela na saída)"
    printf '%s\n' "$OUT" | head -5
  fi
}

# ---------------------------------------------------------------------------
# 8. dry-run EXPLÍCITO com chave no ambiente (sempre roda; não usa rede):
#    --dry-run deve simular MESMO com chave definida — nada é enviado e a
#    chave aparece mascarada na linha do curl. Pega a regressão "dry-run
#    com chave executa requisição real".
# ---------------------------------------------------------------------------
t_dry_run_with_key() {
  local fake_key='sk-or-v1-TESTONLYfakenokey1234567890'  # NUNCA imprimir o valor
  local orig="${OPENROUTER_API_KEY:-}"
  local t="models --dry-run --limit 1 com chave fictícia (dry-run ainda simula)"
  export OPENROUTER_API_KEY="$fake_key"
  OUT="$(env OPENROUTER_API_KEY="$fake_key" "$CLI" models --dry-run --limit 1 2>&1)"
  RC=$?
  # restaura o ambiente do suite (chave original ou remove a fictícia)
  if [[ -n "$orig" ]]; then
    export OPENROUTER_API_KEY="$orig"
  else
    unset OPENROUTER_API_KEY
  fi
  if [[ $RC -ne 0 ]]; then
    fail "$t (exit $RC, esperado 0)"
    printf '%s\n' "$OUT" | head -3
    return
  fi
  if [[ "$OUT" == *"$fake_key"* ]]; then
    fail "$t (VAZOU a chave fictícia na saída!)"
    return
  fi
  if [[ "$OUT" != *"  curl "* || "$OUT" != *"chave mostrada como placeholder"* ]]; then
    fail "$t (saída sem linha do curl com a chave mascarada)"
    printf '%s\n' "$OUT" | head -5
    return
  fi
  if [[ "$OUT" != *"dry-run"* ]]; then
    fail "$t (saída sem o aviso de dry-run)"
    printf '%s\n' "$OUT" | head -5
    return
  fi
  ok "$t"
}

# ---------------------------------------------------------------------------
main() {
  echo "== smoke tests: openrouter-agent-skill =="
  t_syntax
  t_pycompile
  t_json
  t_leak_regex

  dry_case models
  dry_case providers openai/gpt-4o
  dry_case prices openai/gpt-4o
  dry_case tps openai/gpt-4o
  dry_case suggest "extraia os campos do contrato em JSON"
  dry_case chat --model openai/gpt-4o
  dry_case key
  dry_case credits

  usage_case help
  usage_case none

  err_case "comando desconhecido" "comando desconhecido 'frobnicate'" frobnicate
  err_case "providers sem modelo" "providers: informe o modelo" providers
  err_case "chat sem --model" "chat: informe --model" chat

  t_suggest_json
  t_dry_run_with_key
  t_live

  local total=$((PASS + FAIL + SKIP))
  printf '\n%d testes, %d falhas' "$total" "$FAIL"
  [[ $SKIP -gt 0 ]] && printf ' (skip: %d)' "$SKIP"
  printf '\n'
  [[ $FAIL -eq 0 ]]
}

main "$@"
