---
name: "speckit-specify"
description: "Create or update the feature specification from a natural language feature description."
argument-hint: "Describe the feature you want to specify"
compatibility: "Requires spec-kit project structure with .specify/ directory"
metadata:
  author: "github-spec-kit"
  source: "templates/commands/specify.md"
user-invocable: true
disable-model-invocation: false
---


## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).

## Pre-Execution Checks

**Check for extension hooks (before specification)**:
- Check if `.specify/extensions.yml` exists in the project root.
- If it exists, read it and look for entries under the `hooks.before_specify` key
- If the YAML cannot be parsed or is invalid, skip hook checking silently and continue normally
- Filter out hooks where `enabled` is explicitly `false`. Treat hooks without an `enabled` field as enabled by default.
- For each remaining hook, do **not** attempt to interpret or evaluate hook `condition` expressions:
  - If the hook has no `condition` field, or it is null/empty, treat the hook as executable
  - If the hook defines a non-empty `condition`, skip the hook and leave condition evaluation to the HookExecutor implementation
- When constructing slash commands from hook command names, replace dots (`.`) with hyphens (`-`). For example, `speckit.git.commit` → `/speckit-git-commit`.
- For each executable hook, output the following based on its `optional` flag:
  - **Optional hook** (`optional: true`):
    ```
    ## Extension Hooks

    **Optional Pre-Hook**: {extension}
    Command: `/{command}`
    Description: {description}

    Prompt: {prompt}
    To execute: `/{command}`
    ```
  - **Mandatory hook** (`optional: false`):
    ```
    ## Extension Hooks

    **Automatic Pre-Hook**: {extension}
    Executing: `/{command}`
    EXECUTE_COMMAND: {command}

    Wait for the result of the hook command before proceeding to the Outline.
    ```
- If no hooks are registered or `.specify/extensions.yml` does not exist, skip silently

## Outline

The text the user typed after `/speckit-specify` in the triggering message **is** the feature description. Assume you always have it available in this conversation even if `$ARGUMENTS` appears literally below. Do not ask the user to repeat it unless they provided an empty command.

Given that feature description, do this:

1. **Generate a concise short name** (2-4 words) for the change:
   - Analyze the change description and extract the most meaningful keywords
   - Create a 2-4 word short name that captures the essence of the change
   - Use action-noun format when possible (e.g., "add-pow-operator", "fix-float-codegen")
   - Preserve technical terms and token/type names (`**`, `Result`, `struct`, AOT, etc.)
   - Keep it concise but descriptive enough to understand the change at a glance
   - Examples:
     - "Quero adicionar o operador de potência `**`" → "pow-operator"
     - "Inferir tipo sem anotação em `let`" → "let-type-inference"
     - "Codegen de copy-with para struct no alvo JS" → "struct-copywith-js"
     - "Corrigir Float com `.0` no dart2js" → "fix-float-dot-zero-js"

2. **Branch creation** (optional, via hook):

   If a `before_specify` hook ran successfully in the Pre-Execution Checks above, it will have created/switched to a git branch and output JSON containing `BRANCH_NAME` and `FEATURE_NUM`. Note these values for reference, but the branch name does **not** dictate the spec directory name.

   If the user explicitly provided `GIT_BRANCH_NAME`, pass it through to the hook so the branch script uses the exact value as the branch name (bypassing all prefix/suffix generation).

3. **Create the spec feature directory**:

   Specs live under the default `specs/` directory unless the user explicitly provides `SPECIFY_FEATURE_DIRECTORY`.

   **Resolution order for `SPECIFY_FEATURE_DIRECTORY`**:
   1. If the user explicitly provided `SPECIFY_FEATURE_DIRECTORY` (e.g., via environment variable, argument, or configuration), use it as-is
   2. Otherwise, auto-generate it under `specs/`:
      - Check `.specify/init-options.json` for `branch_numbering`
      - If `"timestamp"`: prefix is `YYYYMMDD-HHMMSS` (current timestamp)
      - If `"sequential"` or absent: prefix is `NNN` (next available 3-digit number after scanning existing directories in `specs/`)
      - Construct the directory name: `<prefix>-<short-name>` (e.g., `003-pow-operator` or `20260319-143022-pow-operator`)
      - Set `SPECIFY_FEATURE_DIRECTORY` to `specs/<directory-name>`

   **Create the directory and spec file**:
   - `mkdir -p SPECIFY_FEATURE_DIRECTORY`
   - Copy `.specify/templates/spec-template.md` to `SPECIFY_FEATURE_DIRECTORY/spec.md` as the starting point
   - Set `SPEC_FILE` to `SPECIFY_FEATURE_DIRECTORY/spec.md`
   - Persist the resolved path to `.specify/feature.json`:
     ```json
     {
       "feature_directory": "<resolved feature dir>"
     }
     ```
     Write the actual resolved directory path value (for example, `specs/003-pow-operator`), not the literal string `SPECIFY_FEATURE_DIRECTORY`.
     This allows downstream commands (`/speckit-plan`, `/speckit-tasks`, etc.) to locate the feature directory without relying on git branch name conventions.

   **IMPORTANT**:
   - You must only create one feature per `/speckit-specify` invocation
   - The spec directory name and the git branch name are independent — they may be the same but that is the user's choice
   - The spec directory and file are always created by this command, never by the hook

4. Load `.specify/templates/spec-template.md` — this is the **canonical, MULTI-PHASE technical RFC template** for an Itá language/compiler change (§0 metadados + Constitution check · §1 motivação + exemplo `.tu` antes/depois · §2 léxico · §3 sintaxe · §4 especificação formal ⭐ · §5 SDD · §6 fluxo · §7 codegen por alvo VM/AOT/JS · §8 runtime · §9 checklist Apêndice A · §10 compat/migração · §11 critérios de aceite → corpus). You **MUST** follow its structure and its "COMO PREENCHER" header. It is NOT a product doc — do not impose product-management framing on it. The generated **spec is PT-BR** (prose), `backticks` for identifiers, EN kebab-case for internal errors.

5. Follow this execution flow:
    1. Parse user description from arguments
       If empty: ERROR "No feature description provided"
    2. Extract key concepts: what changes in the language/compiler, which Dragon-Book phases it touches (léxico → codegen), which permanent principles it interacts with (see `.specify/memory/constitution.md`).
    3. For unclear aspects:
       - Make informed guesses based on the constitution, `GRAMMAR.md`, the ROADMAP, and standard compiler practice.
       - Only mark with [NEEDS CLARIFICATION: specific question] if:
         - The choice significantly changes the language's observable semantics or scope
         - Multiple reasonable interpretations exist with different type/codegen implications
         - No reasonable default exists
       - **LIMIT: Maximum 3 [NEEDS CLARIFICATION] markers total**
       - Prioritize by impact: constitution/semantics > type rules > syntax/lexing > codegen detail.
    4. Fill §1 (Motivação e resumo) with a **motivação + exemplo `.tu` antes → depois** — the RFC analog of "user scenarios". If you cannot produce a minimal before/after `.tu` example, ERROR "Cannot determine motivating example".
    5. Fill only the phase sections (§2–§8) the change actually touches; **remove entirely** (heading included) every phase it does not touch — never leave "N/A". §4 (Especificação formal) is OBRIGATÓRIA whenever the change alters a type or semantics; it is dispensable only for purely mechanical sugar. Each phase cites the Dragon-Book chapter that grounds it.
    6. Write §11 (Critérios de aceite) as **testable CAs that each become a case in the conformance corpus** (a `.tu` program → expected output/error), validated live via the MCP `ita`. When codegen is touched, declare behavior **per target (VM/AOT/JS)** in §7.3 and mark VM×JS parity. This replaces "technology-agnostic success criteria" — for a compiler RFC the criteria ARE the observable compiler/runtime behavior.
    7. Fill §0 metadados (fases tocadas, princípios afetados) and run the §0.5 **Constitution check** against `.specify/memory/constitution.md`.
       - **Disparo do guardião da visão (W0):** se o subagente `ita-visionary` existir (`.claude/agents/`), delegue-lhe o Constitution-check de identidade — *"esta mudança respeita os 11 princípios permanentes (Art. I) e o posicionamento Itá:Dart::Elixir:Erlang (Art. II)? Não vira mágica escondida nem trai imutabilidade/`Result`?"*. Incorpore o veredicto no §0.5: se ele apontar violação de princípio permanente, marque **conflito aberto** — a spec não avança sem emenda explícita do dono (Governança). Se o agente não existir, faça o check você mesmo contra a `constitution.md`.
    8. Return: SUCCESS (spec ready for `/speckit-clarify` or `/speckit-plan`)

6. Write the specification to SPEC_FILE using the template structure, replacing placeholders with concrete details derived from the feature description (arguments) while preserving section order and headings.

7. **Specification Quality Validation**: After writing the initial spec, validate it against quality criteria:

   a. **Create Spec Quality Checklist**: Generate a checklist file at `SPECIFY_FEATURE_DIRECTORY/checklists/requirements.md` using the checklist template structure with these validation items:

      ```markdown
      # Checklist de Qualidade da Spec: [NOME DA FEATURE]

      **Propósito**: validar completude e qualidade da spec (RFC de linguagem) antes de planejar
      **Criado**: [DATA]
      **Spec**: [link para spec.md]

      ## Qualidade do conteúdo

      - [ ] Segue o `spec-template.md` (RFC técnico multi-fase); seções de fase não tocadas foram REMOVIDAS (sem "N/A")
      - [ ] §1 tem motivação + exemplo `.tu` **antes → depois** e não-objetivos
      - [ ] Prosa em PT-BR; identificadores em `backticks`; erros internos em EN kebab-case
      - [ ] Cada fase preenchida cita o capítulo do Dragon Book que a fundamenta

      ## Completude da RFC

      - [ ] Nenhum marcador [NEEDS CLARIFICATION] remanescente
      - [ ] §4 (Especificação formal) presente quando a mudança toca tipo ou semântica
      - [ ] Comportamento por alvo (VM/AOT/JS) declarado em §7.3 quando toca codegen; paridade VM×JS marcada
      - [ ] Regras/tipos declarados de forma não-ambígua (premissa/conclusão quando aplicável)
      - [ ] §9 checklist de completude (Apêndice A) coerente com as fases tocadas
      - [ ] Escopo delimitado; compatibilidade/migração (§10) e alternativas descartadas registradas
      - [ ] Premissas de runtime (§8) declaram apenas dependências da Dart VM, sem reespecificá-la

      ## Prontidão

      - [ ] Cada CA de §11 é **testável** e vira caso `.tu` no corpus de conformância (saída/erro esperado)
      - [ ] CAs validáveis ao vivo via MCP `ita` (VM; paridade JS quando aplicável)
      - [ ] Constitution check (§0.5) sem conflito com princípio permanente
      - [ ] Definition of Done coerente com CI (conformance + unit + benchmark de compile-time)

      ## Notas

      - Itens incompletos exigem ajuste da spec antes de `/speckit-clarify` ou `/speckit-plan`
      ```

   b. **Run Validation Check**: Review the spec against each checklist item:
      - For each item, determine if it passes or fails
      - Document specific issues found (quote relevant spec sections)

   c. **Handle Validation Results**:

      - **If all items pass**: Mark checklist complete and proceed to the Mandatory Post-Execution Hooks section

      - **If items fail (excluding [NEEDS CLARIFICATION])**:
        1. List the failing items and specific issues
        2. Update the spec to address each issue
        3. Re-run validation until all items pass (max 3 iterations)
        4. If still failing after 3 iterations, document remaining issues in checklist notes and warn user

      - **If [NEEDS CLARIFICATION] markers remain**:
        1. Extract all [NEEDS CLARIFICATION: ...] markers from the spec
        2. **LIMIT CHECK**: If more than 3 markers exist, keep only the 3 most critical (priority: constitution/semantics > type rules > syntax/lexing > codegen detail) and make informed guesses for the rest
        3. For each clarification needed (max 3), present options to user in this format:

           ```markdown
           ## Question [N]: [Topic]
           
           **Context**: [Quote relevant spec section]
           
           **What we need to know**: [Specific question from NEEDS CLARIFICATION marker]
           
           **Suggested Answers**:
           
           | Option | Answer | Implications |
           |--------|--------|--------------|
           | A      | [First suggested answer] | [What this means for the feature] |
           | B      | [Second suggested answer] | [What this means for the feature] |
           | C      | [Third suggested answer] | [What this means for the feature] |
           | Custom | Provide your own answer | [Explain how to provide custom input] |
           
           **Your choice**: _[Wait for user response]_
           ```

        4. **CRITICAL - Table Formatting**: Ensure markdown tables are properly formatted:
           - Use consistent spacing with pipes aligned
           - Each cell should have spaces around content: `| Content |` not `|Content|`
           - Header separator must have at least 3 dashes: `|--------|`
           - Test that the table renders correctly in markdown preview
        5. Number questions sequentially (Q1, Q2, Q3 - max 3 total)
        6. Present all questions together before waiting for responses
        7. Wait for user to respond with their choices for all questions (e.g., "Q1: A, Q2: Custom - [details], Q3: B")
        8. Update the spec by replacing each [NEEDS CLARIFICATION] marker with the user's selected or provided answer
        9. Re-run validation after all clarifications are resolved

   d. **Update Checklist**: After each validation iteration, update the checklist file with current pass/fail status

## Mandatory Post-Execution Hooks

**You MUST complete this section before reporting completion to the user.**

Check if `.specify/extensions.yml` exists in the project root.
- If it does not exist, or no hooks are registered under `hooks.after_specify`, skip to the Completion Report.
- If it exists, read it and look for entries under the `hooks.after_specify` key.
- If the YAML cannot be parsed or is invalid, skip hook checking silently and continue to the Completion Report.
- Filter out hooks where `enabled` is explicitly `false`. Treat hooks without an `enabled` field as enabled by default.
- For each remaining hook, do **not** attempt to interpret or evaluate hook `condition` expressions:
  - If the hook has no `condition` field, or it is null/empty, treat the hook as executable
  - If the hook defines a non-empty `condition`, skip the hook and leave condition evaluation to the HookExecutor implementation
- When constructing slash commands from hook command names, replace dots (`.`) with hyphens (`-`). For example, `speckit.git.commit` → `/speckit-git-commit`.
- For each executable hook, output the following based on its `optional` flag:
  - **Mandatory hook** (`optional: false`) — **You MUST emit `EXECUTE_COMMAND:` for each mandatory hook**:
    ```
    ## Extension Hooks

    **Automatic Hook**: {extension}
    Executing: `/{command}`
    EXECUTE_COMMAND: {command}
    ```
  - **Optional hook** (`optional: true`):
    ```
    ## Extension Hooks

    **Optional Hook**: {extension}
    Command: `/{command}`
    Description: {description}

    Prompt: {prompt}
    To execute: `/{command}`
    ```

## Completion Report

Report completion to the user with:
- `SPECIFY_FEATURE_DIRECTORY` — the feature directory path
- `SPEC_FILE` — the spec file path
- Checklist results summary
- Readiness for the next phase (`/speckit-clarify` or `/speckit-plan`)

**NOTE:** Branch creation is handled by the `before_specify` hook (git extension). Spec directory and file creation are always handled by this core command.

## Quick Guidelines

- This spec is a **technical RFC for a language/compiler change**, not a product doc. Relax the generic "no implementation details / non-technical stakeholders" rules — here the tokens, grammar productions, type rules, and per-target codegen behavior **are** the spec.
- Focus on **what rule starts to hold** and **why** (the motivation), plus the **observable behavior per target (VM/AOT/JS)**. Describe the RULE, not the low-level line-by-line implementation of compiler internals.
- Written for **language/compiler contributors**, in PT-BR prose with `backticks` for identifiers.
- Load and follow `.specify/templates/spec-template.md`; keep only the phases the change touches.
- DO NOT create any checklists embedded in the spec. The quality checklist is a separate file (see Specification Quality Validation).

### Section Requirements

- **Mandatory sections**: Must be completed for every feature
- **Optional sections**: Include only when relevant to the feature
- When a section doesn't apply, remove it entirely (don't leave as "N/A")

### For AI Generation

When creating this spec from a user prompt:

1. **Make informed guesses**: Use context, industry standards, and common patterns to fill gaps
2. **Document assumptions**: Record reasonable defaults in the Assumptions section
3. **Limit clarifications**: Maximum 3 [NEEDS CLARIFICATION] markers - use only for critical decisions that:
   - Significantly change the language's observable semantics or scope
   - Have multiple reasonable interpretations with different type/codegen implications
   - Lack any reasonable default
4. **Prioritize clarifications**: constitution/semantics > type rules > syntax/lexing > codegen detail
5. **Think like a tester**: Every vague rule should fail the "testable CA in the conformance corpus" checklist item
6. **Common areas needing clarification** (only if no reasonable default exists):
   - Scope of the change (which constructs / which Dragon-Book phases are in vs out)
   - A type/semantic rule where interpretations differ observably (inference vs synthesis, coercion direction)
   - Divergent behavior across targets (VM/AOT/JS) that is not obviously intended

**Examples of reasonable defaults** (don't ask about these):

- Erros internos: mensagem EN kebab-case com span, no padrão do compilador
- Alvo de referência (oracle): a **VM** (JIT); AOT deve empatar; JS conferido por paridade
- Estratégia de tipo: inferência **sem anotações** (Princípio 6); nunca `@decorators`
- Tratamento de erro na linguagem: `Result` + `?` + `panic` (Princípio 7); nunca try/catch
- Sintaxe: reconciliar com o `GRAMMAR.md` normativo e com a gramática tree-sitter

### Acceptance Criteria Guidelines (§11 → corpus de conformância)

For a language RFC, "success criteria" are **acceptance criteria (CAs)** that become conformance cases. Each CA must be:

1. **Testável**: um programa `.tu` concreto → uma saída ou erro esperado (não uma frase vaga).
2. **Executável ao vivo**: validável via MCP `ita` (`compile`/`run`) na VM; paridade JS conferida quando o codegen muda.
3. **Observável**: descreve o comportamento visível (valor impresso, erro interno EN kebab-case + span, `.dill` gerado), não os internals do compilador.
4. **Por alvo quando aplica**: se toca codegen, declara a saída em VM/AOT/JS (§7.3) e marca MATCH/NUM de paridade.

**Good examples**:

- "`let x = 2 ** 10` ⟶ imprime `1024` na VM; paridade JS MATCH"
- "`&`/`|` sobre `Bool` ⟶ `type-error: bitwise-on-bool` com span do operador"
- "copy-with em `struct` ⟶ AOT empata a VM; JS MATCH"
- "o caso novo não regride o benchmark de compile-time do `itac` AOT no CI"

**Bad examples** (não-testáveis / fora de domínio):

- "a sintaxe fica mais intuitiva" (não mensurável)
- "o type-checker é robusto" (adjetivo sem critério)
- "usuários finais ficam satisfeitos" (product framing, fora de escopo de RFC)
- "responde em <200ms" (métrica web sem relação com o comportamento da linguagem)

## Done When

- [ ] Specification written to `SPEC_FILE` and validated against quality checklist
- [ ] Extension hooks dispatched or skipped according to the rules in Mandatory Post-Execution Hooks above
- [ ] Completion reported to user with feature directory, spec file path, and checklist results
