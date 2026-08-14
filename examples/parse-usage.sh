#!/usr/bin/env bash
# ============================================================================
# parse-usage.sh — lê usage (cost, completion_tokens_details.reasoning_tokens,
# cost_details) e o header X-Generation-Id de uma resposta SALVA.
#
# Uso:
#   parse-usage.sh [resposta.json] [headers.txt]
#
# Sem argumentos, usa uma resposta de exemplo embutida (modo dry-run, sem
# chave, sem rede). Para gerar os arquivos reais a partir da API:
#
#   export OPENROUTER_API_KEY=sk-or-v1-...
#   curl -sS https://openrouter.ai/api/v1/chat/completions \
#     -H "Authorization: Bearer $OPENROUTER_API_KEY" \
#     -H "Content-Type: application/json" \
#     -D headers.txt -o resposta.json \
#     -d '{"model":"openai/gpt-4o","messages":[{"role":"user","content":"Oi!"}]}'
#   ./parse-usage.sh resposta.json headers.txt
#
# Extras: parse-usage.sh --generation-id <ID> consulta GET /api/v1/generation
# (estatísticas completas da geração); sem chave, mostra o curl em dry-run.
# ============================================================================
set -euo pipefail

API_BASE="https://openrouter.ai/api/v1"
RESP=""
HDRS=""

# --- modo opcional: --generation-id (estatísticas de uma geração) -----------
if [[ "${1:-}" == "--generation-id" ]]; then
  GID="${2:-}"
  [[ -z "$GID" ]] && { echo "Erro: informe o ID após --generation-id (veja X-Generation-Id na resposta)." >&2; exit 1; }
  if [[ -z "${OPENROUTER_API_KEY:-}" ]]; then
    echo "Modo dry-run: OPENROUTER_API_KEY não definida — nada seria enviado."
    echo "  Para executar de verdade: export OPENROUTER_API_KEY=sk-or-v1-..."
    echo "Curl que seria executado:"
    echo "  curl -sS '$API_BASE/generation?id=$GID' -H 'Authorization: Bearer <OPENROUTER_API_KEY>'"
    exit 0
  fi
  echo "==> GET /api/v1/generation?id=$GID"
  curl -sS --max-time 60 "$API_BASE/generation?id=$GID" \
    -H "Authorization: Bearer $OPENROUTER_API_KEY" | jq .
  exit $?
fi

RESP="${1:-}"
HDRS="${2:-}"
EMBEDDED=0

if [[ -z "$RESP" ]]; then
  echo "==> Sem argumentos: usando resposta de exemplo embutida (dry-run)."
  echo "    Para usar uma resposta real: ./parse-usage.sh resposta.json headers.txt"
  echo
  RESP=$(mktemp)
  trap 'rm -f "$RESP"' EXIT
  cat > "$RESP" <<'EOF'
{
  "id": "gen-3bhGkxlo4XFrqiabUM7NDtwDzWwG",
  "object": "chat.completion",
  "created": 1755190000,
  "model": "openai/gpt-4o",
  "choices": [
    {
      "index": 0,
      "message": { "role": "assistant", "content": "O OpenRouter unifica centenas de modelos sob um só endpoint." },
      "finish_reason": "stop",
      "native_finish_reason": "stop"
    }
  ],
  "usage": {
    "prompt_tokens": 152,
    "completion_tokens": 89,
    "total_tokens": 241,
    "prompt_tokens_details": { "cached_tokens": 120 },
    "completion_tokens_details": { "reasoning_tokens": 22 },
    "cost": 0.000412,
    "cost_details": {
      "upstream_inference_prompt_cost": 0.00011,
      "upstream_inference_completions_cost": 0.00029,
      "upstream_inference_cost": 0.0004
    }
  }
}
EOF
  EMBEDDED=1
fi

[[ -f "$RESP" ]] || { echo "Erro: arquivo '$RESP' não encontrado." >&2; exit 1; }

echo "==> Conteúdo (choices[0].message.content)"
jq -r '.choices[0].message.content // "(vazio)"' "$RESP"
echo

echo "==> usage: tokens"
jq -r '.usage | "  prompt_tokens=\(.prompt_tokens // "?") completion_tokens=\(.completion_tokens // "?") total_tokens=\(.total_tokens // "?")"' "$RESP"
echo

echo "==> usage.cost — custo em USD da requisição"
jq -r '.usage.cost // "indisponível"' "$RESP"
echo

echo "==> completion_tokens_details.reasoning_tokens"
jq -r '.usage.completion_tokens_details.reasoning_tokens // 0' "$RESP"
echo "  (reasoning conta como token de saída e é cobrado como tal.)"
echo

echo "==> usage.cost_details — custos upstream (por camada)"
jq -c '.usage.cost_details // null' "$RESP" | sed 's/^/  /'
echo

echo "==> prompt_tokens_details (cache)"
jq -r '.usage.prompt_tokens_details // null' "$RESP" | sed 's/^/  /'
echo

if [[ -n "$HDRS" ]]; then
  [[ -f "$HDRS" ]] || { echo "Erro: arquivo de headers '$HDRS' não encontrado." >&2; exit 1; }
  echo "==> X-Generation-Id (header da resposta)"
  GID=$(awk 'tolower($1)=="x-generation-id:" {gsub("\r","",$2); print $2}' "$HDRS" | tail -1)
  if [[ -n "$GID" ]]; then
    echo "  $GID"
    echo "  -> estatísticas completas (tokens, custo, latência, cache discount):"
    if [[ -n "${OPENROUTER_API_KEY:-}" ]]; then
      echo "     curl -sS '$API_BASE/generation?id=$GID' -H \"Authorization: Bearer \$OPENROUTER_API_KEY\" | jq ."
    else
      echo "     curl -sS '$API_BASE/generation?id=$GID' -H 'Authorization: Bearer <OPENROUTER_API_KEY>' | jq ."
    fi
  else
    echo "  (header X-Generation-Id não encontrado no arquivo de headers)"
  fi
fi

if [[ "$EMBEDDED" == "1" ]]; then
  echo
  echo "==> Observações sobre o exemplo embutido:"
  echo "  - o X-Generation-Id é um header HTTP, não um campo do body — por isso o"
  echo "    exemplo usa 'headers.txt' separado, salvo com curl -D."
  echo "  - para ver os dois juntos de verdade, faça uma requisição real (instruções no topo)."
fi
