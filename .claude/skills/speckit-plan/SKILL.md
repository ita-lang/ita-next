---
name: "speckit-plan"
description: "Execute the implementation planning workflow using the plan template to generate design artifacts."
argument-hint: "Optional guidance for the planning phase"
compatibility: "Requires spec-kit project structure with .specify/ directory"
metadata:
  author: "github-spec-kit"
  source: "templates/commands/plan.md"
user-invocable: true
disable-model-invocation: false
---


## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).

## Pre-Execution Checks

**Check for extension hooks (before planning)**:
- Check if `.specify/extensions.yml` exists in the project root.
- If it exists, read it and look for entries under the `hooks.before_plan` key
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

1. **Setup**: Run `.specify/scripts/bash/setup-plan.sh --json` from repo root and parse JSON for FEATURE_SPEC, IMPL_PLAN, SPECS_DIR, BRANCH. For single quotes in args like "I'm Groot", use escape syntax: e.g 'I'\''m Groot' (or double-quote if possible: "I'm Groot").

2. **Load context**: Read FEATURE_SPEC and `.specify/memory/constitution.md`. Load IMPL_PLAN template (already copied).

3. **Execute plan workflow**: Follow the structure in the IMPL_PLAN template (`.specify/templates/plan-template.md`) to:
   - Fill Technical Context: which Dragon-Book phases the change touches and which compiler files it will edit under `compiler/lib/{lexer,parser,semantic,codegen}/` (mark unknowns as "NEEDS CLARIFICATION").
   - Fill Constitution Check section from `.specify/memory/constitution.md` (permanent principles + operational rules).
   - Evaluate gates (ERROR if a permanent-principle violation is unjustified).
   - Phase 0: Generate `design-notes.md` (resolve all NEEDS CLARIFICATION — semantics/type decisions, approach per touched phase).
   - Phase 1: Generate `conformance-cases.md` (the `.tu` cases derived from spec §11 CAs, with expected VM/AOT/JS behavior) and, if syntax is touched, `grammar-delta.md`.
   - Phase 1: Update agent context by running the agent script.
   - Re-evaluate Constitution Check post-design.

## Mandatory Post-Execution Hooks

**You MUST complete this section before reporting completion to the user.**

Check if `.specify/extensions.yml` exists in the project root.
- If it does not exist, or no hooks are registered under `hooks.after_plan`, skip to the Completion Report.
- If it exists, read it and look for entries under the `hooks.after_plan` key.
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

Command ends after Phase 2 planning. Report branch, IMPL_PLAN path, and generated artifacts.

## Phases

### Phase 0: Design notes & open questions

1. **Extract unknowns from Technical Context** above:
   - For each NEEDS CLARIFICATION → a design decision to resolve (type rule, coercion direction, ambiguity handling, codegen shape per target).
   - For each touched phase → confirm the approach against the Dragon-Book chapter and `GRAMMAR.md`.
   - For each `dart:` interop or VM dependency → note what is assumed (never re-specify the VM; Grupo B).

2. **Resolve each decision** (delegate live checks to the compiler agent + MCP `ita` when behavior is uncertain — do NOT guess):

   ```text
   For each unknown in Technical Context:
     Decide: "{type/semantic/codegen decision} for {change}", validated via MCP `ita` when observable
   For each touched phase:
     Confirm: "approach for {phase} vs Dragon Book {cap} and GRAMMAR.md"
   ```

   - **Disparo dos especialistas de referência (W1):** se existirem em `.claude/agents/`, delegue as decisões de design aos subagentes antes de consolidar:
     - **`compiler-craftsman`** — para cada fase tocada (léxico/parsing/desugaring/binding/tipos/análises), peça a técnica correta **com o capítulo** do Dragon Book / Crafting Interpreters que a funda. O retorno vira `Rationale` do `design-notes.md`.
     - **`dart-vm-expert`** — para toda dependência de runtime e todo codegen→Kernel, peça o que a Dart VM **entrega** (Grupo B, não implementamos) vs. **exige**, e o comportamento **por alvo** (VM/AOT/JS). O retorno alimenta o `design-notes.md` e o §8 do plan.
     Comportamento observável ainda se confirma no MCP `ita` (agente do compilador); estes especialistas fundamentam a decisão, não a executam.

3. **Consolidate findings** in `design-notes.md` using format:
   - Decision: [what was chosen]
   - Rationale: [why chosen — cite constitution principle / Dragon-Book chapter]
   - Alternatives considered: [what else evaluated and why rejected]

**Output**: `design-notes.md` with all NEEDS CLARIFICATION resolved

### Phase 1: Test plan & surface deltas

**Prerequisites:** `design-notes.md` complete

1. **Derive conformance cases from spec §11** → `conformance-cases.md`:
   - One `.tu` case per CA: program → expected output/error (EN kebab-case + span).
   - Expected behavior **per target** (VM oracle / AOT empata / JS paridade) when codegen is touched.
   - Where each case lands in the conformance corpus, plus any unit tests for `compiler/lib/semantic/` or `compiler/lib/codegen/`.

2. **Declare the compiler surfaces the change touches** (the RFC's "contracts"):
   - Syntax → `grammar-delta.md`: BNF/EBNF delta, reconciliation with `GRAMMAR.md` and the tree-sitter grammar.
   - Types/semantics → the type rules landed in `compiler/lib/semantic/` (consumed via `_analysis.typeOf`).
   - Codegen → the Kernel/`.dill` emission changes and the VM×JS parity check (golden-runner).
   - Skip whichever surface the change does not touch.

3. **Agent context update**:
   - Update the plan reference between the `<!-- SPECKIT START -->` and `<!-- SPECKIT END -->` markers in `CLAUDE.md` to point to the plan file (the IMPL_PLAN path).

**Output**: `conformance-cases.md`, `grammar-delta.md` (if syntax touched), updated agent context file

## Key rules

- Use absolute paths for filesystem operations; use project-relative paths for references in documentation and agent context files
- ERROR on gate failures (Constitution Check) or unresolved clarifications
- The plan lists the files to touch under `compiler/lib/{lexer,parser,semantic,codegen}/`, the strategy per touched phase, and the test plan (corpus + MCP `ita` + VM×JS parity + CI/benchmark de compile-time do `itac` AOT)
- Generated plan artifacts are **PT-BR**; validate any uncertain behavior live via MCP `ita`, never by guessing

## Done When

- [ ] Plan workflow executed and design artifacts generated
- [ ] Extension hooks dispatched or skipped according to the rules in Mandatory Post-Execution Hooks above
- [ ] Completion reported to user with branch, plan path, and generated artifacts
