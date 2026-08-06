---
name: "speckit-tasks"
description: "Generate an actionable, dependency-ordered tasks.md for the feature based on available design artifacts."
argument-hint: "Optional task generation constraints"
compatibility: "Requires spec-kit project structure with .specify/ directory"
metadata:
  author: "github-spec-kit"
  source: "templates/commands/tasks.md"
user-invocable: true
disable-model-invocation: false
---


## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).

## Pre-Execution Checks

**Check for extension hooks (before tasks generation)**:
- Check if `.specify/extensions.yml` exists in the project root.
- If it exists, read it and look for entries under the `hooks.before_tasks` key
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

1. **Setup**: Run `.specify/scripts/bash/setup-tasks.sh --json` from repo root and parse FEATURE_DIR, TASKS_TEMPLATE, and AVAILABLE_DOCS list. `FEATURE_DIR` and `TASKS_TEMPLATE` must be absolute paths when provided. `AVAILABLE_DOCS` is a list of document names/relative paths available under `FEATURE_DIR` (for example `research.md` or `contracts/`). For single quotes in args like "I'm Groot", use escape syntax: e.g 'I'\''m Groot' (or double-quote if possible: "I'm Groot").

2. **Load design documents**: Read from FEATURE_DIR:
   - **Required**: plan.md (files to touch per phase, test plan), spec.md (§11 CAs + fases tocadas)
   - **Optional**: design-notes.md (type/semantic decisions), conformance-cases.md (`.tu` cases per CA), grammar-delta.md (syntax delta)
   - Note: Not all changes touch all phases. Generate tasks based on what's available.

3. **Execute task generation workflow**:
   - Load plan.md and extract the files to touch under `compiler/lib/{lexer,parser,semantic,codegen}/`, the touched phases, and the test plan.
   - Load spec.md and extract the acceptance criteria from §11 (CA1, CA2, …) and their expected VM/AOT/JS behavior.
   - If conformance-cases.md exists: map each `.tu` case to the CA it proves.
   - If grammar-delta.md exists: derive parser/lexer tasks from the syntax delta.
   - If design-notes.md exists: derive the semantic/codegen decisions into implementation tasks.
   - Generate tasks organized fail-first by stage (RED → GREEN → VALIDATE → QUALITY; see Task Generation Rules below).
   - Generate a dependency graph showing stage order (a CA's GREEN tasks depend on its RED case existing).
   - Create parallel execution examples ([P] across independent CAs / independent files).
   - Validate completeness (every §11 CA has a RED case, a GREEN implementation, and a VALIDATE step).

4. **Generate tasks.md**: Read the tasks template from TASKS_TEMPLATE (from the JSON output above) and use it as structure. If TASKS_TEMPLATE is empty, fall back to `.specify/templates/tasks-template.md`. Fill with:
   - Correct feature name from plan.md
   - Phase 1: Setup (branch/scaffold; conformance suite location under the corpus)
   - Phase 2 — **RED**: one failing `.tu` conformance case per §11 CA (asserts the target output/error; must fail on today's compiler)
   - Phase 3 — **GREEN**: implement in `compiler/lib/{lexer,parser,semantic,codegen}/` until each RED case passes
   - Phase 4 — **VALIDATE**: run each case via MCP `ita` on the VM; check VM×JS parity (dart2js) when codegen changed
   - Phase 5 — **QUALITY**: CI green (conformance + unit + benchmark de compile-time do `itac` AOT); reconcile `GRAMMAR.md` / tree-sitter if syntax changed
   - All tasks must follow the strict checklist format (see Task Generation Rules below)
   - Clear file paths for each task (corpus case or `compiler/lib/...` source)
   - Dependencies section showing stage order
   - Parallel execution examples ([P])
   - Implementation strategy section (smallest CA first, incremental)

## Mandatory Post-Execution Hooks

**You MUST complete this section before reporting completion to the user.**

Check if `.specify/extensions.yml` exists in the project root.
- If it does not exist, or no hooks are registered under `hooks.after_tasks`, skip to the Completion Report.
- If it exists, read it and look for entries under the `hooks.after_tasks` key.
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

Output path to generated tasks.md and summary:
- Total task count
- Task count per §11 CA and per stage (RED/GREEN/VALIDATE/QUALITY)
- Parallel opportunities identified ([P])
- Conformance case (RED) that gates each CA
- Suggested first slice (typically the smallest CA — its RED → GREEN → VALIDATE loop)
- Format validation: Confirm ALL tasks follow the checklist format (checkbox, ID, labels, file paths)

Context for task generation: $ARGUMENTS

The tasks.md should be immediately executable - each task must be specific enough that an LLM can complete it without additional context.

## Task Generation Rules

**CRITICAL**: Tasks are **fail-first (compiler-shaped)** and organized by stage — RED → GREEN → VALIDATE → QUALITY — with each task labeled by the §11 acceptance criterion (`[CAn]`) it serves, so every CA is provable end to end.

**Conformance cases are MANDATORY (not optional)**: unlike a generic app, the RED stage is required — each §11 CA MUST get a failing `.tu` case in the conformance corpus before any implementation task. Validation is always live via MCP `ita`.

### Checklist Format (REQUIRED)

Every task MUST strictly follow this format:

```text
- [ ] [TaskID] [P?] [CA?] Description with file path
```

**Format Components**:

1. **Checkbox**: ALWAYS start with `- [ ]` (markdown checkbox)
2. **Task ID**: Sequential number (T001, T002, T003...) in execution order
3. **[P] marker**: Include ONLY if task is parallelizable (different files, no dependencies on incomplete tasks)
4. **[CA] label**: REQUIRED for RED/GREEN/VALIDATE tasks that serve a specific §11 acceptance criterion
   - Format: [CA1], [CA2], [CA3], etc. (maps to the CAs in spec.md §11)
   - Setup phase: NO label
   - QUALITY (cross-cutting CI/benchmark) phase: NO label
   - RED / GREEN / VALIDATE tasks: MUST carry the [CAn] label
5. **Description**: Clear action with the exact file path (corpus case or `compiler/lib/...` source)

**Examples**:

- ✅ CORRECT: `- [ ] T001 Criar suíte de conformância da feature em tests/conformance/<feature>/`
- ✅ CORRECT: `- [ ] T005 [P] [CA1] (RED) Caso .tu que falha em tests/conformance/<feature>/ca1_pow.tu`
- ✅ CORRECT: `- [ ] T012 [CA1] (GREEN) Emitir '**' tipado em compiler/lib/codegen/expr_gen.dart`
- ✅ CORRECT: `- [ ] T018 [CA1] (VALIDATE) Rodar ca1_pow.tu via MCP ita (VM) e conferir paridade JS`
- ❌ WRONG: `- [ ] Emitir pow` (missing ID and CA label)
- ❌ WRONG: `T001 [CA1] Emitir pow` (missing checkbox)
- ❌ WRONG: `- [ ] [CA1] Emitir pow` (missing Task ID)
- ❌ WRONG: `- [ ] T001 [CA1] Emitir pow` (missing file path)

### Task Organization

1. **From §11 Acceptance Criteria (spec.md)** - PRIMARY ORGANIZATION:
   - Each CA (CA1, CA2, …) gets a RED case, then GREEN implementation, then VALIDATE.
   - Map every task to the CA it proves; keep CAs independent where possible.
   - The RED case for a CA MUST precede its GREEN tasks (fail-first).

2. **From grammar-delta.md / syntax**:
   - Each grammar production delta → parser/lexer task in `compiler/lib/parser/` or `compiler/lib/lexer/`, under the GREEN stage of the CA it enables.
   - Reconcile `GRAMMAR.md` and the tree-sitter grammar → QUALITY stage.

3. **From design-notes.md (types/semantics/codegen)**:
   - Each type/semantic decision → task in `compiler/lib/semantic/` (consumed via `_analysis.typeOf`).
   - Each codegen decision → task in `compiler/lib/codegen/`, with a VALIDATE task asserting VM/AOT/JS behavior.

4. **From Setup / cross-cutting**:
   - Conformance suite location + fixtures → Setup phase (Phase 1).
   - CI wiring, compile-time benchmark, parity golden-runner → QUALITY phase (final).

### Phase Structure

- **Phase 1**: Setup (conformance suite location, fixtures, branch)
- **Phase 2 — RED**: one failing `.tu` conformance case per §11 CA (must fail on today's compiler)
- **Phase 3 — GREEN**: implement in `compiler/lib/{lexer,parser,semantic,codegen}/` until each RED case passes
- **Phase 4 — VALIDATE**: run each case via MCP `ita` on the VM; check VM×JS parity (dart2js) when codegen changed
- **Phase 5 — QUALITY**: CI green (conformance + unit + benchmark de compile-time do `itac` AOT); reconcile `GRAMMAR.md` / tree-sitter if syntax changed

## Done When

- [ ] tasks.md generated with all phases, task IDs, and file paths
- [ ] Extension hooks dispatched or skipped according to the rules in Mandatory Post-Execution Hooks above
- [ ] Completion reported to user with task count, story breakdown, and MVP scope
