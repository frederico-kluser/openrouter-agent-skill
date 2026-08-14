# OpenRouter — Integração em projetos (SDKs, CLI e streaming)

> **Quando ler:** ao integrar o OpenRouter num projeto — SDK OpenAI (recomendado), SDK Anthropic (`/api/v1/messages`), Claude Code via `ANTHROPIC_BASE_URL`, ou streaming. Para a API em si veja `api.md`; para roteamento veja `routing.md`; para erros veja `errors.md`.
> **Fonte:** https://openrouter.ai/docs (Quickstart), /docs/guides/community/openai-sdk, /docs/api_reference/streaming, /docs/guides/community/anthropic-agent-sdk e /docs/cookbook/coding-agents/claude-code-integration.

## TOC (nesta página)
1. Base URL e autenticação (o essencial)
2. SDK OpenAI (integração primária)
3. SDK Anthropic — POST /api/v1/messages
4. SDKs oficiais do OpenRouter (@openrouter/sdk, @openrouter/agent)
5. Claude Code via ANTHROPIC_BASE_URL
6. Streaming (SSE)
7. Boas práticas de segurança

## 1. Base URL e autenticação (o essencial)

- **Base URL:** `https://openrouter.ai/api/v1` — drop-in para qualquer cliente OpenAI-compatible.
- **Chave:** `Authorization: Bearer <OPENROUTER_API_KEY>`; criar em https://openrouter.ai/keys, gerenciar/revogar em https://openrouter.ai/settings/keys.
- **Headers opcionais de attribution:** `HTTP-Referer` (URL do site/app, para rankings), `X-OpenRouter-Title` (nome do app; alias `X-Title` aceito), `X-OpenRouter-Categories` (até 2 por request; categorias conhecidas incluem `cli-agent`, `ide-extension`, `cloud-agent`, `programming-app`, `writing-assistant`, `general-chat`, `personal-agent`, `creative-writing`, `image-gen`, `audio-gen`, `video-gen`, `roleplay`, `game`; desconhecidas são descartadas).
- **Sempre ler a chave de uma variável de ambiente** (ex.: `OPENROUTER_API_KEY` em `.env`), nunca hardcoded; ver seção 7.

## 2. SDK OpenAI (integração primária)

O OpenRouter é 100% compatível com o SDK OpenAI apontado para a base URL acima. Use o SDK da OpenAI — é a integração mais estável e documentada.

**Python:**

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

**JavaScript/TypeScript:**

```js
import OpenAI from "openai";

const client = new OpenAI({
  baseURL: "https://openrouter.ai/api/v1",
  apiKey: process.env.OPENROUTER_API_KEY,
});
const completion = await client.chat.completions.create({
  model: "openai/gpt-4o",
  defaultHeaders: {
    "HTTP-Referer": "<YOUR_SITE_URL>",
    "X-OpenRouter-Title": "<YOUR_SITE_NAME>",
  },
  messages: [{ role: "user", content: "Say this is a test" }],
});
console.log(completion.choices[0].message.content);
```

- Headers extras: `extra_headers` (python) / `defaultHeaders` (js); params OpenRouter-only: `extra_body` (python) / `body` (js).
- Params OpenRouter-only via `extra_body`: `models` (fallbacks), `provider`, `plugins`, `reasoning`, `verbosity`, `web_search_options`, `debug`. (`route` existe mas está deprecated — use `provider.sort.partition`.)
- Params OpenAI suportados: `temperature`, `top_p`, `top_k`, `max_tokens`, `max_completion_tokens`, `stop`, `stream`, `tools`, `tool_choice`, `parallel_tool_calls`, `seed`, `frequency_penalty`, `presence_penalty`, `repetition_penalty`, `logit_bias`, `logprobs`, `top_logprobs`, `min_p`, `top_a`, `response_format`, `structured_outputs`, `user`.
- Params não suportados pelo modelo são ignorados silenciosamente ("the parameter is ignored. The rest are forwarded to the underlying model API.").

## 3. SDK Anthropic — POST /api/v1/messages

O OpenRouter expõe `POST /api/v1/messages` no formato Anthropic Messages API (texto, imagens, PDFs, tools e extended thinking). Use o SDK Anthropic com a base URL `https://openrouter.ai/api/v1` (client `Anthropic(base_url="https://openrouter.ai/api/v1", api_key=...)`), e as requests caem em `/api/v1/messages`. Erros seguem o envelope Anthropic (`error.type` nativo + `error_type` canônico dentro de `error`).

Particularidades:

- Fallback de modelos no formato Anthropic: parâmetro `fallbacks: [{model: ...}]` — até 3 entradas (400 se mais), só aceita `model` (sem `max_tokens`/`thinking`/`speed`/`output_config`), não combina com `models` (400).
- Extended thinking: `thinking` (Anthropic-style) e `reasoning` (OpenRouter) — `thinking.display: "summarized"` (default) / `"omitted"`. A variante `:thinking` está deprecada em favor do parâmetro `reasoning`.
- Prompt caching estilo Anthropic: `cache_control: {"type": "ephemeral", "ttl": "5m"|"1h"}` em content blocks — intercambiável com `prompt_cache_breakpoint` (o OpenRouter converte entre estilos). Máx. 4 breakpoints; TTL default 5 min.
- Headers `x-anthropic-beta` pass-through (valores separados por vírgula): `interleaved-thinking-2025-05-14` (thinking interleaved) e `structured-outputs-2025-11-13` (**obrigatório para strict tool use** — sem ele, "OpenRouter will strip the `strict` field and route normally").

## 4. SDKs oficiais do OpenRouter (@openrouter/sdk, @openrouter/agent)

O OpenRouter publica SDKs próprios: `@openrouter/sdk` (cliente da API) e `@openrouter/agent` (agente pronto para construção de apps agentic). **Não há exemplos de API destes SDKs nesta skill** — consulte a documentação oficial (https://openrouter.ai/docs) e o npm (`@openrouter/sdk`, `@openrouter/agent`) antes de usá-los. Para a maioria dos casos, o SDK OpenAI da seção 2 é a integração recomendada.

## 5. Claude Code via ANTHROPIC_BASE_URL

Fonte: https://openrouter.ai/docs/cookbook/coding-agents/claude-code-integration

Rode o Claude Code usando modelos do OpenRouter via env vars (no shell de cada sessão, ou no arquivo de ambiente do projeto — nunca commitar a chave):

```bash
export ANTHROPIC_BASE_URL="https://openrouter.ai/api"
export ANTHROPIC_AUTH_TOKEN="$OPENROUTER_API_KEY"
export ANTHROPIC_API_KEY=""    # obrigatório vazio — senão o SDK Anthropic sobrepõe
# opcional: mapear modelos por papel
export ANTHROPIC_DEFAULT_SONNET_MODEL="~anthropic/claude-sonnet-latest"
export ANTHROPIC_DEFAULT_HAIKU_MODEL="~anthropic/claude-haiku-latest"
export ANTHROPIC_DEFAULT_OPUS_MODEL="~anthropic/claude-opus-latest"
```

- A base URL do SDK Anthropic usada pelo Claude Code é `https://openrouter.ai/api` (sem o `/v1` — o SDK anexa `/v1/messages`), apontando para o endpoint `/api/v1/messages` do OpenRouter.
- Os aliases `~anthropic/...` resolvem para o modelo concreto mais novo da família; para reprodutibilidade, use slugs fixos (`anthropic/claude-sonnet-4.5`).
- Outros CLIs/agentes com integração OpenRouter documentada (OpenClaw, Hermes, Ori Harness) têm páginas próprias em https://openrouter.ai/docs/cookbook/coding-agents/ — consulte antes de assumir formato.

## 6. Streaming (SSE)

`stream: true` funciona para **todos os modelos**.

- Formato: Server-Sent Events; cada chunk é um `data:` JSON com `object: "chat.completion.chunk"`.
- **Linhas de comentário SSE começando com `:` (ex.: `: OPENROUTER PROCESSING`) devem ser ignoradas** — use um parser spec-compliant como `eventsource-parser` em vez de fazer parsing manual linha a linha.
- O `usage` chega **uma única vez, no chunk final**, com `choices: []`, seguido de `data: [DONE]`.
- `reasoning_details` em streaming chega em `choices[].delta.reasoning_details`.
- Com `X-OpenRouter-Metadata: enabled`, o `openrouter_metadata` vem no chunk final antes de `[DONE]`.
- **Cancelamento** via AbortController só funciona em streaming E com providers que suportam; caso contrário "the model will continue processing and you will be billed".
- Erros mid-stream: `error` no topo do chunk + `finish_reason: "error"`, HTTP permanece 200 (ver `errors.md` seção 6).

## 7. Boas práticas de segurança

- **Nunca commitar a chave.** O OpenRouter é GitHub secret scanning partner — chaves vazadas em repositórios públicos são detectadas e rotacionadas. Use `.env` (fora do versionamento) ou um secret manager; leia com `os.getenv("OPENROUTER_API_KEY")` / `process.env.OPENROUTER_API_KEY`.
- **"API keys on OpenRouter are more powerful than keys used directly for model APIs"** — suportam credit limits e OAuth; trate-as com o mesmo cuidado de uma chave de banco de dados.
- **Créditos como orçamento:** defina um credit limit por chave em https://openrouter.ai/keys; monitore `usage_monthly` vs `limit` via `GET /api/v1/key` (ver `errors.md`).
- Não exponha a chave em logs, telemetria ou params de URL.
