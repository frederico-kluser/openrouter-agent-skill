# Áudio no OpenRouter — ElevenLabs (TTS, STT e clonagem de voz)

> **Quando ler:** quando o usuário quiser gerar áudio (text-to-speech), transcrever áudio (speech-to-text), clonar voz, usar "voz da ElevenLabs", audio tags, ou configurar/verificar a conta ElevenLabs.
> **Fonte:** relatório técnico de integração ElevenLabs via OpenRouter (modelos, limites, payloads, BYOK) + docs oficiais (https://openrouter.ai/docs, https://elevenlabs.io/docs). Comportamentos mudam — revalide nas URLs citadas em cada seção.
> **Tudo em terminal:** os fluxos abaixo usam `curl`/`bash`/`python3` direto; o CLI `scripts/elevenlabs.sh` embrulha os mesmos endpoints (`check`, `setup`, `account`, `models`, `tts`, `stt`, `voices`).

Índice:
1. [Topologia: endpoints de áudio](#1-topologia-endpoints-de-áudio)
2. [Modelos TTS da ElevenLabs](#2-modelos-tts-da-elevenlabs)
3. [Modelos STT (Scribe)](#3-modelos-stt-scribe)
4. [TTS: requisição, vozes e response_format](#4-tts-requisição-vozes-e-response_format)
5. [Chunking para textos longos](#5-chunking-para-textos-longos)
6. [Audio Tags (modulação emocional)](#6-audio-tags-modulação-emocional)
7. [Provider passthrough (`provider.options.elevenlabs`)](#7-provider-passthrough-provideroptionselevenlabs)
8. [STT: transcrição com Scribe](#8-stt-transcrição-com-scribe)
9. [Clonagem de voz (IVC vs PVC) e BYOK](#9-clonagem-de-voz-ivc-vs-pvc-e-byok)
10. [Erros e corrupção binária silenciosa](#10-erros-e-corrupção-binária-silenciosa)
11. [Custos e reconciliação](#11-custos-e-reconciliação)
12. [Credenciais: check em memória → setup guiado → puxar dados](#12-credenciais-check-em-memória--setup-guiado--puxar-dados)

---

## 1. Topologia: endpoints de áudio

O OpenRouter NÃO serve áudio pelo `/api/v1/chat/completions`. Existem rotas dedicadas:

| Método | Endpoint | Função | Corpo | Resposta |
|---|---|---|---|---|
| POST | `/api/v1/audio/speech` | TTS (síntese) | JSON: `model`, `input`, `voice`, `response_format`, `provider` | **bytes de áudio brutos** no body (+ headers `Content-Type`, `X-Generation-Id`) |
| POST | `/api/v1/audio/transcriptions` | STT (transcrição) | JSON com áudio Base64 (`input_audio`) OU `multipart/form-data` | JSON com texto, timestamps, `usage` (inclui `usage.cost`) |

- Ambos são **drop-in compatíveis com os SDKs da OpenAI** (Python/Node/Go): aponte `base_url` para `https://openrouter.ai/api/v1` e injete a chave — nada mais muda.
- Resiliência: o roteador monitoriza latência (P50–P99) e throughput em janelas de 5 min; se o nó upstream da ElevenLabs der timeout ou HTTP 5xx, a request é reencaminhada para a próxima instância saudável (uptime frequentemente ~100%).
- Toda transação (sucesso ou erro) emite o header **`X-Generation-Id`** (prefixo `gen-tts-...`) — guarde-o para auditoria/correção de cobrança via `GET /api/v1/generation?id=...`.

## 2. Modelos TTS da ElevenLabs

Preços por **milhão de caracteres**; limite = caracteres por requisição.

| `model` (API slug) | Nome comercial | Limite/request | Perfil de uso | Preço base |
|---|---|---|---|---|
| `elevenlabs/eleven-v4` | Eleven v4 | 10.000 | Topo de gama: máxima expressividade, 90+ idiomas, audio tags, clonagem de alta fidelidade | $40 |
| `elevenlabs/eleven-v4-turbo` | Eleven v4 Turbo | 10.000 | v4 comprimido para baixa latência; agentes conversacionais em tempo real; audio tags | $20 |
| `elevenlabs/eleven-v3` | Eleven v3 | 5.000 | Discurso emocional rico, reações não verbais (risos, suspiros), 70+ idiomas | $40 |
| `elevenlabs/eleven-v3-conversational` | Eleven v3 Conversational | 5.000 | Ritmo natural de diálogos interpessoais | $20 |
| `elevenlabs/eleven-flash-v2.5` | Eleven Flash v2.5 | 40.000 | Latência ultrabaixa (TTFT ~75 ms), 32 idiomas; alto volume sem variação emocional extrema | $20 |
| `elevenlabs/eleven-turbo-v2.5` | Eleven Turbo v2.5 | 40.000 | Equilíbrio velocidade × qualidade além do inglês | $20 |
| `elevenlabs/eleven-flash-v2` | Eleven Flash v2 | 30.000 | **Somente inglês**; tempo real absoluto, alta densidade | $20 |
| `elevenlabs/eleven-multilingual-v2` | Eleven Multilingual v2 | 10.000 | Long-form (audiolivros, documentários), 29 idiomas, suporta `speed` | $40 |

> Condição promocional da parceria: **desconto temporário de 50%** nos modelos ElevenLabs via rede OpenRouter. Verifique o preço efetivo no dashboard antes de orçamentar.

## 3. Modelos STT (Scribe)

Preço por **segundo de áudio**.

| `model` | Nome comercial | Especialização | Preço base |
|---|---|---|---|
| `elevenlabs/scribe-v2` | Scribe v2 | Transcrição em 90+ idiomas; timestamps por palavra, diarização de locutores, marcação de eventos acústicos não verbais | $0.000031/s |
| `elevenlabs/scribe-v2-medical` | Scribe v2 Medical | Fine-tuning clínico (terminologia médica, farmacêutica, patológica); −35% de taxa de erro em áudios médicos; **mesma API**, só muda o `model` | $0.000031/s |

## 4. TTS: requisição, vozes e response_format

Payload mínimo (JSON):

```json
{
  "model": "elevenlabs/eleven-v4-turbo",
  "input": "A atualização da arquitetura do servidor foi implementada.",
  "voice": "george",
  "response_format": "mp3"
}
```

- **`voice` é obrigatório** — a omissão devolve erro de campo ausente. A ElevenLabs traz **21 vozes embutidas** identificadas por nome próprio (`george`, `sarah`, `adam`, `bella`, `rachel`, ...); o reconhecimento é **case-insensitive**. Um `voice_id` alfanumérico de voz clonada também entra aqui (ver seção 9).
- **`response_format` define o codec do arquivo**:
  - `mp3` → `audio/mpeg` (44.1 kHz, 128 kbps): armazenamento (S3, bancos de objetos) e reprodução direta em web/players.
  - `pcm` → `audio/pcm` (**áudio bruto não comprimido**, 16-bit little-endian mono 24 kHz): streaming em tempo real (WebRTC, agentes telefónicos) — elimina a decodificação e minimiza latência.
  - **O default da API é `pcm`** — se o cliente ignorar o `Content-Type` e gravar o fluxo PCM com extensão `.mp3`, os players reportam "ficheiro corrompido" (trocar a extensão NÃO converte o codec). Defina `response_format` sempre explicitamente.

### curl (terminal)

```bash
curl -sS -X POST "https://openrouter.ai/api/v1/audio/speech" \
  -H "Authorization: Bearer $OPENROUTER_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "elevenlabs/eleven-v4-turbo",
    "input": "Bem-vindos à revisão arquitetural do sistema.",
    "voice": "george",
    "response_format": "mp3"
  }' \
  -D "$TMPDIR/hdrs.txt" \
  -o notificacao.mp3

# Auditoria: Content-Type + ID de geração
grep -i "^content-type\|^x-generation-id" "$TMPDIR/hdrs.txt"
file notificacao.mp3
```

Regra de ouro: **só grave o body se `Content-Type` for `audio/*` E o status for 2xx** — caso contrário o body é um erro JSON (ver seção 10).

### Python (SDK OpenAI, com validação)

```python
import os
from openai import OpenAI

cliente_or = OpenAI(
    base_url="https://openrouter.ai/api/v1",
    api_key=os.environ.get("OPENROUTER_API_KEY"),
)

def sintetizar(texto: str, destino: str):
    # with_raw_response: acesso aos headers HTTP (Content-Type, X-Generation-Id)
    resposta = cliente_or.audio.speech.with_raw_response.create(
        model="elevenlabs/eleven-v4-turbo",
        voice="george",
        input=texto,
        response_format="mp3",
    )
    resposta.raise_for_status()
    tipo = resposta.headers.get("Content-Type", "")
    if "audio/mpeg" not in tipo:
        print(f"[Aviso] Tipo de conteúdo inesperado: {tipo}")
    print("X-Generation-Id:", resposta.headers.get("X-Generation-Id", "indisponível"))
    with open(destino, "wb") as f:
        f.write(resposta.content)

sintetizar("A atualização da arquitetura do servidor foi implementada.", "notificacao.mp3")
```

### TypeScript (fetch nativo)

```typescript
async function sintetizar(texto: string): Promise<ArrayBuffer> {
  const resposta = await fetch('https://openrouter.ai/api/v1/audio/speech', {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${process.env.OPENROUTER_API_KEY}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      model: 'elevenlabs/eleven-v4',
      input: texto,
      voice: 'bella',
      response_format: 'mp3',
    }),
  });
  if (!resposta.ok) {
    throw new Error(`HTTP ${resposta.status} - ${await resposta.text()}`);
  }
  console.info('[Voz] X-Generation-Id:', resposta.headers.get('X-Generation-Id'));
  return await resposta.arrayBuffer();
}
```

## 5. Chunking para textos longos

Cada modelo tem teto de caracteres por request (tabela da seção 2: 5.000 em `eleven-v3` a 40.000 em `eleven-flash-v2.5`). Para audiolivros/relatórios, **não divida no meio de palavra ou frase** — quebra a prosódia. Regras:

1. **Friccione em fronteiras sintáticas**: parágrafos (`\n\n`) primeiro; fallback em pontuação de fecho (`.`, `?`, `!`).
2. **Despache sequencial** cada parte.
3. **Injete contexto adjacente** com `provider.options.elevenlabs.previous_text` e `next_text` (a voz "lembra" a emoção anterior sem verbalizar esse texto).
4. **Concatene**: blocos PCM em memória; MP3s com `ffmpeg -i "concat:parte1.mp3|parte2.mp3" -c copy final.mp3`.

Limites por modelo (`max_chars` por request):

| Modelo | `max_chars` |
|---|---|
| `eleven-v4`, `eleven-v4-turbo`, `eleven-multilingual-v2` | 10.000 |
| `eleven-v3`, `eleven-v3-conversational` | 5.000 |
| `eleven-flash-v2.5`, `eleven-turbo-v2.5` | 40.000 |
| `eleven-flash-v2` | 30.000 |

## 6. Audio Tags (modulação emocional)

A série v3/v4 interpreta **etiquetas de direção entre colchetes em minúsculas** inseridas no texto — **a ElevenLabs rejeita SSML**; não use markup XML. As tags manipulam o estado oculto das camadas de atenção fonética sem trocar o timbre.

Três domínios:

1. **Reações biológicas / não verbais:** `[laughs]`, `[sighs]`, `[clears throat]`, `[gasps]` — o som é injetado na coordenada exata de tempo.
2. **Direção tonal e ritmo:** `[whispers]`, `[shouts]`, `[softly]`, `[angry]`, `[happily]`, `[rushed]`, `[drawn out]` — pontuação severa (MAIÚSCULAS, reticências) complementa.
3. **Personificação (sotaque):** `[British accent]`, `[French accent]` — recalcula a projeção fonética sem trocar `voice_id`.

Exemplo de `input`:

```text
[clears throat] Bem-vindos à revisão arquitetural do sistema. [whispers] O nível de redundância falhou no teste noturno. [sighs] Os resultados de estabilidade estão abaixo do limite, mas [happily] a nossa equipa acabou de isolar a fuga de memória!
```

> **Custo:** todos os caracteres das tags (incluindo colchetes) contam no limite de `max_chars` e são cobrados — são processados pela camada semântica do modelo.

## 7. Provider passthrough (`provider.options.elevenlabs`)

Ajustes matemáticos vão no nó de passthrough (o OpenRouter é agnóstico e tunela chaves técnicas da ElevenLabs):

```json
{
  "model": "elevenlabs/eleven-multilingual-v2",
  "input": "O ciclo de vida da aplicação foi atualizado.",
  "voice": "rachel",
  "provider": {
    "options": {
      "elevenlabs": {
        "seed": 8945,
        "language_code": "pt",
        "previous_text": "Frase anterior, só contexto.",
        "next_text": "Frase seguinte, só contexto.",
        "voice_settings": {
          "stability": 0.45,
          "similarity_boost": 0.85,
          "style": 0.2,
          "use_speaker_boost": true
        }
      }
    }
  }
}
```

| Chave | Efeito |
|---|---|
| `seed` | Reprodutibilidade matemática: mesmo texto + mesmo seed → mesmo áudio |
| `previous_text` / `next_text` | Contexto de continuidade para chunking (não é verbalizado) |
| `language_code` | Fixa o idioma de síntese |
| `pronunciation_dictionary_locators` | Dicionários customizados de pronúncia (exigem conta nativa + BYOK) |
| `voice_settings.stability` | Alto = tom uniforme/monótono; baixo = mais emoção/oscilação, risco de rutura fonética |
| `voice_settings.similarity_boost` | Em clones: mimetiza mais agressivamente a amostra original (amplifica ruído herdados) |
| `voice_settings.style` / `use_speaker_boost` | Clareza e amplificação das qualidades da voz |

**Regra do `speed`:** só `eleven-multilingual-v2` e a família Flash aceitam valores contínuos **0.7–1.2**. Os modelos premium (`eleven-v4`, `eleven-v4-turbo`) **rejeitam `speed` ≠ default com HTTP 400** — use pontuação e audio tags (`[rushed]`, `[drawn out]`) para ditar andamento.

## 8. STT: transcrição com Scribe

Endpoint: `POST /api/v1/audio/transcriptions`.

Restrições rígidas:
- **Formato de envio:** bytes brutos em **Base64** dentro de JSON (`input_audio`), **sem** prefixo `data:audio/mp3;base64,` (URI data é recusado), OU `multipart/form-data`.
- **Tamanho máximo: 25 MB** por requisição.
- **Upstream timeout: 60 s** — áudios longos (palestras, reuniões) devem ser **fatiados localmente** antes do envio.

### curl (terminal)

```bash
B64=$(base64 -w0 reuniao.mp3)
jq -n --arg b64 "$B64" '{
  model: "elevenlabs/scribe-v2",
  response_format: "verbose_json",
  "timestamp_granularities[]": "word",
  input_audio: { data: $b64, format: "mp3" },
  provider: { options: { elevenlabs: {
    diarize: true, num_speakers: 2, tag_audio_events: true
  }}}
}' > "$TMPDIR/stt.json"

curl -sS -X POST "https://openrouter.ai/api/v1/audio/transcriptions" \
  -H "Authorization: Bearer $OPENROUTER_API_KEY" \
  -H "Content-Type: application/json" \
  --data @"$TMPDIR/stt.json" | jq '{text, usage}'
```

### Parâmetros de extração (via `provider.options.elevenlabs`)

| Parâmetro | Tipo | Efeito |
|---|---|---|
| `diarize` | bool | Diarização: segmenta e atribui o texto a cada locutor |
| `num_speakers` | int | Força a classificação em N interlocutores |
| `diarization_threshold` | float | Sensibilidade à alternância de locutor (**não usar junto com `num_speakers`** — a API aceita só um dos dois) |
| `tag_audio_events` | bool | Correlaciona ruídos não inteligíveis a etiquetas explicativas |
| `no_verbatim` | bool | Suprime hesitações ("hmm", "uhh") no texto final |
| `language` | str | Induz detecção (aceita formato de 2 letras `en`, `pt`; a saída identifica em ISO 639-3 — `eng`, `por`) |

`response_format: "verbose_json"` + `"timestamp_granularities[]": "word"` → texto, timestamps por palavra, locutores, `usage` com **`usage.cost`** (custo em USD da transação).

## 9. Clonagem de voz (IVC vs PVC) e BYOK

**Limitação estrutural:** o OpenRouter é agregador/roteador — a API dele **NÃO** expõe upload de treino, gestão de clones nem dicionários de pronúncia. Clonagem exige arquitetura híbrida em **3 fases**:

### Fase 1 — Criar o clone na API nativa da ElevenLabs (fora do OpenRouter)

| Método | Material | Latência | Requisitos |
|---|---|---|---|
| **IVC** (Instant Voice Cloning) | Amostras curtas (recomendado MP3 192 kbps, estúdio, ~20 cm do microfone, com filtro pop) | Imediato (few-shot adaptation, sem fine-tuning) | Conta ElevenLabs |
| **PVC** (Professional Voice Cloning) | Horas de material gravado | 6–24 h de treino (fila de fine-tuning) → rótulo "Studio Quality" | **Consentimento por captura de texto** obrigatório; proibido clonar terceiros mesmo com consentimento |

```python
# pip install elevenlabs  (SDK oficial; fala com api.elevenlabs.io, NÃO com o OpenRouter)
import os
from io import BytesIO
from elevenlabs.client import ElevenLabs

cliente_native = ElevenLabs(api_key=os.getenv("ELEVENLABS_API_KEY"))

def criar_clone_ivc(caminho_amostra: str, nome: str) -> str:
    with open(caminho_amostra, "rb") as f:
        bytes_amostra = f.read()
    perfil = cliente_native.voices.ivc.create(
        name=nome,
        description="Clone instantâneo para orquestração híbrida via OpenRouter.",
        files=[BytesIO(bytes_amostra)],
    )
    print("voice_id:", perfil.voice_id)  # ex.: "21m00Tcm4TlvDq8ikWAM"
    return perfil.voice_id
```

O retorno é um `voice_id` alfanumérico (ex.: `21m00Tcm4TlvDq8ikWAM`). **Guarde-o** — fica trancado sob a conta original; só funciona com a chave BYOK dessa conta.

Terminal (sem SDK), com a API nativa:

```bash
curl -sS -X POST "https://api.elevenlabs.io/v1/voices/add" \
  -H "xi-api-key: $ELEVENLABS_API_KEY" \
  -F "name=Representante Oficial" \
  -F "description=Clone instantâneo" \
  -F "files=@discurso_limpo.mp3" | jq '{voice_id: .voice_id}'
```

### Fase 2 — BYOK (Bring Your Own Key) no OpenRouter

1. Em https://openrouter.ai/settings/keys → **BYOK/Provider Keys** → provedor **ElevenLabs** → colar a chave nativa (`ELEVENLABS_API_KEY`). A chave fica encriptada e vinculada à sua `OPENROUTER_API_KEY`.
2. Feito o vínculo, chamadas a `elevenlabs/*` usam a sua conta ElevenLabs por baixo: o OpenRouter vira **proxy de trânsito**, repassando a identidade que valida vozes clonadas e dicionários de pronúncia.
3. **Faturação:** os modelos ElevenLabs cobram primeiro do **saldo/plano nativo** da ElevenLabs; o OpenRouter aplica uma taxa passiva modesta (~5% da transação upstream) pela orquestração. **BYOK não torna nada gratuito.**

### Fase 3 — Inferir o clone via OpenRouter

Igual à requisição TTS da seção 4, trocando o nome da voz pelo `voice_id`:

```bash
curl -sS -X POST "https://openrouter.ai/api/v1/audio/speech" \
  -H "Authorization: Bearer $OPENROUTER_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "elevenlabs/eleven-v4",
    "voice": "21m00Tcm4TlvDq8ikWAM",
    "input": "[laughs] O pipeline híbrido validou o modelo de voz clonada!",
    "response_format": "mp3"
  }' \
  -D "$TMPDIR/hdrs.txt" -o saida_clone.mp3
grep -i "^x-generation-id" "$TMPDIR/hdrs.txt"
```

Sem BYOK configurado, o `voice_id` privado devolve erro (voz inacessível) — a Fase 2 é pré-requisito.

## 10. Erros e corrupção binária silenciosa

A falha de produção mais catastrófica: request mal formada (campo desconhecido, `voice` ausente, `speed` em `eleven-v4`) → **HTTP 400** com corpo em padrão **ZodError** (JSON de erro). Se o cliente não validar status/Content-Type e gravar o body como `.mp3`, o "áudio" é um ficheiro de texto de erro — o player reporta "mídia vazia ou inválida".

Mitigações obrigatórias em qualquer cliente:
1. `raise_for_status()` (ou equivalente) **antes** de gravar;
2. Interrogar `Content-Type` (esperado `audio/mpeg` ou `audio/pcm` em sucesso);
3. Logar `X-Generation-Id` sempre;
4. Em erro, imprimir o body — o ZodError aponta o campo exato: mensagens aninhadas tipo `["path": ["voice"]]`.

Exemplo de corpo ZodError (abstrato):

```json
{ "error": { "message": "Validation failed", "issues": [{ "path": ["voice"], "message": "Required" }] } }
```

Outros erros relevantes: 401 (chave inválida), 402 (créditos insuficientes), 404 (modelo/provider indisponível sob as restrições), 429 (rate limit — backoff + `Retry-After`), 503 (nenhum provider saudável). Tabela completa: [errors.md](errors.md).

## 11. Custos e reconciliação

- **TTS:** cobrança por **milhão de caracteres submetidos** (tabelas das seções 2; áudio tags incluídas).
- **STT:** cobrança por **segundo de áudio** ($0.000031/s nas variantes Scribe).
- Respostas STT `verbose_json` trazem o custo em `usage.cost`.
- Em contas com BYOK, os descritores de geração (`GET /api/v1/generation?id=...`) expõem `is_byok`/`isByok` — útil para auditorias de orçamento (custos correm no plano nativo + taxa OpenRouter).
- Consulta de saldo da chave OpenRouter: `GET /api/v1/key` (`limit`, `limit_remaining`, `usage_monthly`, `is_free_tier`) — o CLI `scripts/openrouter.sh key` faz isto; o `scripts/elevenlabs.sh account` junta o dado da ElevenLabs.

## 12. Credenciais: check em memória → setup guiado → puxar dados

Fluxo **100% em terminal** para as duas contas (`OPENROUTER_API_KEY` e `ELEVENLABS_API_KEY`), implementado em `scripts/elevenlabs.sh`:

```bash
# 1. VERIFICAR em memória (stores de credenciais) se já temos o login de cada conta
scripts/elevenlabs.sh check

# 2. Se faltar: SETUP GUIADO — pede a chave (input oculto), valida o formato,
#    testa o login real contra a API e SALVA como variável de ambiente
#    (~/.secrets com chmod 600 + export via ~/.zshenv, idempotente)
scripts/elevenlabs.sh setup

# 3. PUXAR os dados da conta (plano, créditos, uso, voice_ids) direto no terminal
scripts/elevenlabs.sh account
```

Ordem de busca do `check` (a "memória" de credenciais desta máquina):

| # | Store | Onde "puxar" |
|---|---|---|
| 1 | Variável do processo atual | já disponível (`echo $OPENROUTER_API_KEY`) |
| 2 | `./.env` do projeto | `set -a; source .env; set +a` |
| 3 | `~/.secrets` | `source ~/.secrets` (fonte canônica, `chmod 600`) |
| 4 | `~/.zshenv` | `source ~/.zshenv` (exporta em todo shell zsh) |
| 5 | `~/.dsh/.credentials.yaml` (`refs:`) | credential store do DSH (hot reload) |
| 6 | Memória CoALA do projeto (`.agents/*/memory/coala.sqlite`) | registos de conta/login guardados pela skill `coala-agent-skill` |

O `check` imprime, por conta: status (`PRESENTE`/`AUSENTE`), store onde achou, valor mascarado (últimos 4 dígitos) e o comando exato para carregar. Com `--json`, saída estruturada; com `--live`, além de achar a chave, valida o login contra a API (OpenRouter `GET /api/v1/key`; ElevenLabs `GET /v1/user`) e mostra o "quem é" da conta.

**Onde criar as chaves:** OpenRouter → https://openrouter.ai/keys (formato `sk-or-v1-...`); ElevenLabs → https://elevenlabs.io/api-keys (necessária para clonagem/BYOK). **Nunca commitar chaves**; o `setup` grava só em `~/.secrets` (600).
