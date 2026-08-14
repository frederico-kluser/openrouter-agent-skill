# API OpenRouter — endpoints, modelos, usage e observabilidade

> **Quando ler:** antes de fazer qualquer chamada à API — endpoints, query params e filtros de `/models`, exemplos de resposta reais, e como ler `usage`/metadata. Para roteamento (objeto `provider` etc.) veja `routing.md`; para erros veja `errors.md`; para integração veja `integrations.md`.
>
> **Base URL:** `https://openrouter.ai/api/v1` — todos os endpoints carregam o prefixo `/v1`.
> **Auth:** header `Authorization: Bearer <OPENROUTER_API_KEY>` (chave criada em https://openrouter.ai/keys).
> **Versioning:** uma única versão estável (`v1`), escolhida pelo path; não há version headers nem pinning por data; mudanças que quebram compatibilidade são anunciadas em https://openrouter.ai/docs/changelog.

## TOC (nesta página)
1. Tabela de endpoints
2. GET /api/v1/models — listar modelos
3. GET /api/v1/models/count — contar modelos
4. GET /api/v1/model/{author}/{slug} — detalhe de UM modelo (singular)
5. GET /api/v1/models/{author}/{slug}/endpoints — providers por modelo
6. GET /api/v1/key e GET /api/v1/credits
7. POST /api/v1/chat/completions — requisição principal
8. POST /api/v1/messages — compat Anthropic
9. Parâmetros de sampling
10. Usage e observabilidade
11. Dicas de consulta (filtros e ordenação em um lugar)

## 1. Tabela de endpoints

| Método | Path | Propósito |
|---|---|---|
| GET | `/api/v1/models` | Listar todos os modelos com propriedades (paginação `offset`/`limit`) |
| GET | `/api/v1/models/count` | Contar modelos (filtro `output_modalities`) |
| GET | `/api/v1/model/{author}/{slug}` | Detalhe de UM modelo — **`model` no singular** (ver seção 4) |
| GET | `/api/v1/models/{author}/{slug}/endpoints` | Providers que servem o modelo: preços, throughput e latência por provider |
| GET | `/api/v1/models/user` | Modelos com BYOK (provider keys do usuário) |
| GET | `/api/v1/credits` | Créditos comprados/usados — **requer management key** |
| GET | `/api/v1/key` | Informações e limites da chave atual |
| POST | `/api/v1/chat/completions` | Chat completions (endpoint principal, compat OpenAI) |
| POST | `/api/v1/messages` | Formato Anthropic Messages API (texto, imagens, PDFs, tools, extended thinking) |
| POST | `/api/v1/responses` | OpenResponses API format |
| GET | `/api/v1/generation?id=$ID` | Estatísticas de uma geração (tokens e custo); o ID vem no header `X-Generation-Id` |

Obs.: `/api/v1/completions` (legado) não existe no OpenAPI spec atual — os docs só o citam como "legacy Completions"; não prometa suporte. Existem ainda `/api/v1/embeddings`, `/api/v1/audio/*`, `/api/v1/images`, `/api/v1/rerank`, `/api/v1/files`, `/api/v1/guardrails`, `/api/v1/presets`, `/api/v1/keys` (gestão de chaves), `/api/v1/providers`, fora do escopo desta skill.

## 2. GET /api/v1/models — listar modelos

Lista todos os modelos com `id` no formato `author/slug` (ex.: `openai/gpt-4o`), preços, janela de contexto, parâmetros suportados e mais.

**Query params** (fonte: openapi.yaml): `offset`, `limit`, `category`, `supported_parameters`, `output_modalities`, `input_modalities`, `sort`, `q`, `context`, `min_price`, `max_price`, `min_output_price`, `max_output_price`, `min_age_days`, `max_age_days`, `min_agentic_index`, `max_agentic_index`, `min_coding_index`, `max_coding_index`, `min_intelligence_index`, `max_intelligence_index`, `min_tool_success_rate`, `max_tool_success_rate`, `region`, `zdr`, `arch`, `model_authors`, `providers`, `distillable`.

- `output_modalities` — separado por vírgula ou `"all"`: `text` (padrão), `image`, `audio`, `embeddings`, `all`.
- `supported_parameters` — ex.: `?supported_parameters=tools` para achar modelos com tool calling; `structured_outputs`, `reasoning` etc.
- `sort` — enum completo: `most-popular`, `newest`, `top-weekly`, `pricing-low-to-high`, `pricing-high-to-low`, `context-high-to-low`, `throughput-high-to-low`, `latency-low-to-high`, `intelligence-high-to-low`, `coding-high-to-low`, `agentic-high-to-low`, `design-arena-elo-high-to-low`. Modelos sem dados para a dimensão ordenam por último.
- Paginação: `offset` + `limit`; `limit` default **500**, máximo **1000**; omitindo ambos, retorna a **lista completa**; itere com `links.next`. (Não existe `per_page` nem `cursor`.)

**Exemplo de resposta** (abreviado):

```json
{
  "data": [
    {
      "id": "openai/gpt-4",
      "canonical_slug": "openai/gpt-4",
      "name": "GPT-4",
      "created": 1692901234,
      "description": "GPT-4 is a large multimodal model...",
      "context_length": 8192,
      "architecture": {
        "input_modalities": ["text"],
        "output_modalities": ["text"],
        "instruct_type": "chatml",
        "modality": "text->text",
        "tokenizer": "GPT"
      },
      "pricing": {
        "prompt": "0.00003",
        "completion": "0.00006",
        "request": "0",
        "image": "0"
      },
      "top_provider": {
        "context_length": 8192,
        "max_completion_tokens": 4096,
        "is_moderated": true
      },
      "per_request_limits": null,
      "supported_parameters": ["temperature", "top_p", "max_tokens"],
      "default_parameters": null,
      "expiration_date": null,
      "knowledge_cutoff": null
    }
  ],
  "total_count": 150,
  "links": { "next": "https://openrouter.ai/api/v1/models?offset=500" }
}
```

**Campos do objeto Model** (o que interessa na prática):

| Campo | Tipo | Como usar |
|---|---|---|
| `id` | string | Identificador usado em `model` na request (ex.: `openai/gpt-4`) |
| `canonical_slug` | string | Slug permanente que nunca muda |
| `name` | string | Nome exibível |
| `created` | integer | Unix timestamp de quando entrou no OpenRouter |
| `context_length` | integer | Janela máxima de contexto em tokens (a saída máxima = context − prompt) |
| `architecture` | object | `input_modalities`, `output_modalities`, `instruct_type`, `modality`, `tokenizer` |
| `pricing` | object | **Strings USD POR TOKEN** (`prompt`, `completion`, `request`, `image`, `audio`, `input_cache_read`, `input_cache_write`, `internal_reasoning`, `web_search`, `discount`, `overrides`...) — o preço COBRADO é o do provider selecionado (ver seção 5), não necessariamente o de lista |
| `top_provider` | object | `context_length`, `max_completion_tokens`, `is_moderated` do provider principal |
| `per_request_limits` | object \| null | `prompt_tokens`/`completion_tokens` — limites de tokens por requisição (null = sem limite) |
| `supported_parameters` | array | Parâmetros que o modelo aceita (ex.: `tools`, `tool_choice`, `max_tokens`, `temperature`, `reasoning`, `structured_outputs`, `response_format`, `seed`) |
| `reasoning` | object \| null | `supported_efforts`, `default_effort`, `default_enabled`, `supports_max_tokens`, `mandatory` |
| `default_parameters` | object \| null | Parâmetros default do modelo |
| `expiration_date` | string \| null | Data de deprecação do endpoint do modelo (null = não deprecado) |
| `benchmarks` | object \| null | Rankings (ex.: Design Arena: `arena`, `category`, `elo`, `win_rate`, `rank`) |
| `links` | object | Ex.: `details: "/api/v1/models/openai/gpt-4/endpoints"` |
| `alias_target` | object \| null | Modelo concreto alvo de um alias `~latest` |

Não existe campo `limits` top-level no modelo: limites ficam em `context_length`, `per_request_limits` e `top_provider.{context_length, max_completion_tokens}`.

## 3. GET /api/v1/models/count — contar modelos

Resposta: `{ "data": { "count": 411 } }` (411 verificado em 2026-08-14). Filtro disponível: `output_modalities`. Use para responder "quantos modelos o OpenRouter tem?" em vez de chutar números.

## 4. GET /api/v1/model/{author}/{slug} — detalhe de UM modelo (singular)

- **Path singular:** `/api/v1/model/{author}/{slug}` — atenção: `model` no SINGULAR (o plural é para listagem e `/endpoints`).
- Resolve aliases automaticamente (ex.: `anthropic/claude-3-5-sonnet` → `anthropic/claude-3.5-sonnet`) e aceita sufixos de variante (`:free`, `:thinking`, `:extended`, `:nitro`, `:online` — ex.: `openai/gpt-4:free`).
- Retorna `404` se o modelo não existe e não é alias.
- Resposta: o mesmo objeto Model da seção 2, envolto em `data`.

## 5. GET /api/v1/models/{author}/{slug}/endpoints — providers por modelo

Resposta: `{ "data": { "id", "name", "description", "architecture", "created", "endpoints": [...] } }`. Use para escolher/forçar provider, comparar preço, tokens por segundo e latência.

**Exemplo de item de `endpoints`:**

```json
{
  "context_length": 8192,
  "latency_last_30m": { "p50": 0.25, "p75": 0.35, "p90": 0.48, "p99": 0.85 },
  "max_completion_tokens": 4096,
  "max_prompt_tokens": 8192,
  "model_id": "openai/gpt-4",
  "model_name": "GPT-4",
  "name": "OpenAI: GPT-4",
  "pricing": { "completion": "0.00006", "image": "0", "prompt": "0.00003", "request": "0" },
  "provider_name": "OpenAI",
  "quantization": "fp16",
  "status": 0,
  "supported_parameters": ["temperature", "top_p", "max_tokens"],
  "supports_implicit_caching": true,
  "tag": "openai",
  "throughput_last_30m": { "p50": 45.2, "p75": 38.5, "p90": 28.3, "p99": 15.1 },
  "uptime_last_1d": 99.8,
  "uptime_last_30m": 99.5,
  "uptime_last_5m": 100
}
```

**Campos que importam:**

| Campo | O que é |
|---|---|
| `provider_name` | Nome exibível do provider (ex.: "OpenAI") |
| `tag` | **Slug do provider** (ex.: `openai`) — é o valor usado em `provider.order`/`provider.only` (não existe `provider_id`) |
| `quantization` | Nível: `int4`, `int8`, `fp4`, `mxfp4`, `nvfp4`, `fp6`, `fp8`, `mxfp8`, `fp16`, `bf16`, `fp32`, `unknown` |
| `throughput_last_30m` | **Tokens por segundo** em percentis p50/p75/p90/p99 (janela rolante de 30 min) |
| `latency_last_30m` | Latência em **segundos**, percentis p50/p75/p90/p99 |
| `uptime_last_5m` / `uptime_last_30m` / `uptime_last_1d` | % de uptime |
| `pricing` | **Preço POR TOKEN por provider** (strings USD): prompt/completion/request/image — o que será cobrado de fato |
| `context_length`, `max_prompt_tokens`, `max_completion_tokens` | Limites do endpoint — **variam por provider** |
| `supports_implicit_caching` | Caching implícito do provider |
| `status` | Inteiro sem enum documentado no spec |

## 6. GET /api/v1/key e GET /api/v1/credits

- `GET /api/v1/key` — limites da chave: `label`, `limit` (spending limit em USD), `limit_remaining`, `limit_reset` (ex.: `'monthly'`), `usage`, `usage_daily`, `usage_weekly`, `usage_monthly` (USD), `is_free_tier`, `is_management_key`, `expires_at`, `rate_limit` (deprecated — ignore). Use para monitorar consumo (`usage_monthly` vs `limit`).
- `GET /api/v1/credits` — **requer management key**. Resposta: `{ "data": { "total_credits": 100.5, "total_usage": 25.75 } }` — créditos comprados e usados, em USD.

## 7. POST /api/v1/chat/completions — requisição principal

Formato OpenAI (`messages`) ou `prompt` puro (resposta com `text` no choice). Parâmetros extras do OpenRouter vão via `extra_body` no SDK OpenAI (ver `integrations.md`): `models`, `route` (deprecated), `provider`, `plugins`, `reasoning`, `verbosity`, `web_search_options`, `debug`.

**Resposta não-streaming:**

```json
{
  "id": "gen-abc123",
  "object": "chat.completion",
  "created": 1720000000,
  "model": "openai/gpt-4o",
  "choices": [
    {
      "index": 0,
      "message": { "role": "assistant", "content": "..." },
      "finish_reason": "stop",
      "native_finish_reason": "stop"
    }
  ],
  "usage": {
    "prompt_tokens": 10,
    "completion_tokens": 25,
    "total_tokens": 35
  }
}
```

- `finish_reason` normalizado: `tool_calls`, `stop`, `length`, `content_filter`, `error`; o valor bruto do provider fica em `native_finish_reason`.
- Parâmetros não suportados pelo modelo são **ignorados silenciosamente** (não é erro).

## 8. POST /api/v1/messages — compat Anthropic

Formato Anthropic Messages API: suporta texto, imagens, PDFs, tools e extended thinking. Use com o SDK Anthropic apontando a base URL `https://openrouter.ai/api/v1`. Erros seguem o envelope Anthropic (`error.type` nativo + `error_type` canônico dentro de `error`). Detalhes de uso em `integrations.md`.

## 9. Parâmetros de sampling

| Parâmetro | Range | Default | Nota |
|---|---|---|---|
| `temperature` | 0.0–2.0 | 1.0 | 0 = sempre a mesma resposta |
| `top_p` | 0.0–1.0 | 1.0 | Só tokens cuja probabilidade soma P |
| `top_k` | 0+ | 0 (off) | 1 = sempre o token mais provável |
| `frequency_penalty` | -2.0–2.0 | 0.0 | Penaliza por ocorrência |
| `presence_penalty` | -2.0–2.0 | 0.0 | Não escala com ocorrências |
| `repetition_penalty` | 0.0–2.0 | 1.0 | Baseado na probabilidade original do token |
| `min_p` | 0.0–1.0 | 0.0 | Prob. mínima relativa ao token mais provável |
| `top_a` | 0.0–1.0 | 0.0 | "Dynamic Top-P" |
| `seed` | int | — | Sampling determinístico (não garantido) |
| `max_tokens` / `max_completion_tokens` | int 1+ | — | Teto = `context_length − prompt_length` (e `max_completion_tokens` do provider) |
| `logit_bias` | map token→-100..100 | — | ±100 ≈ banir/forçar token |
| `logprobs` / `top_logprobs` | bool / 0–20 | — | `top_logprobs` requer `logprobs: true` |
| `response_format` | map | — | `{"type":"json_object"}` ou `{"type":"json_schema","json_schema":{name,strict,schema}}` |
| `structured_outputs` | bool | — | Suporte a json_schema |
| `stop` | array | — | Para no primeiro token listado |
| `tools` / `tool_choice` | array / string\|obj | — | Tool calling estilo OpenAI; `tool_choice`: `none`, `auto`, `required`, `{type,function:{name}}` |
| `parallel_tool_calls` | bool | true | Só com `tools` |
| `reasoning_effort` | enum | — | `max, xhigh, high, medium, low, minimal, none` (mesmo enum de `reasoning.effort`) |
| `reasoning` | map | — | `{effort, max_tokens, exclude, enabled, context, mode}` — detalhes em `routing.md` |
| `verbosity` | enum | medium | `low, medium, high, xhigh, max` |
| `web_search_options` | map | — | Web search nativo |

Obs.: o OpenRouter NÃO injeta valores omitidos — omite o parâmetro upstream em vez de substituir por um default hardcoded.

## 10. Usage e observabilidade

### 10.1 Campos de `usage` (chat completions)

- `prompt_tokens`, `completion_tokens`, `total_tokens`
- `prompt_tokens_details`: `cached_tokens`, `cache_write_tokens`, `audio_tokens`, `video_tokens`
- `completion_tokens_details`: **`reasoning_tokens`** (aninhado aqui, não no topo de `usage`), `audio_tokens`, `image_tokens`
- `cost` — custo em USD da requisição
- `is_byok` — se usou BYOK
- `cost_details` — ex.: `upstream_inference_prompt_cost`, `upstream_inference_completions_cost`, `upstream_inference_cost`
- `server_tool_use` — ex.: `web_search_requests` (quantas buscas o modelo fez)

`reasoning_tokens` é contado e cobrado como token de saída. Alguns modelos de reasoning não retornam seus tokens (ex.: família o-series da OpenAI). Para raciocinar sem devolver os tokens: `"reasoning": {"exclude": true}`. O reasoning chega em `choices[].message.reasoning_details` (ou `choices[].delta.reasoning_details` em streaming), tipos `reasoning.summary` / `reasoning.encrypted` / `reasoning.text`.

### 10.2 Header X-OpenRouter-Metadata

Envie `X-OpenRouter-Metadata: enabled` (case-insensitive) para receber o campo **`openrouter_metadata`** na resposta, ao lado de `id`/`model`/`choices`/`usage` (em streaming: no chunk final antes de `[DONE]`; em erros: no topo do envelope, irmão de `error`, exceto 500s, auth/rate-limit e validações pré-router).

Campos documentados: `requested` (slug enviado), `strategy` (`direct`, `auto`, `free`, `latest`, `alias`, `fallback`, `pareto`, `bodybuilder`, `fusion`), `region`, `summary` (resumo legível da decisão), `attempt` (1-indexed; 0 = nenhum provider alcançado), `is_byok`, `endpoints` (`{total, available: [{provider, model, selected}]}`), `params` (floors do router), `attempts` (por tentativa: `{provider, model, status}`), `pipeline` (estágios de plugins/guardrails).

Caveats: **cache hits nunca incluem `openrouter_metadata`**; o formato é aditivo — decodifique de forma permissiva. Para custo/latência exatos, use `usage.cost` + `X-Generation-Id` (abaixo).

### 10.3 X-Generation-Id e GET /api/v1/generation

Toda resposta traz o header `X-Generation-Id`. Depois da request, `GET /api/v1/generation?id=$ID` retorna stats da geração: `id`, `model`, `finish_reason`, `native_finish_reason`, `api_type`, `latency` (ms), `generation_time` (ms), `native_tokens_prompt`, `native_tokens_completion`, `native_tokens_reasoning`, `native_tokens_cached`, `cache_discount`, `is_byok`, `app_id`, `http_referer`, `data_region`, `external_user`, `moderation_latency`, `cancelled`, `created_at`.

### 10.4 Debug

`debug: {"echo_upstream_body": true}` no body — **só funciona com `stream: true`**; devolve o body transformado enviado ao provider no primeiro chunk (`debug.echo_upstream_body`); um debug chunk por provider tentado. Não usar em produção (pode vazar dados sensíveis).

## 11. Dicas de consulta (filtros e ordenação em um lugar)

- **Buscar modelos baratos:** `GET /api/v1/models?sort=pricing-low-to-high` (+ `max_price`/`max_output_price` em USD).
- **Modelos com tool calling:** `?supported_parameters=tools`.
- **Modelos multimodais:** `?output_modalities=image,audio` (ou `all`).
- **Modelos recentes:** `?min_age_days=0&sort=newest` (ou `top-weekly`).
- **Por tarefa:** índices `min_coding_index`, `min_agentic_index`, `min_intelligence_index`, `min_tool_success_rate` (com `max_*` para limitar o teto).
- **Janela de contexto:** `?context=128000` (filtro) e `sort=context-high-to-low`.
- **Por autor/ID:** não há query param `id` nem `author` em `/models`; use `q` (busca) + `model_authors` (lista de autores). Para um modelo específico, use `GET /api/v1/model/{author}/{slug}`.
- **Providers que servem um modelo:** `GET /api/v1/models/{author}/{slug}/endpoints` → compare `pricing`, `throughput_last_30m.p50`, `latency_last_30m.p50`, `quantization`, `uptime_last_1d`.
- **Contagem do catálogo:** `GET /api/v1/models/count`.
- **Paginação:** `offset`/`limit` (default 500, máx 1000); omita ambos para a lista completa; use `links.next`.
