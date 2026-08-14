# OpenRouter — Roteamento e configuração avançada

> **Quando ler:** ao configurar roteamento — forçar um provider, fallbacks, variantes, plugins, caching, auto-router, BYOK, service tiers, ZDR. Para a API em si (endpoints, filtros, usage) veja `api.md`; para erros veja `errors.md`.
>
> **Fonte:** docs oficiais do OpenRouter (provider-selection, model-variants, plugins, routers, response-caching, prompt-caching, byok, zdr, service-tiers, presets) e o OpenAPI spec (https://openrouter.ai/openapi.yaml). Comportamentos mudam — revalide nas URLs citadas em cada seção.

## TOC (nesta página)
1. Objeto `provider` — tabela completa campo → tipo → default → comportamento
2. Roteamento default (load balancing por preço)
3. Fallback de modelos (`models[]`) e Zero-Completion Insurance
4. Variantes de modelo
5. Plugins e server tools
6. Response caching
7. Prompt caching e sticky routing
8. Auto Router, cost_tier, Pareto, Free
9. BYOK (Bring Your Own Key)
10. Service tiers e presets
11. ZDR e data collection
12. `route` deprecated → `providers.sort.partition`

## 1. Objeto `provider` — tabela completa campo → tipo → default → comportamento

Enviado no body da request (`provider: {...}`; via `extra_body` no SDK OpenAI). Fonte: https://openrouter.ai/docs/guides/routing/provider-selection + OpenAPI (`ProviderPreferences`).

| Campo | Tipo | Valores válidos | Default | Comportamento |
|---|---|---|---|---|
| `only` | string[] | slugs de provider (ex.: `"google-ai-studio"`) | — | **Restrição (allow-list).** Limita o roteamento aos slugs listados. O `only` da request estreita DENTRO da allow-list da conta; se nenhum provider satisfizer ambos, a request falha com **404**. Slugs base (ex.: `google-vertex`) casam TODOS os endpoints do provider, inclusive variantes regionais (`google-vertex/us-east5`); endpoints de service tier (`openai/priority`, `google-vertex/flex`) NÃO são casados por slug base — exigem `service_tier` ou slug com sufixo. |
| `ignore` | string[] | slugs de provider | — | **Restrição (deny-list).** Pula os slugs listados (mesclado com os providers ignorados na conta). |
| `order` | string[] | slugs, em ordem | — | **Ordem estrita de tentativa** ("prioritize providers in this list, and in this order"). Providers tentados um a um. Com `order`, o load balancing é **desligado**. Para restringir DE FATO à lista, combine com `allow_fallbacks: false`. |
| `allow_fallbacks` | boolean | `true` / `false` | `true` | `true`: permite providers de backup quando o primário está indisponível. `false`: só o top provider serve a request. |
| `require_parameters` | boolean | `true` / `false` | `false` | **Estrito.** `true`: a request "won't even be routed to that provider" se ele não suportar TODOS os parâmetros enviados. `false` (default): providers que não suportam um parâmetro "can still receive the request, but will ignore unknown parameters". Exceções (soft mesmo com `false`): `tools`, `response_format` (incl. structured outputs) e `verbosity` — a request só vai para providers que suportem; se NENHUM suportar, ainda assim é roteada e o parâmetro é ignorado. |
| `data_collection` | string | `"allow"` / `"deny"` | `"allow"` | `"allow"`: permite providers que armazenam dados de forma não-transitória (podem treinar). `"deny"`: só providers que não coletam dados de usuário. **Estrito** (erro se nenhum atender). Também configurável account-wide em Privacy settings. |
| `zdr` | boolean | `true` / `false` | omitido | `true`: restringe a "only ZDR (Zero Data Retention) endpoints". Semântica OR com ZDR da conta e de guardrails — a request só consegue GARANTIR ZDR, nunca desligar (ver seção 11). |
| `enforce_distillable_text` | boolean | `true` / `false` | omitido | `true`: só modelos onde o autor permitiu destilação de texto (útil para fine-tuning). |
| `max_price` | object | `{ "prompt": N, "completion": N, "request": N, "image": N }` — **USD por MILHÃO de tokens** (request/image por unidade) | — | **Estrito** — diferente dos thresholds de performance, `max_price` "will prevent your request from running if the price is not available". Ex.: `{"prompt": 1, "completion": 2}` = providers com prompt ≤ $1/M e completion ≤ $2/M. Combina bem com `sort`. |
| `sort` | string \| object | string: `"price"` \| `"throughput"` \| `"latency"` \| `"exacto"`; object: `{ by: ..., partition: "model"\|"none" }` | — | `"price"` = menor preço; `"throughput"` = maior throughput (tokens/s); `"latency"` = menor latência; `"exacto"` = qualidade de tool-calling. **Qualquer `sort` desliga o load balancing.** `partition` (default `"model"`): agrupa por modelo antes de ordenar; `"none"`: ordena globalmente entre TODOS os modelos da cadeia de fallback. |
| `preferred_min_throughput` | number \| object | número (aplica-se à p50) ou `{ p50, p75, p90, p99 }` tokens/s | — | **Preferência, NÃO garantia** (janela rolante de 5 min). "All specified cutoffs must be met" para entrar no grupo preferido. Endpoints abaixo do threshold são **deprioritizados (movidos para o fim), nunca excluídos** — "should therefore never prevent your request from being executed". |
| `preferred_max_latency` | number \| object | número (p50) ou `{ p50, p75, p90, p99 }` segundos | — | Mesma semântica de preferência da linha acima. |
| `quantizations` | string[] | `int4`, `int8`, `fp4`, `mxfp4`, `nvfp4`, `fp6`, `fp8`, `mxfp8`, `fp16`, `bf16`, `fp32`, `unknown` | — | Filtro de níveis de quantização dos endpoints. Aviso oficial: "Quantized models may exhibit degraded performance for certain prompts". |
| `route` | — | — | — | **Não existe dentro do objeto `provider`.** O parâmetro top-level `route` está deprecated (ver seção 12). |

## 2. Roteamento default (load balancing por preço)

Sem `sort`/`order`, o comportamento é: (1) "prioritize providers that have not seen significant outages in the last 30 seconds"; (2) entre os estáveis, "select one weighted by inverse square of the price" (peso ∝ 1/preço²); (3) "use the remaining providers as fallbacks". Exemplo dos docs: providers a $1, $2 e $3 → o de $1 é ~9x mais provável de ser tentado primeiro que o de $3.

Requests com `tools`/`tool_choice` vão para providers com suporte a tools; `max_tokens` filtra providers por capacidade de resposta. Fallback automático em 5xx e rate limits. Se nenhum provider satisfaz restrições de conta+request → **404**.

## 3. Fallback de modelos (`models[]`) e Zero-Completion Insurance

### 3.1 Cadeia de fallback de modelos

Parâmetro top-level `models: string[]` (OpenRouter-only): "If the first model returns an error, OpenRouter will automatically try the next model in the list." Qualquer erro pode disparar o fallback — os docs citam context length validation errors, moderation flags, rate-limiting, downtime. Se TODOS falharem, o erro do último é retornado. Preço: "Requests are priced using the model that was ultimately used" (refletido no campo `model` da resposta). No SDK OpenAI: `extra_body={"models": [...]}` com `model` = primário.

Cuidado: com `preferred_min_throughput`/`preferred_max_latency`, um modelo de fallback pode vencer o primário se só ele atender o threshold. `sort.partition: "none"` permite ordenar endpoints entre modelos (ex.: "whichever endpoint across all three models currently has the highest throughput"). Na API Anthropic `/api/v1/messages`: use `fallbacks: [{model: ...}]` — até 3 entradas (400 se mais), só aceita `model`, não combina com `models` (400).

### 3.2 Zero-Completion Insurance

Automático para todas as contas (sem config). Cobre: resposta com ZERO completion tokens E finish reason em branco/null, OU resposta com finish reason de erro (`error`) — nessas condições "no credits will be deducted for the model's prompt, completion, or reasoning tokens". NÃO cobre serviços auxiliares já executados (web search, file parsing/OCR de PDF, web fetch podem ser cobrados). A qualificação é por finish reason/zero tokens, não por código HTTP.

## 4. Variantes de modelo

Formato: `provider/model:variante` (ex.: `openai/gpt-4:free`). Fonte: https://openrouter.ai/docs/guides/routing/model-variants/{free,extended,exacto,thinking,nitro}.

| Variante | O que faz | Status |
|---|---|---|
| `:free` | Versões gratuitas (ex.: `meta-llama/llama-3.2-3b-instruct:free`). Rate limits próprios: 20 req/min; 50 req/dia (< 10 créditos comprados) ou 1000 req/dia (≥ 10 créditos). | Ativa |
| `:nitro` | Atalho para `provider.sort: "throughput"` — prioriza providers de maior tokens/s. | Ativo |
| `:floor` | Atalho para `provider.sort: "price"` (variante virtual). | Ativa |
| `:exacto` | Atalho para `provider.sort: "exacto"` — ordena por sinais de qualidade de tool-calling. **Variante virtual, sem pool de endpoints próprio**; sort explícito tem precedência sobre ela. | Ativa |
| `:extended` | Contexto estendido (ex.: `openai/gpt-4o:extended`). | Ativa |
| `:thinking` | Reasoning estendido (ex.: `deepseek/deepseek-r1:thinking`). **Deprecada para modelos Anthropic** — "Use the `reasoning` parameter instead". | Em deprecação |
| `:online` | Atalho para o plugin web search — **deprecated**: "The `:online` variant and the web search plugin are deprecated". Substituir pela server tool `openrouter:web_search`. | Deprecated |

- `:nitro`/`:floor`/`:exacto` são meros shorthands de `provider.sort` — coexistem com `only`/`ignore`/`order`/`quantizations`.
- Alias `~` (latest): `~anthropic/claude-sonnet-latest` resolve para o modelo concreto mais novo da família (nunca outro alias nem modelo oculto). O campo `model` da resposta reflete o concreto. Não recomendado para reprodutibilidade.
- Formato nativo é `author/model`; o prefixo `openrouter/` é só para slugs especiais (`openrouter/auto`, `openrouter/free`, `openrouter/pareto-code`, `openrouter/fusion`, `openrouter/auto-beta`).

## 5. Plugins e server tools

### 5.1 Plugins (`plugins[]` no body)

Formato: `"plugins": [{"id": "...", ...params}]`. "plugins always run once when enabled" (diferente de server tools, que o modelo chama 0–N vezes). Habilitáveis por request ou como defaults da conta (Settings > Plugins). Precedência: request > conta. Desligar um default por request: `{"id": "web", "enabled": false}`.

| Plugin `id` | O que faz | Parâmetros | Notas |
|---|---|---|---|
| `web` | Web search — **DEPRECATED** | `max_results` | Substituir por server tool `openrouter:web_search` |
| `response-healing` | Corrige JSON malformado de respostas LLM (brackets faltando, trailing commas, chaves sem aspas, code fences). | nenhum | Só ativa com `response_format` `json_schema` ou `json_object`; **só non-streaming**; não repara truncamento por `max_tokens` |
| `file-parser` | Parse de PDFs (e arquivos). | `pdf: { engine: "mistral-ocr" \| "cloudflare-ai" \| "native" }` (default: nativo do modelo, senão `mistral-ocr`); `pdf-text` (deprecated) → `cloudflare-ai` | Preços: mistral-ocr $2/1.000 páginas; cloudflare-ai grátis; native cobra como tokens de input. OCR é cobrado inclusive em BYOK. Máx. 8 imagens por PDF (mistral). PDFs vão no `content` como `{type: "file", file: {filename, file_data}}` (URL ou data URI `data:application/pdf;base64,...`). |
| `context-compression` | Comprime prompts que excedem a janela usando truncamento middle-out. | `engine` (default `'middle-out'`) | Funciona com qualquer modelo. **Default ON para endpoints com contexto ≤ 8.192 tokens** — desligue com `"enabled": false`. Claude: limite de 1.000 mensagens. |
| `fusion` | Deliberação multi-modelo: painel de modelos responde em paralelo (com `openrouter:web_search` + `openrouter:web_fetch` por default), um analista devolve análise JSON estruturada. | `preset` (`general-high`/`general-budget`/`general-fast`), `analysis_models` (1–8), `model`, `max_tool_calls` (default 4), `tools`, `enabled` | Modelo `openrouter/fusion` = habilitar server tool `openrouter:fusion`. Sem taxa extra documentada (só os completions extras). |
| `auto-router` | Config do Auto Router (seção 8). | `cost_tier`, `allowed_models`, `excluded_models`, `pin_model`, `enabled` | `cost_tier` vai AQUI, não top-level |
| `pareto-router` | Config do Pareto Router de código (seção 8). | `min_coding_score` (guia oficial); OpenAPI mostra também `max_price` (US$/M input) e `price_source` (`"prompt"` \| `"weighted_avg"`) | |

### 5.2 Server tools

- `openrouter:web_search` (beta): declare direto em `tools`: `{"type": "openrouter:web_search", "parameters": {...}}` — sem wrapper `type: "function"`. Parâmetros: `engine` (`auto` default, `native`, `exa`, `firecrawl`, `parallel`, `perplexity`), `mode`, `max_results` (1–25; default 5), `max_uses`, `max_total_results`, `search_context_size`, `max_characters`, `user_location`, `allowed_domains`/`excluded_domains`. Preços por engine (Exa $0.007/req; Parallel $0.001–0.005; Perplexity $0.005; Firecrawl usa créditos BYOK; native repassado do provider). Orçamento: `max_tool_calls` default 30. Uso reportado em `usage.server_tool_use.web_search_requests`.
- `openrouter:fusion`, `openrouter:advisor`, `openrouter:subagent`, `openrouter:experimental__search_models` — outros tipos de server tool no OpenAPI.

## 6. Response caching

Fonte: https://openrouter.ai/docs/guides/features/response-caching

- O que é cacheado: respostas de REQUISIÇÕES IDÊNTICAS na camada OpenRouter (antes do provider). Funciona com qualquer modelo, streaming e non-streaming, nas rotas chat completions, responses, messages e embeddings. **Só respostas 200 OK** são cacheadas (erros/rate limits/parciais nunca).
- **Chave do cache:** API key + modelo + tipo de endpoint + modo streaming + **SHA-256 do corpo da requisição** (normalizado por whitespace; **a ordem das propriedades JSON importa** — reordenar keys muda a chave). Headers de attribution e provider-specific ficam fora. Cache é escopado por API key.
- **TTL:** default **300 s**; range 1 s a 86.400 s (24 h). Config: header `X-OpenRouter-Cache-TTL` (inválidos caem no default; fora do range clampa) ou preset `cache_ttl_seconds`.
- **Custo:** "Cache hits are free" — todos os contadores de usage zerados; não contam para rate limits de provider. Requests simultâneas idênticas NÃO são coalescidas (ambas MISS e cobram).
- **Controle:** `X-OpenRouter-Cache: true|false` (por request), `X-OpenRouter-Cache-Clear: true` (apaga a entrada), presets `cache_enabled` + `cache_ttl_seconds`. **"If neither header nor preset is set, caching is off"** — caching é OFF por default. Respostas cacheadas são verbatim, "regardless of stochastic parameters like `temperature`".
- **Response headers:** `X-OpenRouter-Cache-Status` (`HIT`/`MISS`), `X-OpenRouter-Cache-Age` (só hits), `X-Generation-Id`.
- **ZDR:** com ZDR account-wide, o caching é DESLIGADO (caching requer armazenamento temporário). `provider.zdr` por request NÃO afeta a elegibilidade do cache.
- Não confundir com prompt caching do provider (próxima seção) — camadas separadas, podem ser usadas juntas.

## 7. Prompt caching e sticky routing

Fonte: https://openrouter.ai/docs/guides/best-practices/prompt-caching

- **Caching implícito** (OpenAI, Grok, Moonshot, Groq, DeepSeek, Z.AI, Gemini 2.5...): comportamento do provider, automático, sem config. `prompt_tokens_details.cached_tokens` mostra o que foi lido do cache.
- **Caching explícito (OpenAI GPT-5.6+):** marque blocos com `prompt_cache_breakpoint` (estilo OpenAI, em content blocks de texto) ou `cache_control: {"type": "ephemeral", "ttl": "5m"|"1h"}` (estilo Anthropic — o OpenRouter converte entre os dois). Máx. 4 breakpoints explícitos (Anthropic); TTL default 5 min; 1h custa 2x write. OpenAI explícito: TTL mínimo 30 min; cache writes 1.25x e reads 0.25x–0.5x (GPT-5.6+).
- **`prompt_cache_options`:** `{ "mode": "explicit", "ttl": N }` — o enum de `mode` tem **só `"explicit"`** (desliga breakpoints gerenciados pela OpenAI; só blocos marcados são cacheados). Não existe mode "simple".
- **`session_id`** (≤ 256 chars; body ou header `x-session-id`, body vence): "When provided, OpenRouter uses it as the sticky routing key" — ativa sticky routing em QUALQUER request bem-sucedido. **Sticky sessions expiram após 10 min de inatividade** (cada sucesso reseta o timer); keyed por conta+modelo+conversa (hash da primeira system/developer message + primeira message não-system por default). `prompt_cache_key` é o fallback estilo OpenAI.

## 8. Auto Router, cost_tier, Pareto, Free

### 8.1 `openrouter/auto` (Auto Router)

Fonte: https://openrouter.ai/docs/guides/routing/routers/auto-router

"Automatically selects the best model for your prompt" — use como `model` normal. Sem taxa extra ("You pay the standard rate for whichever model is selected"). Pipeline: (1) classificador rápido atribui ~30 task types (ex.: `code:debugging`, `agent:multi_step_planning`, `math`); (2) ranking por **spend share de mercado** (gasto agregado de milhões de usuários, janela de 7 dias, por task type); (3) aplica o cost_tier; (4) os top sobreviventes viram primário + fallbacks, respeitando restrições de conta/guardrails/ZDR/`allowed_models`/modalities. Degrada para um modelo default se classificação/rankings indisponíveis. **Sticky**: lembra o modelo da conversa e o prefere em turns seguintes (via `session_id` ou fingerprint das mensagens).

Config via `plugins: [{"id": "auto-router", ...}]`: `allowed_models`/`excluded_models` (wildcards: `anthropic/*`, `openai/gpt-5*`, `*/claude-*`; até 1024 patterns; exclusão vence allowlist; se nada sobrar → 404 "No models match your request and model restrictions"), `pin_model` (reusa o modelo da última mensagem assistant, default `false`), `enabled`. Defaults salvos na aba Routing do workspace; request vence, salvo "prevent overrides". `openrouter/auto-beta` = plugin `auto-beta-router`.

### 8.2 `cost_tier`

**Não é top-level** — vai em `plugins: [{"id": "auto-router", "cost_tier": "..."}]`. Tiers: `low`, `medium`, `high`, `xhigh`, `max` ("low favors the cheapest capable models, while max favors the most capable models regardless of price"). Bandas por percentil de custo (OpenAPI): low = [0, 20), medium = [20, 40), high = [40, 60), xhigh = [60, 80), max = [80, 100]. "A tier is a band, not a ceiling, so models cheaper than the band are excluded as well as models above it." Sem setting → roteia como se fosse `low`. `cost_quality_tradeoff` (0–10, default 9) está deprecated; `cost_tier` tem precedência.

### 8.3 `openrouter/pareto-code` (Pareto Router)

Plugin `pareto-router`; parâmetro documentado: `min_coding_score` (0–1; ≥0.66 high, ≥0.33 medium, <0.33 low, omitido = high; barra é percentil relativo à fronteira). Ordena por preço asc (ou p50 throughput com `:nitro`); primário + 2 fallbacks do mesmo tier; "The fallbacks only fire on transient provider errors or rate limits, they do not load-balance traffic". Seleção determinística. Sticky com expiração de 5 min de inatividade. Sem taxa extra. O OpenAPI mostra também `max_price` (US$/M input) e `price_source` (`"prompt"` | `"weighted_avg"`) no schema do plugin.

### 8.4 `openrouter/free` (Free Router)

Roteia para modelos `:free` disponíveis (https://openrouter.ai/docs/guides/routing/routers/free-router). Sujeito aos rate limits da seção de chave free de `errors.md`.

## 9. BYOK (Bring Your Own Key)

Fonte: https://openrouter.ai/docs/guides/overview/auth/byok

Usar suas próprias API keys de provider (OpenAI, Azure, AWS Bedrock, Google Vertex, etc.) através do OpenRouter; "your provider keys are securely encrypted and used for all requests routed through the specified provider".

- **Taxa:** 5% do custo que o mesmo modelo/provider custaria no OpenRouter, descontado dos créditos. Franquia isenta: PAYG $25.000/mês, Enterprise $200.000.
- **Ordem de tentativa:** Prioritized keys → OpenRouter shared endpoints → Fallback keys. Se uma key falha (rate limit/erro), cai para a próxima. Toggle "Always use for this provider" nunca cai para endpoints compartilhados.
- **Interação com `order`:** "OpenRouter **always prioritizes BYOK endpoints first, regardless of where that provider appears in your specified order.** There is currently no way to change this behavior."
- **Data policies:** políticas (ZDR, `data_collection`) são aplicadas ANTES de endpoints BYOK existirem; "a BYOK key does not exempt a provider from your ZDR or `data_collection` restrictions".
- **Budgets:** BYOK spend NÃO conta para guardrail/workspace budgets por default (`include_byok_in_budgets: true` para contar).
- **Debug:** Activity → "View Raw Metadata" → `provider_responses` (400 bad request, 401 invalid key, 403 permissions, 429 provider rate limit, 500 provider error).

## 10. Service tiers e presets

### 10.1 Service tiers (`service_tier`)

Fonte: https://openrouter.ai/docs/guides/features/service-tiers

- Valores: `flex` (menor custo, maior latência), `priority` (mais rápido, mais caro), `fast` = alias de `priority`. Anthropic `speed: "fast"` é intercambiável.
- Endpoints de tier são opt-in: parâmetro `service_tier` ou slugs com sufixo (`openai/priority`, `google-vertex/flex`) em `provider.only`/`order`.
- `priority`: endpoints matching tentados primeiro (sorted por throughput), com fallback off-tier possível (cobrado na taxa do endpoint real). `flex`: restrito a flex endpoints (sorted por price), NUNCA cai para default tier; se não há provider flex, roteia normal.
- Providers: OpenAI, Google Vertex, Google AI Studio, SpaceXAI (só `priority`). Billing sempre pela taxa do tier realmente servido. Resposta: `service_tier` top-level (chat/responses) ou dentro de `usage` (messages).

### 10.2 Presets

Fonte: https://openrouter.ai/docs/guides/features/presets

Configs nomeadas (modelos, provider preferences, system prompts, parâmetros, tools, e array de modelos com fallbacks). Referência: `model: "@preset/<slug>"`, campo `preset: "<slug>"`, ou `model: "<modelo>@preset/<slug>"`. Merge: parâmetros da request vencem o preset (shallow); tools são unidas (request sobrepõe por identidade). Criar: `POST /api/v1/presets/{slug}/chat/completions` (e skins messages/responses).

## 11. ZDR e data collection

- **ZDR** ("Zero Data Retention"): ativação account-wide (Privacy settings), por grupo de modelo (Anthropic, OpenAI, Google, SpaceXAI, Non-frontier), por guardrail (`enforce_zdr_*`) ou por request `provider.zdr: true`. Semântica OR — só garante, nunca desliga.
- **In-memory prompt caching NÃO é considerado "retaining"** — endpoints com cache implícito continuam elegíveis com ZDR. ZDR não se aplica a plugins/tools (web search etc. têm políticas próprias). Lista programática: `https://openrouter.ai/api/v1/endpoints/zdr`.
- **`data_collection`:** `"allow"` (default) permite providers que armazenam dados não-transitórios (podem treinar); `"deny"` restringe a providers que não coletam. Account-wide em Privacy settings. "OpenRouter does not log your source code prompts unless you explicitly opt-in to prompt logging in your account settings."
- **Guardrails** existem como recurso de ORG (dashboard + `POST /api/v1/guardrails`): budgets, model/provider allowlists, ZDR por grupo, prompt-injection detection, PII com ações `redact`/`block` (403 em block). **Não é parâmetro do body do chat** — privacidade por request é `provider.zdr`/`provider.data_collection`. O estágio `guardrail` aparece no `pipeline` do router metadata.

## 12. `route` deprecated → `providers.sort.partition`

O parâmetro top-level `route` está **DEPRECATED** (OpenAPI: `DeprecatedRoute`): "Use providers.sort.partition instead. Backwards-compatible alias... Accepts legacy values: 'fallback' (maps to 'model'), 'sort' (maps to 'none')." Ou seja, `route: "fallback"` ≡ `provider.sort.partition: "model"` e `route: "sort"` ≡ `partition: "none"`. Em código novo, use `provider.sort.partition` diretamente.
