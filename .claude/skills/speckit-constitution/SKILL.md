---
name: "speckit-constitution"
description: "Create or update the project constitution from interactive or provided principle inputs, ensuring all dependent templates stay in sync."
argument-hint: "Principles or values for the project constitution"
compatibility: "Requires spec-kit project structure with .specify/ directory"
metadata:
  author: "github-spec-kit"
  source: "templates/commands/constitution.md"
user-invocable: true
disable-model-invocation: false
---


## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).

## Pre-Execution Checks

**Check for extension hooks (before constitution update)**:
- Check if `.specify/extensions.yml` exists in the project root.
- If it exists, read it and look for entries under the `hooks.before_constitution` key
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

You are creating or updating the **Constituição do Itá** at `.specify/memory/constitution.md`. This is NOT a placeholder template — it is a **live, article-structured document**: Artigo I (princípios permanentes da linguagem) · Artigo II (posicionamento Itá:Dart::Elixir:Erlang) · Artigo III (régua do Dragon Book) · Artigo IV (regras operacionais) · Governança. Your job is to (a) understand the amendment the user is requesting, (b) apply it **inside the existing article structure** without flattening it into the generic spec-kit format, and (c) propagate the change across dependent artifacts and bump the version.

**Artifact language**: the constitution is written in **PT-BR** prose, code identifiers in `backticks`, internal errors in EN kebab-case — preserve that convention.

**Note**: `.specify/memory/constitution.md` already exists and is the project's single veto source. Do NOT re-initialize it from a generic `constitution-template.md` and do NOT overwrite its article format. If it were somehow missing, reconstruct it from the article layout above — never from a bracket-placeholder template.

### Ratification boundary (READ FIRST)

- **Artigo I (princípios permanentes) e Artigo II (posicionamento) são ratificados pelo dono.** Per the document's own Governança, only the owner (`GabrielAderaldo`) may add, remove, or redefine a permanent principle or the Dart-VM positioning. This skill **drafts and proposes** such amendments — it does **not** self-ratify them. When the requested change touches Artigo I or II, produce the proposed diff, mark it clearly as **PROPOSTA DE EMENDA — aguarda ratificação do dono (`GabrielAderaldo`)**, and do not treat it as adopted.
- **Artigos III (Dragon Book) e IV (regras operacionais) evoluem com o roadmap.** The skill may apply well-justified operational adjustments directly, recording the rationale.

Follow this execution flow:

1. Load the existing constitution at `.specify/memory/constitution.md`.
   - Identify the four articles and the Governança section. Note the current version line (`**Ratificada:** … · **Versão:** X.Y.Z`).
   - **IMPORTANT**: The user may add, revise, or remove a principle/rule. Respect the requested scope, but keep every change inside the correct article and honor the ratification boundary above.

2. Collect/derive the amendment content:
   - If user input (conversation) supplies the new/changed text, use it.
   - Otherwise infer from the constitution's own cited sources: `CLAUDE.md` (raiz + `ita/`), `references/livro-compiladores/ROADMAP.md`, and the project memory. This constitution **references, does not replace** the normative sources of each repo (e.g., `GRAMMAR.md` for syntax).
   - `Ratificada` is the original adoption date — keep it unless this is the first ratification. Update the version per step 3.

3. Determine the version bump per the document's **own Governança** (not generic semver labels):
   - **MAJOR**: removal or redefinition of a permanent principle (Artigo I) or of the positioning (Artigo II). Requires owner ratification.
   - **MINOR**: a new principle/rule is added, or an article gains materially new normative guidance.
   - **PATCH**: wording/clarification/typo fix that does not change any normative meaning.
   - If the bump type is ambiguous, state your reasoning before finalizing.

4. Draft the updated constitution content:
   - Edit **in place** inside the affected article. Preserve the heading hierarchy, the veto note at the top, the numbered-principle style of Artigo I, and the Governança section.
   - Keep principles declarative and testable so that each `/speckit-specify` Constitution check (spec-template §0) can point at a concrete rule.
   - Never introduce anything that contradicts an un-amended permanent principle (e.g., a rule implying `@decorators`/annotations, build-time code generation, or a non-Dart-VM backend). Flag such a request instead of writing it.

5. Consistency propagation checklist (validate the dependent artifacts still agree):
   - Read `.specify/templates/plan-template.md` and ensure its **Constitution Check** gate reflects the amended principles.
   - Read `.specify/templates/spec-template.md` and ensure its **§0 Constitution check** and any mandatory-phase requirement align (e.g., if a new principle adds a required phase or veto).
   - Read `.specify/templates/tasks-template.md` and ensure task categories tied to constitution rules (conformance corpus, MCP `ita` validation, VM×JS parity, compile-time benchmark) still map.
   - Read the sibling `speckit-*/SKILL.md` files only if the amendment changes a rule they cite — do not rewrite their spec-kit machinery.

6. Produce a Sync Impact Report (prepend as an HTML comment at the top of the constitution file after the update):
   - Version change: old → new (with bump rationale per step 3).
   - Articles/principles touched (Artigo N — antes → depois).
   - Added / removed rules.
   - Adoption state: **adopted** or **PROPOSTA (aguarda ratificação do dono)** for Artigo I/II changes.
   - Templates requiring updates (✅ updated / ⚠ pending) with file paths.
   - Follow-up TODOs, if any.

7. Validation before final output:
   - No contradiction with an un-amended permanent principle.
   - Version line matches the report; dates in ISO `YYYY-MM-DD`.
   - Article structure intact (I/II/III/IV + Governança); PT-BR prose preserved.
   - Rules are declarative and testable (prefer MUST/SHOULD with rationale over vague "should").

8. Write the completed constitution back to `.specify/memory/constitution.md` (overwrite), updating `**Versão:**` (and `**Ratificada:**` only on first ratification).

9. Output a final summary to the user with:
   - New version and bump rationale.
   - Whether it is adopted or awaits the owner's ratification (Artigo I/II).
   - Any files flagged for manual follow-up.
   - Suggested commit message (e.g., `docs: emenda à constituição vX.Y.Z (novo princípio + governança)`).

Formatting & Style Requirements:

- Prose in **PT-BR**; code identifiers in `backticks`; internal errors in EN kebab-case.
- Use Markdown headings exactly as in the existing document (do not demote/promote article levels).
- Keep a single blank line between sections; avoid trailing whitespace.

If the user supplies a partial amendment (e.g., only one rule revision), still perform the validation and version-decision steps.

If critical info is missing (e.g., the amendment needs an owner decision that has not been given), insert `TODO(<CAMPO>): explicação` and list it in the Sync Impact Report under deferred items — never fabricate ratification.

Do not create a new template; always operate on the existing `.specify/memory/constitution.md` file, preserving its article format.

## Post-Execution Checks

**Check for extension hooks (after constitution update)**:
Check if `.specify/extensions.yml` exists in the project root.
- If it exists, read it and look for entries under the `hooks.after_constitution` key
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

    **Optional Hook**: {extension}
    Command: `/{command}`
    Description: {description}

    Prompt: {prompt}
    To execute: `/{command}`
    ```
  - **Mandatory hook** (`optional: false`):
    ```
    ## Extension Hooks

    **Automatic Hook**: {extension}
    Executing: `/{command}`
    EXECUTE_COMMAND: {command}
    ```
- If no hooks are registered or `.specify/extensions.yml` does not exist, skip silently
