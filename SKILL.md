---
name: openrouter-agent-skill
description: 'Ensina a usar a API do OpenRouter do início ao fim: buscar modelos e seus providers, consultar preços, tokens por segundo, latência e quantização por provider, forçar um provider específico, configurar roteamento (fallbacks, variantes, plugins, cache, auto-router, BYOK), tratar erros e rate limits, integrar em projetos via SDK OpenAI, API Anthropic /messages, Claude Code ou streaming — incluindo ÁUDIO com ElevenLabs via OpenRouter (TTS, STT/Scribe, audio tags, clonagem de voz + BYOK) e o sistema de credenciais em terminal (verificar login de conta em memória, setup guiado, salvar variáveis de ambiente). Use quando o usuário quiser buscar modelos ou providers no OpenRouter, comparar preços, tokens por segundo ou latência, forçar um provider, montar roteamento, resolver erros de chave, créditos ou rate limit, integrar um app ao OpenRouter, gerar áudio/text-to-speech, transcrever áudio/speech-to-text, usar voz ou clonar voz (ElevenLabs), ou configurar/verificar chaves de conta.'
metadata:
  type: skill
---

# OpenRouter Skill

Guia de uso da API do OpenRouter (`https://openrouter.ai/api/v1`) de ponta a ponta: busca de modelos e providers, preços, tokens por segundo, roteamento e integração em projetos. Nomes de campos e termos técnicos ficam em inglês (como na API); o restante em pt-BR.

## Quando usar esta skill

Dispare para tarefas como:

- "Busque modelos que suportam tool calling / até $X / com janela de N tokens" — Passo 2
- "Quais providers servem o modelo X? Qual é mais barato, mais rápido (tokens/s) ou tem menor latência?" — Passo 3
- "Force o provider Y" / "não deixe cair em fallback" — Passo 4
- "Monte roteamento com fallbacks, variantes, plugins, cache, auto-router" — Passo 4 + [references/routing.md](references/routing.md)
- "Erro 429/402/503" ou "rate limit" ao usar o OpenRouter — Passo 7 + [references/errors.md](references/errors.md)
- "Integre o OpenRouter no meu projeto" — Passo 5 + [references/integrations.md](references/integrations.md)
- "Gere áudio com a voz da ElevenLabs" / "text-to-speech" / "narração com emoção (audio tags)" — Passo 8 + [references/audio-elevenlabs.md](references/audio-elevenlabs.md)
- "Transcreva este áudio" / "speech-to-text" / "diarize os falantes" — Passo 8 + [references/audio-elevenlabs.md](references/audio-elevenlabs.md)
- "Clone uma voz" / "use minha voz clonada" / "BYOK ElevenLabs" — Passo 8 + [references/audio-elevenlabs.md](references/audio-elevenlabs.md)
- "Temos o login/credenciais dessa conta?" / "configure a chave e salve" / "puxe os dados da conta" — Passo 8.1 (`scripts/elevenlabs.sh check|setup|account`)

## Como usar esta skill (navegação)

O núcleo abaixo (fluxo em passos + GOTCHAS) cobre o essencial de toda execução. Detalhes ficam em `references/` — leia cada arquivo QUANDO o caso pedir, não todos de uma vez:

| Arquivo | Quando ler |
|---|---|
| [references/api.md](references/api.md) | Antes de qualquer chamada de API: endpoints completos, query params e filtros de `/models`, exemplos de resposta reais, campos de `usage`/metadata |
| [references/routing.md](references/routing.md) | Ao configurar roteamento: objeto `provider` completo (campo→tipo→default), variantes, fallbacks, plugins, caching, auto-router, BYOK, service tiers, ZDR |
| [references/errors.md](references/errors.md) | Ao tratar erros: tabela `error_type` → HTTP → ação, rate limits, retries, erros em streaming, chave free |
| [references/integrations.md](references/integrations.md) | Ao integrar num projeto: SDK OpenAI, SDK Anthropic (`/messages`), Claude Code via `ANTHROPIC_BASE_URL`, streaming |
| [references/audio-elevenlabs.md](references/audio-elevenlabs.md) | Para ÁUDIO: TTS/STT ElevenLabs, modelos e preços, response_format, chunking, audio tags, provider passthrough, clonagem de voz + BYOK, erros de binário, credenciais/conta |

Ferramentas prontas do repo: `scripts/openrouter.sh` (CLI que embrulha os endpoints — `models`, `providers`, `prices`, `tps`, `suggest`, `chat`, `key`, `credits`; suporta `--dry-run` sem chave), `scripts/elevenlabs.sh` (CLI de áudio + credenciais — `check`, `setup`, `account`, `models`, `tts`, `stt`, `voices`; `--dry-run` e `--json` globais) e `examples/` (quickstart em Python/shell, exemplo de body de roteamento em `router-example.json` e parser de `usage`). Consulte-as antes de escrever curls à mão.

## Fluxo essencial (passo a passo)

### Passo 1 — Autenticar

- Chave: crie em https://openrouter.ai/keys (defina um credit limit); gerencie/revogue em https://openrouter.ai/settings/keys. Formato `sk-or-v1-...`.
- Header em toda request: `Authorization: Bearer <OPENROUTER_API_KEY>`.
- Headers opcionais de attribution: `HTTP-Referer` (URL do app), `X-OpenRouter-Title` (nome do app; alias `X-Title` aceito), `X-OpenRouter-Categories`.
- **Nunca commitar a chave** (ver GOTCHAS e [references/integrations.md](references/integrations.md) seção 7). Leia de `OPENROUTER_API_KEY` no ambiente (`.env` fora do git).
- **Antes de pedir a chave ao usuário, verifique se já a temos em memória**: `scripts/elevenlabs.sh check` varre ambiente → `./.env` → `~/.secrets` → `~/.zshenv` → `~/.dsh/.credentials.yaml` → memória CoALA e mostra status + como puxar cada variável. Se faltar, o `setup` guiado configura e **salva as variáveis de ambiente** (Passo 8.1).

### Passo 2 — Buscar modelos

`GET /api/v1/models` lista todos os modelos com `id` (formato `author/slug`, ex.: `openai/gpt-4o`), `pricing`, `context_length`, `supported_parameters`, `architecture`, `top_provider`.

Filtros reais (query params): `supported_parameters=tools` (modelos com tool calling), `output_modalities` / `input_modalities` (`text` default, `image`, `audio`, `embeddings`, `all`), `min_price`/`max_price` e `min_output_price`/`max_output_price`, `min_age_days`/`max_age_days`, `min_coding_index`/`max_coding_index`, `min_agentic_index`/`max_agentic_index`, `min_intelligence_index`/`max_intelligence_index`, `min_tool_success_rate`/`max_tool_success_rate`, `context`, `region`, `zdr`, `arch`, `model_authors`, `providers`, `category`, `distillable`, `q` (busca).

Ordenação: `sort` — `most-popular`, `newest`, `top-weekly`, `pricing-low-to-high`, `pricing-high-to-low`, `context-high-to-low`, `throughput-high-to-low`, `latency-low-to-high`, `intelligence-high-to-low`, `coding-high-to-low`, `agentic-high-to-low`, `design-arena-elo-high-to-low`.

- Paginação: `offset` + `limit` (default 500, máx 1000); omita ambos = lista completa; itere com `links.next`. (Não há `per_page` nem `cursor`.)
- Contagem do catálogo: `GET /api/v1/models/count` → `{ "data": { "count": N } }`.
- Se o repo tiver o helper `scripts/openrouter.sh`, veja-o antes de escrever curls — ele embrulha estes endpoints (confira a interface dele no próprio arquivo).
- Detalhes e exemplos de resposta: [references/api.md](references/api.md) seção 2.

### Passo 3 — Buscar providers de um modelo

`GET /api/v1/models/{author}/{slug}/endpoints` retorna `data.endpoints[]`, um item por provider que serve o modelo, com:

- `tag` — slug do provider (ex.: `openai`) — **é o valor usado no roteamento** (`provider.order`/`provider.only`);
- `provider_name` — nome exibível (ex.: "OpenAI");
- `pricing` — **preço cobrado por aquele provider** (strings USD por token): pode diferir do preço de lista do modelo;
- `throughput_last_30m` — **tokens por segundo** em percentis `{p50, p75, p90, p99}` (janela de 30 min);
- `latency_last_30m` — latência em **segundos**, percentis p50–p99;
- `quantization` — `int4, int8, fp4, mxfp4, nvfp4, fp6, fp8, mxfp8, fp16, bf16, fp32, unknown`;
- `uptime_last_5m`/`uptime_last_30m`/`uptime_last_1d`;
- `context_length`/`max_prompt_tokens`/`max_completion_tokens` — **variam por provider**;
- `supports_implicit_caching`, `status`.

Para detalhe de UM modelo, `GET /api/v1/model/{author}/{slug}` (singular — ver GOTCHAS), que resolve aliases e devolve o objeto Model completo. Exemplo de resposta em [references/api.md](references/api.md) seção 5.

### Passo 4 — Escolher a estratégia de roteamento

**Default (sem `provider`):** load balancing por preço (peso ∝ 1/preço²; prioriza providers sem outage nos últimos 30 s) com fallback automático (`allow_fallbacks: true`).

**Forçar um provider específico** (o pedido mais comum):

- `"provider": {"only": ["<tag>"]}` — allow-list estrita: só aquele provider serve. Se nenhum provider satisfizer `only` ∩ allow-list da conta → **404**.
- Alternativa com ordem: `"provider": {"order": ["<tag1>", "<tag2>"], "allow_fallbacks": false}` — tenta na ordem, sem backup.
- Teto de custo estrito: `"provider": {"max_price": {"prompt": 1, "completion": 2}}` — USD por **MILHÃO** de tokens; impede a request de rodar se o preço não estiver disponível/dentro.
- Restrições extras: `quantizations` (ex.: `["fp8","fp16"]`), `data_collection: "deny"`, `zdr: true`, `require_parameters: true`.

**Fallback de modelo:** `"models": ["openai/gpt-4o", "mistralai/mixtral-8x22b-instruct"]` — se o primeiro der erro, tenta o próximo; cobra o modelo efetivamente usado (campo `model` da resposta).

**Sem provider disponível** → **503** ("There is no available model provider that meets your routing requirements"): relaxe `provider`/`max_price` ou adicione fallbacks.

Configurações avançadas (variantes `:free`/`:nitro`/`:exacto`/`:extended`/`:thinking`/`:online`, plugins, cache, auto-router, BYOK, service tiers, ZDR): **leia [references/routing.md](references/routing.md)** antes de usá-las.

### Passo 5 — Fazer a requisição e integrar num projeto

Endpoint principal: `POST /api/v1/chat/completions` (formato OpenAI). Integração primária: **SDK OpenAI** apontado para a base URL:

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

- Params OpenRouter-only (fallbacks, `provider`, `plugins`, `reasoning`...) vão via `extra_body` (python) / `body` (js).
- Params não suportados pelo modelo são ignorados silenciosamente — não é erro.
- Streaming: `stream: true` (detalhes em [references/integrations.md](references/integrations.md) seção 6).
- Alternativa Anthropic: `POST /api/v1/messages` com o SDK Anthropic na mesma base URL.
- Claude Code: `ANTHROPIC_BASE_URL="https://openrouter.ai/api"` + `ANTHROPIC_AUTH_TOKEN="$OPENROUTER_API_KEY"` + `ANTHROPIC_API_KEY=""` (vazio, obrigatório).
- SDKs oficiais `@openrouter/sdk` e `@openrouter/agent` existem — consulte a documentação oficial (https://openrouter.ai/docs) antes de usá-los; esta skill não documenta a API deles.
- `.env` com `OPENROUTER_API_KEY=...` fora do git; nunca commitar a chave.

Tudo isso em detalhe (JS, Anthropic, CLI, streaming, segurança): [references/integrations.md](references/integrations.md).

### Passo 6 — Observar custo e performance

- `usage.cost` na resposta = custo em USD da requisição.
- Header `X-Generation-Id` em toda resposta → `GET /api/v1/generation?id=...` para tokens, custo e latência exatos.
- Para ver a decisão de roteamento: header `X-OpenRouter-Metadata: enabled` → campo `openrouter_metadata` na resposta (requested, strategy, attempt, endpoints, attempts, pipeline...).
- Monitoramento: `GET /api/v1/key` → `limit`, `limit_remaining`, `usage_monthly`, `is_free_tier`; `GET /api/v1/credits` (requer management key) → `total_credits`/`total_usage`.

### Passo 7 — Tratar erros

- **429** → backoff exponencial + honrar `Retry-After` — implemente manualmente (SDKs não honram sozinhos, ver GOTCHAS).
- **402** → créditos insuficientes: informe o usuário; cheque `GET /api/v1/key` (cap da chave) e adicione créditos.
- **401** → chave inválida/revogada: https://openrouter.ai/settings/keys.
- **404** → modelo inexistente (confira o slug) OU nenhum provider atende as restrições (relaxe `provider`/`max_price`).
- **503** → nenhum provider disponível: retry com pequeno delay ou relaxe o roteamento.
- Erros do provider podem vir com **HTTP 200 e erro no body** (mid-stream em streaming) — use `error_type`, não só o status.
- Tabela completa `error_type` → HTTP → ação: [references/errors.md](references/errors.md).

### Passo 8 — Áudio com ElevenLabs (TTS/STT/clonagem) e credenciais em memória

Endpoints dedicados (NÃO são `/chat/completions`): `POST /api/v1/audio/speech` (TTS → bytes de áudio no body) e `POST /api/v1/audio/transcriptions` (STT → JSON com `usage.cost`). Detalhe completo (modelos, limites, chunking, audio tags, passthrough): **[references/audio-elevenlabs.md](references/audio-elevenlabs.md)**.

**8.1 — Credenciais: verificar em memória → setup guiado → puxar dados (tudo em terminal)**

```bash
scripts/elevenlabs.sh check      # temos o login? varre: ambiente → ./.env → ~/.secrets
                                 # → ~/.zshenv → ~/.dsh/.credentials.yaml → memória CoALA
                                 # (mostra status, fonte, valor mascarado e como puxar)
scripts/elevenlabs.sh setup      # GUIA o usuário: pede a chave (oculto), valida o formato,
                                 # testa o login real e SALVA as variáveis de ambiente
                                 # em ~/.secrets (chmod 600) + export via ~/.zshenv
scripts/elevenlabs.sh account    # PUXA os dados da conta: OpenRouter (limit/usage/créditos)
                                 # + ElevenLabs (tier, caracteres, vozes)
```

Variáveis: `OPENROUTER_API_KEY` (obrigatória; `sk-or-v1-...`) e `ELEVENLABS_API_KEY` (opcional; necessária só para clonagem/BYOK; alias `ELEVENLABS_NATIVE_API_KEY`). **Nunca peça a chave ao usuário antes de rodar o `check`** — pode já estar salva.

**8.2 — TTS:** `model` + `input` + `voice` (obrigatório — nome das 21 vozes embutidas ou `voice_id` de clone) + `response_format` (`mp3`|`pcm`; **o default da API é `pcm`** — declare sempre). Em terminal: `scripts/elevenlabs.sh tts "texto" --out f.mp3 [--voice sarah] [--model elevenlabs/eleven-v4-turbo]`. Valida `Content-Type` + `X-Generation-Id` (anti-corrupção binária).

**8.3 — STT (Scribe):** áudio em Base64 dentro de JSON (`input_audio`), máx. 25 MB, upstream timeout 60 s (fatie áudios longos). `--diarize` + (`--speakers N` OU `--threshold`), `--tag-events`, `--no-verbatim`; custo sai em `usage.cost`. Ex.: `scripts/elevenlabs.sh stt reuniao.mp3 --diarize --speakers 2`.

**8.4 — Audio tags e passthrough:** emoção via `[laughs]`, `[whispers]`, `[happily]`, `[British accent]`... no próprio `input` (a ElevenLabs rejeita SSML); hiperparâmetros via `provider.options.elevenlabs` (`seed`, `previous_text`/`next_text`, `voice_settings.stability/similarity_boost`). `speed` (0.7–1.2) só em multilingual-v2/flash — `eleven-v4` devolve 400.

**8.5 — Clonagem de voz (híbrida, 3 fases):** (1) criar o clone na API NATIVA da ElevenLabs (IVC instantâneo ou PVC 6–24 h com consentimento) → guardar o `voice_id`; (2) configurar **BYOK** em https://openrouter.ai/settings/keys (Provider Keys → ElevenLabs); (3) inferir via `/audio/speech` com `voice: "<voice_id>"`. O OpenRouter não expõe treino de clones — só inferência. BYOK cobra o plano nativo da ElevenLabs + ~5% de taxa do OpenRouter.

## GOTCHAS — fatos que desafiam suposições

Cada item: "NÃO faça X — o correto é Y". Leia todos ANTES de agir.

**Identificadores e paths**

1. **NÃO use `provider_id` para identificar o provider** — o campo dos endpoints é `tag` (slug, ex.: `openai`); o nome exibível é `provider_name`. Só `tag` entra em `provider.order`/`provider.only`.
2. **NÃO use `/api/v1/models/{author}/{slug}` para detalhe de UM modelo** — o path é SINGULAR: `/api/v1/model/{author}/{slug}`. O plural existe para a listagem (`/models`) e para `/models/{author}/{slug}/endpoints`.
3. **NÃO afirme "mais de 500 modelos"** — o catálogo tem centenas (411 verificados em 2026-08-14); cheque `GET /api/v1/models/count`.
4. **NÃO procure `per_page`/`cursor` em `/models`** — a paginação é `offset`/`limit` (default 500, máx 1000; omita = lista completa) com `links.next`.

**Roteamento e parâmetros**

5. **NÃO use `q8_0` como quantização** — o enum oficial é `int4, int8, fp4, mxfp4, nvfp4, fp6, fp8, mxfp8, fp16, bf16, fp32, unknown`.
6. **NÃO use o campo `weights` no objeto `provider`** — ele não existe; restrições são `only`/`ignore`/`order`/`quantizations`.
7. **NÃO use `route` top-level para fallback** — está DEPRECATED; use `provider.sort.partition` ("fallback"→`"model"`, "sort"→`"none"`).
8. **NÃO envie `guardrails` no body do chat** — guardrails são recurso de organização (dashboard + `/api/v1/guardrails`); privacidade por request é `provider.zdr`/`provider.data_collection`.
9. **NÃO envie `cost_tier` top-level** — vai DENTRO de `plugins: [{"id": "auto-router", "cost_tier": "low"}]` (tiers: `low`, `medium`, `high`, `xhigh`, `max`).
10. **NÃO use `price_source: "completion"`** — o schema do plugin pareto-router aceita apenas `"prompt"` ou `"weighted_avg"`.

**Headers e metadata**

11. **NÃO use o header `X-OpenRouter-App`** — attribution usa `HTTP-Referer` + `X-OpenRouter-Title` (alias `X-Title`) + `X-OpenRouter-Categories`.
12. **NÃO espere `mode`/`cost`/`tps`/`timings` no header `X-OpenRouter-Metadata`** — o formato atual é o campo `openrouter_metadata` (requested, strategy, attempt, endpoints, attempts, pipeline...). Custo/latência exatos: `usage.cost` + `X-Generation-Id` → `GET /api/v1/generation?id=...`. Cache hits NÃO trazem metadata.

**Parâmetros de request**

13. **NÃO use effort `"min"`** — o enum de `reasoning.effort` é `max, xhigh, high, medium, low, minimal, none`; `reasoning_effort` top-level tem o MESMO enum (`max, xhigh, high, medium, low, minimal, none`).
14. **NÃO leia `reasoning_tokens` no topo de `usage`** — está em `usage.completion_tokens_details.reasoning_tokens`; é contado e cobrado como token de saída.
15. **NÃO use `prompt_cache_options.mode: "simple"`** — o único valor é `"explicit"`; caching implícito é comportamento do provider, não um mode.
16. **NÃO use o plugin `pdf-input`** — o plugin correto é `file-parser` (com `pdf.engine`: `mistral-ocr` | `cloudflare-ai` | `native`).
17. **NÃO defina `max_tokens` acima de `context_length − prompt_length`** — esse é o teto (além do `max_completion_tokens` do provider escolhido); estouro → 400 `context_length_exceeded`.

**Comportamento de SDKs e preços**

18. **NÃO confie que o SDK honra `Retry-After`** — os SDKs (OpenAI, Anthropic, Vercel AI, OpenRouter) não retentam com o header sozinhos; implemente backoff exponencial + `Retry-After` manualmente, inclusive com `fetch` puro.
19. **NÃO trate o preço do modelo como fixo** — `pricing.prompt`/`pricing.completion` são POR TOKEN (strings USD, ex.: `"0.00003"`); `provider.max_price` é por MILHÃO de tokens; e o valor cobrado é o do provider selecionado (veja `/endpoints`), não o de lista.
20. **NÃO espere que erros de provider venham sempre com HTTP não-200** — mid-stream eles chegam com 200 + `error` no chunk e `finish_reason: "error"`.
21. **NÃO prometa volume ilimitado em modelos `:free`** — têm 20 req/min e 50 ou 1000 req/dia; o limiar é em CRÉDITOS comprados (10), não em dólares. `GET /api/v1/key` → `is_free_tier`.

**Áudio (ElevenLabs)**

22. **NÃO espere áudio no `/chat/completions`** — TTS é `POST /api/v1/audio/speech` (resposta = bytes brutos) e STT é `POST /api/v1/audio/transcriptions` (resposta = JSON); endpoints dedicados.
23. **NÃO salve o body como `.mp3` sem checar status + `Content-Type`** — um payload inválido devolve HTTP 400 com corpo ZodError em JSON; gravado como `.mp3` vira "mídia corrompida" no player. Sucesso é `audio/mpeg` (mp3) ou `audio/pcm` (pcm). E **o default de `response_format` é `pcm`, não `mp3`** — declare sempre explicitamente.
24. **NÃO omita o campo `voice`** — é obrigatório (nome das 21 vozes embutidas, case-insensitive, ou `voice_id` de clone); a omissão devolve erro de campo ausente.
25. **NÃO envie `speed` para `eleven-v4`/`eleven-v4-turbo`** — rejeitam com HTTP 400; `speed` (0.7–1.2) só existe em `eleven-multilingual-v2` e família Flash. Em v4 use audio tags (`[rushed]`, `[drawn out]`) e pontuação.
26. **NÃO use SSML nos modelos novos da ElevenLabs** — é rejeitado; a modulação é por Audio Tags em colchetes minúsculos (`[whispers]`, `[laughs]`, `[British accent]`), que **contam no limite de caracteres e são cobradas**.
27. **NÃO divida texto longo no meio de palavra/frase** — fracione em fronteiras sintáticas (`\n\n`, `.`, `?`, `!`) e injete continuidade com `provider.options.elevenlabs.previous_text`/`next_text`; concatene PCM em memória ou MP3 via `ffmpeg -i "concat:..."`.
28. **NÃO tente clonar voz só via OpenRouter** — a API dele não expõe treino/uploads: o clone nasce na API nativa da ElevenLabs (IVC/PVC), e a inferência com o `voice_id` só funciona com **BYOK** configurado (Settings → Provider Keys → ElevenLabs). PVC exige consentimento por captura de texto e treino de 6–24 h.
29. **NÃO envie áudio STT com prefixo `data:audio/...;base64,`** — o Base64 vai "limpo" dentro do JSON (`input_audio.data`); há teto de **25 MB** por request e **upstream timeout de 60 s** (fatie palestras/aulas), e `num_speakers`/`diarization_threshold` são mutuamente exclusivos.

## Exemplos

### Com a skill — buscar modelos com tool calling, ordenados por popularidade

**Input:** "Ache modelos com tool calling, mais usados primeiro."

```
curl "https://openrouter.ai/api/v1/models?supported_parameters=tools&sort=most-popular" \
  -H "Authorization: Bearer $OPENROUTER_API_KEY"
```

**Output (resumo do que ler):** `data[].id` (ex.: `openai/gpt-4o`), `data[].pricing.prompt` (USD por token), `data[].context_length`, `data[].supported_parameters`. O `id` é o valor a usar no campo `model` da request.

### Com a skill — inspecionar providers e forçar um

**Input:** "Quais providers servem openai/gpt-4o? Force o mais barato."

1. `GET /api/v1/models/openai/gpt-4o/endpoints` → compare `pricing`, `throughput_last_30m.p50` (tokens/s), `latency_last_30m.p50`, `quantization` por `tag`.
2. Requisição forçada (curls → mesma coisa via SDK):

```json
{
  "model": "openai/gpt-4o",
  "provider": { "only": ["<tag-do-provider>"], "max_price": { "prompt": 1, "completion": 2 } },
  "messages": [{ "role": "user", "content": "..." }]
}
```

**Output esperado:** resposta normal se o provider atende o teto; **404** se `only` ∩ allow-list da conta não tem ninguém; **503** se nenhum provider está disponível — relaxe as restrições ou adicione fallbacks.

### Sem a skill — o que costuma dar errado

- Usar o path PLURAL para detalhe de modelo → 404 desnecessário; o certo é `/api/v1/model/{author}/{slug}`.
- Consultar `/models` com `per_page=...` → parâmetro ignorado (a paginação certa é `offset`/`limit`).
- Assumir que o SDK retenta 429 sozinho → a request simplesmente falha; implemente backoff + `Retry-After`.
- Informar o preço de lista do modelo como o que será cobrado → o cobrado é o do provider selecionado.
