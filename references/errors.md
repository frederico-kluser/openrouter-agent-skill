# OpenRouter — Erros, rate limits e chave free

> **Quando ler:** ao tratar erros de requisição — decodificar o envelope de erro, mapear `error_type` → HTTP → ação, retries com backoff, rate limits de modelos `:free`, chave free (`is_free_tier`) e o fluxo de créditos insuficientes (402).
> **Fonte:** https://openrouter.ai/docs/api_reference/errors-and-debugging, /docs/api_reference/limits e openapi.yaml.

## TOC (nesta página)
1. Envelope de erro
2. Códigos HTTP
3. Tabela principal: error_type → HTTP → ação
4. Rate limits e chave free
5. Retries recomendados
6. Erros em streaming
7. Fluxo 402 e monitoramento de créditos

## 1. Envelope de erro

```json
{
  "error": {
    "code": 429,
    "message": "Rate limit exceeded",
    "metadata": { "error_type": "rate_limit_exceeded" }
  }
}
```

- O HTTP status é código de erro real **apenas se** a request original era inválida ou a chave/créditos são insuficientes; caso contrário o status é `200` e o erro do modelo aparece no body/SSE (ver seção 6).
- `metadata` pode conter: `error_type`, `provider_code` (código original do provider, quando não-500), `reasons`, `flagged_input` (até 100 chars), `provider_name`, `model_slug` (moderação/guardrails).
- **Use `error_type`, não só o HTTP status, para distinguir categorias** — status é ambíguo (ex.: vários 400s diferentes).

## 2. Códigos HTTP

| Code | Significado (docs) |
|---|---|
| 400 | Bad Request (params inválidos/faltando, CORS) |
| 401 | Invalid credentials (OAuth expirado, chave inválida/desabilitada) |
| 402 | "Your account or API key has insufficient credits. Add more credits and retry the request." |
| 403 | Forbidden (permissões insuficientes, guardrail, flag de moderação) |
| 404 | Resource not found (modelo inexistente **ou** provider indisponível dado as restrições) |
| 408 | "Your request timed out" |
| 412 | Precondition failed |
| 413 | Payload too large |
| 422 | Unprocessable |
| 429 | "You are being rate limited" (plataforma OU provider upstream) |
| 500 | Internal server error (mensagem upstream mascarada) |
| 502 | "Your chosen model is down or we received an invalid response from it" |
| 503 | "There is no available model provider that meets your routing requirements" |
| 504 | Gateway timeout (provider não respondeu a tempo) |

## 3. Tabela principal: error_type → HTTP → ação

| error_type | HTTP | Significado | Ação |
|---|---|---|---|
| `context_length_exceeded` | 400 | Tokens combinados (prompt + saída prevista) excedem a janela | Reduzir/truncar o prompt ou trocar para modelo com janela maior; lembrar que `max_tokens` máx = `context_length − prompt_length` |
| `max_tokens_exceeded` | 400 | Bateu no `max_tokens`/`max_completion_tokens` | Aumentar o teto (respeitando context − prompt) ou reduzir a saída esperada |
| `token_limit_exceeded` | 400 | Orçamento do OpenRouter (ex.: credit cap da chave) | Subir/aguardar o cap da chave (`GET /api/v1/key`) |
| `string_too_long` | 400 | String de entrada longa demais | Encurtar a string |
| `authentication` | 401 | "The API key is missing, invalid, or revoked" | Revisar/recriar a chave em https://openrouter.ai/settings/keys |
| `permission_denied` | 403 | Permissões insuficientes | Verificar permissões/guardrails da conta |
| `payment_required` | 402 | Créditos insuficientes | Adicionar créditos ou aguardar reset do limite (ver seção 7) |
| `rate_limit_exceeded` | 429 | Rate limit (plataforma ou provider) | Backoff exponencial + honrar `Retry-After` (implementar manualmente — SDKs não honram sozinhos); `provider_code` identifica o provider |
| `provider_overloaded` | 503 | "Temporarily overloaded" | Retry após pequeno delay; fallback routing pode trocar de provider |
| `provider_unavailable` | 502 | "Invalid or empty response" | Se fallback routing ativo, o OpenRouter pode retryar com outro provider; senão trocar de provider/modelo |
| `not_found` | 404 | Modelo não existe/não é alias **OU** nenhum provider atende as restrições de roteamento | Conferir slug (formato `author/slug`), variante e aliases; se havia `provider.only`/`max_price`/quantizações, relaxar |
| `invalid_request` | 400 | Params inválidos/faltando | Validar o body contra a API |
| `invalid_prompt` | 400 | Prompt inválido | Corrigir o prompt |
| `precondition_failed` | 412 | — | Verificar pré-condições do request |
| `payload_too_large` | 413 | Body grande demais | Reduzir payload |
| `unprocessable` | 422 | — | Verificar formato do request |
| `content_policy_violation` | 400 | Flag de moderação/guardrail | Ajustar o conteúdo; `model_slug`/`flagged_input` no metadata dão contexto |
| `refusal` | 400 | Modelo recusou responder | Ajustar o prompt |
| `invalid_image` / `image_too_large` / `image_too_small` / `unsupported_image_format` | 400 | Problemas com imagem de entrada | Validar formato/tamanho da imagem |
| `image_not_found` | 404 | Imagem não encontrada | Verificar URL |
| `image_download_failed` | 400 | Falha ao baixar imagem | Verificar URL/network |
| `server` | 500 | Erro interno (mensagem mascarada) | Retry com backoff; se persistir, reportar |
| `timeout` | 504 | Gateway timeout — provider não respondeu a tempo | Retry ou trocar de provider/modelo |
| `unmapped` | 500 | Erro não categorizado | Inspecionar `message`/`provider_code` |

## 4. Rate limits e chave free

- **Só variantes `:free` têm cap de requisições** (variantes pagas não têm cap no nível da plataforma). O limiar é em **créditos comprados (all time)**, não em dólares — `FREE_MODEL_CREDITS_THRESHOLD = 10`:

| Créditos comprados (total) | Requests/min | Requests/dia |
|---|---|---|
| Menos de 10 | 20 | 50 |
| 10 ou mais | 20 | 1000 |

- "Making additional accounts or API keys will not affect your rate limits, as we govern capacity globally" — mas modelos diferentes têm limites diferentes. Cloudflare DDoS protection bloqueia uso "dramatically exceeding reasonable usage".
- **Headers de rate limit:** respostas de sucesso NÃO incluem `X-RateLimit-*`; só quando o próprio OpenRouter responde `429` é que vêm `X-RateLimit-Limit`, `X-RateLimit-Remaining`, `X-RateLimit-Reset`. Quando todo provider tentado retornou retry hint, a resposta carrega `Retry-After`.
- **Chave free:** `GET /api/v1/key` → `is_free_tier` (boolean), `limit` (spending limit USD), `limit_remaining`, `limit_reset` (ex.: `'monthly'`), `usage_monthly`. Se `is_free_tier: true`, espere os limites acima nos modelos `:free` e avise o usuário antes de prometer volume.

## 5. Retries recomendados

- **"Retry with exponential backoff and honor the Retry-After header when present"** — 429 e 503 podem incluir `Retry-After` (segundos). **Nenhuma fonte oficial afirma que os SDKs (OpenAI, Anthropic, Vercel AI, OpenRouter) honram o header automaticamente** (o SDK OpenAI, por exemplo, não lê `Retry-After`) — implemente o retry com backoff exponencial + `Retry-After` manualmente na aplicação, inclusive com `fetch` puro.
- `provider_overloaded` → retry após um pequeno delay; `provider_unavailable` → o OpenRouter pode retryar com outro provider se fallback routing estiver habilitado.
- Resposta vazia (cold start) → retry simples ou trocar de provider/modelo. Nota: "you may still be charged for the prompt processing cost by the upstream provider, even if no content is generated" — a Zero-Completion Insurance cobre apenas zero completion tokens + finish reason blank/null OU finish reason `error` (ver `routing.md` seção 3.2).

## 6. Erros em streaming

- **Pré-stream:** erro HTTP normal; o OpenRouter pode ainda retryar silenciosamente com fallback.
- **Mid-stream** (HTTP 200 já enviado): o erro chega como evento SSE com `error` no topo do chunk e `choices[0].finish_reason: "error"`; o status HTTP permanece 200:

```json
{
  "id": "gen-abc123",
  "object": "chat.completion.chunk",
  "created": 1720000000,
  "model": "openai/gpt-4o",
  "provider": "openai",
  "error": { "code": 429, "message": "Rate limit exceeded", "metadata": { "error_type": "rate_limit_exceeded" } },
  "choices": [{ "index": 0, "delta": { "content": "" }, "finish_reason": "error" }]
}
```

Causas típicas: desconexão/timeout do provider, max_tokens/context durante geração, content filter de saída, overload.

## 7. Fluxo 402 e monitoramento de créditos

1. Recebeu `402 payment_required` → informe o usuário que há créditos insuficientes.
2. Diagnostique: `GET /api/v1/key` → `usage_monthly` vs `limit` (se o limite da chave é o gargalo) e `is_free_tier` (se conta free, considerar comprar créditos para destravar o teto diário).
3. `GET /api/v1/credits` (requer **management key**) → `data.total_credits` (comprados) / `data.total_usage` (usados), em USD.
4. Resolução: adicionar créditos em https://openrouter.ai/settings/credits, subir o cap da chave ou aguardar o reset (`limit_reset`).
5. Prevenção: monitorar `usage_monthly` e avisar quando se aproximar do limite.
