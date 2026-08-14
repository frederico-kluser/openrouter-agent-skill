# OpenRouter API — Pesquisa factual (fonte de verdade da skill)

> **Status da pesquisa:** dados verificados em 2026-08-14 contra as fontes oficiais listadas em cada seção (páginas de docs e o OpenAPI spec publicado). Toda afirmação tem fonte. Divergências entre o briefing e os docs atuais estão marcadas com **[NÃO CONFIRMADO nos docs]**.
>
> **Fontes primárias usadas:**
> - Índice completo dos docs: https://openrouter.ai/docs/llms.txt
> - Quickstart: https://openrouter.ai/docs
> - OpenAPI spec oficial (autoritativo para paths, métodos, query params e schemas): https://openrouter.ai/openapi.yaml
> - Guia de modelos: https://openrouter.ai/docs/guides/overview/models.md
> - API reference overview: https://openrouter.ai/docs/api_reference/overview.md
> - Autenticação: https://openrouter.ai/docs/api_reference/authentication.md
> - Limites: https://openrouter.ai/docs/api_reference/limits.md
> - Erros: https://openrouter.ai/docs/api_reference/errors-and-debugging.md
> - Router metadata: https://openrouter.ai/docs/guides/features/router-metadata.md
> - Parâmetros: https://openrouter.ai/docs/api_reference/parameters.md
> - Provider selection: https://openrouter.ai/docs/guides/routing/provider-selection.md
> - Reasoning tokens: https://openrouter.ai/docs/guides/best-practices/reasoning-tokens.md
> - Streaming: https://openrouter.ai/docs/api_reference/streaming.md
> - Versioning: https://openrouter.ai/docs/api_reference/versioning.md
> - OpenAI SDK: https://openrouter.ai/docs/guides/community/openai-sdk.md

---

## 1. Visão geral

- **Base URL:** `https://openrouter.ai/api/v1` — todos os endpoints carregam o prefixo `/v1`. Fonte: Quickstart (`https://openrouter.ai/docs`) e api_reference/overview.
- **Formato:** "very similar to the OpenAI Chat API"; o OpenRouter **normaliza o schema entre modelos e provedores** (mesmo formato de resposta para modelos de qualquer provider).
- **Versão:** existe **uma única versão estável, `v1`**, escolhida pelo path. "There are no version headers and no date-based version pinning." Mudanças que quebram compatibilidade são anunciadas no changelog (`https://openrouter.ai/docs/changelog`). Fonte: api_reference/versioning.
- **Clientes:** OpenRouter oferece SDKs próprios (`@openrouter/sdk`, `@openrouter/agent`) e é 100% compatível com o SDK OpenAI apontado para a base URL acima. Fonte: docs Quickstart.
- **Autenticação:** header `Authorization: Bearer <OPENROUTER_API_KEY>`.
- **Modelos:** 411 modelos (verificado em 2026-08-14 via `GET /api/v1/models/count`; o quickstart oficial fala em "centenas de modelos"; catálogo em https://openrouter.ai/models), com IDs no formato `author/slug` (ex.: `openai/gpt-4o`).

## 2. Endpoints essenciais

### 2.1 Tabela de endpoints

| Método | Path | Propósito | Notas |
|---|---|---|---|
| GET | `/api/v1/models` | Listar todos os modelos com propriedades | Paginação via `offset`/`limit` (NÃO `per_page`/`cursor` — ver 8.1) |
| GET | `/api/v1/models/count` | Contar modelos | Filtro `output_modalities` |
| GET | `/api/v1/model/{author}/{slug}` | Detalhe de UM modelo | **`model` no singular** — ver 2.4 |
| GET | `/api/v1/models/{author}/{slug}/endpoints` | Listar endpoints/providers que servem o modelo | Preços, throughput e latência por provider — ver 2.5 |
| GET | `/api/v1/models/user` | Modelos com BYOK (provider keys do usuário) | Fonte: openapi.yaml |
| GET | `/api/v1/credits` | Créditos comprados/usados | **Requer management key** — ver 2.6 |
| GET | `/api/v1/key` | Informações e limites da chave atual | Ver 2.7 |
| POST | `/api/v1/chat/completions` | Chat completions (endpoint principal) | Compatível OpenAI |
| POST | `/api/v1/messages` | Formato Anthropic Messages API | Suporta texto, imagens, PDFs, tools e extended thinking |
| POST | `/api/v1/responses` | OpenResponses API format | |
| POST | `/api/v1/completions` | Completions **legado** | **[NÃO CONFIRMADO nos docs]** — não existe no OpenAPI spec atual; docs ainda citam "legacy Completions" como rota viva (router-metadata) |
| GET | `/api/v1/generation?id=$GENERATION_ID` | Estatísticas de uma geração (tokens e custo) | ID também vem no header `X-Generation-Id` |

Outros endpoints existentes (fora do escopo da skill, listados no spec): `/api/v1/embeddings`, `/api/v1/audio/speech`, `/api/v1/audio/transcriptions`, `/api/v1/images`, `/api/v1/rerank`, `/api/v1/classifications/task`, `/api/v1/files`, `/api/v1/guardrails`, `/api/v1/presets`, `/api/v1/analytics/*`, `/api/v1/activity`, `/api/v1/benchmarks`, `/api/v1/keys` (gestão de chaves, management key), `/api/v1/auth/keys`, `/api/v1/organization/members`, `/api/v1/observability/destinations`, `/api/v1/providers`.

Fonte: openapi.yaml (73 paths), llms.txt.

### 2.2 `GET /api/v1/models` — listar modelos

**Query parameters documentados (openapi.yaml):** `offset`, `limit`, `category`, `supported_parameters`, `output_modalities`, `sort`, `q`, `input_modalities`, `context`, `min_price`, `max_price`, `min_output_price`, `max_output_price`, `min_age_days`, `max_age_days`, `min_agentic_index`, `max_agentic_index`, `min_coding_index`, `max_coding_index`, `min_intelligence_index`, `max_intelligence_index`, `min_tool_success_rate`, `max_tool_success_rate`, `region`, `zdr`, `arch`, `model_authors`, `providers`, `distillable`.

Detalhes (fonte: guia models + openapi.yaml):
- `output_modalities` — separado por vírgula ou `"all"`: `text` (padrão — "Models that produce text output (default)"), `image`, `audio`, `embeddings`, `all`.
- `supported_parameters` — ex.: `?supported_parameters=tools` para achar modelos com tool calling.
- `sort` — enum completo: `most-popular`, `newest`, `top-weekly`, `pricing-low-to-high`, `pricing-high-to-low`, `context-high-to-low`, `throughput-high-to-low`, `latency-low-to-high`, `intelligence-high-to-low`, `coding-high-to-low`, `agentic-high-to-low`, `design-arena-elo-high-to-low`. "Models without data for the requested sort dimension ... sort last."
- Paginação: `offset` + `limit`; `limit` default **500**, máximo **1000**; omitindo ambos, retorna a **lista completa**. (Não há `per_page` nem `cursor` no spec atual.)

**Formato da resposta:**

```json
{
  "data": [
    {
      "id": "openai/gpt-4",
      "canonical_slug": "openai/gpt-4",
      "name": "GPT-4",
      "created": 1692901234,
      "description": "GPT-4 is a large multimodal model that can solve difficult problems with greater accuracy.",
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

Fonte: guia models (`https://openrouter.ai/docs/guides/overview/models.md`) + openapi.yaml.

**Campos do objeto Model (openapi.yaml, schema `Model`):**

| Campo | Tipo | Descrição (do spec) |
|---|---|---|
| `id` | string | "Unique model identifier used in API requests" (ex.: `openai/gpt-4`) |
| `canonical_slug` | string | "Permanent slug for the model that never changes" |
| `name` | string | Nome exibível (ex.: `GPT-4`) |
| `created` | integer | Unix timestamp de quando foi adicionado ao OpenRouter |
| `description` | string | Descrição de capacidades |
| `context_length` | integer | "Maximum context window size in tokens" |
| `architecture` | object | `input_modalities` (ex.: `["file","image","text"]`), `output_modalities` (ex.: `["text"]`), `instruct_type`, `modality`, `tokenizer` |
| `pricing` | object | Todos os valores em **string USD**. Chaves: `prompt` (custo por token de entrada), `completion` (por token de saída), `request` (custo fixo por requisição), `image`, `image_output`, `audio`, `audio_output`, `image_token`, `input_audio_cache`, `input_cache_read`, `input_cache_write`, `internal_reasoning`, `web_search`, `discount` (0 = sem desconto, 1 = grátis), `overrides` (preço condicional por `min_prompt_tokens`/janela de horário `utc_start`/`utc_end` — ex.: limiar de 200K tokens) |
| `top_provider` | object | `context_length`, `max_completion_tokens`, `is_moderated` (se o top provider modera conteúdo) |
| `per_request_limits` | object \| null | "Rate limiting information (null if no limits)": `prompt_tokens`, `completion_tokens` (limites de tokens por requisição) |
| `supported_parameters` | array | Parâmetros que o modelo suporta (ex.: `tools`, `tool_choice`, `max_tokens`, `temperature`, `top_p`, `reasoning`, `structured_outputs`, `response_format`, `stop`, `seed`) |
| `reasoning` | object \| null | `supported_efforts`, `default_effort`, `default_enabled`, `supports_max_tokens`, `mandatory` |
| `default_parameters` | object \| null | Parâmetros default do modelo |
| `expiration_date` | string \| null | Data de deprecação do endpoint do modelo (null se não deprecado) |
| `knowledge_cutoff` | string \| null | — |
| `benchmarks` | object \| null | Rankings (Design Arena: `arena`, `category`, `elo`, `win_rate`, `rank`) |
| `links` | object | Ex.: `details: "/api/v1/models/openai/gpt-4/endpoints"` |
| `supported_voices` | array \| null | Vozes para TTS |
| `hugging_face_id` | string \| null | — |
| `alias_target` | object \| null | Modelo concreto alvo de um alias `~latest` |

**[NÃO CONFIRMADO nos docs]** — O briefing pedia um campo `limits` no objeto do modelo. **Não existe campo `limits` top-level no spec atual**: a informação de limites está distribuída em `context_length`, `per_request_limits` e `top_provider.{context_length,max_completion_tokens}`. A SKILL.md não deve ensinar a ler `model.limits`.

### 2.3 `GET /api/v1/models/count`

Resposta: `{ "data": { "count": 150 } }`. Filtro: `output_modalities`. Fonte: openapi.yaml.

### 2.4 `GET /api/v1/model/{author}/{slug}` — detalhe de um modelo

- **Path singular:** `/api/v1/model/{author}/{slug}` (spec: `getModel`). **[NÃO CONFIRMADO nos docs]** — o briefing pedia `/api/v1/models/{author}/{slug}` (plural); o spec oficial expõe apenas a forma **singular**.
- Resolve aliases automaticamente (ex.: `anthropic/claude-3-5-sonnet` → `anthropic/claude-3.5-sonnet`) e aceita sufixos de variante (`:free`, `:thinking`, `:extended`, `:nitro`, `:online` — ex.: `openai/gpt-4:free`).
- Retorna `404` se o modelo não existe e não é alias.
- Resposta: o mesmo objeto Model envolvido em `data`.

Fonte: guia models + openapi.yaml.

### 2.5 `GET /api/v1/models/{author}/{slug}/endpoints` — providers que servem o modelo

Resposta: `{ "data": { "id", "name", "description", "architecture", "created", "endpoints": [...] } }`.

Cada item de `endpoints` (spec, schema `ListEndpointsResponse` + exemplo inline):

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

Campos documentados por item:
- `provider_name` — nome exibível do provider (ex.: "OpenAI").
- `tag` — **slug do provider** (ex.: `openai`), usado no routing (`provider.order`, `provider.only`). **[NÃO CONFIRMADO nos docs]** — não existe campo `provider_id` no spec atual; o papel de identificador é do `tag`.
- `quantization` — níveis válidos em todo o sistema: `int4`, `int8`, `fp4`, `mxfp4`, `nvfp4`, `fp6`, `fp8`, `mxfp8`, `fp16`, `bf16`, `fp32`, `unknown` (fonte: provider-selection).
- `throughput_last_30m` — tokens por segundo em percentis p50/p75/p90/p99 (janela rolante de 30 min).
- `latency_last_30m` — latência em **segundos**, percentis p50/p75/p90/p99.
- `uptime_last_5m` / `uptime_last_30m` / `uptime_last_1d` — % de uptime.
- `pricing` — **preços por provider** (prompt/completion/request/image, strings USD). Importante: o preço cobrado é o do provider selecionado, que pode diferir do preço de lista do modelo.
- `context_length`, `max_completion_tokens`, `max_prompt_tokens` — limites por endpoint (variam por provider!).
- `status` — inteiro (0 no exemplo; sem enum documentado no spec) — **[NÃO CONFIRMADO nos docs]** o significado dos valores.
- `name` — "OpenAI: GPT-4" (nome exibível do endpoint).

**Como usar para escolher/forçar provider:** com esses dados você decide `provider.order` (lista de slugs na ordem de tentativa), `provider.only` (restringir a providers específicos), `provider.quantizations` (filtrar por quantização) e `provider.max_price` (teto de preço em USD). Ver seção 7.

Fonte: openapi.yaml + provider-selection.

### 2.6 `GET /api/v1/credits` — saldo/créditos

- **Requer management key** ("[Management key](/docs/guides/overview/auth/management-api-keys) required" — spec).
- Resposta: `{ "data": { "total_credits": 100.5, "total_usage": 25.75 } }` — créditos **comprados** e **usados** (números USD).

**[NÃO CONFIRMADO nos docs]** — o briefing pedia campos `{total, used, limit}`; o spec atual usa `data.total_credits` / `data.total_usage` (sem campo `limit` nesse endpoint; o limite da chave fica em `/api/v1/key`).

Fonte: openapi.yaml.

### 2.7 `GET /api/v1/key` — limites da chave

Resposta (campos do spec): `label`, `limit` (spending limit em USD), `limit_remaining`, `limit_reset` (tipo de reset, ex.: `'monthly'`), `usage`, `usage_daily`, `usage_weekly`, `usage_monthly` (em USD), `is_free_tier`, `is_management_key`, `expires_at`, `creator_user_id`, `include_byok_in_limit`, `byok_usage_*` (uso externo BYOK), `rate_limit` (deprecated — o spec diz apenas "This field is deprecated and safe to ignore."; a afirmação "Will always return -1" é **[NÃO CONFIRMADO nos docs]**).

Use para monitorar consumo: ex. `usage_monthly` vs `limit`.

Fonte: openapi.yaml + limits.md.

### 2.8 `POST /api/v1/chat/completions` (principal)

Aceita `messages` (formato OpenAI) ou `prompt` (texto puro; resposta com `text` no choice). Ver seção 6 (parâmetros) e 4 (uso).

Resposta não-streaming:

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

- Top-level: `id`, `choices` (sempre array), `created`, `model`, `object` (`chat.completion` | `chat.completion.chunk`), `system_fingerprint` (opcional), `usage`.
- `finish_reason` normalizado: `tool_calls`, `stop`, `length`, `content_filter`, `error`; o valor bruto do provider fica em `native_finish_reason`.

Fonte: api_reference/overview.

### 2.9 `POST /api/v1/messages` (compat Anthropic)

"Creates a message using the Anthropic Messages API format. Supports text, images, PDFs, tools, and extended thinking." Use com o SDK Anthropic apontando a base URL `https://openrouter.ai/api/v1`. Erros seguem o envelope Anthropic (`error.type` nativo + `error_type` canônico dentro de `error`). Fonte: openapi.yaml + errors-and-debugging.

### 2.10 `POST /api/v1/completions` (legado)

**[NÃO CONFIRMADO nos docs]** — **não existe no OpenAPI spec atual** (grep no spec não encontra `/completions`). Os docs (router-metadata) ainda se referem a "legacy Completions" como uma das quatro rotas (Chat Completions, Messages, Responses, legacy Completions). A SKILL.md deve mencioná-la apenas como rota legada não documentada no spec, sem prometer suporte.

### 2.11 `GET /api/v1/generation?id=$GENERATION_ID`

"Query for the generation stats (including token counts and cost) after the request is complete." O ID da geração é retornado no header `X-Generation-Id` de cada resposta. Exemplo de resposta (spec): `data` com `id` (ex.: `gen-3bhGkxlo4XFrqiabUM7NDtwDzWwG`), `model`, `finish_reason`, `native_finish_reason`, `api_type`, `latency` (ms), `generation_time` (ms), `native_tokens_prompt`, `native_tokens_completion`, `native_tokens_reasoning`, `native_tokens_cached`, `cache_discount`, `is_byok`, `app_id`, `http_referer`, `data_region`, `external_user`, `moderation_latency`, `cancelled`, `created_at`. Fonte: api_reference/overview + openapi.yaml.

## 3. Autenticação

- **Header obrigatório:** `Authorization: Bearer <OPENROUTER_API_KEY>` — "Our API authenticates requests using Bearer tokens."
- **Formato da chave:** `sk-or-v1-...` (padrão conhecido; os docs oficiais usam o placeholder `<OPENROUTER_API_KEY>` em vez de mostrar chaves reais — a string `sk-or-v1-` não aparece literalmente na página de auth).
- **Onde obter:** criar em **https://openrouter.ai/keys** (dê um nome, opcionalmente defina credit limit); gerenciar/revogar em **https://openrouter.ai/settings/keys**.
- **Headers opcionais:**
  - `HTTP-Referer` — "Optional. Site URL for rankings on openrouter.ai."
  - `X-OpenRouter-Title` — "Optional. Site title for rankings on openrouter.ai." (A página de overview também aceita `X-Title` como alias: "`X-OpenRouter-Title` (`X-Title` also accepted)" — a página de auth documenta apenas `X-OpenRouter-Title`.)
  - `X-OpenRouter-Categories` — categorias do app (overview).
- **Segurança:** OpenRouter é GitHub secret scanning partner; nunca commite chaves em repositórios públicos. "API keys on OpenRouter are more powerful than keys used directly for model APIs" (suportam credit limits, OAuth etc.).
- Ao usar o SDK OpenAI: passe `api_key` + `base_url` (python) ou `apiKey` + `baseURL` (js), e os headers via `extra_headers` (python) ou `defaultHeaders` (js).

Fonte: api_reference/authentication + api_reference/overview + guides/community/openai-sdk.

## 4. Compatibilidade OpenAI

- **Base URL:** `https://openrouter.ai/api/v1` — drop-in para o SDK OpenAI (python: `from openai import OpenAI; client = OpenAI(base_url="https://openrouter.ai/api/v1", api_key=...)`; js: `new OpenAI({ baseURL: "https://openrouter.ai/api/v1", apiKey: ... })`).
- **Exemplo python (docs):**

```python
from openai import OpenAI
from os import getenv

client = OpenAI(
    base_url="https://openrouter.ai/api/v1",
    api_key=getenv("OPENROUTER_API_KEY"),
)
completion = client.chat.completions.create(
    model="openai/gpt-4o",
    extra_headers={
        "HTTP-Referer": "<YOUR_SITE_URL>",
        "X-OpenRouter-Title": "<YOUR_SITE_NAME>",
    },
    messages=[{"role": "user", "content": "Say this is a test"}],
)
print(completion.choices[0].message.content)
```

- **Parâmetros OpenAI suportados:** `temperature`, `top_p`, `top_k`, `max_tokens`, `max_completion_tokens`, `stop`, `stream`, `tools`, `tool_choice`, `parallel_tool_calls`, `seed`, `frequency_penalty`, `presence_penalty`, `repetition_penalty`, `logit_bias`, `logprobs`, `top_logprobs`, `min_p`, `top_a`, `response_format`, `structured_outputs`, `user`.
- **Parâmetros extras OpenRouter** (via `extra_body` no SDK OpenAI): `models` (lista de fallbacks), `route`, `provider`, `transforms` **[NÃO CONFIRMADO — ausente no OpenAPI ao vivo 2026-08-14]**, `plugins`, `reasoning`, `verbosity`, `web_search_options`, `debug`.
- **Parâmetros não suportados pelo modelo são ignorados silenciosamente:** "the parameter is ignored. The rest are forwarded to the underlying model API."
- **Streaming:** `stream: true` funciona para **todos os modelos** (SSE, ver seção 5). Último chunk traz `usage` com `choices` vazio, seguido de `data: [DONE]`. Linhas de comentário SSE começando com `:` (ex.: `: OPENROUTER PROCESSING`) devem ser ignoradas; o docs recomenda um parser spec-compliant como `eventsource-parser`. Cancelamento via AbortController só funciona em streaming e com providers que suportam; caso contrário "the model will continue processing and you will be billed".
- **Versioning:** sem pinning por data; v1 única e estável; changelog em `https://openrouter.ai/docs/changelog`.

Fonte: guides/community/openai-sdk + api_reference/streaming + api_reference/versioning.

## 5. Usage e observabilidade

### 5.1 Campos `usage` na resposta (chat completions)

- `prompt_tokens`, `completion_tokens`, `total_tokens`
- `prompt_tokens_details`: `cached_tokens`, `cache_write_tokens`, `audio_tokens`, `video_tokens`
- `completion_tokens_details`: `reasoning_tokens`, `audio_tokens`, `image_tokens`
- `cost` — custo em USD da requisição
- `is_byok` — se usou BYOK
- `cost_details` — ex.: `upstream_inference_prompt_cost`, `upstream_inference_completions_cost`, `upstream_inference_cost` (custos upstream, schema `CostDetails`)
- `server_tool_use` / `server_tool_use_details` — **[conflito de fontes]** o guia overview usa `server_tool_use` (ex.: `web_search_requests`), mas o schema `ChatUsage` do openapi.yaml usa `server_tool_use_details`

Em **streaming**, o `usage` chega **uma única vez, no chunk final**, com `choices: []`, antes de `[DONE]`.

**[NÃO CONFIRMADO nos docs]** — o briefing pedia `reasoning_tokens` no topo de `usage`; o schema `ChatUsage` do openapi.yaml o coloca em `completion_tokens_details.reasoning_tokens` — embora o exemplo JSON do overview o mostre também no topo de `usage` (as fontes divergem nesse ponto).

Fonte: api_reference/overview + openapi.yaml.

### 5.2 `reasoning_tokens` (detalhe)

- `reasoning_tokens` é contado como **token de saída e cobrado como tal** ("Reasoning tokens are considered output tokens and charged accordingly").
- Alguns modelos de reasoning não retornam seus tokens de reasoning (ex.: família OpenAI o-series).
- Para **excluir** o reasoning da resposta: `"reasoning": { "exclude": true }` (o modelo ainda raciocina, mas não devolve os tokens).
- O reasoning chega em `choices[].message.reasoning_details` (não-streaming) ou `choices[].delta.reasoning_details` (streaming), com tipos `reasoning.summary`, `reasoning.encrypted`, `reasoning.text`.
- Preço de reasoning: campo `internal_reasoning` no objeto `pricing` do modelo.

Fonte: guides/best-practices/reasoning-tokens + guia models.

### 5.3 Header `X-OpenRouter-Metadata` (router metadata)

- **Como habilitar:** envie o header `X-OpenRouter-Metadata: enabled` (case-insensitive; `disabled` = omitir; o header legado `X-OpenRouter-Experimental-Metadata` ainda é aceito). Funciona nas quatro rotas (Chat Completions, Messages, Responses, legacy Completions), streaming e não-streaming.
- **Onde aparece:** ao lado de `id`/`model`/`choices`/`usage` na resposta (campo `openrouter_metadata`); em streaming, no chunk final antes de `[DONE]`; em erros, no topo do envelope, irmão de `error` (exceto 500s, auth/rate-limit e validações pré-router).
- **Campos documentados (todos os nomes são do doc):**
  - `requested` (string) — slug/alias enviado pelo cliente (pode diferir do que serviu)
  - `strategy` (string) — `direct`, `auto`, `free`, `latest`, `alias`, `fallback`, `pareto`, `bodybuilder`, `fusion`
  - `region` (string|null) — edge region
  - `summary` (string) — resumo legível da decisão de roteamento
  - `attempt` (integer) — tentativa (1-indexed) que teve sucesso; `0` = nenhum provider alcançado
  - `is_byok` (boolean)
  - `endpoints` — `{ total, available: [{ provider, model, selected }] }`
  - `params` (opcional) — parâmetros do router (qualidade/throughput floors)
  - `attempts` (opcional) — por tentativa: `{ provider, model, status }`
  - `pipeline` (opcional) — estágios de plugins/guardrails que rodaram
- **Caveats:** "Cache hits never include `openrouter_metadata`" (respostas de cache não trazem metadata); o formato é aditivo ("existing fields are stable") — decodifique de forma permissiva.

**[NÃO CONFIRMADO nos docs]** — o briefing pedia campos `mode`, `cost`, `tps`, `provider_name`, `quantization`, `timings: {ttft, total}` no header. **Esses campos NÃO existem na documentação atual** do `X-OpenRouter-Metadata` (formato `openrouter_metadata` acima). O nome `timings`/`ttft` corresponde a um formato antigo da header `X-OpenRouter-Experimental-Metadata`, não documentado hoje. A SKILL.md deve ensinar o formato atual (`openrouter_metadata` + `attempts`) e, para custo/latência exatos, `usage.cost` + `X-Generation-Id` + `GET /api/v1/generation?id=`.

Fonte: guides/features/router-metadata + api_reference/streaming.

### 5.4 Outros sinais de observabilidade

- Header `X-Generation-Id` em toda resposta → `GET /api/v1/generation?id=...` para stats (tokens, custo, latência, cache discount).
- Opção `debug` no body (`{ "echo_upstream_body": true }`) — **só funciona com `stream: true`**; devolve o body transformado enviado ao provider no primeiro chunk (`debug.echo_upstream_body`); envia um debug chunk por provider tentado; não usar em produção (pode vazar dados sensíveis).

Fonte: api_reference/errors-and-debugging + api_reference/streaming.

## 6. Parâmetros da requisição (chat completions)

### 6.1 Sampling / OpenAI (com defaults convencionais; o OpenRouter NÃO injeta valores omitidos — "OpenRouter omits it upstream rather than substituting a hardcoded value")

| Parâmetro | Tipo / range | Default | Notas |
|---|---|---|---|
| `temperature` | float 0.0–2.0 | 1.0 | 0 = sempre a mesma resposta |
| `top_p` | float 0.0–1.0 | 1.0 | Só os top tokens cuja probabilidade soma P |
| `top_k` | int 0+ | 0 (off) | 1 = sempre o token mais provável |
| `frequency_penalty` | float -2.0–2.0 | 0.0 | Penalidade escala com nº de ocorrências |
| `presence_penalty` | float -2.0–2.0 | 0.0 | Não escala com ocorrências |
| `repetition_penalty` | float 0.0–2.0 | 1.0 | Baseado na probabilidade original do token |
| `min_p` | float 0.0–1.0 | 0.0 | Prob. mínima relativa ao token mais provável |
| `top_a` | float 0.0–1.0 | 0.0 | "Think of it like a dynamic Top-P" |
| `seed` | int | — | Sampling determinístico (não garantido) |
| `max_tokens` | int 1+ | — | Teto = context length − prompt length |
| `max_completion_tokens` | int 1+ | — | Mesma função de `max_tokens` |
| `logit_bias` | map token→-100..100 | — | ±100 ≈ banir/forçar token |
| `logprobs` | bool | — | Logprobs por token de saída |
| `top_logprobs` | int 0–20 | — | Requer `logprobs: true` |
| `response_format` | map | — | `{"type":"json_object"}` ou `{"type":"json_schema","json_schema":{name,strict,schema}}` |
| `structured_outputs` | bool | — | Suporte a json_schema |
| `stop` | array | — | Para a geração no primeiro token listado |
| `tools` / `tool_choice` | array / string\|obj | — | Tool calling estilo OpenAI, transformado p/ providers não-OpenAI; `tool_choice`: `none`, `auto`, `required`, `{type,function:{name}}` |
| `parallel_tool_calls` | bool | **true** | Só quando `tools` presente |
| `reasoning_effort` | enum | — | `xhigh`, `high`, `medium`, `low`, `minimal`, `none` |
| `reasoning` | map | — | `{effort, max_tokens, exclude, enabled, context, mode}` — ver 6.3 |
| `verbosity` | enum | medium | `low`, `medium`, `high`, `xhigh`, `max` |
| `web_search_options` | map | — | Web search nativo |
| `include_reasoning` | bool | — | **Deprecated** alias de `reasoning.exclude` |

### 6.2 Roteamento (OpenRouter-only)

| Parâmetro | Descrição |
|---|---|
| `models` | array de fallbacks (ex.: `["openai/gpt-4o", "mistralai/mixtral-8x22b-instruct"]`) |
| `route` | `'fallback'` (**deprecated** — spec: "Use `providers.sort.partition` instead"; `'fallback'` mapeia para `'model'`) |
| `provider` | objeto de preferências — ver abaixo |
| `transforms` | **[NÃO CONFIRMADO]** — ausente no OpenAPI ao vivo 2026-08-14; a página "Message Transforms" documenta o plugin `context-compression`, não um param `transforms` (ver `routing-config.md` §14) |
| `plugins` | `web`, `file-parser`, `response-healing`, `context-compression` |
| `debug` | `{ echo_upstream_body: true }` — só com streaming |

**Objeto `provider` (todos os campos são do doc provider-selection):**

| Campo | Default | Descrição |
|---|---|---|
| `order` | — | `["anthropic", "openai"]` — slugs na ordem de tentativa |
| `allow_fallbacks` | `true` | Permitir providers de backup |
| `require_parameters` | `false` | Só providers que suportam TODOS os parâmetros da request |
| `data_collection` | `"allow"` | `"allow"` \| `"deny"` (só providers que não coletam dados) |
| `zdr` | — | Só endpoints Zero Data Retention |
| `enforce_distillable_text` | — | Só modelos que permitem destilação de texto |
| `only` | — | Lista de slugs permitidos (forçar provider) |
| `ignore` | — | Lista de slugs a pular (o doc NÃO usa `exclude` — campo equivalente é `ignore`) |
| `quantizations` | — | `["int4","int8"]` etc. (níveis na seção 2.5) |
| `sort` | — | `"price"` \| `"throughput"` \| `"latency"`, ou objeto `{by, partition}` (`"model"` default \| `"none"`); atalhos `:nitro` (throughput), `:floor` (preço) |
| `preferred_min_throughput` | — | Tokens/s mínimos; número ou percentil `{p50,p75,p90,p99}` |
| `preferred_max_latency` | — | Latência máx em segundos; número ou percentil |
| `max_price` | — | `{prompt, completion, request, image}` em USD — teto de preço |

**Roteamento default:** "requests are load balanced across the top providers to maximize uptime," com preço como fator primário — prioriza providers sem outage nos últimos 30s; entre os estáveis, escolhe por preço ponderado pelo inverso do quadrado (provider de $1 é ~9x mais provável que um de $3). Se `sort` ou `order` forem definidos, o load balancing é desativado. Requests com `tools`/`tool_choice` vão para providers com suporte a tools; `max_tokens` filtra providers por capacidade de resposta. Fallback automático em 5xx e rate limits. Se nenhum provider satisfaz restrições de conta+request: **404**. `max_price` pode impedir a request de rodar; `preferred_min_throughput`/`preferred_max_latency` não garantem nada (só deprioritizam).

Fonte: guides/routing/provider-selection + api_reference/overview + api_reference/parameters.

### 6.3 `reasoning` em detalhe

- Use `effort` **ou** `max_tokens` (não ambos): `effort` ∈ `max`, `xhigh`, `high`, `medium`, `low`, `minimal`, `none`; `max_tokens` = orçamento em tokens (estilo Anthropic).
- Conversão entre estilos: max/xhigh ≈ 95% do max_tokens, high ≈ 80%, medium ≈ 50%, low ≈ 20%, minimal ≈ 10%; `none` desliga reasoning.
- `exclude: true` — raciocina mas não devolve os tokens.
- `enabled: true` — equivale a medium sem exclusões.
- `context`: `"auto"` | `"all_turns"` | `"current_turn"` (GPT-5.6+); `mode`: `"standard"` | `"pro"`.
- Modelo Gemini: effort → `thinkingLevel` (xhigh mapeado para high); Anthropic: `budget_tokens = max(min(max_tokens * ratio, 128000), 1024)`.
- Suporte por modelo em `GET /api/v1/models` → `reasoning` (`supported_efforts`, `default_effort`, `default_enabled`, `supports_max_tokens`, `mandatory`).
- Ex.: `"reasoning": { "effort": "high", "exclude": true }`.

Fonte: guides/best-practices/reasoning-tokens.

## 7. Erros e rate limits

### 7.1 Envelope de erro

```json
{
  "error": {
    "code": 429,
    "message": "Rate limit exceeded",
    "metadata": { "error_type": "rate_limit_exceeded" }
  }
}
```

- HTTP status é código de erro real **apenas se** a request original era inválida ou chave/creditos insuficientes; senão, o status é `200` e o erro do modelo aparece no body/SSE.
- `metadata` pode conter: `error_type`, `provider_code` (código original do provider, quando não-500), `reasons`, `flagged_input` (até 100 chars), `provider_name`, `model_slug` (moderação/guardrails).

### 7.2 Códigos HTTP documentados

| Code | Significado (docs) |
|---|---|
| 400 | Bad Request (params inválidos/faltando, CORS) |
| 401 | Invalid credentials (OAuth expirado, chave inválida/desabilitada) |
| 402 | "Your account or API key has insufficient credits. Add more credits and retry the request." |
| 403 | Forbidden (permissões insuficientes, guardrail, flag de moderação) |
| 404 | Resource not found (modelo inexistente, provider indisponível dado as restrições) |
| 408 | "Your request timed out" |
| 412 | Precondition failed |
| 413 | Payload too large |
| 422 | Unprocessable |
| 429 | "You are being rate limited" (plataforma OU provider upstream) |
| 500 | Internal server error (mensagem upstream mascarada) |
| 502 | "Your chosen model is down or we received an invalid response from it" |
| 503 | "There is no available model provider that meets your routing requirements" |
| 504 | Gateway timeout (provider não respondeu a tempo) |

### 7.3 Vocabulário `error_type` (use-o, não o status, para distinguir categorias)

- **Token/length (todos 400):** `context_length_exceeded` (tokens combinados excedem a janela), `max_tokens_exceeded` (bateu no `max_tokens`/`max_completion_tokens`), `token_limit_exceeded` (orçamento OpenRouter, ex. credit cap), `string_too_long`.
- **Auth:** `authentication` (401, "The API key is missing, invalid, or revoked"), `permission_denied` (403), `payment_required` (402).
- **Rate/availability:** `rate_limit_exceeded` (429), `provider_overloaded` (503, "temporarily overloaded"), `provider_unavailable` (502, "invalid or empty response").
- **Validation:** `invalid_request` (400), `invalid_prompt` (400), `not_found` (404), `precondition_failed` (412), `payload_too_large` (413), `unprocessable` (422).
- **Content policy:** `content_policy_violation` (400), `refusal` (400).
- **Imagens (400):** `invalid_image`, `image_too_large`, `image_too_small`, `unsupported_image_format`, `image_not_found` (404), `image_download_failed`.
- **Genéricos:** `server` (500, mensagem mascarada), `timeout` (504), `unmapped` (500).

### 7.4 Rate limits (plataforma)

- **Só variantes `:free` têm cap de requisições** (não há cap para variantes pagas):

| Créditos comprados (total) | Requests/min | Requests/dia |
|---|---|---|
| Menos de 10 | 20 | 50 |
| 10 ou mais | 20 | 1000 |

- "Making additional accounts or API keys will not affect your rate limits, as we govern capacity globally" — mas modelos diferentes têm limites diferentes.
- Cloudflare DDoS protection bloqueia uso "dramatically exceeding reasonable usage".
- **Headers:** respostas de sucesso NÃO incluem `X-RateLimit-*`; só quando o próprio OpenRouter responde 429 é que vêm `X-RateLimit-Limit`, `X-RateLimit-Remaining`, `X-RateLimit-Reset`. Quando todo provider tentado retornou retry hint, a resposta carrega `Retry-After`.
- **Créditos → 402;** resolução: adicionar créditos, subir/aguardar cap da chave, monitorar via `GET /api/v1/key`.

### 7.5 Retries recomendados

- "Retry with exponential backoff and honor the Retry-After header when present" — 429 e 503 podem incluir `Retry-After` (segundos). **[NÃO CONFIRMADO nos docs]** — nenhuma fonte oficial afirma que os SDKs (OpenAI, Anthropic, Vercel AI, OpenRouter) honram o header automaticamente (o SDK OpenAI, por exemplo, não lê `Retry-After`); implemente o retry com backoff exponencial e `Retry-After` manualmente na aplicação, inclusive com `fetch` puro.
- `provider_overloaded` → retry após um pequeno delay; `provider_unavailable` → o OpenRouter pode retryar com outro provider se fallback routing estiver habilitado.
- Resposta vazia (cold start) → retry simples ou trocar de provider/modelo. Nota: "you may still be charged for the prompt processing cost by the upstream provider, even if no content is generated."

### 7.6 Erros em streaming

- **Pré-stream:** erro HTTP normal; OpenRouter pode ainda retryar silenciosamente com fallback.
- **Mid-stream** (HTTP 200 já enviado): erro chega como evento SSE com `error` no topo do chunk e `choices[0].finish_reason: "error"`; status HTTP permanece 200. Shape:

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

Causas: desconexão/timeout do provider, max_tokens/context durante geração, content filter de saída, overload.

Fonte: api_reference/errors-and-debugging + api_reference/limits + api_reference/streaming.

## 8. Limites de contexto e max_tokens

- **Consultar:** `GET /api/v1/models` → `context_length` (janela máxima do modelo), `top_provider.{context_length, max_completion_tokens}` (limites do provider principal), `per_request_limits.{prompt_tokens, completion_tokens}` (limites por request, null se não há) e por provider em `GET /api/v1/models/{author}/{slug}/endpoints` → `context_length`, `max_prompt_tokens`, `max_completion_tokens` (**variam por provider**).
- **`max_tokens`:** "The maximum is the context length minus the prompt length." O teto efetivo de saída também é limitado por `max_completion_tokens` do provider escolhido.
- **Overflow de contexto:** requisição com prompt + saída prevista excedendo a janela → erro 400 com `error_type: context_length_exceeded` ("combined tokens exceed context window").
- **Bater em max_tokens:** o modelo para de gerar; no chat completions isso é normalizado como `finish_reason: "length"` (não é erro), e o tipo `max_tokens_exceeded` também existe (400) para casos de erro. No Responses API, `context_length_exceeded`/`max_tokens_exceeded`/`token_limit_exceeded`/`string_too_long` são transformados em conclusões **bem-sucedidas** com `finish_reason: "length"`.
- **Estratégias doc nas melhores práticas:** fallbacks de modelo (`models: [...]` + `route: 'fallback'` — **[deprecated no spec]**, "Use `providers.sort.partition` instead", ver 6.2), routing com `provider.max_price`/`sort`/`quantizations`, e compressão de contexto via plugin `context-compression`.

Fonte: guia models + api_reference/parameters + errors-and-debugging.

## 9. Dicas de consulta (resumo operacional)

### 9.1 `GET /api/v1/models` — filtros e ordenação

- **Paginação:** `offset` + `limit` (default 500, máx 1000); omita ambos para a lista completa; use `links.next` para iterar. **[NÃO CONFIRMADO nos docs]** — o briefing pedia `per_page`/`cursor`; o spec atual usa `offset`/`limit` com `links.next`.
- **Por autor/ID:** não há query param `id` nem `author` em `/models` no spec atual; use `q` (busca) e `model_authors` (lista de autores). Para um modelo específico, use `GET /api/v1/model/{author}/{slug}`.
- **Filtros úteis:** `supported_parameters=tools` (modelos com tool calling), `output_modalities=image,audio`, `input_modalities`, `min_price`/`max_price` e `min_output_price`/`max_output_price` (USD), `min_age_days`/`max_age_days` (idade do modelo), índices `min_agentic_index`/`max_agentic_index`, `min_coding_index`/`max_coding_index`, `min_intelligence_index`/`max_intelligence_index`, `min_tool_success_rate`/`max_tool_success_rate`, `region` (edge region), `zdr` (só endpoints Zero Data Retention), `context` (tamanho de janela), `providers` (filtro por provider), `category`, `arch`, `distillable`.
- **Ordenação:** `sort` — `most-popular`, `newest`, `top-weekly`, `pricing-low-to-high`, `pricing-high-to-low`, `context-high-to-low`, `throughput-high-to-low`, `latency-low-to-high`, `intelligence-high-to-low`, `coding-high-to-low`, `agentic-high-to-low`, `design-arena-elo-high-to-low`.

### 9.2 Seleção de provider na prática

1. `GET /api/v1/models/{author}/{slug}/endpoints` para ver providers, preços por provider, tokens/s (p50–p99), latência, quantização, uptime.
2. Escolher um provider e forçar com `provider: { only: ["slug"] }` (ou `order` + `allow_fallbacks: false`).
3. Filtrar por qualidade: `provider.quantizations` (ex.: `["fp8","fp16"]`), `provider.data_collection: "deny"`, `provider.zdr: true`.
4. Teto de custo: `provider.max_price: { "prompt": 1, "completion": 2 }` (USD por 1M tokens — "<= $1/m prompt tokens").
5. Otimizar velocidade: `provider.sort: "throughput"` ou `"latency"`, com `preferred_min_throughput`/`preferred_max_latency`; `sort: {by: "throughput", partition: "none"}` para comparar entre modelos de fallback.
6. Observar a decisão: header `X-OpenRouter-Metadata: enabled` → `openrouter_metadata` (strategy, attempts, endpoints selecionados).

### 9.3 Erros que a skill deve tratar de forma exemplar

- 429 → backoff exponencial + `Retry-After`; em streaming, catch no chunk com `finish_reason: "error"`.
- 402 → avisar o usuário sobre créditos insuficientes (`GET /api/v1/credits`).
- 503 → nenhum provider disponível; relaxar `provider`/adicionar fallbacks (`models: [...]`).
- 400 `context_length_exceeded` → reduzir/truncar o prompt ou trocar modelo com janela maior.
- 401 → chave inválida/revogada (openrouter.ai/settings/keys).

---

## Apêndice A — Mapa de fontes por tópico

| Tópico | Fontes |
|---|---|
| Endpoints e paths | openapi.yaml; llms.txt |
| Lista de modelos / Model object | guides/overview/models; openapi.yaml |
| Endpoints por modelo (providers) | openapi.yaml (ListEndpointsResponse) |
| Credits / key | openapi.yaml; api_reference/limits |
| Auth | api_reference/authentication; api_reference/overview; guides/community/openai-sdk |
| Compat OpenAI | guides/community/openai-sdk; docs (Quickstart) |
| Usage / observabilidade | api_reference/overview; guides/features/router-metadata; guides/best-practices/reasoning-tokens |
| Erros | api_reference/errors-and-debugging; api_reference/limits; api_reference/streaming |
| Limites / contexto | api_reference/limits; api_reference/parameters; guia models |
| Parâmetros / provider | api_reference/parameters; guides/routing/provider-selection |

## Apêndice B — Divergências do briefing (resumo do que NÃO é como foi pedido)

1. Detalhe de modelo: `GET /api/v1/model/{author}/{slug}` (**singular**), não `/models/{author}/{slug}`.
2. Paginação de `/models`: `offset`/`limit` (+ `links.next`), não `per_page`/`cursor`.
3. Campo `limits` no Model: **não existe**; usar `context_length` + `per_request_limits` + `top_provider`.
4. `/credits` responde `data.total_credits`/`data.total_usage` (não `{total, used, limit}`); requer management key.
5. `provider_id` em endpoints: não existe; o identificador é `tag` (slug) + `provider_name`.
6. `X-OpenRouter-Metadata`: o formato atual é o objeto `openrouter_metadata` (requested, strategy, attempt, endpoints, attempts, pipeline...); os campos `mode/cost/tps/provider_name/quantization/timings{ttft,total}` do briefing não estão nos docs atuais.
7. `/api/v1/completions` (legado): fora do OpenAPI spec; docs só citam como "legacy Completions".
8. `reasoning_tokens` fica em `completion_tokens_details.reasoning_tokens` (não no topo de `usage`).
9. Headers opcionais: `X-OpenRouter-Title` (com `X-Title` aceito como alias no overview) e `HTTP-Referer`.
10. Query params do briefing (`author`, `order`, `id` em `/models`) não existem; os reais são `offset`, `limit`, `category`, `supported_parameters`, `output_modalities`, `input_modalities`, `sort`, `q`, `context`, `min_price`, `max_price`, `arch`, `model_authors`, `providers`, `distillable`.
