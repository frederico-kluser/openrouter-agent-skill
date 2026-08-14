# Pesquisa: Design de Agent Skills — Estado da Arte (2026-08-14)

> **Objetivo deste documento:** orientar a autoria de uma `SKILL.md` de produção, com base em pesquisa profunda sobre fontes primárias (docs oficiais da Anthropic/Claude Code, especificação aberta de Agent Skills em agentskills.io, docs do opencode, Codex, Cursor e Gemini CLI) e exemplos reais de skills em produção.
>
> **Método:** WebFetch direto nas fontes primárias (conteúdo verbatim abaixo) + WebSearch de confirmação + 2 tentativas do `search.sh` do deep-orchestrator (Tier 1 surf-ai), que falharam por erro de rede em todos os providers — ver "Ressalvas" (seção 6). Toda afirmação carrega a fonte (título + URL) na seção 5.5. Nada foi inventado; itens não verificáveis estão marcados `[NÃO CONFIRMADO]`.
>
> **Nota de convenção:** "SKILL.md" (spec aberta) e "Skill" (Anthropic) são o mesmo conceito. Citações em inglês foram mantidas verbatim; traduções são minhas.

---

## 1. Anatomia de uma skill

### 1.1 O que é uma skill

Uma skill é, no mínimo, **uma pasta com um arquivo `SKILL.md`** contendo frontmatter YAML + instruções em Markdown. A definição canônica (spec aberta, agentskills.io):

> "At its core, a skill is a folder containing a `SKILL.md` file. This file includes metadata (`name` and `description`, at minimum) and instructions that tell an agent how to perform a specific task."

Fonte: [agentskills.io — Overview](https://agentskills.io/)

A definição da Anthropic:

> "Agent Skills are modular capabilities that extend Claude's functionality. Each Skill packages instructions, metadata, and optional resources (scripts, templates) that Claude uses automatically when relevant."

Fonte: [platform.claude.com — Agent Skills overview](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/overview)

No blog de engenharia da Anthropic, a analogia que fixa o conceito: **"Building a skill for an agent is like putting together an onboarding guide for a new hire."** Fonte: [anthropic.com/engineering — Equipping agents for the real world with Agent Skills](https://www.anthropic.com/engineering/equipping-agents-for-the-real-world-with-agent-skills).

Distinção estrutural vs. prompt (docs Claude Code): um prompt/CLAUDE.md é instrução permanente no contexto; uma skill só carrega o corpo **quando usada** — "a skill's body loads only when it's used, so long reference material costs almost nothing until you need it." Fonte: [code.claude.com — Extend Claude with skills](https://code.claude.com/docs/en/skills).

### 1.2 Estrutura de diretório canônica

Spec aberta (agentskills.io/specification) — diretório mínimo + convenções:

```text
skill-name/
├── SKILL.md          # Required: metadata + instructions
├── scripts/          # Optional: executable code
├── references/       # Optional: documentation
├── assets/           # Optional: templates, resources
└── ...               # Any additional files or directories
```

- `scripts/` — código executável. Devem ser "self-contained or clearly document dependencies", com "helpful error messages" e "handle edge cases gracefully". Linguagens comuns: Python, Bash, JavaScript.
- `references/` — documentação adicional lida sob demanda (`REFERENCE.md`, `FORMS.md`, arquivos por domínio como `finance.md`). "Keep individual reference files focused. Agents load these on demand, so smaller files mean less use of context."
- `assets/` — recursos estáticos: templates, imagens, dados (tabelas de lookup, schemas).

Fonte: [agentskills.io — Specification](https://agentskills.io/specification)

Exemplo do mundo real (docs Anthropic, skill de PDF):

```text
pdf/
├── SKILL.md              # Main instructions (loaded when triggered)
├── FORMS.md              # Form-filling guide (loaded as needed)
├── reference.md          # API reference (loaded as needed)
├── examples.md           # Usage examples (loaded as needed)
└── scripts/
    ├── analyze_form.py   # Utility script (executed, not loaded)
    ├── fill_form.py      # Form filling script
    └── validate.py       # Validation script
```

Fonte: [platform.claude.com — Skill authoring best practices](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices)

A spec permite **qualquer** arquivo/diretório adicional ("Any additional files or directories") — a convenção `scripts/|references/|assets/` é recomendação, não regra.

### 1.3 Frontmatter YAML

#### 1.3.1 Campos da especificação aberta (agentskills.io) — o mínimo multiplataforma

| Campo | Obrigatório | Restrições (verbatim) |
|---|---|---|
| `name` | Sim | "Max 64 characters. Lowercase letters, numbers, and hyphens only. Must not start or end with a hyphen." Além disso: "Must be 1-64 characters; May only contain unicode lowercase alphanumeric characters (`a-z`, `0-9`) and hyphens (`-`); Must not start or end with a hyphen (`-`); Must not contain consecutive hyphens (`--`); **Must match the parent directory name**" |
| `description` | Sim | "Max 1024 characters. Non-empty. Describes what the skill does and when to use it." / "Should include specific keywords that help agents identify relevant tasks" |
| `license` | Não | "License name or reference to a bundled license file." Recomenda-se curto. |
| `compatibility` | Não | "Max 500 characters. Indicates environment requirements (intended product, system packages, network access, etc.)." "Most skills do not need the `compatibility` field." |
| `metadata` | Não | "Arbitrary key-value mapping for additional metadata (a map from string keys to string values)." Recomenda-se chaves razoavelmente únicas para evitar conflitos. |
| `allowed-tools` | Não | "Space-separated string of pre-approved tools the skill may use. **(Experimental)**" Ex.: `allowed-tools: Bash(git:*) Bash(jq:*) Read` |

Exemplo mínimo da spec:

```yaml
---
name: skill-name
description: A description of what this skill does and when to use it.
---
```

Fonte: [agentskills.io — Specification](https://agentskills.io/specification)

#### 1.3.2 Restrições adicionais na plataforma Anthropic (Claude API/claude.ai)

- `name`: "Maximum 64 characters; Must contain only lowercase letters, numbers, and hyphens; Cannot contain XML tags; Cannot contain reserved words: 'anthropic', 'claude'"
- `description`: "Must be non-empty; Maximum 1024 characters; Cannot contain XML tags"
- "The `description` must include both what the Skill does and when Claude should use it."

Fonte: [platform.claude.com — Agent Skills overview, "Skill structure"](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/overview)

> **Atenção:** os docs da plataforma (2026-08) não citam um campo `display_title` — sumário de busca secundário o mencionou, mas o texto primário oficial não o contém. `display_title`: `[NÃO CONFIRMADO]`.

#### 1.3.3 Extensões do Claude Code (frontmatter completo)

O Claude Code aceita **todos** os campos da tabela abaixo (todos opcionais; só `description` é recomendado — "All fields are optional. Only `description` is recommended so Claude knows when to use the skill"):

```yaml
---
name: my-skill
description: What this skill does
disable-model-invocation: true
allowed-tools: Read Grep
---
```

| Campo | O que faz (resumo fiel do doc) |
|---|---|
| `name` | Nome exibido nas listagens. **O comando de invocação vem do NOME DO DIRETÓRIO** (não do frontmatter) em skills pessoais/projeto; em skills de plugin, `name` vira o último segmento do comando. |
| `description` | O que a skill faz e quando usar. "Claude uses this to decide when to apply the skill. If omitted, uses the first paragraph of markdown content. Put the key use case first: the combined `description` and `when_to_use` text is truncated at 1,536 characters in the skill listing". |
| `when_to_use` | Contexto adicional de quando invocar (frases-gatilho, exemplos). Anexado a `description` no listing; conta para o teto de 1.536 chars. |
| `argument-hint` | Dica exibida no autocomplete (ex.: `[issue-number]`). |
| `arguments` | Argumentos posicionais nomeados para substituição `$name`. |
| `disable-model-invocation` | `true` = só o usuário invoca (`/name`); Claude fica proibido de carregar automaticamente. |
| `user-invocable` | `false` = some do menu `/` (conhecimento de fundo; só Claude invoca). |
| `allowed-tools` | Ferramentas pré-aprovadas sem prompt na turn que invoca a skill (grant limpa na próxima mensagem). Ex.: `Bash(git add *) Bash(git commit *)`. |
| `disallowed-tools` | Ferramentas removidas do pool enquanto a skill está ativa. |
| `model` / `effort` | Override de modelo/esforço enquanto a skill está ativa (turn). |
| `context` | `fork` = roda em subagent isolado (ver seção 4.9). |
| `agent` | Tipo de subagent quando `context: fork` (`Explore`, `Plan`, `general-purpose`, ou custom em `.claude/agents/`). |
| `background` | Só com `context: fork`; `false` = espera o resultado na mesma turn. |
| `hooks` / `paths` / `shell` | Hooks no ciclo de vida; `paths` = globs que limitam ativação automática a arquivos correspondentes; `shell` = `bash` ou `powershell` para comandos `!`. |
| `metadata` | "Free-form YAML map for your own key-value data... Claude Code doesn't act on its contents, and drops a value that isn't a map. Don't reuse frontmatter field names such as `paths` as keys." |
| `license`, `compatibility` | Parte da spec aberta; o Claude Code aceita mas não age sobre eles. |

**Portabilidade crítica:** fora do Claude Code (upload no claude.ai, Skills API, empacotamento com `package_skill.py` do anthropics/skills), **só os 6 campos da spec são aceitos**: `name`, `description`, `license`, `compatibility`, `metadata`, `allowed-tools`. Campo a mais = erro duro de empacotamento:

```text
Unexpected key(s) in SKILL.md frontmatter: argument-hint. Allowed properties are: allowed-tools, compatibility, description, license, metadata, name
```

**Regra de ouro para uma skill portável:** restringir o frontmatter aos 6 campos da spec (evita o erro acima e funciona em todos os clientes da spec — Claude Code, opencode, Gemini, Cursor, Codex, etc.).

Fonte: [code.claude.com — Extend Claude with skills, "Frontmatter reference"](https://code.claude.com/docs/en/skills)

#### 1.3.4 Frontmatter nas demais plataformas (detalhe na seção 3)

- **opencode:** só `name` (obrig.), `description` (obrig.), `license`, `compatibility`, `metadata` (map string→string). "Unknown frontmatter fields are ignored." `name`: 1–64 chars, regex `^[a-z0-9]+(-[a-z0-9]+)*$`, deve bater com o nome do diretório. `description`: 1–1024 chars. Fonte: [opencode.ai/docs/skills](https://opencode.ai/docs/skills/)
- **Gemini CLI:** exatamente `name` + `description` obrigatórios; frontmatter deve ser a primeira coisa do arquivo (delimitadores `---` em linhas próprias, nada antes). Malformado → skill **silenciosamente ignorada**. Fonte: [geminicli.com/docs/cli/creating-skills](https://geminicli.com/docs/cli/creating-skills/)
- **Codex:** `name` + `description` obrigatórios ("must include `name` and `description`"); arquivo opcional `agents/openai.yaml` com `interface` (display_name, short_description, ícones, brand_color, default_prompt), `policy.allow_implicit_invocation` (default `true`) e `dependencies` (ferramentas/MCP). Fonte: [learn.chatgpt.com — Build skills](https://learn.chatgpt.com/docs/build-skills)
- **Cursor (skills):** `name` (obrig., deve bater com a pasta), `description` (obrig.), `paths` (globs — o antigo `globs` ainda aceito como fallback), `disable-model-invocation`, `metadata`. Fonte: [cursor.com/docs/context/skills](https://cursor.com/docs/context/skills)

### 1.4 Corpo em Markdown

O corpo após o frontmatter é livre: "The Markdown body after the frontmatter contains the skill instructions. There are no format restrictions. Write whatever helps agents perform the task effectively." Seções recomendadas pela spec: "Step-by-step instructions; Examples of inputs and outputs; Common edge cases." Fonte: [agentskills.io — Specification](https://agentskills.io/specification)

Template do repo anthropics/skills:

```markdown
---
name: my-skill-name
description: A clear description of what this skill does and when to use it
---

# My Skill Name

[Add your instructions here that Claude will follow when this skill is active]

## Examples
- Example usage 1
- Example usage 2

## Guidelines
- Guideline 1
- Guideline 2
```

Fonte: [github.com/anthropics/skills — README](https://github.com/anthropics/skills)

### 1.5 Progressive disclosure — o coração do design

A spec define explicitamente:

> "Agents load skills *progressively*, pulling in more detail only as a task calls for it."

Três níveis com custo de contexto:

| Nível | Quando carrega | Custo | Conteúdo |
|---|---|---|---|
| **1. Metadados** | Sempre, no startup | ~100 tokens por skill | `name` + `description` do frontmatter (injetados no system prompt) |
| **2. Instruções** | Quando a skill é ativada | <5.000 tokens recomendado | corpo completo do SKILL.md |
| **3. Recursos** | Sob demanda | 0 até serem lidos | arquivos em `scripts/`, `references/`, `assets/`; scripts rodam via bash e só a SAÍDA entra no contexto |

Fonte: [agentskills.io — Specification](https://agentskills.io/specification) e [platform.claude.com — Agent Skills overview, "How Skills work"](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/overview)

Mecânica no Claude (arquitetura de VM com filesystem): "When a Skill is triggered, Claude uses bash to read SKILL.md from the filesystem, bringing its instructions into the context window. If those instructions reference other files (such as FORMS.md or a database schema), Claude reads those files too using additional bash commands. When instructions mention executable scripts, Claude runs them through bash and receives only the output (the script code itself never enters context)." Consequências documentadas: acesso sob demanda a dezenas de arquivos sem custo, execução de scripts determinística sem carregar o código, e **"No practical limit on bundled content"**. Fonte: [platform.claude.com — Agent Skills overview](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/overview)

### 1.6 Limites de tamanho e relevância (síntese verificada)

- **SKILL.md: < 500 linhas** — repetido em três fontes oficiais: spec ("Keep your main `SKILL.md` under 500 lines. Move detailed reference material to separate files"), best practices da Anthropic ("Keep SKILL.md body under 500 lines for optimal performance"), e docs do Claude Code ("Keep `SKILL.md` under 500 lines. Move detailed reference material to separate files").
- **SKILL.md: < 5.000 tokens** recomendado (nível 2 da spec e do overview da plataforma).
- **`description`: ≤ 1.024 caracteres** (spec e plataforma Anthropic). No listing do Claude Code o teto combinado description+when_to_use é **1.536 caracteres**, com key use case primeiro ("Put the key use case first").
- **Orçamento do listing:** Claude Code usa **1% do contexto do modelo** para a listagem de nomes+descrições; se estourar, corta descrições começando pelas skills menos invocadas. Codex: "at most 2% of the model's context window, or 8,000 characters", encurtando descrições primeiro.
- **Nomes:** 1–64 chars, minúsculas+números+hífens, sem `--`, sem hífen nas pontas, sem XML, sem palavras reservadas ("anthropic", "claude").
- **Referências de arquivos: 1 nível de profundidade.** "Keep references one level deep from SKILL.md" — referências aninhadas fazem Claude ler parcialmente (`head -100`) e perder informação. Para references > 100 linhas: **tabela de conteúdos no topo**, para Claude enxergar o escopo mesmo em leitura parcial.

Fontes: [agentskills.io/specification](https://agentskills.io/specification); [platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices); [code.claude.com/docs/en/skills](https://code.claude.com/docs/en/skills); [learn.chatgpt.com/docs/build-skills](https://learn.chatgpt.com/docs/build-skills)

---

## 2. Descoberta e invocação — a descrição como gatilho

### 2.1 Como o agente "vê" as skills

Mecânica comum a todos os clientes da spec (progressive disclosure nível 1): **no startup, apenas `name` + `description` de cada skill entram no system prompt**. Implementações verificadas:

- **Claude Code:** skills listadas para Claude via ferramenta Skill (name + descrição); usuário vê via `/skills` e menu `/`. "In a regular session, skill descriptions are loaded into context so Claude knows what's available, but full skill content only loads when invoked." Fonte: [code.claude.com/docs/en/skills](https://code.claude.com/docs/en/skills)
- **opencode:** a ferramenta nativa `skill` lista as skills como entradas XML `<available_skills>` — ex.: `<name>git-release</name>` + `<description>Create consistent releases and changelogs</description>`; o agente chama `skill({ name: "git-release" })` e só então o conteúdo completo é carregado. Fonte: [opencode.ai/docs/skills](https://opencode.ai/docs/skills/)
- **Gemini CLI:** "at session start, Gemini CLI scans the discovery tiers and injects only the name and description of all enabled skills into the system prompt"; ativação via tool `activate_skill`, com confirmação do usuário antes da injeção do corpo. Fonte: [geminicli.com/docs/cli/skills](https://geminicli.com/docs/cli/skills/)
- **Codex:** idem — "hosts start with each skill's name and description, then load the full SKILL.md only when the skill is selected". Ativação implícita ("your task matches the skill `description`") ou explícita (`@` no ChatGPT; `$` ou `/skills` no Codex CLI/IDE). Fonte: [learn.chatgpt.com/docs/build-skills](https://learn.chatgpt.com/docs/build-skills)

### 2.2 Como escrever descrições que disparam o uso correto

Requisito duplo, repetido em TODAS as fontes: a descrição deve dizer **o que a skill faz** E **quando usar**. Da spec: "Should describe both what the skill does and when to use it; Should include specific keywords that help agents identify relevant tasks". Da Anthropic: "The `description` is what Claude matches your request against when determining whether to trigger the Skill, so it must say both what the Skill does and when to use it."

Regras verificadas (best practices da Anthropic):

1. **Sempre em terceira pessoa.** "The description is injected into the system prompt, and inconsistent point-of-view can cause discovery problems."
   - Bom: "Processes Excel files and generates reports"
   - Ruim: "I can help you process Excel files" / "You can use this to process Excel files"
2. **Específica, com termos-chave e gatilhos/contextos.** "Claude uses it to choose the right Skill from potentially 100+ available Skills."
3. **Padrão "verbo + quando":** dizer o que faz no início e terminar com "Use when...".

Exemplos bons (verbatim):

```yaml
description: Extract text and tables from PDF files, fill forms, merge documents. Use when working with PDF files or when the user mentions PDFs, forms, or document extraction.
```

```yaml
description: Analyze Excel spreadsheets, create pivot tables, generate charts. Use when analyzing Excel files, spreadsheets, tabular data, or .xlsx files.
```

```yaml
description: Generate descriptive commit messages by analyzing git diffs. Use when the user asks for help writing commit messages or reviewing staged changes.
```

Exemplos ruins (verbatim): `Helps with documents` · `Processes data` · `Does stuff with files`.

A spec (agentskills.io) usa o mesmo par bom/ruim: bom = "Extracts text and tables from PDF files, fills PDF forms, and merges multiple PDFs. Use when working with PDF documents or when the user mentions PDFs, forms, or document extraction."; ruim = "Helps with PDFs."

O Gemini CLI diz o mesmo com outra ênfase: a `description` é "**CRITICAL.** This is how Gemini decides when to use the skill. Be specific about the tasks it handles and the keywords that should trigger it."

**Front-loading:** no Claude Code a descrição combinada é truncada a 1.536 chars e o listing inteiro pode ser encurtado (1% do contexto) — portanto o caso de uso-chave e as palavras-gatilho precisam vir no início da descrição ("Put the key use case first"). Idem no Codex: "front-load key use cases and trigger words so matching survives truncation."

Fontes: [platform.claude.com — Skill authoring best practices](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices); [agentskills.io/specification](https://agentskills.io/specification); [geminicli.com/docs/cli/creating-skills](https://geminicli.com/docs/cli/creating-skills/); [code.claude.com/docs/en/skills](https://code.claude.com/docs/en/skills); [learn.chatgpt.com/docs/build-skills](https://learn.chatgpt.com/docs/build-skills)

### 2.3 Invocação: manual e automática

- **Manual:** `/nome-da-skill` (Claude Code, Gemini via `/skills list`/`/` menu, Cursor via `/` no chat, opencode via chamada explícita `skill({name})`, Codex via `$skill` ou `/skills`).
- **Automática:** o modelo casa o pedido do usuário com a `description` (match semântico, não keyword rígido) e carrega a skill.
- **Controle fino (Claude Code):**
  - `disable-model-invocation: true` → só manual (ex.: `/deploy`, `/commit` — "You don't want Claude deciding to deploy because your code looks ready").
  - `user-invocable: false` → só o modelo (conhecimento de fundo).
  - Regras de permissão: `Skill(commit)`, `Skill(review-pr *)`, `Skill(deploy *)` em deny/allow.
  - `skillOverrides` em settings: `"on" | "name-only" | "user-invocable-only" | "off"` (off esconde também do menu).
  - `paths` no frontmatter → ativação automática só quando os arquivos trabalhados batem com os globs.
  - `disable-model-invocation: true` também impede pré-carga em subagents e execução por scheduled tasks (v2.1.196+).
- **Gemini CLI:** ativação pede **consentimento do usuário** (mostra nome, propósito e diretório que será acessado).

Fontes: [code.claude.com/docs/en/skills](https://code.claude.com/docs/en/skills); [geminicli.com/docs/cli/skills](https://geminicli.com/docs/cli/skills/)

### 2.4 O que NÃO fazer (armadilhas de descoberta, verificadas)

- Descrições vagas ("Helps with documents", "Processes data") — o modelo não consegue discriminar entre 100+ skills.
- Primeira pessoa / segunda pessoa na descrição — "inconsistent point-of-view can cause discovery problems".
- Esperar keywords rígidas: o match é semântico sobre a descrição.
- Descrição muito longa que será truncada no listing: sempre caso de uso primeiro.
- Ignorar que "Seems right" não é critério: "Seeing a skill trigger tells you Claude found it, not that it did what you intended" — medir invocação e qualidade separadamente (ver 4.12).
- `disable-model-invocation: true` onde o carregamento automático seria útil (e vice-versa: deploy automático sem controle).

---

## 3. Onde as skills vivem e a mecânica de instalação/consumo

### 3.1 Claude Code (Anthropic)

**Locais (tabela dos docs oficiais):**

| Local | Caminho | Escopo |
|---|---|---|
| Enterprise | managed settings | Todos da organização |
| Pessoal | `~/.claude/skills/<skill-name>/SKILL.md` | Todos os projetos |
| Projeto | `.claude/skills/<skill-name>/SKILL.md` | Só este projeto |
| Plugin | `<plugin>/skills/<skill-name>/SKILL.md` | Onde o plugin está habilitado |

- **Resolução de conflitos:** enterprise > pessoal > projeto; qualquer nível vence skill bundled de mesmo nome; plugin usa namespace `plugin-name:skill-name` (`/my-plugin:deploy`); skill vence `.claude/commands/deploy.md` de mesmo nome; tudo vence skill sincronizada do claude.ai.
- **Skills aninhadas:** `.claude/skills/` em subdiretórios carregam quando Claude lê/edita arquivos daquele diretório (monorepo); nomes qualificados (`apps/web:deploy`).
- **Descoberta de projeto:** `.claude/skills/` do diretório de partida e de todos os pais até a raiz do repo. `--add-dir`/`/add-dir` carregam skills de diretórios adicionais.
- **Live change detection:** editar/adicionar/remover skill em `~/.claude/skills/` ou `.claude/skills/` é detectado na sessão corrente, sem restart.
- **Sync do claude.ai:** `CLAUDE_CODE_SYNC_SKILLS=1 claude -p "..."` baixa skills habilitadas para `~/.claude/skills/synced/`; o nome `synced` é reservado.
- **Invocação com argumentos:** `$ARGUMENTS`, `$ARGUMENTS[N]`, `$0..$N`, `$name`, `${CLAUDE_SKILL_DIR}`, `${CLAUDE_PROJECT_DIR}`, `${CLAUDE_PLUGIN_ROOT}`, `${CLAUDE_PLUGIN_DATA}`, `${CLAUDE_SESSION_ID}`, `${CLAUDE_EFFORT}`. Injeção dinâmica de contexto: `` !`comando` `` e blocos ` ```! ` rodam antes do conteúdo ser enviado ao modelo (comando falhou → invocação abortada).
- **Comandos custom foram fundidos em skills:** `.claude/commands/deploy.md` e `.claude/skills/deploy/SKILL.md` criam o mesmo `/deploy`; skills adicionam arquivos de apoio, frontmatter de controle e carregamento automático.
- **Ciclo de vida do conteúdo:** o corpo renderizado entra na conversa como uma mensagem e **fica para o resto da sessão** (não é relido); após compactação, skills invocadas são re-anexadas (primeiros 5.000 tokens de cada; orçamento compartilhado de 25.000 tokens, mais recentes primeiro).

Fontes: [code.claude.com/docs/en/skills](https://code.claude.com/docs/en/skills) (seções "Where skills live", "How a skill gets its command name", "Available string substitutions", "Skill content lifecycle")

### 3.2 opencode (SST)

**Locais (um diretório por skill contendo `SKILL.md`):**

- Projeto: `.opencode/skills/<name>/SKILL.md` · `.claude/skills/<name>/SKILL.md` · `.agents/skills/<name>/SKILL.md`
- Global: `~/.config/opencode/skills/<name>/SKILL.md` · `~/.claude/skills/<name>/SKILL.md` · `~/.agents/skills/<name>/SKILL.md`

"OpenCode walks up from your current working directory until it reaches the git worktree", coletando `skills/*/SKILL.md` no caminho (as definições globais são "also loaded"). **Precedência entre os caminhos não é documentada** `[NÃO CONFIRMADO]` — nem projeto vs global, nem ordem entre `.opencode/skills`, `.claude/skills` e `.agents/skills`; a única orientação oficial é o troubleshooting: "Ensure skill names are unique across all locations" (ver abaixo).

- **Frontmatter:** só `name` (obrig.), `description` (obrig.), `license`, `compatibility`, `metadata`; "Unknown frontmatter fields are ignored". `name`: 1–64 chars, regex `^[a-z0-9]+(-[a-z0-9]+)*$`, deve bater com o nome do diretório. `description`: 1–1024 chars.
- **Permissões:** `opencode.json` → `"skill": { "*": "allow", "pr-review": "allow", "internal-*": "deny", "experimental-*": "ask" }` — allow carrega na hora; deny esconde do agente; ask pede aprovação. Desabilitável com `"tools": { "skill": false }`. Overrides por agente.
- **Troubleshooting (doc oficial):** `SKILL.md` em MAIÚSCULAS exatas; frontmatter com `name` e `description`; nomes únicos entre todos os locais; permissões não podem ser `deny` (skills negadas ficam ocultas).
- **Caminhos configuráveis:** `{"skills": {"paths": [...]}}` em opencode.json (merge PR #9640, jan/2026) — alternativa a symlinks para times compartilhados.

Fontes: [opencode.ai/docs/skills](https://opencode.ai/docs/skills/); [github.com/anomalyco/opencode PR #9640 — "feat: support config skill registration" (merged 2026-01-29)](https://github.com/anomalyco/opencode/pull/9640)

### 3.3 Codex (OpenAI): AGENTS.md + skills

**AGENTS.md (instruções/regras de projeto)** — hierarquia e precedência (docs oficiais, learn.chatgpt.com):

1. **Global:** `~/.codex/AGENTS.md` (ou `$CODEX_HOME`); `~/.codex/AGENTS.override.md` tem precedência (override temporário sem deletar o arquivo base).
2. **Projeto:** `AGENTS.md` na raiz do repo.
3. **Diretório:** `AGENTS.md` no cwd e diretórios aninhados até a raiz do git; cada diretório checa `AGENTS.override.md` primeiro, depois `AGENTS.md`, depois fallbacks configuráveis (`project_doc_fallback_filenames`).
4. **Merge:** concatenados da raiz para o cwd, separados por linhas em branco; arquivos mais próximos do cwd vêm por último e **sobrescrevem** orientação mais global.
5. **Limite de tamanho:** `project_doc_max_bytes` = **32 KiB por padrão**; Codex pula arquivos vazios e para de acumular ao atingir o teto.
6. Boas práticas que a página de fato documenta: `## Code Review Rules` no AGENTS.md mais próximo do código ("add a `## Code Review Rules` section to the `AGENTS.md` closest to the code the rules govern"); "Put repository-wide checks at the root and service-specific checks in a nested file"; "Keep rules concise, explain the behavior to flag and any safe path or exception, and reserve formatting and lint checks for CI". Validação (comandos da página): `codex --ask-for-approval never "Summarize the current instructions."` (Codex ecoa as instruções globais e do projeto em ordem de precedência), `codex --cd <subdir> --ask-for-approval never "Show which instruction files are active."`, `codex status` e auditoria por log (`codex -c log_dir=./.codex-log` → `codex-tui.log`/`session-*.jsonl`). Itens como conciso, estrutura clara com headers, específico, exemplos concretos, camadas global→repo→time e commitar no versionamento NÃO constam nessa página `[NÃO CONFIRMADO]` como boas práticas oficiais de AGENTS.md; `codex execpolicy check` existe como comando, mas não é citado nessa página.

Nota: a página de AGENTS.md do Codex não documenta frontmatter YAML (sem `description`/`allowed-tools` no AGENTS.md).

Fontes: [learn.chatgpt.com — AGENTS.md (Custom instructions)](https://learn.chatgpt.com/docs/agent-configuration/agents-md)

**Skills no Codex (adota a spec aberta)** — locais verificados em [learn.chatgpt.com — Build skills](https://learn.chatgpt.com/docs/build-skills):

| Escopo | Caminho |
|---|---|
| REPO | `$CWD/.agents/skills` · `$CWD/../.agents/skills` · `$REPO_ROOT/.agents/skills` |
| USER | `$HOME/.agents/skills` |
| ADMIN | `/etc/codex/skills` |
| SYSTEM | Bundled (ex.: skill-creator) |

- Codex varre `.agents/skills` de cada diretório do cwd até a raiz do repo; **"Symlinked skill folders are followed"** (verificado).
- Frontmatter: `name` + `description` obrigatórios; opcional `agents/openai.yaml` (interface/policy/dependencies).
- Listing limitado a 2% do contexto ou 8.000 chars; invocação implícita (match de description) ou explícita (`@`, `$`, `/skills`).
- Instalação: `$skill-installer <nome>`; desabilitar sem deletar em `~/.codex/config.toml`:

```toml
[[skills.config]]
path = "/path/to/skill/SKILL.md"
enabled = false
```

### 3.4 Cursor: rules `.mdc` + skills

**Regras (`.cursor/rules/*.mdc`)** — o formato legado que continua vivo [NÃO CONFIRMADO via fetch direto; verificado via resumo de busca sobre docs do Cursor + exemplo de rule oficial no GitHub justdoinc]:

- Arquivos Markdown com extensão `.mdc` (obrigatória — `.md` puro não é tratado como rule) em `.cursor/rules/`; regras de usuário em `~/.cursor/rules/`; `alwaysApply` nao se aplica a user rules (não são migráveis para skills porque não ficam no filesystem).
- Frontmatter com 3 campos: `description` (formato recomendado `<topic>: <details>`; crítica para o modo "apply intelligently" — o modelo casa semanticamente a descrição com o pedido do usuário), `globs` (padrões gitignore-style, comma-separated) e `alwaysApply` (boolean).
- Quatro modos de aplicação: **Always Apply** (`alwaysApply: true`), **Apply Intelligently** (`false` sem globs — decisão do modelo pela description), **Apply to Specific Files** (`false` + globs), **Apply Manually** (referência explícita `@rule-name`).
- Práticas comuns: concisas (uma regra = um tópico; ~50–300 linhas/≈500 tokens conforme fontes), globs específicos, `alwaysApply` com moderação, numerar prefixos para ordenação, commitar no git.
- Criação: `/create-rule` no chat; Cursor UI → Rules → Add Rule.

**Skills (adota a spec aberta)** — [cursor.com/docs/context/skills](https://cursor.com/docs/context/skills):

- Raízes: `.agents/skills/` e `.cursor/skills/` (projeto); `~/.agents/skills/` e `~/.cursor/skills/` (usuário). Compatibilidade: também carrega `.claude/skills/`, `.codex/skills/`, `~/.claude/skills/`, `~/.codex/skills/`.
- Caminha recursivamente pelas raízes ("walks the skills root recursively and picks up any `SKILL.md` it finds"); suporta aninhamento e monorepo (skills em subdiretórios ficam escopadas ao diretório).
- Frontmatter: `name`, `description`, `paths` (globs; `globs` aceito como fallback), `disable-model-invocation`, `metadata`.
- Comandos: `/create-skill`, `/migrate-to-skills` (converte rules dinâmicas e slash commands elegíveis em skills; `alwaysApply: true` e rules com globs NÃO migram, pois o gatilho é diferente).
- Diretriz do addyosmani/agent-skills para Cursor: "Put workflow skills under `.cursor/skills/` and short policies in `.cursor/rules/*.mdc` — do not paste full skills into rules."

### 3.5 Gemini CLI (Google)

- **Locais e precedência** (do menor para o maior): Built-in → Extension → User (`~/.gemini/skills/` **ou** alias `~/.agents/skills/`) → Workspace (`.gemini/skills/` **ou** alias `.agents/skills/`). Dentro do mesmo tier, o alias `.agents/skills/` vence `.gemini/skills/`. Nome duplicado → o de maior precedência vence.
- `SKILL.md` é descoberto na raiz do diretório de skills OU um nível abaixo (`.gemini/skills/<skill-name>/SKILL.md`); mais de um nível de profundidade não é descoberto.
- Frontmatter: `name` (deve bater com o diretório; caracteres `: \ / < > * ? " |` no nome viram `-`) + `description` ("CRITICAL" — gatilho de uso). Se faltar campo ou o `---` não abrir o arquivo → skill **silenciosamente ignorada**.
- Comandos: `/skills list|link|disable|enable|reload` (na sessão); `gemini skills install <path|git-url|.skill>` (`--scope user|workspace`, `--path` para monorepos), `gemini skills link <path>`, `gemini skills uninstall <nome>` (no terminal).
- Estrutura recomendada: `SKILL.md` + `scripts/` + `references/` + `assets/`. "When a skill is activated, the model is granted access to this entire directory."

Fontes: [geminicli.com/docs/cli/skills](https://geminicli.com/docs/cli/skills/); [geminicli.com/docs/cli/creating-skills](https://geminicli.com/docs/cli/creating-skills/)

### 3.6 O padrão aberto `.agents/skills` (agentskills.io)

A Anthropic publicou o formato como **padrão aberto em 18/12/2025**, adotado por dezenas de ferramentas (lista do próprio site: Claude Code, Claude, ChatGPT & Codex, Gemini CLI, Cursor, opencode, GitHub Copilot, VS Code, OpenHands, Goose, Roo Code, pi, TRAE, Junie, Letta, Spring AI, etc. — ver o carrossel em agentskills.io). As convenções de diretório `.agents/skills/` (projeto) e `~/.agents/skills/` (global) são o ponto de interseção: **uma mesma pasta de skills funciona em opencode, Codex, Gemini CLI e Cursor** (o Claude Code NÃO lê `.agents/skills/` — lê apenas `.claude/skills/` e `~/.claude/skills/`, ver 3.1 e tabela 3.9). Recomendação prática documentada na comunidade (ver 3.8): manter o repo versionado e linkar nesses pontos.

Fontes: [agentskills.io](https://agentskills.io/); [anthropic.com/engineering — Equipping agents for the real world with Agent Skills](https://www.anthropic.com/engineering/equipping-agents-for-the-real-world-with-agent-skills)

### 3.7 Marketplaces e plugins (formato de entrada)

O repo `anthropics/skills` é registrado como marketplace de plugin do Claude Code. Formato real do manifest `.claude-plugin/marketplace.json` (verificado no raw):

```json
{
  "name": "anthropic-agent-skills",
  "owner": { "name": "Keith Lazuka", "email": "klazuka@anthropic.com" },
  "metadata": { "description": "Anthropic example skills", "version": "1.0.0" },
  "plugins": [
    {
      "name": "document-skills",
      "description": "Collection of document processing suite including Excel, Word, PowerPoint, and PDF capabilities",
      "source": "./",
      "strict": false,
      "skills": ["./skills/xlsx", "./skills/docx", "./skills/pptx", "./skills/pdf"]
    }
  ]
}
```

Instalação (README do repo):

```text
/plugin marketplace add anthropics/skills
/plugin install document-skills@anthropic-agent-skills
/plugin install example-skills@anthropic-agent-skills
```

Extras: uma pasta de skill com `.claude-plugin/plugin.json` vira um plugin `<name>@skills-dir` (pode empacotar agents, hooks e MCP); plugin skills usam namespace `plugin-name:skill-name`; "Share files within a marketplace with symlinks" é uma seção dos docs de plugins do Claude Code.

Fontes: [github.com/anthropics/skills](https://github.com/anthropics/skills) (README + `.claude-plugin/marketplace.json`); [code.claude.com/docs/en/skills](https://code.claude.com/docs/en/skills)

### 3.8 Symlink de repositórios versionados para diretórios globais de skills

**A mecânica, verificada em fontes primárias:**

- **Claude Code (docs oficiais):** "A `<skill-name>` entry in the enterprise, personal, or project locations **can be a symlink to a directory elsewhere on disk. Claude Code follows the symlink and reads `SKILL.md` from the target directory**, and if the same target is reachable from more than one location, Claude Code loads the skill once." → O symlink deve apontar para **um diretório cuja raiz contenha `SKILL.md`** (ex.: `ln -s ~/repos/minha-skill ~/.claude/skills/minha-skill`, onde `~/repos/minha-skill/SKILL.md` existe). Deduplicação: mesmo target alcançável por múltiplos locais carrega uma única vez.
- **Codex (docs oficiais):** "Symlinked skill folders are followed."
- **Gemini CLI (docs oficiais):** comando nativo de link: `gemini skills link <path>` (e `gemini skills install <git-url>`).
- **opencode:** não documenta symlink explicitamente, mas (a) lê as três árvores globais (`~/.config/opencode/skills`, `~/.claude/skills`, `~/.agents/skills`), então um symlink em qualquer uma delas é consumido; e (b) desde jan/2026 suporta `"skills": {"paths": [...]}` em opencode.json como alternativa nativa a symlinks.
- **hf skills add (huggingface_hub PR #3755):** instala uma skill em local central (`.agents/skills/<nome>/` global) e cria **symlinks relativos** a partir dos diretórios específicos (`.claude/skills/`, `.codex/skills/`, `.opencode/skills/`) apontando para o central — o padrão "um repo, N ferramentas" automatizado. Comandos: `hf skills add --claude --codex --opencode`; `hf skills add --claude --global`.
- **skill-sync.sh (zzu-ken/ai-skills):** mantém `~/.agents/skills/` como fonte única e faz symlink de `~/.config/opencode/skills/`, `~/.claude/skills/` etc. para os mesmos arquivos; detecta ferramentas instaladas, pula arquivos que não são symlinks e limpa links quebrados.

**Prática recomendada (síntese):** manter a skill versionada num repo git (ex.: `repo/skills/<skill-name>/SKILL.md`), e linkar o diretório da skill — que contém `SKILL.md` na raiz — em cada ponto de consumo: `~/.claude/skills/<skill-name>` (o único diretório global que o Claude Code lê) e, para portabilidade multiplataforma, `~/.agents/skills/<skill-name>` — lido por opencode, Codex, Gemini CLI e Cursor, **não** pelo Claude Code (ver tabela 3.9). Atualizações = `git pull` no repo; os agentes enxergam a nova versão na próxima sessão (no Claude Code, live change detection pega até na sessão corrente, para edições de `SKILL.md`).

Ressalva honesta: os docs do Claude Code/Gemini não documentam o padrão "repo completo + symlinks em massa" (essa parte vem da comunidade: zzu-ken/ai-skills, hf skills add); o que é oficialmente verificado é (1) que symlinks de skill são seguidos, (2) que os caminhos globais canônicos são os listados, e (3) os comandos de link do Gemini.

### 3.9 Tabela-resumo: onde cada plataforma procura

| Plataforma | Projeto | Global (usuário) | Extra |
|---|---|---|---|
| Claude Code | `.claude/skills/` (e pais até a raiz do repo; aninhados por subdiretório) | `~/.claude/skills/` | plugins, enterprise (managed), `--add-dir`, `~/.claude/skills/synced/` |
| opencode | `.opencode/skills/` · `.claude/skills/` · `.agents/skills/` | `~/.config/opencode/skills/` · `~/.claude/skills/` · `~/.agents/skills/` | `skills.paths` em opencode.json |
| Codex (skills) | `.agents/skills/` (cwd → raiz) | `~/.agents/skills/` | `/etc/codex/skills` (admin), bundled |
| Codex (AGENTS.md) | `AGENTS.md` raiz + por diretório | `~/.codex/AGENTS.md` (+ `.override`) | `project_doc_max_bytes` 32 KiB |
| Cursor | `.cursor/skills/` · `.agents/skills/` (+ compat `.claude/skills/`, `.codex/skills/`) | `~/.cursor/skills/` · `~/.agents/skills/` (+ compat) | rules em `.cursor/rules/*.mdc`; user rules em `~/.cursor/rules/` |
| Gemini CLI | `.gemini/skills/` · `.agents/skills/` | `~/.gemini/skills/` · `~/.agents/skills/` | `gemini skills link/install`; 1 nível de profundidade |

---

## 4. Melhores práticas de conteúdo

### 4.1 Concisão é a regra nº 1

Verbatim: "**Concise is key.** The context window is a public good. Your Skill shares the context window with everything else Claude needs to know." Default assumption: "Claude is already very smart" — só adicionar o que Claude não sabe; desafiar cada parágrafo: "Does Claude really need this explanation? Can I assume Claude knows this? Does this paragraph justify its token cost?" O guia da agentskills.io: "Add what the agent lacks, omit what it knows" e "Would the agent get this wrong without this instruction? If the answer is no, cut it."

Exemplo bom (≈50 tokens) vs ruim (≈150 tokens) documentado pela Anthropic — o bom assume que Claude sabe o que é PDF e entrega só o que ele não saberia (biblioteca + código).

Fontes: [platform.claude.com — Skill authoring best practices](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices); [agentskills.io — Best practices for skill creators](https://agentskills.io/skill-creation/best-practices)

### 4.2 Graus de liberdade (calibrar prescrição à fragilidade)

- **Alta liberdade** (texto): múltiplas abordagens válidas → dar direção, não script. Ex.: processo de code review em passos.
- **Média liberdade** (pseudocódigo/template com parâmetros): padrão preferido com variação aceitável.
- **Baixa liberdade** (scripts exatos, poucos parâmetros): operações frágeis → "Run exactly this script: `python scripts/migrate.py --verify --backup`. Do not modify the command or add additional flags."
- Analogia oficial: ponte estreita com precipícios (guardrails exatos) vs campo aberto (direção geral).

Fonte: [platform.claude.com — Skill authoring best practices](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices); reforço em [agentskills.io — Best practices](https://agentskills.io/skill-creation/best-practices) ("Match specificity to fragility").

### 4.3 Nomeação

- Gerúndio preferido (verb + -ing): `processing-pdfs`, `analyzing-spreadsheets`, `managing-databases`, `testing-code`, `writing-documentation`.
- Aceitáveis: substantivo (`pdf-processing`), orientado a ação (`process-pdfs`).
- Evitar: vagos (`helper`, `utils`, `tools`), genéricos (`documents`, `data`, `files`), palavras reservadas (`anthropic-helper`, `claude-tools`), padrões inconsistentes.
- Técnica: kebab-case, minúsculas, hífens únicos (regex `^[a-z0-9]+(-[a-z0-9]+)*$` no opencode; 1–64 chars; deve bater com o nome do diretório).

Fonte: [platform.claude.com — Skill authoring best practices](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices); [agentskills.io/specification](https://agentskills.io/specification)

### 4.4 O que colocar no SKILL.md vs references/

**No SKILL.md (núcleo, carregado sempre que a skill roda):** visão geral + navegação, instruções essenciais de cada execução, gotchas que o agente precisa ver ANTES de encontrar a situação, o caso de uso e os gatilhos.

**Em references/ (carregado sob demanda):** documentação detalhada de API, schemas, exemplos extensos, material de domínio mutuamente exclusivo. Padrões oficiais:

1. **High-level guide with references** — SKILL.md aponta `FORMS.md`/`REFERENCE.md`/`EXAMPLES.md` com links; Claude lê só o que precisa.
2. **Domain-specific organization** — `reference/finance.md`, `reference/sales.md`, `reference/product.md`; "When a user asks about sales metrics, Claude only needs to read sales-related schemas, not finance or marketing data."
3. **Conditional details** — conteúdo básico inline, avançado linkado ("**For tracked changes**: See [REDLINING.md](REDLINING.md)").

**Regra de ouro:** "Keep references one level deep from SKILL.md" — cada referência deve ser linkada diretamente do SKILL.md, nunca de outro reference (referências aninhadas causam leituras parciais com `head -100`).

**Fonte da agentskills.io sobre o gatilho de leitura:** dizer QUANDO ler cada arquivo — "Read `references/api-errors.md` if the API returns a non-200 status code" é mais útil que "see references/ for details".

Fontes: [platform.claude.com — Skill authoring best practices](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices); [agentskills.io — Best practices](https://agentskills.io/skill-creation/best-practices)

### 4.5 Padrões de estrutura de workflows

- **Workflows para tarefas complexas:** passos sequenciais claros; para fluxos longos, fornecer **checklist copiável** que Claude marca no decorrer ("Copy this checklist and track your progress" — ex. com `- [ ] Step 1: ...`).
- **Feedback loops:** "Run validator → fix errors → repeat"; "**Only proceed when validation passes**".
- **Plan-validate-execute:** para operações em lote/destrutivas, plano intermediário estruturado (ex.: `field_values.json`) validado por script contra a fonte de verdade antes de executar; mensagens de erro do validador devem ser específicas o bastante para o agente se autocorrigir ("Field 'signature_date' not found. Available fields: ...").
- **Conditional workflow:** decisões em árvore ("Creating new content? → Creation workflow; Editing? → Editing workflow"); se ficar grande, mover sub-workflows para arquivos separados e dizer ao Claude qual ler.
- **Templates de saída:** formato estrito → "ALWAYS use this exact template structure" com bloco markdown; formato flexível → "sensible default, use your best judgment".

Fontes: [platform.claude.com — Skill authoring best practices](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices); [agentskills.io — Best practices](https://agentskills.io/skill-creation/best-practices)

### 4.6 Exemplos (input/output)

"Examples convey the desired style and level of detail to Claude more clearly than descriptions alone." Fornecer pares input/output reais (ex.: 3 exemplos de commit message com `Input:`/`Output:` e a regra geral por último: "Follow this style: type(scope): brief description..."). Diretriz do blog de engenharia: exemplos "concrete, not abstract" (checklist oficial).

Fonte: [platform.claude.com — Skill authoring best practices](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices)

### 4.7 Gotchas (o conteúdo de maior valor)

"**The highest-value content in many skills is a list of gotchas** — environment-specific facts that defy reasonable assumptions." Não é conselho geral; são correções concretas de erros que o agente cometeria (ex.: "The `users` table uses soft deletes. Queries must include `WHERE deleted_at IS NULL`..."). Manter gotchas no SKILL.md, não em reference (o agente pode não reconhecer o gatilho de leitura). Ao corrigir um erro do agente, adicionar a correção aos gotchas — "one of the most direct ways to improve a skill iteratively".

Fonte: [agentskills.io — Best practices](https://agentskills.io/skill-creation/best-practices)

### 4.8 Scripts: quando criar e como os agentes os usam

- **Benefícios de scripts utilitários pré-escritos** (verbatim, resumido): "More reliable than generated code; Save tokens (no need to include code in context); Save time; Ensure consistency across uses." Sinal para criar um script: o agente reinventa a mesma lógica a cada execução (gráficos, parsing de formato, validação) — "that's a signal to write a tested script once and bundle it in `scripts/`".
- **"Solve, don't defer":** scripts devem tratar erros explicitamente (try/except com fallback) em vez de "Just fail and let Claude figure it out".
- **Sem "voodoo constants"** (Ousterhout's law): valores de configuração justificados e auto-documentados (`REQUEST_TIMEOUT = 30  # HTTP requests typically complete within 30 seconds`).
- **Mecânica de uso pelos agentes:** o script é **executado** via bash e apenas a saída entra no contexto; o código do script nunca entra no contexto (nível 3 da progressive disclosure). Distinguir no SKILL.md: "Run `analyze_form.py` to extract fields" (executar) vs "See `analyze_form.py` for the field extraction algorithm" (ler como referência) — "For most utility scripts, execution is preferred".
- **Dependências:** listar pacotes no SKILL.md; não assumir instalados ("Don't assume packages are installed" — instalar explicitamente quando aplicável). No Claude Code há rede; na API não há rede nem instalação em runtime.
- **Saídas intermediárias verificáveis:** padrão "plan-validate-execute" (4.5) para operações de alto risco.
- **Paths:** sempre forward slashes (`scripts/helper.py`, nunca `scripts\helper.py`), mesmo em Windows.

Fontes: [platform.claude.com — Skill authoring best practices](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices); [agentskills.io — Best practices / Using scripts in skills](https://agentskills.io/skill-creation/best-practices)

### 4.9 "Run skills in a subagent" — o que é verificado sobre a "Skill Principle #1"

**Veredito da pesquisa:** `[NÃO CONFIRMADO]` como "Skill Principle #1" numerada — nenhuma fonte primária oficial (docs da plataforma, docs do Claude Code, spec aberta, blog de engenharia, README do anthropics/skills, issue oficial do claude-cookbooks) contém um princípio numerado com esse título. O blog de engenharia lista 4 guidelines SEM numeração ("Start with evaluation", "Structure for scale", "Think from Claude's perspective", "Iterate with Claude"). Duas buscas independentes pela frase exata retornaram apenas fontes comunitárias.

**O que É oficial e verificado (o conteúdo real por trás do princípio):**

1. **Claude Code — seção oficial "Run skills in a subagent":** frontmatter `context: fork` faz a skill rodar em contexto isolado: "The skill content becomes the prompt that drives the subagent. It won't have access to your conversation history." O campo `agent` escolhe o tipo (`Explore` — somente leitura, contexto mínimo; `Plan`; `general-purpose` — default; custom em `.claude/agents/`). O subagent devolve apenas um resumo ao thread principal ("its result arrives in your conversation when it completes").
2. **Casos de uso oficiais:** pesquisas profundas / leitura massiva de arquivos que poluiriam o contexto principal (ex.: skill `deep-research` com `context: fork` + `agent: Explore`); **Aviso oficial:** "`context: fork` only makes sense for skills with explicit instructions" — uma skill de convenções sem tarefa retorna vazio.
3. **Delegação a partir da skill forked:** o subagent de uma skill `context: fork` é um agente regular ("the skill's subagent is a regular agent type") e **pode** spawnar sub-subagents: "By default, a subagent can spawn subagents of its own, up to three layers below the main conversation", configurável com `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH` (`1` desliga o aninhamento; na profundidade máxima, a ferramenta `Agent` é retirada do subagent).
4. **Fronteira skill vs subagent (blog "Steering Claude Code"):** "Use a skill when you want the procedure to play out inside the main thread so you can see and steer each step"; use subagent quando for "side tasks that should run in isolation and return only a summary" (deep search, log analysis, dependency audit). Subagents podem ter skills pré-carregadas via campo `skills` no frontmatter do agente.
5. **Na spec aberta não existe o conceito** — é extensão do Claude Code (o doc diz explicitamente: "Claude Code extends the standard with additional features like invocation control, subagent execution, and dynamic context injection").

Fontes: [code.claude.com/docs/en/skills — "Run skills in a subagent"](https://code.claude.com/docs/en/skills); [code.claude.com/docs/en/sub-agents — "Let subagents spawn their own subagents"](https://code.claude.com/docs/en/sub-agents); [claude.com/blog — Steering Claude Code](https://claude.com/blog/steering-claude-code-skills-hooks-rules-subagents-and-more); [anthropic.com/engineering — Equipping agents for the real world](https://www.anthropic.com/engineering/equipping-agents-for-the-real-world-with-agent-skills)

### 4.10 Skill vs CLAUDE.md vs hook vs subagent (quando usar cada um)

Tabela oficial (claude.com/blog, "Steering Claude Code"):

| Mecanismo | Quando usar (verbatim resumido) | Custo de contexto |
|---|---|---|
| CLAUDE.md raiz | "Build commands, directory layout, monorepo structure, coding conventions, and team norms" | Alto — cada linha custa tokens sempre |
| Rules | "Specific constraints or conventions (e.g., all API handlers must validate input with Zod)" | Médio — sempre carregado a menos que path-scoped |
| **Skills** | "**Procedural workflows (deploy or release checklists)**" | Baixo — só name+description no start; corpo na invocação |
| Subagents | "Running work in parallel or side tasks that should run in isolation and return only a summary" | Zero no contexto principal até chamado |
| Hooks | "Deterministic automation" (linters, Slack ao completar, bloqueio de comandos) | Baixo — config fora do contexto |

Sinais de refatoração (verbatim): um procedimento de ~30 linhas no CLAUDE.md → "**Procedures belong in skills.** CLAUDE.md is for facts Claude should hold at all times"; "Every time X, always do Y" → hook; "Never do this" → guardrail determinístico (hooks/permissões), não instrução. Higiene do CLAUDE.md: < 200 linhas, com dono, revisado como código.

### 4.11 Granularidade: uma skill = um objetivo coerente

agentskills.io: "**Design coherent units.** Deciding what a skill should cover is like deciding what a function should do: you want it to encapsulate a coherent unit of work that composes well with other skills. Skills scoped too narrowly force multiple skills to load for a single task, risking overhead and conflicting instructions. Skills scoped too broadly become hard to activate precisely." Exemplo oficial: "A skill for querying a database and formatting the results may be one coherent unit, while a skill that also covers database administration is probably trying to do too much." (Codex docs ecoam: "one job per skill".)

### 4.12 Testes, avaliação e iteração

- **"Build evaluations first":** rodar tarefas representativas SEM skill, documentar falhas, criar ≥ 3 cenários de eval, medir baseline, escrever instruções mínimas, iterar. "There is not currently a built-in way to run these evaluations. Users can create their own evaluation system."
- **Testar com todos os modelos planejados** (Haiku precisa de mais orientação; Opus sofre com over-explaining).
- **Iterar com Claude (padrão A/B oficial):** Claude A (autor) cria a skill; Claude B (instância limpa) usa em tarefas reais; observar → refinar → repetir. "Claude models understand the Skill format and structure natively. You don't need special system prompts or a 'writing skills' skill."
- **Observar como Claude navega:** ordem de leitura inesperada, links ignorados, re-leitura repetida do mesmo arquivo (→ mover para o SKILL.md), arquivos nunca acessados (→ remover ou sinalizar melhor).
- **skill-creator (plugin oficial do Claude Code):** automatiza o loop — `evals/evals.json`, subagent por caso de teste, `grading.json`, `benchmark.json` (com vs sem skill), A/B cego entre versões, **description tuning** (gera prompts should-trigger/should-not-trigger, mede hit rate e propõe edição da descrição). Instalação: `/plugin install skill-creator@claude-plugins-official`. Formato de eval documentado em agentskills.io/skill-creation/evaluating-skills.

Fontes: [platform.claude.com — Skill authoring best practices](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices); [code.claude.com/docs/en/skills — "Evaluate and iterate on a skill"](https://code.claude.com/docs/en/skills); [agentskills.io — Evaluating skill output quality](https://agentskills.io/skill-creation/evaluating-skills)

### 4.13 Armadilhas comuns (antipadrões verificados)

- **Windows-style paths** (`scripts\helper.py`) — sempre forward slashes.
- **Muitas opções sem default** ("You can use pypdf, or pdfplumber, or PyMuPDF, or pdf2image, or...") — dar um default com escape hatch.
- **Informação sensível a tempo** ("If you're doing this before August 2025, use the old API") — usar seção "Current method" + "Old patterns" em `<details>`.
- **Terminologia inconsistente** (API endpoint/URL/API route/path misturados) — "Consistency helps Claude parse and follow instructions."
- **Instruções muito longas que ninguém lê** — "Overly comprehensive skills can hurt more than they help — the agent struggles to extract what's relevant."
- **"MUST"-language excessivo** — o skill-creator oficial recomenda explicar o *porquê* em vez de prescrever com força bruta (lição do próprio SKILL.md de produção do skill-creator).
- **MCP tools sem nome qualificado** — usar `ServerName:tool_name` ("Without the server prefix, Claude may fail to locate the tool").
- **Assumir ferramentas instaladas** — instruir a instalação quando necessário.
- **Referências aninhadas** (SKILL.md → advanced.md → details.md) — leitura parcial por `head -100`.
- **Ignorar segurança** — "Use Skills only from trusted sources"; skills maliciosas podem exfiltrar dados ou executar código; auditar SKILL.md, scripts e dependências externas.

### 4.14 Formatação para modelos

- Markdown simples e direto; seções claras com headings (`##`/`###`); passos numerados; **tabelas quando útil** (comparações, mapeamentos); **code blocks** com linguagem (ex.: ` ```python `) para código e templates; checklists `- [ ]` copiáveis.
- Imperativo ("State what to do rather than narrating how or why" — docs Claude Code).
- Arquivos de reference > 100 linhas: TOC no topo.
- Nomes de arquivos descritivos (`form_validation_rules.md`, não `doc2.md`); organizar por domínio (`reference/finance.md`), não por documento (`docs/file1.md`).

---

## 5. Exemplos reais e referências

### 5.1 anthropics/skills (GitHub, Anthropic)

Repo oficial com skills de produção da Anthropic + a spec + template. Estrutura: `.claude-plugin/` (marketplace metadata), `skills/` (Creative & Design; Development & Technical; Enterprise & Communication; **Document Skills**: `docx`, `pdf`, `pptx`, `xlsx` — "the document creation & editing skills that power Claude's document capabilities", source-available, não open source), `spec/` (a especificação), `template/`. Instalação via plugin marketplace (`/plugin marketplace add anthropics/skills`). A skill `claude-api` (bundled no Claude Code) é referência de skill de produção com progressive disclosure (reference files de APIs por linguagem). URL: https://github.com/anthropics/skills

### 5.2 skill-creator (plugin oficial)

Skill meta de produção (cria/avalia skills): frontmatter com `name` + `description` (~340 chars, com gatilhos explícitos), corpo com seções "Anatomy of a Skill", "Progressive Disclosure", "Principle of Lack of Surprise", "Writing Patterns"; usa `scripts/` (aggregate_benchmark, run_loop, package_skill), `agents/` (grader, comparator, analyzer), `references/schemas.md`, `assets/eval_review.html` — exemplo concreto de como uma skill de produção organiza progressive disclosure E scripts. URL: https://github.com/anthropics/claude-plugins-official/tree/main/plugins/skill-creator

### 5.3 addyosmani/agent-skills (Addy Osmani — ~87k stars)

"Production-grade engineering skills for AI coding agents" — 24 skills do ciclo Define→Plan→Build→Verify→Review→Ship (ex.: `test-driven-development`, `spec-driven-development`, `code-review-and-quality`, `security-and-hardening`), 8 slash commands, 4 agent personas, 7 checklists em `references/`. Estrutura de cada skill: frontmatter `name`+`description` + seções Overview/When to Use/Process/Rationalizations/Red Flags/Verification. Instalação multiplataforma: `npx skills add addyosmani/agent-skills`; `gemini skills install <git-url> --path skills`; `codex plugin marketplace add`; `claude --plugin-dir /path/to/agent-skills`; para Cursor: skills em `.cursor/skills/` e políticas curtas em `.cursor/rules/*.mdc`. Lições: "Process, not prose", anti-rationalization tables, "Verification is non-negotiable" ("Seems right" is never sufficient), progressive disclosure. URL: https://github.com/addyosmani/agent-skills

### 5.4 Outros exemplos/referências de produção

- **DeepLearning.AI — "Agent Skills with Anthropic"** (Andrew Ng × Anthropic, instrutor Elie Schoppik): curso oficial cobrindo SKILL.md, progressive disclosure, best practices, skills vs tools/MCP/subagents e multi-agente com Claude Agent SDK. URL: https://learn.deeplearning.ai/courses/agent-skills-with-anthropic
- **Claude cookbook — custom_skills/**: skills de exemplo da Anthropic (analyzing-financial-statements, applying-brand-guidelines, creating-financial-models) e proposta de revisão multi-agente com personas como skills (issue #665). URLs: https://github.com/anthropics/claude-cookbooks
- **hf skills add (huggingface_hub PR #3755)** e **zzu-ken/ai-skills (skill-sync.sh)**: padrão central+`~/.agents/skills`+symlinks, discutido em 3.8. URLs: https://github.com/huggingface/huggingface_hub/pull/3755 · https://github.com/zzu-ken/ai-skills
- **justdoinc/.cursor/rules/999-mdc-format.mdc**: exemplo real de rule `.mdc` oficialmente estilizada (globs comma-separated, sem brackets). URL: https://github.com/justdoinc/justdo/blob/master/.cursor/rules/999-mdc-format.mdc

### 5.5 Fontes primárias (todas verificadas por fetch direto, salvo onde indicado)

| Fonte | URL | Uso neste documento |
|---|---|---|
| Agent Skills overview (Anthropic) | https://platform.claude.com/docs/en/agents-and-tools/agent-skills/overview | Definição, 3 níveis, estrutura, frontmatter, locais, segurança |
| Skill authoring best practices (Anthropic) | https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices | Concisão, graus de liberdade, descrições, progressive disclosure, workflows, evals, checklist |
| Extend Claude with skills (Claude Code) | https://code.claude.com/docs/en/skills | Locais, frontmatter completo, symlinks, invocação, `context: fork`, troubleshooting |
| Agent Skills specification | https://agentskills.io/specification | Formato canônico, campos, restrições, progressive disclosure, validação |
| Agent Skills overview (open standard) | https://agentskills.io/ | Conceito, clientes adotantes, 3 estágios |
| Best practices for skill creators | https://agentskills.io/skill-creation/best-practices | Expertise real, gotchas, granularidade, defaults, plan-validate-execute |
| anthropics/skills (repo) | https://github.com/anthropics/skills | Template, marketplaces, categorias, spec |
| marketplace.json (raw) | https://raw.githubusercontent.com/anthropics/skills/main/.claude-plugin/marketplace.json | Formato exato de marketplace |
| Engineering blog — Agent Skills | https://www.anthropic.com/engineering/equipping-agents-for-the-real-world-with-agent-skills | 3 níveis, 4 guidelines, padrão aberto |
| Steering Claude Code blog | https://claude.com/blog/steering-claude-code-skills-hooks-rules-subagents-and-more | Skill vs CLAUDE.md vs hook vs subagent |
| opencode skills docs | https://opencode.ai/docs/skills/ | Caminhos, frontmatter, permissões, troubleshooting |
| Codex skills docs | https://learn.chatgpt.com/docs/build-skills | Caminhos `.agents/skills`, frontmatter, listing 2%/8k, openai.yaml |
| Codex AGENTS.md docs | https://learn.chatgpt.com/docs/agent-configuration/agents-md | Hierarquia, override, merge, 32 KiB |
| Cursor skills docs | https://cursor.com/docs/context/skills | Raízes, frontmatter, /create-skill, migração |
| Cursor rules (formato .mdc) | https://cursor.com/docs (JS; verificado via busca + exemplo justdoinc) | Frontmatter description/globs/alwaysApply, modos de aplicação |
| Gemini CLI skills docs | https://geminicli.com/docs/cli/skills/ | Tiers, alias `~/.agents/skills`, lifecycle, comandos |
| Gemini CLI creating-skills | https://geminicli.com/docs/cli/creating-skills/ | Frontmatter obrigatório, silent skip, estrutura |
| skill-creator plugin | https://github.com/anthropics/claude-plugins-official/tree/main/plugins/skill-creator | Exemplo de skill de produção + evals |
| addyosmani/agent-skills | https://github.com/addyosmani/agent-skills | Exemplo de produção multiplataforma |
| DeepLearning.AI course | https://learn.deeplearning.ai/courses/agent-skills-with-anthropic | Curso oficial de referência |

---

## 6. Itens não confirmados / ressalvas

1. **"Skill Principle #1: Run skills in a subagent"** — `[NÃO CONFIRMADO]` como princípio numerado em qualquer fonte oficial da Anthropic. O mecanismo real existe e está documentado (Claude Code `context: fork`, seção oficial "Run skills in a subagent", ver 4.9), mas não há numeração de princípios nos docs, na spec ou no blog de engenharia. A autoria da skill NÃO deve citar "Skill Principle #1" como se fosse um axioma oficial; deve citar o recurso `context: fork` + a guideline "Think from Claude's perspective" / decisão skill-vs-subagent do blog Steering Claude Code.
2. **Campo `display_title`** — `[NÃO CONFIRMADO]`: não aparece no texto primário dos docs atuais da Anthropic (surgiu só em sumário de busca).
3. **Formato `.mdc` do Cursor** — os campos `description`, `globs`, `alwaysApply` foram verificados por resumo de busca sobre os docs do Cursor (página é JS app, sem fetch direto) + exemplo real no GitHub (justdoinc). Não há schema oficial publicado do .mdc (confirmado por fonte comunitária/forum do Cursor).
4. **`search.sh` (Tier 1 surf-ai)** — 2 tentativas executadas conforme a metodologia; ambas falharam por erro de rede em todos os providers (surf/parallel, tavily, ddg; "AllProvidersExhausted" e network errors). A pesquisa foi conduzida com WebFetch direto nas fontes primárias + WebSearch, com citações verbatim — cobertura superior ao esperado do search.sh.
5. **Symlink em massa repo→diretórios globais** — a mecânica individual (symlink seguido) e os caminhos são oficiais (Claude Code, Codex, Gemini); o padrão "repo central + sync de N symlinks" é prática comunitária (hf skills add, skill-sync.sh) — tratado como tal na seção 3.8.
6. **Versões**: os docs do Claude Code citados (v2.1.x, 2026-08) mudam rápido; campos como `background`, `shell`, `skillOverrides` são de versões recentes — o autor deve testar contra a versão local.
7. **`allowed-tools` é experimental na spec** ("Support for this field may vary between agent implementations") — em opencode a política de ferramentas é feita por permissões, não pelo campo.

---

## 7. CHECKLIST final de qualidade (para o autor da SKILL.md)

### Estrutura de diretórios
- [ ] Pasta única com nome = `name` do frontmatter (kebab-case).
- [ ] `SKILL.md` na raiz da pasta (é o entrypoint obrigatório; o symlink — se usado — aponta para uma pasta que contém `SKILL.md` na raiz).
- [ ] `scripts/` apenas com código testado, self-contained, com mensagens de erro úteis.
- [ ] `references/` (e/ou `assets/`) para material detalhado; nada de referências aninhadas (1 nível de profundidade a partir do SKILL.md).
- [ ] Forward slashes em todos os caminhos; nomes de arquivo descritivos (`form_validation_rules.md`, não `doc2.md`).

### Frontmatter (portabilidade)
- [ ] Apenas os 6 campos da spec: `name`, `description`, `license`, `compatibility`, `metadata`, `allowed-tools` — assim funciona em Claude Code, opencode, Gemini CLI, Codex, Cursor e na Skills API sem erro de empacotamento.
- [ ] `name` ≤ 64 chars, `^[a-z0-9]+(-[a-z0-9]+)*$` (minúsculas/números/hífens), sem hífen nas pontas, sem `--`, sem XML, sem "anthropic"/"claude", igual ao nome do diretório.
- [ ] `description` 1–1024 chars, sem XML tags.
- [ ] `metadata` (se usar): map string→string, sem colidir com nomes de campos.
- [ ] `compatibility` (se usar) ≤ 500 chars, só quando há requisitos de ambiente reais.
- [ ] `allowed-tools` (se usar): string space-separated; lembrar que é experimental na spec e que grants do Claude Code limpam na próxima mensagem.

### Descrição-gatilho (descoberta)
- [ ] Terceira pessoa ("Processes/Extracts/Analyzes..."), nunca "I/You".
- [ ] Padrão "o que faz + quando usar": terminar com "Use when the user..." e incluir palavras que o usuário diria naturalmente (sinônimos, formatos de arquivo, verbos de ação).
- [ ] Caso de uso-chave e gatilhos nos primeiros ~200 chars (truncamento no listing: teto 1.536 chars por skill; orçamento 1% do contexto no Claude Code; 2%/8.000 chars no Codex).
- [ ] Nada de "Helps with..."/"Does stuff with..."/"Processes data".
- [ ] Sem `disable-model-invocation: true` se o carregamento automático for desejado; usar nos fluxos com efeito colateral que devem ser manuais.

### Progressive disclosure
- [ ] SKILL.md < 500 linhas (ideal < 5.000 tokens ≈ 250–350 linhas).
- [ ] Núcleo: instruções essenciais de toda execução + gotchas + navegação; detalhe em references/.
- [ ] Cada reference linkado diretamente do SKILL.md com instrução de QUANDO ler ("Read X if Y"), não "see references/ for details".
- [ ] References > 100 linhas com TOC no topo.
- [ ] Conteúdo mutuamente exclusivo em arquivos separados (por domínio), nunca em cascata.
- [ ] Nada de informação sensível a tempo no corpo; seções "Current method" + "Old patterns" se necessário.

### Conteúdo e exemplos
- [ ] Conciso: só o que o agente erraria sem a instrução ("Would the agent get this wrong without this instruction?").
- [ ] Graus de liberdade calibrados: prescrição exata para operações frágeis; direção para tarefas abertas; default único com escape hatch em vez de menu de opções.
- [ ] Workflows com passos numerados; checklists copiáveis (`- [ ]`) para fluxos longos.
- [ ] Feedback loop "validar → corrigir → repetir" com gate ("Only proceed when validation passes"); plan-validate-execute para operações em lote/destrutivas.
- [ ] Exemplos input/output concretos (3+), não abstratos.
- [ ] Gotchas concretos (fatos de ambiente que desafiam suposições razoáveis) no SKILL.md.
- [ ] Terminologia consistente; Markdown simples + tabelas onde agregam + code blocks com linguagem.
- [ ] MCP tools com nome qualificado `Server:tool`; dependências listadas e verificadas.

### Scripts
- [ ] Scripts resolvem, não adiam ("Solve, don't defer"): erros tratados com fallback útil.
- [ ] Sem constantes mágicas não justificadas ("voodoo constants").
- [ ] SKILL.md distingue "Run X" (executar) de "See X" (ler como referência).
- [ ] Saída do script legível/parseável (o agente só vê a saída, nunca o código).

### Verificação
- [ ] Validação de frontmatter: `skills-ref validate ./minha-skill` (spec aberta, agentskills.io) OU conferência manual contra a tabela da seção 1.3.
- [ ] Testado em pelo menos 3 cenários representativos (evals), com baseline com-vs-sem skill; se disponível, `skill-creator` (Claude Code) para grading e description tuning.
- [ ] Testado com os modelos-alvo (Haiku vs Sonnet vs Opus comportam-se diferente).
- [ ] Testado em sessão limpa (contexto fresco) — o sucesso na sessão de autoria mascara gaps da escrita.
- [ ] Verificado o disparo: pedido que DEVE ativar e pedido que NÃO deve ativar.
- [ ] Testado o fluxo de instalação pretendido (cópia, plugin ou symlink: `ln -s <repo>/skills/<nome> ~/.claude/skills/<nome>` e `~/.agents/skills/<nome>`).
- [ ] Revisado por terceiros (contexto fresco) e commitado no versionamento.
