# OpenRouter — Roteamento e Configuração Avançada (Pesquisa com Fontes)

> Pesquisa profunda sobre TODAS as opções de configuração e roteamento do OpenRouter, com fontes verificáveis nos docs oficiais. Todo parâmetro, default e comportamento listado abaixo foi extraído dos docs oficiais (URLs no final de cada seção e na seção Fontes) ou do OpenAPI spec oficial (`https://openrouter.ai/openapi.yaml`). Itens não encontrados nos docs estão marcados **[NÃO CONFIRMADO nos docs]**.
>
> Data da pesquisa: 2026-08-14. Os docs do OpenRouter mudam rápido — a SKILL.md deve citar as URLs e não hardcodar comportamento sem revalidar.

---

## 1. Visão geral

- Base da API: `POST https://openrouter.ai/api/v1/chat/completions` (OpenAI-compatible). Também: `/api/v1/responses` (Responses API), `/api/v1/messages` (Anthropic Messages API), `/api/v1/embeddings`, `/api/v1/completions`.
- "OpenRouter normalizes the schema across models and providers so you only need to learn one" — o corpo da requisição é "very similar to the OpenAI Chat API, with a few small differences" (fonte: https://openrouter.ai/docs/api_reference/overview).
- Parâmetros desconhecidos/não suportados: "the parameter is ignored" quando não suportado pelo provider (idem).
- Campos top-level do body (fonte: overview + OpenAPI): `model`, `models[]`, `provider`, `route` (deprecated), `service_tier`, `session_id`, `plugins[]`, `reasoning`, `response_format`, `structured_outputs`, `prompt_cache_options`, `prompt_cache_key`, `safety_identifier`/`user`, `transforms` (não confirmado), `web_search_options`, `verbosity`, `max_tokens`, `temperature`, `tools`, `tool_choice`, `stop`, `seed`, etc.

---

## 2. Objeto `provider` no corpo do request

Fonte primária: https://openrouter.ai/docs/guides/routing/provider-selection e https://openrouter.ai/openapi.yaml (schema `ProviderPreferences`).

### 2.1 Tabela campo → tipo → comportamento → default

| Campo | Tipo | Valores válidos | Default | Semântica (estrito/preferência) |
|---|---|---|---|---|
| `only` | `string[]` | slugs de provider (ex.: `"google-ai-studio"`) | — | **Restrição (allow-list).** Limita roteamento aos slugs listados. Aviso dos docs: "Only allowing some providers may significantly reduce fallback options and limit request recovery." O `only` da request estreita DENTRO da allow-list da conta; se nenhum provider satisfizer ambos, a request falha com 404. Slugs base (ex.: `google-vertex`) casam TODOS os endpoints do provider, incluindo variantes regionais (`google-vertex/us-east5`); endpoints de service tier (`openai/priority`, `google-vertex/flex`) NÃO são casados por slug base — exigem `service_tier` ou slug com sufixo. |
| `ignore` | `string[]` | slugs de provider | — | **Restrição (deny-list).** Pula os slugs listados; é mesclado com os providers ignorados na conta. Mesmo aviso sobre redução de fallbacks. |
| `order` | `string[]` | slugs, em ordem | — | **Ordem estrita de tentativa.** "The router will prioritize providers in this list, and in this order". Providers são tentados um a um. Com `order` definido, **o load balancing é desligado**. Para restringir de fato à lista, combine com `allow_fallbacks: false`. |
| `allow_fallbacks` | `boolean` | `true` / `false` | **`true`** | Permite providers de backup quando o primário está indisponível. `false` garante que só o top provider sirva a request. |
| `require_parameters` | `boolean` | `true` / `false` | `false` | **Estrito.** Com `true`, a request "won't even be routed to that provider" se ele não suportar todos os parâmetros enviados. Com `false` (default), providers que não suportam parâmetros "can still receive the request, but will ignore unknown parameters". Exceção: `tools`, `response_format` (incl. structured outputs) e `verbosity` funcionam como **soft preferences** mesmo com `false` — a request só é roteada para providers que suportem; mas se NENHUM provider do modelo suportar, a request ainda é roteada e o parâmetro é ignorado (nunca remove o modelo da lista de candidatos). |
| `data_collection` | `"allow"` \| `"deny"` | — | `"allow"` | `"allow"` (default): "allow providers which store user data non-transiently and may train on it". `"deny"`: "use only providers which do not collect user data". Também configurável account-wide em Privacy settings. **Estrito** (se nenhum provider atender, erro). |
| `zdr` | `boolean` | `true` / `false` | omitido | `true` restringe o roteamento a "only ZDR (Zero Data Retention) endpoints". Semântica OR com ZDR da conta e de guardrails — a request só consegue GARANTIR ZDR, nunca desligar (ver seção 10.4). |
| `enforce_distillable_text` | `boolean` | `true` / `false` | omitido | `true` restringe a "only models where the author has allowed text distillation" (útil para fine-tuning). |
| `max_price` | `object` | `{ "prompt": N, "completion": N }` (USD por MILHÃO de tokens) + `request` (preço por request), `image` (preço por imagem) e `audio` (preço por unidade de áudio) | — | **Estrito** — ao contrário dos thresholds de performance, "max_price ... will prevent your request from running if the price is not available" (o 404 documentado em provider-selection é do `only` ∩ allow-list da conta, não do max_price). Ex.: `{"prompt": 1, "completion": 2}` = providers com prompt ≤ $1/M e completion ≤ $2/M. Combina bem com `sort`. |
| `sort` | `string` \| `object` | string: `"price"` \| `"throughput"` \| `"latency"` \| `"exacto"`; object: `{ by: "price"|"throughput"|"latency"|"exacto", partition: "model"|"none" }` | — | `"price"` = menor preço; `"throughput"` = maior throughput (tokens/s); `"latency"` = menor latência; `"exacto"` = qualidade (tool-calling) — valor presente no OpenAPI (ProviderSort enum). **Qualquer valor de `sort` desliga o load balancing** ("If you have `sort` or `order` set in your provider preferences, load balancing will be disabled"). `partition` (default `"model"`): agrupa endpoints por modelo antes de ordenar; `"none"` ordena globalmente entre TODOS os modelos da cadeia de fallback (ex.: deixar um modelo fallback com BYOK vencer o primário). |
| `preferred_min_throughput` | `number` \| `object` | número (aplica-se à p50) ou objeto com percentis | — | **Preferência (NÃO é garantia).** `{ p50, p75, p90, p99 }` tokens/s, janela rolante de 5 minutos. "When you specify multiple percentile cutoffs, all specified cutoffs must be met for a model and provider to be in the preferred group." Endpoints abaixo do threshold são **deprioritizados (movidos para o fim da lista), nunca excluídos** — "should therefore never prevent your request from being executed". Com fallback de modelos, pode fazer um modelo fallback vencer o primário se só ele atender o threshold. |
| `preferred_max_latency` | `number` \| `object` | número (p50) ou objeto com percentis | — | Mesma semântica de preferência: `{ p50, p75, p90, p99 }` segundos. Mesma regra "all specified cutoffs must be met" e deprioritização em vez de exclusão. |
| `quantizations` | `string[]` | enum: `int4`, `int8`, `fp4`, `mxfp4`, `nvfp4`, `fp6`, `fp8`, `mxfp8`, `fp16`, `bf16`, `fp32`, `unknown` | — | Filtro de níveis de quantização dos endpoints. **Nota: `q8_0` NÃO existe no enum oficial** (presente em material não-oficial; ver tabela final). Aviso: "Quantized models may exhibit degraded performance for certain prompts". |
| `weights` | — | — | — | **[NÃO CONFIRMADO nos docs]** — o campo `weights` não existe no schema `ProviderPreferences` do OpenAPI nem na página de provider routing. |
| `route` | — | — | — | **[NÃO CONFIRMADO dentro do objeto provider]** — não existe no objeto `provider`. Existe o parâmetro top-level `route` (ver 2.3). |

### 2.2 Load balancing default (estocástico por preço)

Estratégia default (sem `sort`/`order`), citação direta dos docs:
1. "Prioritize providers that have not seen significant outages in the last 30 seconds" (**janela de interrupção de 30s**).
2. "For the stable providers, look at the lowest-cost candidates and select one weighted by inverse square of the price" (**peso ∝ 1/preço²**).
3. "Use the remaining providers as fallbacks."

Exemplo dos docs: provider A = $1/M, B = $2/M, C = $3/M (B em outage): A é tentado primeiro e "9x more likely to be first routed to Provider A than Provider C because $(1/3² = 1/9)$".

Fonte: https://openrouter.ai/docs/guides/routing/provider-selection

### 2.3 Parâmetro top-level `route` (DEPRECATED)

O OpenAPI define `route` como `DeprecatedRoute`: "**DEPRECATED** Use providers.sort.partition instead. Backwards-compatible alias for providers.sort.partition. Accepts legacy values: 'fallback' (maps to 'model'), 'sort' (maps to 'none')." — ou seja, `route: "fallback"` ≡ `provider.sort.partition: "model"` e `route: "sort"` ≡ `partition: "none"`. Marcar como deprecated na SKILL.

### 2.4 Cabeçalhos provider-specific

- `x-anthropic-beta` pass-through (valores separados por vírgula): `interleaved-thinking-2025-05-14` (thinking interleaved) e `structured-outputs-2025-11-13` (strict tool use p/ Claude).
- Para **strict tool use** (`strict: true` nas tools), o header `structured-outputs-2025-11-13` é OBRIGATÓRIO — sem ele, "OpenRouter will strip the `strict` field and route normally". Os demais (prompt caching, JSON-schema structured outputs) são auto-gerenciados.

Fonte: https://openrouter.ai/docs/guides/routing/provider-selection

---

## 3. Variantes de modelo (model variants)

Formato: `provider/model:variante`. Páginas oficiais: https://openrouter.ai/docs/guides/routing/model-variants/{free,extended,exacto,thinking,nitro}.md e https://openrouter.ai/docs/guides/overview/models ("Variant suffixes are also supported. Append `:free`, `:thinking`, etc. to the slug").

| Variante | O que faz | Equivalência | Status |
|---|---|---|---|
| `:free` | Acesso a versões gratuitas (ex.: `meta-llama/llama-3.2-3b-instruct:free`). Rate limits próprios: 20 req/min; 50 req/dia (<10 créditos comprados) ou 1000 req/dia (≥10 créditos). | — | Ativo. Fonte: model-variants/free + https://openrouter.ai/docs/api_reference/limits |
| `:nitro` | "alias for sorting providers by throughput" — prioriza providers de maior throughput (tokens/s). | "exactly equivalent to setting `provider.sort` to `'throughput'`" | Ativo. Fonte: model-variants/nitro |
| `:floor` | Ordenação por preço. | `provider.sort: "price"` (variante virtual). "Any of these will bypass Auto Exacto and revert to standard price-weighted ordering." | Documentado na página do Auto Exacto. Fonte: https://openrouter.ai/docs/guides/routing/auto-exacto |
| `:exacto` | Ordenação quality-first: "prefers providers with stronger tool-calling quality signals"; "a shortcut for setting the provider sort to Exacto on that model". **Variante virtual, sem endpoint pool próprio** — mesmo modelo, providers re-rankeados pelos mesmos sinais do Auto Exacto (tool-call success rate, throughput/latência, benchmarks). Interage: fallbacks via `models[]` funcionam; sort explícito (price/throughput/latency) **tem precedência** sobre exacto. | `provider.sort: "exacto"` (valor presente no OpenAPI ProviderSort enum) | **Ativo e documentado — o `:exacto` do material do usuário EXISTE oficialmente.** Fonte: https://openrouter.ai/docs/guides/routing/model-variants/exacto |
| `:extended` | Contexto estendido (ex.: `openai/gpt-4o:extended`). | — | Ativo. Fonte: model-variants/extended |
| `:thinking` | Reasoning estendido (ex.: `deepseek/deepseek-r1:thinking`). **Deprecado** segundo a página de Reasoning Tokens: "The `:thinking` variant is no longer supported for Anthropic models. Use the `reasoning` parameter instead." | `reasoning` param | Em deprecação (não suportado p/ Anthropic). Fontes: model-variants/thinking + https://openrouter.ai/docs/guides/best-practices/reasoning-tokens |
| `:online` | Atalho para o plugin web search — **deprecated**: "The `:online` variant and the web search plugin are deprecated." | `plugins: [{"id": "web"}]` → substituir por server tool `openrouter:web_search` | Deprecated. Fonte: https://openrouter.ai/docs/guides/features/plugins |

### Interação variantes × objeto provider

- `:nitro`/`:floor`/`:exacto` são meros shorthands de `provider.sort` — podem coexistir com `provider.only`/`ignore`/`order`/`quantizations` etc. (as demais restrições continuam valendo). O sort explícito tem precedência sobre `:exacto`.
- O alias `~` (latest): `~anthropic/claude-sonnet-latest` resolve para o modelo concreto mais novo da família (nunca resolve para outro alias nem modelo oculto; erro se nenhum elegível). O campo `model` da resposta reflete o modelo concreto. Alias retargetam parâmetros de reasoning quando o modelo exige (ex.: `effort: "none"` → menor effort suportado). Não recomendado para reprodutibilidade (pode mudar a qualquer momento). Fonte: https://openrouter.ai/docs/guides/routing/routers/latest-resolution
- **Nota sobre o formato `openrouter/<modelo>`**: a convenção nativa é `autor/modelo` (ex.: `anthropic/claude-sonnet-4.5`). O prefixo `openrouter/` é usado por SLUGS ESPECIAIS (`openrouter/auto`, `openrouter/free`, `openrouter/pareto-code`, `openrouter/fusion`, `openrouter/auto-beta`) e é a convenção de config de alguns CLIs (ex.: OpenClaw referencia `openrouter/~anthropic/claude-sonnet-latest` — ver seção 12).

---

## 4. Fallback de modelos (parâmetro `models`) e Zero-Completion Insurance

Fonte: https://openrouter.ai/docs/guides/routing/model-fallbacks e https://openrouter.ai/docs/guides/features/zero-completion-insurance

### 4.1 Cadeia de fallback

- Parâmetro top-level `models: string[]` (OpenRouter-only): "If the first model returns an error, OpenRouter will automatically try the next model in the list." **Qualquer erro pode disparar o fallback** — exemplos explícitos dos docs: "Context length validation errors" (context overflow), "Moderation flags for filtered models" (content filter), "Rate-limiting", "Downtime". (Os docs não listam códigos HTTP específicos 5xx/429 — descrevem categorias.)
- Se TODOS os fallbacks falharem: "If the fallback model is down or returns an error, OpenRouter will return that error."
- Preço: "Requests are priced using the model that was ultimately used", retornado no campo `model` da resposta.
- Cuidado com `preferred_min_throughput`/`preferred_max_latency`: "When using fallback models, this may cause a fallback model to be used instead of the primary model if it meets the threshold" (OpenAPI).
- `sort.partition: "none"` permite ordenar endpoints entre modelos — ex.: "whichever endpoint across all three models currently has the highest throughput"; ou maximizar uso de BYOK (endpoints BYOK são priorizados automaticamente quando há keys configuradas).
- **API Anthropic Messages** (`/api/v1/messages`): parâmetro `fallbacks: [{model: ...}]` — até 3 entradas (400 se mais), só aceita `model` (sem `max_tokens`/`thinking`/`speed`/`output_config`), não combina com `models` (400), e "The `fallbacks` parameter does not use Anthropic's server-side fallback feature" (OpenRouter faz o roteamento).
- SDK OpenAI: `extra_body={"models": [...]}` com `model` = primário.

### 4.2 Zero-Completion Insurance

- "Zero completion insurance is automatically enabled for all accounts and requires no configuration. ... automatically applies to all requests across all models and providers."
- Cobre: "The response has zero completion tokens AND a blank/null finish reason" OU "The response has an error finish reason". Nesses casos "no credits will be deducted for the model's prompt, completion, or reasoning tokens" — "even in cases where OpenRouter may have been charged by the provider for prompt processing".
- NÃO cobre: serviços auxiliares que já rodaram — web search fees, "file parsing / PDF OCR", "web fetch" "may still be billed based on the work actually performed".
- TTS (áudio vazio/inválido/truncado não é cobrado; pelo menos 1 frame MP3 ou sample PCM = cobrável) e image generation (sem imagem/base64 vazio/inválido = não cobrado) têm regras próprias.
- A página oficial NÃO enumera códigos HTTP (5xx, 429, timeouts, content filters, context overflow) — a qualificação é por finish reason/zero completion tokens.

---

## 5. Plugins e middleware

### 5.1 Plugins (parâmetro `plugins[]`)

Formato: `"plugins": [{ "id": "...", ...params }]`. "plugins always run once when enabled" (diferente de server tools, que o modelo chama 0–N vezes). Habilitáveis por request ou como defaults da conta (Settings > Plugins), com toggle "Prevent overrides". Precedência: request > conta. Desabilitar default por request: `{ "id": "web", "enabled": false }`.

Fonte: https://openrouter.ai/docs/guides/features/plugins

| Plugin `id` | O que faz | Parâmetros | Notas |
|---|---|---|---|
| `web` | Web search plugin — **DEPRECATED** | `max_results` | Substituir por server tool `openrouter:web_search`. |
| `response-healing` | "Automatically fix malformed JSON responses from LLMs" (brackets faltando, trailing commas, chaves sem aspas, code fences). **Só ativa com `response_format` `json_schema` ou `json_object`. Só non-streaming.** Não repara truncamento por `max_tokens`. | nenhum | Fonte: https://openrouter.ai/docs/guides/features/plugins/response-healing |
| `file-parser` | Parse de PDFs (e arquivos). **Nota: o plugin é `file-parser`, NÃO `pdf-input`** (material do usuário errou o id). | `pdf: { engine: "mistral-ocr" \| "cloudflare-ai" \| "native" }` (default: nativo do modelo, senão `mistral-ocr`); `pdf-text` deprecated → `cloudflare-ai` | Preços: mistral-ocr $2/1.000 páginas; cloudflare-ai grátis; native cobra como tokens de input. OCR é cobrado inclusive em BYOK (usa key da própria OpenRouter). Máx. 8 imagens por PDF (mistral). PDFs vão no `content` como `{type: "file", file: {filename, file_data}}` (URL ou data URI `data:application/pdf;base64,...`). Annotations `file.annotations` permitem evitar re-parse. Fonte: https://openrouter.ai/docs/guides/overview/multimodal/pdfs |
| `context-compression` | "Compress prompts that exceed a model's context window using middle-out truncation" (remove/trunca mensagens do meio). Funciona com qualquer modelo. **Default ON para endpoints com contexto ≤ 8.192 tokens** — desligar com `"enabled": false`. Claude: limite de 1.000 mensagens (mantém metade do início + metade do fim). Seleção de modelo: com compressão on, considera primeiro modelos com contexto ≥ metade dos tokens totais; senão usa o de maior contexto e comprime. | `engine` ("The compression engine to use. Defaults to 'middle-out'" — enum: [`middle-out`]) | Fonte: https://openrouter.ai/docs/guides/features/message-transforms (a página documenta o plugin) + OpenAPI (`ContextCompressionPlugin`) |
| `fusion` | Acesso a ferramenta de deliberação multi-modelo: painel de modelos responde em paralelo (com `openrouter:web_search` + `openrouter:web_fetch` por default — "Each model receives the same user prompt with web_search + web_fetch enabled"), um analista compara e devolve análise JSON estruturada (consenso, contradições, blind spots). Modelo `openrouter/fusion` = habilitar server tool `openrouter:fusion`. | `preset` (`general-high`/`general-budget`/`general-fast`), `analysis_models` (1–8), `model` (analista), `max_tool_calls` (default 4, 1–16), `tools` (server tools das chamadas internas de painelistas/analista; default `[{type: "openrouter:web_search"}, {type: "openrouter:web_fetch"}]`; array vazio desliga tools), `enabled` | Sem taxa extra documentada (só os completions extras). Anti-recursão via header `x-openrouter-fusion-depth`. Fonte: https://openrouter.ai/docs/guides/features/plugins/fusion + OpenAPI (`FusionPlugin`) |
| `auto-router` / `auto-beta-router` | Config do Auto Router (ver seção 6). | `cost_tier`, `allowed_models`, `excluded_models`, `pin_model`, `cost_quality_tradeoff` (deprecated), `enabled` | Fonte: https://openrouter.ai/docs/guides/routing/routers/auto-router + OpenAPI |
| `pareto-router` | Config do Pareto Router para código (ver seção 6). | `min_coding_score` (guia oficial); OpenAPI mostra também `max_price` (US$/M input) e `price_source` (`prompt`\|`weighted_avg`) no schema | Fonte: https://openrouter.ai/docs/guides/routing/routers/pareto-router + OpenAPI |
| `context_compression` (como estágio de pipeline) | Estágio de pipeline no metadata: `pipeline: [{type: "context_compression", ...}]` com engine e contagens | — | Fonte: https://openrouter.ai/docs/guides/features/router-metadata |

### 5.2 Server tools

- `openrouter:web_search` (beta): declarar direto em `tools`: `{ "type": "openrouter:web_search", "parameters": {...} }` — sem wrapper `type: "function"`. O modelo decide quando buscar e gera a query. Parâmetros: `engine` (`auto` default, `native`, `exa`, `firecrawl`, `parallel`, `perplexity`), `mode`, `max_results` (1–25; 1–20 Perplexity; default 5), `max_uses`, `max_total_results`, `search_context_size` (low/medium/high), `max_characters`, `user_location`, `allowed_domains`/`excluded_domains`. Preços: Exa $0.007/req (Instant/Fast/Auto; $0.012 Deep Lite/Deep; $0.015 Deep Reasoning); Parallel $0.001 (Turbo/Fast) / $0.005 (Basic/Advanced); Perplexity $0.005; Firecrawl usa seus créditos BYOK (2 créditos/10 resultados); native repassado do provider (OpenAI, Anthropic, Google, Perplexity, SpaceXAI). Orçamento: `max_tool_calls` default 30 steps. Uso reportado em `usage.server_tool_use.web_search_requests` (aninhado em `server_tool_use` dentro do objeto `usage` — "The `web_search_requests` field counts the total number of search queries the model made during the request"). Fonte: https://openrouter.ai/docs/guides/features/server-tools/web-search
- `openrouter:fusion`, `openrouter:advisor`, `openrouter:subagent` (presets podem carregá-los), `openrouter:experimental__search_models` (tipo de server tool no OpenAPI — o "experimental" do spec é tool, não um modelo `openrouter/experimental`).

### 5.3 Middleware / parâmetros especiais

| Parâmetro | Tipo | Valores / comportamento | Fonte |
|---|---|---|---|
| `reasoning` | objeto | `{ effort: "max"\|"xhigh"\|"high"\|"medium"\|"low"\|"minimal"\|"none", max_tokens: N, exclude: bool (default false), enabled: bool (default inferido), context: "auto"\|"all_turns"\|"current_turn" (GPT-5.6+), mode: "standard"\|"pro" (GPT-5.6+ via OpenAI/Azure) }`. **"min" NÃO é valor válido — é `minimal`** (correção ao material do usuário). Alocação de budget: max/xhigh ≈95%, high ≈80%, medium ≈50%, low ≈20%, minimal ≈10% do `max_tokens`. Reasoning tokens contam como output (cobrados). `include_reasoning` = alias deprecated de `reasoning.exclude`. Fórmula Anthropic: `budget_tokens = max(min(max_tokens × ratio, 128000), 1024)`; `max_tokens` deve ser estritamente maior que o budget. | https://openrouter.ai/docs/guides/best-practices/reasoning-tokens |
| `reasoning_effort` | enum | `xhigh, high, medium, low, minimal, none` (OpenAI-style, top-level). | parameters page |
| `response_format` | objeto | `{"type": "json_object"}` (JSON mode) ou `{"type": "json_schema", "json_schema": {"name", "strict": true, "schema"}}` (structured outputs). Suporte é POR ENDPOINT — verificar em `supported_parameters=structured_outputs`; para garantir, use `require_parameters: true`. Funciona com streaming. "Enforcement varies by provider: some guarantee schema-conforming output, while others translate your schema ... or treat it as a strong hint." | https://openrouter.ai/docs/guides/features/structured-outputs |
| `structured_outputs` | boolean | "If the model can return structured outputs using response_format json_schema". | parameters page |
| `thinking` | — | Anthropic Messages API: `thinking.display: "summarized"` (default) / `"omitted"`. A variante `:thinking` está deprecada em favor do `reasoning`. | https://openrouter.ai/docs/guides/best-practices/reasoning-tokens |
| `cache_control` | objeto | Compat Anthropic: `{"type": "ephemeral", "ttl": "5m"\|"1h"}` em content blocks. Intercambiável com `prompt_cache_breakpoint` (OpenRouter converte entre estilos). Anthropic: máx. 4 breakpoints explícitos; TTL default 5 min, 1h custa 2x write. | https://openrouter.ai/docs/guides/best-practices/prompt-caching |
| `prompt_cache_breakpoint` | objeto | OpenAI-style, em content blocks de texto (`type: "text"`/`"input_text"`). GPT-5.6+ para explícito. | idem |
| `prompt_cache_options` | objeto | Top-level: `{ mode: "explicit", ttl }` — enum do schema `PromptCacheOptions` é **só `"explicit"`** (desliga breakpoints gerenciados pela OpenAI; só blocos marcados com `prompt_cache_breakpoint` são cacheados; suportado por OpenAI GPT-5.6+). **"simple" NÃO existe como valor de mode.** O caching implícito (OpenAI, Grok, Moonshot, Groq, DeepSeek, Z.AI, Gemini 2.5 — auto, sem config) é comportamento de provider, não um valor de mode. OpenAI explícito: mínimo TTL 30 min. | idem + OpenAPI (`PromptCacheOptions`) |
| `prompt_cache_key` | string | Chave de sessão estilo OpenAI (fallback de `session_id` para sticky routing). | idem + OpenAPI |
| `session_id` | string (≤256 chars) | Top-level ou header `x-session-id` (body vence). "When provided, OpenRouter uses it as the sticky routing key" — ativa sticky routing em QUALQUER request bem-sucedido (mesmo antes de cache hit); agrupa requests de chat/responses/embeddings/reranking/speech/image/video na aba Sessions. **Sticky sessions expiram após 10 minutos de inatividade** (cada sucesso reseta o timer); keyed por conta+modelo+conversa (hash da primeira system/developer message + primeira message não-system por default). Obs.: Pareto Router usa expiração de 5 min. | https://openrouter.ai/docs/guides/best-practices/prompt-caching + OpenAPI |
| `web_search_options` | objeto | "Configures native web search options for models and providers that support web-connected answers." (Nenhum sub-campo documentado na parameters page.) | parameters page |
| `input_audio` | content part | `{type: "input_audio", input_audio: {data: base64, format: "wav"\|"mp3"\|"flac"\|"m4a"\|"ogg"\|"aiff"\|"aac"\|"pcm16"\|"pcm24"}}` — formatos variam por provider. | OpenAPI |
| `guardrails` | — | **[NÃO CONFIRMADO como parâmetro de request]**. Guardrails existem como recurso de ORG: dashboard + API `/api/v1/guardrails` (budget, model allowlist, provider allowlist, ZDR por grupo, prompt injection, PII sensitive info, custom content filters; ações `redact`/`block`; 403 em block). Não encontrado campo `guardrails` no body em nenhum doc — ZDR por request é via `provider.zdr`. Estágio `guardrail` (ex.: `content-filter`, `moderation`) aparece no `pipeline` do metadata. | https://openrouter.ai/docs/guides/features/guardrails + router-metadata |
| `transforms` | — | **[NÃO CONFIRMADO nos docs]** — não encontrado no OpenAPI nem nas páginas (a página "Message Transforms" documenta o plugin context-compression, não um param `transforms`). | OpenAPI + llms.txt |
| `context_compression` | — | **[NÃO CONFIRMADO como parâmetro]** — existe como PLUGIN (`id: "context-compression"`), não como parâmetro de body. | message-transforms |
| `cost_tier` | string | NÃO é top-level: vai em `plugins: [{id: "auto-router", cost_tier: ...}]` (ver seção 6). | auto-router |

---

## 6. Roteamento especial: Auto Router, cost_tier, Pareto, Fusion, Free

Fonte: https://openrouter.ai/docs/guides/routing/routers/auto-router e OpenAPI.

### 6.1 `openrouter/auto` (Auto Router)

- "automatically selects the best model for your prompt"; usar como `model` normal. Sem taxa extra ("You pay the standard rate for whichever model is selected. There is no additional fee").
- Pipeline: (1) classificador rápido atribui ~30 task types (`code:debugging`, `agent:multi_step_planning`, `math`, `customer_support`, ...) — visível em `data.task_type` do router metadata (header `X-OpenRouter-Metadata: enabled`); (2) ranking por **spend share do mercado** — "the aggregate spend of millions of people using OpenRouter, measured over a trailing 7-day window for each task type" (sinal vivo: "when developers migrate a workload to a new model, the router follows within days"); (3) aplica o cost_tier; (4) "the top surviving models (in market spend-share order) become the primary pick plus fallbacks", respeitando restrições de conta/guardrails/ZDR/`allowed_models`/modalities. Degrada para um modelo default se classificação/rankings indisponíveis.
- **Sticky**: "remembers the model a conversation landed on and prefers it on later turns", via `session_id` ou fingerprint das mensagens; só reutiliza enquanto o modelo ainda estiver entre os top candidatos.
- Config: `allowed_models`/`excluded_models` (wildcards: `anthropic/*`, `openai/gpt-5*`, `*/claude-*`; até 1024 patterns; exclusão vence allowlist; se nada sobrar → 404 "No models match your request and model restrictions"). Defaults salvos na aba Routing do workspace; request vence, salvo "prevent overrides".
- `openrouter/auto-beta` (early access, plugin id `auto-beta-router`; cada slug só lê settings do próprio plugin id).

### 6.2 `cost_tier`

- Enviado como `plugins: [{ id: "auto-router", cost_tier: "..." }]`. Tiers: `low`, `medium`, `high`, `xhigh`, `max` ("low favors the cheapest capable models, while max favors the most capable models regardless of price").
- OpenAPI define as bandas por percentil de custo: **low = [0, 20), medium = [20, 40), high = [40, 60), xhigh = [60, 80), max = [80, 100]**.
- "A tier is a band, not a ceiling, so models cheaper than the band are excluded as well as models above it."
- Sem setting → roteia "as if you had asked for roughly the `low` band".
- `cost_quality_tradeoff` (0–10, default 9) está DEPRECATED; `cost_tier` tem precedência.
- `pin_model` (auto-router only): "reuses the model from the most recent assistant message's `model` attribute", default `false`.

### 6.3 Outros routers `openrouter/*`

- `openrouter/free` — Free Models Router: roteia para modelos `:free` disponíveis (https://openrouter.ai/docs/guides/routing/routers/free-router).
- `openrouter/pareto-code` — Pareto Router para coding: plugin `pareto-router`; parâmetro único documentado `min_coding_score` (0–1; ≥0.66 high, ≥0.33 medium, <0.33 low, omitido = high; barra é percentil relativo à fronteira). Ordena por preço asc (ou p50 throughput com `:nitro`); primário + 2 fallbacks do mesmo tier; "The fallbacks only fire on transient provider errors or rate limits, they do not load-balance traffic". Seleção determinística. Sticky com expiração de 5 min de inatividade. Sem taxa extra. OpenAPI mostra também `max_price` (US$/M input) e `price_source` no schema do plugin (a página do guia diz que só existe min_coding_score — citar ambos com nota). Fonte: https://openrouter.ai/docs/guides/routing/routers/pareto-router
- `openrouter/fusion` — Fusion Router: equivalência ao plugin/server tool `fusion` (ver 5.1).
- `openrouter/auto-beta` — ver 6.1.
- **[NÃO CONFIRMADO]** `openrouter/experimental` — nenhum doc/slug oficial encontrado (o único "experimental" no OpenAPI é o tipo de server tool `openrouter:experimental__search_models`).

---

## 7. Response caching (cache de respostas)

Fonte: https://openrouter.ai/docs/guides/features/response-caching

- O que é cacheado: respostas de REQUISIÇÕES IDÊNTICAS na camada OpenRouter (antes do provider) — funciona com qualquer modelo; streaming e non-streaming; **só respostas 200 OK** (erros/rate limits/parciais nunca são cacheados; respostas com tool calls são cacheadas normalmente). Endpoints: `/api/v1/chat/completions`, `/api/v1/responses`, `/api/v1/messages`, `/api/v1/embeddings`.
- **Chave do cache (hash)**: API key + modelo + tipo de endpoint + modo streaming + **SHA-256 do corpo da requisição** (normalizado por whitespace; **a ordem das propriedades JSON importa** — reordenar keys ou enviar defaults explicitamente muda a chave). Headers de attribution e provider-specific ficam de fora. Cache é escopado por API key (rotação de key = cache vazio). Conteúdo multimodal entra no hash.
- **TTL**: default **300 segundos** (5 min); range **1 s a 86.400 s (24 h)**. Config: header `X-OpenRouter-Cache-TTL` (sobrepõe presets; valores inválidos caem para o default; decimals truncados; fora do range clampa em [1, 86400]) ou preset `cache_ttl_seconds`.
- **Custo**: "Cache hits are free" — todos os contadores de usage zerados, nada é cobrado (você paga só pela request original). "Cache hits do not count toward provider rate limits since the request never reaches a provider." Requests simultâneas idênticas NÃO são coalescidas (ambas MISS e cobram).
- Controle por header: `X-OpenRouter-Cache: true|false` (liga/desliga por request), `X-OpenRouter-Cache-TTL`, `X-OpenRouter-Cache-Clear: true` (apaga a entrada e refaz). Presets: `cache_enabled` + `cache_ttl_seconds`. Precedência: preset `cache_enabled: false` não pode ser sobrescrito; header `false` desliga mesmo com preset on; header `true` só liga se o preset estiver omisso. **"If neither header nor preset is set, caching is off."** Respostas cacheadas são devolvidas verbatim — "regardless of stochastic parameters like `temperature`".
- Response headers: `X-OpenRouter-Cache-Status` (`HIT`/`MISS`), `X-OpenRouter-Cache-Age` (só hits), `X-OpenRouter-Cache-TTL`, `X-Generation-Id` (todas as respostas).
- **ZDR vs cache**: com ZDR account-wide ativo, o caching é DESLIGADO ("caching requires temporarily storing response data"). **`provider.zdr` por request NÃO afeta a elegibilidade do cache.**
- **NÃO confundir** com provider-side prompt caching (Anthropic cache_control etc.) — são camadas separadas e podem ser usadas juntas. `session_id` não tem interação documentada com o response cache.

---

## 8. BYOK (Bring Your Own Key)

Fonte: https://openrouter.ai/docs/guides/overview/auth/byok

- O que é: usar suas próprias API keys de provider (OpenAI, Azure, AWS Bedrock, Google Vertex, etc.) através do OpenRouter; "your provider keys are securely encrypted and used for all requests routed through the specified provider".
- **Taxa: 5% do custo que o mesmo modelo/provider custaria normalmente no OpenRouter**, descontado dos seus créditos. Franquia isenta: **PAYG $25.000/mês, Enterprise $200.000** (medida pelo custo list-price de inferência, não por contagem de requests).
- Ordem de tentativa: **Prioritized keys → OpenRouter shared endpoints → Fallback keys**. Se uma key falha (rate limit/erro), cai para a próxima. Toggle **"Always use for this provider"**: nunca cai para endpoints compartilhados (pode gerar rate-limit errors, mas garante que tudo passa pela sua conta).
- **Interação com `order`**: "OpenRouter **always prioritizes BYOK endpoints first, regardless of where that provider appears in your specified order.** ... There is currently no way to change this behavior." Exemplo: `order: ["amazon-bedrock", "google-vertex"]` com key Vertex → Vertex BYOK → Bedrock shared → Vertex shared.
- Várias keys por provider: cada uma vira um endpoint próprio pinado; ordem por `sort_order`; filtros por modelo / API key / membro.
- **Data policies**: "BYOK endpoints are subject to your data policies" — políticas (ZDR, `data_collection`) são aplicadas ANTES de endpoints BYOK existirem; "a BYOK key does not exempt a provider from your ZDR or `data_collection` restrictions".
- Budgets: BYOK spend NÃO conta para guardrail budgets por default (`include_byok_in_budgets: true` para contar o valor que OpenRouter cobraria); o mesmo vale para workspace budgets.
- Debug: Activity → "View Raw Metadata" → `provider_responses` (400 bad request, 401 invalid key, 403 permissions, 429 provider rate limit, 500 provider error).
- Providers suportados com credenciais: OpenAI, Azure (config Foundry ou per-deployment), AWS Bedrock (API key region-locked ou credentials JSON), Google Vertex (service account JSON + região), etc.

---

## 9. Headers de roteamento e atribuição

Fonte: https://openrouter.ai/docs/guides/features/router-metadata e https://openrouter.ai/docs/app-attribution

| Header | Uso |
|---|---|
| `X-OpenRouter-Metadata: enabled` | Opt-in por request (case-insensitive) nos 4 endpoints. Adiciona `openrouter_metadata` à resposta (e ao envelope de erro). Campos: `requested`, `strategy` (`direct`, `auto`, `free`, `latest`, `alias`, `fallback`, `pareto`, `bodybuilder`, `fusion`), `region`, `summary`, `attempt` (1-indexed; >1 = falhas anteriores), `is_byok`, `endpoints[]` (provider/model/selected), `params` (ex.: `quality_floor`, `throughput_floor`), `attempts[]`, `pipeline[]` (estágios `guardrail`/`plugin`/`server_tools`/`response_healing`/`context_compression`). Streaming: no chunk final antes de `[DONE]`. **Cache hits NÃO incluem o metadata.** 500s são scrubbed (outros 5xx incluem). `X-OpenRouter-Experimental-Metadata` = nome antigo, ainda aceito. (Nota: a página do Auto Router menciona `data.task_type` no metadata; a página do Router Metadata não o lista — citar com ressalva.) |
| `HTTP-Referer` | **Obrigatório para app attribution** — identificador primário do app nos rankings. |
| `X-OpenRouter-Title` | Nome de exibição do app (com `X-Title` como legacy). Sozinho não cria app page — precisa do `HTTP-Referer`. |
| `X-OpenRouter-Categories` | Comma-separated, até 2 por request; categorias reconhecidas: `cli-agent`, `ide-extension`, `cloud-agent`, `programming-app`, `native-app-builder`, `creative-writing`, `video-gen`, `image-gen`, `audio-gen`, `writing-assistant`, `general-chat`, `personal-agent`, `legal`, `roleplay`, `game`; não reconhecidas são descartadas; merge até 10 por app. |
| `X-OpenRouter-App` | **[NÃO CONFIRMADO nos docs]** — não existe nos docs de attribution; o par de headers correto é `HTTP-Referer` + `X-OpenRouter-Title`. |
| `X-OpenRouter-Cache`, `X-OpenRouter-Cache-TTL`, `X-OpenRouter-Cache-Clear`, `X-OpenRouter-Cache-Status`, `X-OpenRouter-Cache-Age` | Cache de respostas (ver seção 7). |
| `X-Generation-Id` | Em toda resposta; usado para buscar a geração em `GET /api/v1/generation`. |
| `X-RateLimit-*`, `Retry-After` | Só em 429s gerados pela plataforma (respostas bem-sucedidas não incluem). |

---

## 10. Outros recursos relevantes

### 10.1 Service tiers (`service_tier`)
Fonte: https://openrouter.ai/docs/guides/features/service-tiers
- Valores: `flex` (menor custo, maior latência), `priority` (mais rápido, mais caro), `fast` = alias de `priority`. Anthropic `speed: "fast"` é intercambiável.
- Endpoints de tier são opt-in: parâmetro `service_tier` ou slugs com sufixo (`openai/priority`, `google-vertex/flex`) em `provider.only`/`order`.
- `priority`: endpoints matching tentados primeiro (sorted por throughput), com fallback off-tier possível (cobrado na taxa do endpoint real). `flex`: restrito a flex endpoints (sorted por price), NUNCA cai para default tier; se não há provider flex, roteia normal.
- Providers: OpenAI, Google Vertex, Google AI Studio, SpaceXAI (só `priority`). Billing sempre pela taxa do tier realmente servido.
- Resposta: `service_tier` top-level (chat/responses) ou dentro de `usage` (messages; `"standard"` vs `"default"`).

### 10.2 Presets
Fonte: https://openrouter.ai/docs/guides/features/presets
- Configs nomeadas (modelos, provider preferences, system prompts, parâmetros, tools, e "array of models with fallbacks"). Referência: `model: "@preset/<slug>"`, campo `preset: "<slug>"`, ou `model: "<modelo>@preset/<slug>"`.
- Merge: parâmetros da request vencem o preset (shallow); tools são unidas (request sobrepõe por identidade).
- Criar: `POST /api/v1/presets/{slug}/chat/completions` (e skins messages/responses). Versões: sempre a latest via API.

### 10.3 Data collection & logging
- `data_collection` por request (ver 2.1); Privacy settings account-wide; "Input & Output Logging" é opt-in; "OpenRouter does not log your source code prompts unless you explicitly opt-in to prompt logging in your account settings" (fonte: claude-code-integration cookbook).

### 10.4 ZDR
Fonte: https://openrouter.ai/docs/guides/features/zdr
- "Zero Data Retention (ZDR) means that a provider will not store your data for any period of time." Ativação: account-wide (Privacy), por grupo de modelo (**Anthropic, OpenAI, Google, SpaceXAI, Non-frontier**), por guardrail (`enforce_zdr_anthropic`, `enforce_zdr_openai`, `enforce_zdr_google`, `enforce_zdr_xai`, `enforce_zdr_other`; `enforce_zdr` legacy deprecated), ou por request `provider.zdr: true`. Semântica OR — só garante, nunca desliga.
- **In-memory prompt caching NÃO é considerado "retaining"** — endpoints com cache implícito continuam elegíveis com ZDR.
- ZDR não se aplica a plugins/tools (web search etc. têm políticas próprias).
- Lista programática: `https://openrouter.ai/api/v1/endpoints/zdr`.

### 10.5 Limits / rate limits
Fonte: https://openrouter.ai/docs/api_reference/limits
- Modelos `:free`: 20 RPM sempre; 50 req/dia (< 10 créditos comprados no total) ou 1.000 req/dia (≥ 10 créditos) — `FREE_MODEL_CREDITS_THRESHOLD = 10`, unidade é **créditos** (coluna "Credits purchased (all time)"), não dólares. Variantes pagas: sem cap de requests no nível da plataforma.
- 402 = créditos/limite; 429 = rate limit (plataforma ou provider — `error.metadata.provider_code` identifica; fallback re-tenta outros providers). Mid-stream: rate limits chegam como SSE com `finish_reason: "error"`.
- `GET /api/v1/key` → `limit`, `limit_remaining`, `limit_reset`, `is_free_tier`, contadores diários/semanais/mensais.

### 10.6 Reasoning details na resposta
- `choices[].message.reasoning_details` (non-streaming) / `choices[].delta.reasoning_details` (streaming), com tipos `reasoning.summary`, `reasoning.encrypted`, `reasoning.text`; formatos `anthropic-claude-v1` (default), `google-gemini-v1`, `openai-responses-v1`, etc. Preservar entre turns ecoando `message.reasoning` ou `reasoning_details` (necessário para tool calling multi-turn). Fonte: reasoning-tokens.

---

## 11. TABELA FINAL DE VERIFICAÇÃO DO MATERIAL DO USUÁRIO

| # | Claim do material do usuário | Status | Fonte (URL oficial) | Correção / nota |
|---|---|---|---|---|
| 1 | Balanceamento estocástico 1/p² com janela de interrupção de 30s | **[VERIFICADO]** | https://openrouter.ai/docs/guides/routing/provider-selection | "weighted by inverse square of the price"; "not seen significant outages in the last 30 seconds"; exemplo 1/9 (3²). |
| 2 | Fallback de provider por padrão (`allow_fallbacks: true`) | **[VERIFICADO]** | https://openrouter.ai/docs/guides/routing/provider-selection + OpenAPI (`ProviderPreferences.allow_fallbacks`, default true) | Confirma: default `true`. |
| 3 | Seguro de zero-completion (não cobra chamadas que falham) | **[VERIFICADO]** | https://openrouter.ai/docs/guides/features/zero-completion-insurance | Automático para todas as contas/modelos/providers. NUANCE: qualificação é por "zero completion tokens + finish reason blank/null" OU "error finish reason" — os docs não enumeram 5xx/429/timeouts; custos auxiliares (web search, OCR de PDF) podem ser cobrados mesmo em falha. |
| 4 | Variantes `:nitro` e `:floor`; sort throughput/price | **[VERIFICADO]** | https://openrouter.ai/docs/guides/routing/model-variants/nitro (nitro = sort "throughput"); https://openrouter.ai/docs/guides/routing/auto-exacto (:floor = sort "price"); sort: provider-selection | `sort` também aceita `"latency"` e `"exacto"` (OpenAPI). |
| 5 | `preferred_min_throughput` / `preferred_max_latency` com percentis | **[VERIFICADO]** | https://openrouter.ai/docs/guides/routing/provider-selection + OpenAPI (`PercentileThroughputCutoffs`/`PercentileLatencyCutoffs`: p50/p75/p90/p99; janela rolante 5 min; "all specified cutoffs must be met") | Preferência, não garantia: endpoints são deprioritizados, nunca excluídos. |
| 6 | Quantização: campo `quantization` nos endpoints; filtro `quantizations` | **[VERIFICADO com correção]** | https://openrouter.ai/docs/guides/routing/provider-selection + OpenAPI (`Quantization` enum) | Filtro `provider.quantizations` confirmado. **Correção: `q8_0` NÃO existe — enum oficial: `int4, int8, fp4, mxfp4, nvfp4, fp6, fp8, mxfp8, fp16, bf16, fp32, unknown`.** Campo `quantization` individual de endpoint não foi localizado nos docs consultados (só o filtro). |
| 7 | Sticky routing (`session_id`; expiração 10 min) | **[VERIFICADO]** | https://openrouter.ai/docs/guides/best-practices/prompt-caching | "Sticky sessions expire after 10 minutes of inactivity" — para cache de prompts. `session_id` (≤256 chars, body ou header `x-session-id`) é a chave de sticky routing. NUANCE: Pareto Router usa expiração de 5 min. |
| 8 | Response caching: hash da requisição; TTL; custo zero em cache hit | **[VERIFICADO]** | https://openrouter.ai/docs/guides/features/response-caching | Chave = API key + modelo + endpoint + streaming + SHA-256 do body (ordem de propriedades importa). TTL default 300 s, range 1 s–24 h. "Cache hits are free". Headers `X-OpenRouter-Cache[-TTL/-Clear/-Status/-Age]`. |
| 9 | Auto Exacto; `"plugins": [{"id": "response-healing"}]` | **[VERIFICADO]** | https://openrouter.ai/docs/guides/routing/auto-exacto; https://openrouter.ai/docs/guides/features/plugins/response-healing | Auto Exacto roda por default em TODAS as requests com tools (reordena providers por throughput real-time, tool-call success rate e benchmarks). response-healing: só com `response_format` json_schema/json_object e só non-streaming. |
| 10 | Web search via tool `openrouter:web_search` | **[VERIFICADO]** | https://openrouter.ai/docs/guides/features/server-tools/web-search | `{"type": "openrouter:web_search", "parameters": {...}}` direto no `tools[]`. Engines: auto/native/exa/firecrawl/parallel/perplexity; preços por engine (Exa $0.007, Parallel $0.001–0.005, Perplexity $0.005, Firecrawl BYOK). Plugin `web` e `:online` deprecated. |
| 11 | "GPT-5.6" cache pricing 1.25x/0.25x | **[VERIFICADO]** | https://openrouter.ai/docs/guides/best-practices/prompt-caching | OpenAI: cache writes **1.25x** (GPT-5.6+; grátis pre-5.6), cache reads **0.25x–0.5x**. Explicit caching GPT-5.6+ via `prompt_cache_breakpoint` + `prompt_cache_options` (TTL mínimo 30 min). |
| 12 | "SpaceXAI Search" | **[PARCIALMENTE CONFIRMADO]** | https://openrouter.ai/docs/guides/features/server-tools/web-search (native: "Passed through from the provider (OpenAI, Anthropic, Google, Perplexity, SpaceXAI)"); https://openrouter.ai/docs/guides/features/zdr (grupo SpaceXAI); service-tiers (SpaceXAI priority only) | SpaceXAI é confirmado como provider com native search passthrough e grupo ZDR próprio. A marca exata "SpaceXAI Search" não aparece nos docs — a SKILL deve usar "native search (SpaceXAI)". |
| 13 | "Ori Harness" | **[VERIFICADO]** | https://openrouter.ai/docs/guides/ori/harness; https://openrouter.ai/blog/announcements/ori-harness/ | Produto oficial: roda Claude Code, Codex, Hermes, OpenCode e Pi com OpenRouter (instala: `curl -fsSL https://openrouter.ai/labs/ori/install.sh | bash`; `ori claude --model ...`; login OAuth; guardrails e uma conta só). |
| 14 | "Tau2-Bench" | **[VERIFICADO]** | https://openrouter.ai/docs/guides/routing/auto-exacto | Benchmark do Auto Exacto: "Tau2-Bench Airline" (agentic tool-calling; temp 0, 1 epoch; mínimo 45 tasks; janela rolante 32 dias; derank = baseline − 2σ). Também GPQA Diamond. |
| 15 | Auto Router com "spend share" | **[VERIFICADO]** | https://openrouter.ai/docs/guides/routing/routers/auto-router | "the aggregate spend of millions of people using OpenRouter, measured over a trailing 7-day window for each task type". |
| 16 | `zdr: true` | **[VERIFICADO]** | https://openrouter.ai/docs/guides/routing/provider-selection + https://openrouter.ai/docs/guides/features/zdr | `provider.zdr: true` — OR com conta/guardrails; só garante ZDR, nunca desliga. |
| 17 | `data_collection: deny` | **[VERIFICADO]** | https://openrouter.ai/docs/guides/routing/provider-selection + OpenAPI | `provider.data_collection: "allow"` (default) / `"deny"`. |
| 18 | Variante `:exacto` | **[VERIFICADO]** | https://openrouter.ai/docs/guides/routing/model-variants/exacto + OpenAPI (`ProviderSort` inclui `"exacto"`) | Variante virtual de qualidade: "a shortcut for setting the provider sort to Exacto"; sem endpoint pool próprio; sort explícito tem precedência. |
| 19 | Clientes CLI: Claude Code via `ANTHROPIC_BASE_URL=https://openrouter.ai/api` | **[VERIFICADO]** | https://openrouter.ai/docs/cookbook/coding-agents/claude-code-integration; https://openrouter.ai/docs/guides/community/anthropic-agent-sdk | `ANTHROPIC_BASE_URL="https://openrouter.ai/api"` + `ANTHROPIC_AUTH_TOKEN="$OPENROUTER_API_KEY"` + `ANTHROPIC_API_KEY=""` (obrigatório vazio). Mapear modelos: `ANTHROPIC_DEFAULT_SONNET_MODEL="~anthropic/claude-sonnet-latest"` etc. |
| 20 | Clientes CLI: "openclaw/hermes" com `openrouter/~anthropic/claude-sonnet-latest` | **[VERIFICADO com nuance]** | OpenClaw: https://openrouter.ai/docs/cookbook/coding-agents/openclaw-integration; Hermes: https://hermes-agent.nousresearch.com/docs/user-guide/features/provider-routing (oficial Nous) | OpenClaw (agent open-source multi-canal) tem integração oficial OpenRouter e usa o formato `openrouter/<author>/<slug>` com prefixo `~` para latest — ex.: `openrouter/~anthropic/claude-sonnet-latest`. Hermes Agent (Nous Research) passa `provider` routing por `extra_body`. NUANCE: na API nativa, slugs são `author/model` (o prefixo `openrouter/` é só para slugs especiais tipo `openrouter/auto`); o formato com prefixo é convenção do OpenClaw. |
| 21 | "openrouter/experimental" | **[NÃO CONFIRMADO nos docs]** | llms.txt + OpenAPI | Nenhum slug `openrouter/experimental` documentado. No OpenAPI, "experimental" aparece apenas como tipo de server tool `openrouter:experimental__search_models`. Slug real mais próximo em early access: `openrouter/auto-beta`. |
| 22 | `X-OpenRouter-App` (header) | **[NÃO CONFIRMADO nos docs]** | https://openrouter.ai/docs/app-attribution | Attribution real = `HTTP-Referer` (obrigatório) + `X-OpenRouter-Title` (nome; `X-Title` legacy) + `X-OpenRouter-Categories`. |
| 23 | `weights` (campo do provider) | **[NÃO CONFIRMADO nos docs]** | OpenAPI (`ProviderPreferences`) + provider-selection | Não existe no schema oficial. |
| 24 | `route` como opção de roteamento | **[VERIFICADO com correção]** | OpenAPI (`DeprecatedRoute`) | Parâmetro top-level `route` EXISTE mas está **DEPRECATED**: alias de `providers.sort.partition` — `"fallback"`→`"model"`, `"sort"`→`"none"`. NÃO é campo do objeto provider. |
| 25 | Plugin "pdf-input" | **[NÃO CONFIRMADO — id errado]** | https://openrouter.ai/docs/guides/overview/multimodal/pdfs | O plugin correto é `file-parser` com `pdf.engine` (`mistral-ocr` $2/1.000 páginas, `cloudflare-ai` grátis, `native`). |
| 26 | "middleware reasoning effort: min/low/medium/high" | **[VERIFICADO com correção]** | https://openrouter.ai/docs/guides/best-practices/reasoning-tokens | Enum oficial: `max, xhigh, high, medium, low, minimal, none` — **`min` não existe; é `minimal`**. `reasoning_effort` top-level: `xhigh, high, medium, low, minimal, none`. |
| 27 | Guardrails como middleware de request (content moderation, refusal detection, PII) | **[PARCIALMENTE CONFIRMADO]** | https://openrouter.ai/docs/guides/features/guardrails | Guardrails existem como recurso de ORG (dashboard + `/api/v1/guardrails`): budgets, model/provider allowlists, ZDR por grupo, prompt-injection detection, sensitive info (PII) com redact/block. **Não confirmado como parâmetro `guardrails` no body do chat** — o equivalente per-request de privacidade é `provider.zdr`/`data_collection`. Estágio `guardrail` aparece no `pipeline` do router metadata. |

---

## 12. Fontes (todas oficiais)

Docs:
- https://openrouter.ai/docs/llms.txt (índice completo — usar para revalidar URLs)
- https://openrouter.ai/docs/api_reference/overview · https://openrouter.ai/docs/api_reference/parameters · https://openrouter.ai/openapi.yaml (spec oficial; as definições de schema citadas vieram daqui)
- https://openrouter.ai/docs/guides/routing/provider-selection (objeto provider, load balancing 1/p², 30s)
- https://openrouter.ai/docs/guides/routing/model-fallbacks · https://openrouter.ai/docs/guides/features/zero-completion-insurance
- https://openrouter.ai/docs/guides/routing/auto-exacto · https://openrouter.ai/docs/guides/routing/model-variants/{free,extended,exacto,thinking,nitro}.md · https://openrouter.ai/docs/guides/routing/routers/latest-resolution
- https://openrouter.ai/docs/guides/features/plugins · https://openrouter.ai/docs/guides/features/plugins/response-healing · https://openrouter.ai/docs/guides/features/plugins/fusion · https://openrouter.ai/docs/guides/overview/multimodal/pdfs · https://openrouter.ai/docs/guides/features/message-transforms (context-compression)
- https://openrouter.ai/docs/guides/features/server-tools/web-search
- https://openrouter.ai/docs/guides/routing/routers/auto-router · .../pareto-router · .../free-router · https://openrouter.ai/docs/guides/routing/routers/fusion-router
- https://openrouter.ai/docs/guides/features/response-caching · https://openrouter.ai/docs/guides/best-practices/prompt-caching · https://openrouter.ai/docs/guides/features/zdr
- https://openrouter.ai/docs/guides/overview/auth/byok · https://openrouter.ai/docs/guides/features/guardrails · https://openrouter.ai/docs/guides/features/service-tiers · https://openrouter.ai/docs/guides/features/router-metadata · https://openrouter.ai/docs/app-attribution · https://openrouter.ai/docs/api_reference/limits
- https://openrouter.ai/docs/guides/best-practices/reasoning-tokens · https://openrouter.ai/docs/guides/features/structured-outputs · https://openrouter.ai/docs/guides/features/presets · https://openrouter.ai/docs/guides/overview/models
- https://openrouter.ai/docs/cookbook/coding-agents/claude-code-integration · https://openrouter.ai/docs/guides/community/anthropic-agent-sdk · https://openrouter.ai/docs/cookbook/coding-agents/openclaw-integration · https://openrouter.ai/docs/guides/ori/harness

Blogs oficiais (secundários):
- https://openrouter.ai/blog/insights/model-routing/ · https://openrouter.ai/blog/insights/reliability-failover/ · https://openrouter.ai/blog/tutorials/keep-your-agent-running-when-models-disappear/ · https://openrouter.ai/blog/announcements/ori-harness/

Referências de terceiros citadas (apenas para contexto de integrações de CLI):
- https://hermes-agent.nousresearch.com/docs/user-guide/features/provider-routing (Hermes Agent / Nous Research)
- https://github.com/openclaw/openclaw (OpenClaw — agent open-source; tem cookbook oficial no OpenRouter)
