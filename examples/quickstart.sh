#!/usr/bin/env bash
# ============================================================================
# quickstart.sh — passo a passo comentado do uso da API OpenRouter com curl+jq
#
# A mesma mecânica que scripts/openrouter.sh automatiza, aqui didaticamente:
#   1. pré-requisitos (curl + jq)
#   2. variável de ambiente OPENROUTER_API_KEY (a chave NUNCA vai no código)
#   3. primeira chamada: curl com header Authorization: Bearer
#   4. leitura da resposta com jq
#   5. usage (tokens e custo) e o header X-Generation-Id
#   6. streaming (SSE) com `data: [DONE]`
#
# Sem OPENROUTER_API_KEY, roda em modo dry-run: mostra os comandos exatos
# que seriam executados (com placeholder) e sai com código 0.
#
# Dependências: curl e jq (nada mais).
# ============================================================================
set -euo pipefail

API_BASE="https://openrouter.ai/api/v1"
KEY="${OPENROUTER_API_KEY:-}"

if [[ -z "$KEY" ]]; then
  cat <<'EOF'
==> Modo dry-run: OPENROUTER_API_KEY não está definida.
    Para executar de verdade:
      1) Crie uma chave em https://openrouter.ai/keys
      2) export OPENROUTER_API_KEY=sk-or-v1-...
    Os comandos abaixo são exatamente o que este script executaria.
    ------------------------------------------------------------------
EOF
  TMP=$(mktemp)
  trap 'rm -f "$TMP"' EXIT
  echo "# 1. Chamada de chat (sem streaming), com a chave no header Bearer:"
  echo "curl -sS '$API_BASE/chat/completions' \\"
  echo "  -H 'Authorization: Bearer <OPENROUTER_API_KEY>' \\"
  echo "  -H 'Content-Type: application/json' \\"
  echo "  -H 'X-OpenRouter-Title: quickstart' \\"
  echo "  -d '{\"model\": \"openai/gpt-4o\", \"messages\": [{\"role\": \"user\", \"content\": \"Explique o que é o OpenRouter em uma frase.\"}]}' \\"
  echo "  -D headers.txt -o resposta.json"
  echo
  echo "# 2. Leitura da resposta com jq:"
  echo "jq -r '.choices[0].message.content' resposta.json"
  echo
  echo "# 3. Usage (tokens e custo em USD) e o X-Generation-Id:"
  echo "jq -r '.usage | \"prompt=\\(.prompt_tokens) completion=\\(.completion_tokens) cost=\\$\(.cost)\"' resposta.json"
  echo "grep -i '^x-generation-id:' headers.txt"
  echo
  echo "# 4. Streaming (SSE):"
  echo "curl -sS -N '$API_BASE/chat/completions' -H 'Authorization: Bearer <OPENROUTER_API_KEY>' \\"
  echo "  -H 'Content-Type: application/json' \\"
  echo "  -d '{\"model\": \"openai/gpt-4o\", \"stream\": true, \"messages\": [{\"role\": \"user\", \"content\": \"Conte uma piada curta.\"}]}'"
  echo "  # cada linha 'data: {...}' é um chunk; termina com 'data: [DONE]'"
  exit 0
fi

TMP=$(mktemp)
TMP_HDR=$(mktemp)
trap 'rm -f "$TMP" "$TMP_HDR"' EXIT

# ---------------------------------------------------------------------------
# 1. Primeira chamada: curl com o Bearer token (a chave vem do ambiente)
# ---------------------------------------------------------------------------
echo "==> 1. POST /chat/completions (sem streaming)"
curl -sS --max-time 120 "$API_BASE/chat/completions" \
  -H "Authorization: Bearer $KEY" \
  -H "Content-Type: application/json" \
  -H "X-OpenRouter-Title: quickstart" \
  -D "$TMP_HDR" -o "$TMP" \
  -d '{
    "model": "openai/gpt-4o",
    "messages": [
      {"role": "user", "content": "Explique o que é o OpenRouter em uma frase."}
    ]
  }'

# Erros vêm no envelope {error:{code,message,metadata:{error_type}}} — checar:
if jq -e '.error' "$TMP" >/dev/null 2>&1; then
  echo "Erro da API:"
  jq -r '.error | "  \(.code // "?") \(.metadata.error_type // "?") — \(.message)"' "$TMP"
  exit 1
fi

# ---------------------------------------------------------------------------
# 2. jq na resposta: conteúdo do assistant
# ---------------------------------------------------------------------------
echo "==> 2. Conteúdo (jq -r .choices[0].message.content)"
jq -r '.choices[0].message.content' "$TMP"
echo

# ---------------------------------------------------------------------------
# 3. Usage: tokens, custo (USD) e o header X-Generation-Id
# ---------------------------------------------------------------------------
echo "==> 3. Usage e X-Generation-Id"
jq -r '.usage | "prompt_tokens=\(.prompt_tokens) completion_tokens=\(.completion_tokens) total=\(.total_tokens) cost=$\(.cost)"' "$TMP"
jq -c '.usage.completion_tokens_details // null' "$TMP" | sed 's/^/completion_tokens_details: /' || true
GEN_ID=$(awk 'tolower($1)=="x-generation-id:" {gsub("\r","",$2); print $2}' "$TMP_HDR" | tail -1)
echo "X-Generation-Id: $GEN_ID"
echo "  -> estatísticas (tokens, custo, latência) via:"
echo "     curl -sS \"$API_BASE/generation?id=$GEN_ID\" -H \"Authorization: Bearer $KEY\" | jq ."
echo

# ---------------------------------------------------------------------------
# 4. Streaming: SSE cru; o uso chega no chunk final, antes de 'data: [DONE]'
# ---------------------------------------------------------------------------
echo "==> 4. Streaming (SSE): delta de conteúdo à medida que chega"
curl -sS -N --max-time 120 "$API_BASE/chat/completions" \
  -H "Authorization: Bearer $KEY" \
  -H "Content-Type: application/json" \
  -D "$TMP_HDR" \
  -d '{
    "model": "openai/gpt-4o",
    "stream": true,
    "messages": [
      {"role": "user", "content": "Conte uma piada curta sobre programadores."}
    ]
  }' | while IFS= read -r line; do
    case "$line" in
      'data: [DONE]') break ;;
      'data: '*)
        delta=$(printf '%s' "${line#data: }" | jq -r '.choices[0].delta.content // empty' 2>/dev/null || true)
        [[ -n "$delta" ]] && printf '%s' "$delta"
        ;;
      ':'*) : ;; # comentário SSE (ex.: ": OPENROUTER PROCESSING") — ignorar
    esac
  done
echo
echo "==> Fim. Lembre: a chave vive em OPENROUTER_API_KEY — nunca no código,"
echo "    nunca em commits (o OpenRouter é parceiro de secret scanning do GitHub)."
