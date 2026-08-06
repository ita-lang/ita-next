---
name: "speckit-implement"
description: "Execute the implementation plan by processing and executing all tasks defined in tasks.md"
argument-hint: "Optional implementation guidance or task filter"
compatibility: "Requires spec-kit project structure with .specify/ directory"
metadata:
  author: "github-spec-kit"
  source: "templates/commands/implement.md"
user-invocable: true
disable-model-invocation: false
---


## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).

## Pre-Execution Checks

**Check for extension hooks (before implementation)**:
- Check if `.specify/extensions.yml` exists in the project root.
- If it exists, read it and look for entries under the `hooks.before_implement` key
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

1. Run `.specify/scripts/bash/check-prerequisites.sh --json --require-tasks --include-tasks` from repo root and parse FEATURE_DIR and AVAILABLE_DOCS list. All paths must be absolute. For single quotes in args like "I'm Groot", use escape syntax: e.g 'I'\''m Groot' (or double-quote if possible: "I'm Groot").

2. **Check checklists status** (if FEATURE_DIR/checklists/ exists):
   - Scan all checklist files in the checklists/ directory
   - For each checklist, count:
     - Total items: All lines matching `- [ ]` or `- [X]` or `- [x]`
     - Completed items: Lines matching `- [X]` or `- [x]`
     - Incomplete items: Lines matching `- [ ]`
   - Create a status table:

     ```text
     | Checklist | Total | Completed | Incomplete | Status |
     |-----------|-------|-----------|------------|--------|
     | ux.md     | 12    | 12        | 0          | ✓ PASS |
     | test.md   | 8     | 5         | 3          | ✗ FAIL |
     | security.md | 6   | 6         | 0          | ✓ PASS |
     ```

   - Calculate overall status:
     - **PASS**: All checklists have 0 incomplete items
     - **FAIL**: One or more checklists have incomplete items

   - **If any checklist is incomplete**:
     - Display the table with incomplete item counts
     - **STOP** and ask: "Some checklists are incomplete. Do you want to proceed with implementation anyway? (yes/no)"
     - Wait for user response before continuing
     - If user says "no" or "wait" or "stop", halt execution
     - If user says "yes" or "proceed" or "continue", proceed to step 3

   - **If all checklists are complete**:
     - Display the table showing all checklists passed
     - Automatically proceed to step 3

3. Load and analyze the implementation context:
   - **REQUIRED**: Read tasks.md for the complete task list (RED → GREEN → VALIDATE → QUALITY) and execution order
   - **REQUIRED**: Read plan.md for the files to touch under `compiler/lib/{lexer,parser,semantic,codegen}/` and the test plan
   - **IF EXISTS**: Read design-notes.md for type/semantic/codegen decisions
   - **IF EXISTS**: Read conformance-cases.md for the `.tu` cases per §11 CA and expected VM/AOT/JS behavior
   - **IF EXISTS**: Read grammar-delta.md for the syntax delta
   - **REQUIRED**: Read `.specify/memory/constitution.md` for the permanent principles + operational rules (veto)

4. **Environment verification** (compiler-shaped, not app scaffolding):
   - Confirm the `itac` used is the **AOT** binary (built via `tools/build-itac.sh`), not JIT — compile-time is a tracked metric with a CI benchmark that fails on regression.
   - Confirm the conformance suite location exists (or create it per the Setup tasks) and that new `.tu` cases can be added there.
   - Confirm the MCP `ita` server is reachable (`compile`/`run`) — **all behavior is validated live through it**, never guessed.
   - Do NOT scaffold app-style project files (no `node_modules`, package managers, or web ignore-files) — this is a change to a compiler.
   - **Operational rule (constitution Artigo IV)**: do not touch git (`checkout`/`branch`/`commit`) while a subagent is actively editing the same working tree — it swaps HEAD under its feet.

5. Parse tasks.md structure and extract:
   - **Task phases**: Setup, Tests, Core, Integration, Polish
   - **Task dependencies**: Sequential vs parallel execution rules
   - **Task details**: ID, description, file paths, parallel markers [P]
   - **Execution flow**: Order and dependency requirements

6. Execute implementation following the task plan:
   - **Stage-by-stage execution**: complete RED → GREEN → VALIDATE → QUALITY in order; do not skip ahead.
   - **Respect dependencies**: run sequential tasks in order; parallel tasks [P] (different files) can run together.
   - **Fail-first**: the RED `.tu` conformance case must exist and fail on today's compiler before its GREEN implementation.
   - **File-based coordination**: tasks editing the same `compiler/lib/...` file must run sequentially.
   - **Validation checkpoints**: verify each stage live via MCP `ita` before proceeding.

7. Implementation execution rules:
   - **Setup first**: conformance suite location + fixtures; confirm the AOT `itac`.
   - **RED before GREEN**: write the failing `.tu` conformance case(s) for each §11 CA first.
   - **GREEN (core)**: implement in `compiler/lib/{lexer,parser,semantic,codegen}/`; type rules land in `compiler/lib/semantic/` (consumed via `_analysis.typeOf`), codegen emits Dart Kernel (`.dill`).
   - **VALIDATE**: run each case via MCP `ita` on the VM (oracle); confirm AOT empata and check VM×JS parity (dart2js) when codegen changed.
   - **QUALITY**: CI green (conformance + unit + benchmark de compile-time do `itac` AOT); reconcile `GRAMMAR.md` / tree-sitter if syntax changed.

8. Progress tracking and error handling:
   - Report progress after each completed task
   - Halt execution if any non-parallel task fails
   - For parallel tasks [P], continue with successful tasks, report failed ones
   - Provide clear error messages with context for debugging
   - Suggest next steps if implementation cannot proceed
   - **IMPORTANT** For completed tasks, make sure to mark the task off as [X] in the tasks file.

9. Completion validation:
   - Verify all required tasks are completed and marked `[X]`.
   - Check that the observable behavior matches spec §11 CAs, confirmed live via MCP `ita`.
   - Validate the conformance corpus is green on VM/AOT and VM×JS parity holds; the compile-time benchmark did not regress.
   - Confirm the implementation follows the plan and violates no permanent principle (constitution).
   - **Revisão dos especialistas de referência (W3, contexto fresco):** se existirem em `.claude/agents/`, rode uma revisão final independente do diff com os três subagentes (cada um vê só o diff + os CAs, não o raciocínio que os produziu):
     - **`ita-visionary`** — a implementação entregou a ergonomia que a visão prometia? Não introduziu mágica escondida nem feriu um princípio permanente?
     - **`compiler-craftsman`** — o passe está fiel ao algoritmo/capítulo (maximal munch, recursão à esquerda removida, contratos de fase Binding×Semântica)?
     - **`dart-vm-expert`** — o codegen→Kernel emite o que a VM espera e roda em VM/AOT/JS (paridade)?
     Trate como **gaps de correção** que afetam os §11 CAs, não preferências de estilo; corrija os reais e re-valide via MCP `ita`.

Note: This command assumes a complete task breakdown exists in tasks.md. If tasks are incomplete or missing, suggest running `/speckit-tasks` first to regenerate the task list.

## Mandatory Post-Execution Hooks

**You MUST complete this section before reporting completion to the user.**

Check if `.specify/extensions.yml` exists in the project root.
- If it does not exist, or no hooks are registered under `hooks.after_implement`, skip to the Completion Report.
- If it exists, read it and look for entries under the `hooks.after_implement` key.
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

Report final status with summary of completed work.

## Done When

- [ ] All tasks in tasks.md completed and marked `[X]`
- [ ] Implementation validated live via MCP `ita` (VM + VM×JS parity) and CI green (conformance + unit + benchmark de compile-time)
- [ ] Extension hooks dispatched or skipped according to the rules in Mandatory Post-Execution Hooks above
- [ ] Completion reported to user with summary of completed work
