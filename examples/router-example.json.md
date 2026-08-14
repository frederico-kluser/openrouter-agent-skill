# router-example.json — payload completo de roteamento, campo a campo

Este arquivo documenta o payload em `router-example.json`: um exemplo **completo e válido** de roteamento + structured outputs para `POST /api/v1/chat/completions`. O JSON é validável com `jq -e .` (saída 0). Se você alterar o payload, revalide: `jq -e . examples/router-example.json`.

```json
{
  "model": "anthropic/claude-3.5-sonnet",
  "provider": {
    "order": ["anthropic", "openai", "google-ai-studio"],
    "allow_fallbacks": true,
    "max_price": {
      "prompt": 5,
      "completion": 15
    },
    "quantizations": ["fp8", "fp16"]
  },
  "plugins": [
    {
      "id": "response-healing"
    }
  ],
  "response_format": {
    "type": "json_schema",
    "json_schema": {
      "name": "analysis_result",
      "strict": true,
      "schema": {
        "type": "object",
        "properties": {
          "summary": { "type": "string" },
          "confidence": { "type": "number" },
          "tags": { "type": "array", "items": { "type": "string" } }
        },
        "required": ["summary", "confidence", "tags"],
        "additionalProperties": false
      }
    }
  },
  "messages": [
    {
      "role": "user",
      "content": "Analise o texto abaixo e devolva um JSON conforme o schema declarado em response_format: resumo, confiança (0-1) e tags.\n\nTEXTO: O OpenRouter é um gateway de API que unifica centenas de modelos de IA sob um único endpoint compatível com a API OpenAI, com roteamento automático entre providers por preço, latência e disponibilidade."
    }
  ],
  "max_tokens": 512,
  "temperature": 0
}
```

## Campo a campo

### `model`
O modelo a usar, no formato `autor/slug` (ex.: `anthropic/claude-3.5-sonnet`). Aceita sufixos de variante (`:free`, `:nitro`, `:extended`...) e aliases `~`. Veja `openrouter.sh models --query <termo>` para descobrir IDs reais.

### `provider` — preferências de roteamento (só OpenRouter)

| Campo | Valor aqui | Semântica |
|---|---|---|
| `order` | `["anthropic", "openai", "google-ai-studio"]` | **Ordem estrita de tentativa** entre os slugs listados. Com `order` definido, o load balancing default (estocástico por preço, peso ~ 1/preço²) é desligado. Use slugs `tag` (o identificador é `tag`, não `provider_id`). |
| `allow_fallbacks` | `true` | Permite providers de backup quando o primário falha (default da API: `true`). `false` garante que só o top provider sirva a request. |
| `max_price` | `{"prompt": 5, "completion": 15}` | **Teto estrito de preço em USD por 1 MILHÃO de tokens** (prompt ≤ $5/M, completion ≤ $15/M). Ao contrário dos thresholds de performance, `max_price` pode impedir a request de rodar. Combina bem com `sort`. |
| `quantizations` | `["fp8", "fp16"]` | Filtro de quantização dos endpoints. Enum oficial: `int4, int8, fp4, mxfp4, nvfp4, fp6, fp8, mxfp8, fp16, bf16, fp32, unknown` — **`q8_0` NÃO existe** no enum oficial. |

Outros campos úteis de `provider` (não usados aqui): `only` (allow-list de slugs; força provider), `ignore` (deny-list), `sort` (`"price"`/`"throughput"`/`"latency"`/`"exacto"` — desliga load balancing), `preferred_min_throughput` / `preferred_max_latency` (preferências, não garantias), `data_collection: "deny"`, `zdr: true`, `require_parameters: true`.

### `plugins`
`[{"id": "response-healing"}]` — corrige automaticamente JSON malformado vindo do modelo (brackets faltando, trailing commas, code fences). **Restrições:** só ativa com `response_format` do tipo `json_schema` ou `json_object`; **só funciona sem streaming**. (Não confundir com o plugin `web`, que está deprecated em favor da server tool `openrouter:web_search`.)

### `response_format`
Structured outputs no formato OpenAI:

- `{"type": "json_object"}` — modo JSON simples.
- `{"type": "json_schema", "json_schema": {"name", "strict", "schema"}}` — schema validado. `strict: true` exige suporte a structured outputs no **endpoint** escolhido (verifique com `supported_parameters`; para garantir, use `provider.require_parameters: true`).

Aqui: schema `analysis_result` com `summary` (string), `confidence` (number) e `tags` (array de strings), todos obrigatórios, sem propriedades extras — o formato esperado por `strict: true`.

### `messages`
Formato OpenAI padrão. Aqui há só o `user`; em uso real, mantenha o histórico (system/assistant/...).

### `max_tokens` e `temperature`
`max_tokens` = teto de tokens de saída (respeite `context_length` do modelo e `max_completion_tokens` do provider). `temperature: 0` para tarefas de extração determinísticas.

## Como testar

Com o CLI da skill (payload não enviado em dry-run; para enviar de verdade precisa de chave):

```bash
./scripts/openrouter.sh chat --model anthropic/claude-3.5-sonnet --dry-run
# e, para ver os providers/quantizações/preços reais do modelo:
./scripts/openrouter.sh providers anthropic/claude-3.5-sonnet
./scripts/openrouter.sh prices anthropic/claude-3.5-sonnet
```

Com curl puro:

```bash
export OPENROUTER_API_KEY=sk-or-v1-...
curl -sS https://openrouter.ai/api/v1/chat/completions \
  -H "Authorization: Bearer $OPENROUTER_API_KEY" \
  -H "Content-Type: application/json" \
  -d @examples/router-example.json
```

Observação: o suporte a `json_schema` + `strict` é **por endpoint**; se o provider selecionado não suportar, a API ignora ou degrada a garantia. Confira com `providers <modelo>` quais endpoints anunciam `structured_outputs`.
