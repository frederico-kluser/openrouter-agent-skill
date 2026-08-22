# openrouter-agent-skill

> Agent skill que ensina agentes de LLM (Claude Code, opencode, Codex, Cursor, Gemini CLI) a usar o OpenRouter: buscar modelos e providers, forçar provider, preços e tokens/segundo e integrar o roteamento completo em projetos.

## O que é

Uma **agent skill** (no padrão aberto de skills da Anthropic, spec [agentskills.io](https://agentskills.io/)) que ensina agentes de LLM a usar a API do OpenRouter com proficiência:

- **Buscar modelos** no catálogo (411 modelos verificados em 2026-08-14, IDs no formato `author/slug`, ex.: `deepseek/deepseek-chat`);
- **Buscar providers** que servem um modelo, com preço e **tokens/segundo** (TPS) por provider;
- **Forçar provider** via objeto `provider` (order/allow/ignore/sort);
- **Integrar o OpenRouter em projeto** — drop-in do SDK OpenAI apontando para `https://openrouter.ai/api/v1`;
- **Todas as configurações de roteamento**: objeto `provider`, variantes de modelo, `plugins[]`, fallbacks de modelos (`models[]`) e cache de respostas.

Funciona em **Claude Code, opencode, Codex, Cursor e Gemini CLI** — a mesma pasta de skill servida em cada plataforma (ver [Instalação](#instalação)).

## Recursos

- **`SKILL.md`** — instruções da skill em menos de 500 linhas, com *progressive disclosure*: o essencial na raiz, os detalhes carregados de `references/` somente quando o agente precisa.
- **`references/`** — material de referência por tópico: API, roteamento, erros e integrações.
- **`scripts/openrouter.sh`** — CLI auxiliar: `models`, `providers`, `prices`, `tps`, `suggest`, `chat`, `key`, `credits`. Suporta **dry-run sem chave** (mostra o que seria chamado sem bater na API).
- **`examples/`** — exemplos prontos: bash, Python com o SDK OpenAI, payload de roteamento e parse de `usage`.
- **`docs/research/`** — pesquisa verificada em **2026-08-14** contra os docs oficiais e a OpenAPI spec, com afirmações não confirmadas marcadas como `[NÃO CONFIRMADO]`.

## Instalação

Três modos. O recomendado é o **global via symlink**: um único `git pull` no repositório atualiza a skill em todos os agentes.

### 1. Global via symlink (recomendado)

```bash
git clone https://github.com/frederico-kluser/openrouter-agent-skill.git ~/Projects/openrouter-agent-skill
mkdir -p ~/.claude/skills ~/.agents/skills ~/.claude-deepseek/skills
ln -s ~/Projects/openrouter-agent-skill ~/.claude/skills/openrouter-agent-skill
```

- **Claude Code** lê `~/.claude/skills/` — o symlink acima já basta.
- **opencode, Codex, Cursor e Gemini CLI** leem `~/.agents/skills/` (o Claude Code **não** lê essa pasta):

```bash
ln -s ~/Projects/openrouter-agent-skill ~/.agents/skills/openrouter-agent-skill
```

- Se você usa a variante **`claude-deepseek`** do Claude Code:

```bash
ln -s ~/Projects/openrouter-agent-skill ~/.claude-deepseek/skills/openrouter-agent-skill
```

> **NOTA:** o symlink aponta para o **diretório do repositório** (que contém `SKILL.md` na raiz), não para um subdiretório. Se o seu clone estiver em outro caminho, troque `~/Projects/openrouter-agent-skill` pelo caminho real (`/caminho/do/repo`) em todos os comandos acima.

### 2. Por projeto

Skill disponível apenas para o projeto corrente, em `.claude/skills/`:

```bash
mkdir -p .claude/skills
cp -r ~/Projects/openrouter-agent-skill .claude/skills/openrouter-agent-skill
# ou symlink, para continuar atualizando junto com o clone:
ln -s ~/Projects/openrouter-agent-skill .claude/skills/openrouter-agent-skill
```

### 3. Marketplace

O formato segue a especificação aberta [agentskills.io](https://agentskills.io/) (`~/.agents/skills/` e `.agents/skills/`), compatível com ferramentas e marketplaces que adotam o padrão. Não há registro de marketplace próprio — instale via symlink ou cópia (modos 1 e 2).

## Uso rápido

Invoque `/openrouter-agent-skill` no Claude Code, ou simplesmente peça em qualquer agente suportado. Perguntas que ativam a skill:

- "Busque modelos baratos com contexto 128k."
- "Liste os providers de `deepseek/deepseek-chat` com preço e TPS."
- "Monte um payload forçando o provider X com fallback."

Sem chave? Teste a CLI em **dry-run**, que mostra o que seria chamado sem tocar na API:

```bash
scripts/openrouter.sh models --dry-run
```

## Estrutura do repositório

```
openrouter-agent-skill/
├── SKILL.md                  # instruções da skill (< 500 linhas, progressive disclosure)
├── references/               # referências por tópico: api, routing, errors, integrations
├── scripts/
│   └── openrouter.sh         # CLI: models, providers, prices, tps, suggest, chat, key, credits
├── examples/                 # exemplos prontos: bash, Python (SDK OpenAI), payload, usage
├── docs/research/            # pesquisa verificada contra docs oficiais + OpenAPI spec
└── README.md                 # este arquivo
```

## Configuração

1. Crie uma chave de API em **https://openrouter.ai/keys** (formato `sk-or-v1-...`).
2. Defina a chave no ambiente:

```bash
export OPENROUTER_API_KEY="sk-or-v1-..."
# ou em um arquivo .env na raiz do projeto (a skill também lê .env)
```

3. **Nunca commite a chave.** O repositório ignora `.env` e `.env.*` no `.gitignore`, e o GitHub faz *secret scanning* automático — chaves vazadas em repositórios públicos são detectadas e devem ser revogadas em **https://openrouter.ai/settings/keys**.

## Documentação de pesquisa

O diretório `docs/research/` contém o levantamento factual que sustenta a skill, todo verificado em **2026-08-14** contra os docs oficiais do OpenRouter (`https://openrouter.ai/docs`, índice `llms.txt`) e a **OpenAPI spec** (`https://openrouter.ai/openapi.yaml`):

- [`docs/research/agent-skill-design.md`](docs/research/agent-skill-design.md) — design de agent skills: anatomia, progressive disclosure, descoberta e mecânica de instalação/symlinks por plataforma;
- [`docs/research/openrouter-api.md`](docs/research/openrouter-api.md) — endpoints, autenticação, compatibilidade OpenAI, `usage` e erros;
- [`docs/research/openrouter-routing-config.md`](docs/research/openrouter-routing-config.md) — objeto `provider`, variantes, plugins, fallbacks e cache.

Afirmações que não puderam ser confirmadas nas fontes primárias estão marcadas como `[NÃO CONFIRMADO]` — leia antes de citar como fato.
