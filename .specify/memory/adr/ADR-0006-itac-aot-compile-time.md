# ADR-0006: `itac` roda AOT — compile-time perto do Go

- **Status:** Accepted
- **Data:** 2026-07-08
- **Relacionados:** [[ADR-0001]] (compile-time rápido é o objetivo nº1). Fonte: [[ita-velocidade-compilacao-aot]] (PR #31).

## Contexto

**Métrica obrigatória do Itá** (definida pelo dono): o tempo de compilação e o pipeline de CI/CD **não
podem** ser lentos — o norte é **perto do Go** (mesma classe: binário nativo). A causa da lentidão era
o **modo de execução**, não o compilador: rodar o `itac` em **JIT** (`dart --packages itac.dart`) paga
startup da VM + JIT dos ~11k linhas do `itac.dart` a cada invocação → **~5–9s para `hello.tu`** (70
linhas). Inaceitável.

## Decisão

**O `itac` de dev e de CI é o binário AOT, não JIT.** `tools/build-itac.sh` gera `build/itac`
(`dart compile exe`, nativo, ~10MB, gitignored, sob demanda); `bin/itac` usa `$ITA_ITAC_BIN`/`build/itac`
se existir, com **fallback JIT** automático. O `.dill` emitido é byte-idêntico ao do JIT.

- **Guard de regressão no CI:** benchmark de compile-time (`compiler/test/bench/compile_bench.sh`) que
  **falha se a mediana > 0,5s/arquivo** — barreira contra volta ao JIT ou codegen O(n²).

## Consequências

- **~50–250× mais rápido:** `hello.tu` em **0,03s quente / 0,83s frio**, já na faixa do Go.
  `run_conformance.sh` (76 arquivos): **76,4s (JIT) → 1,5s (AOT)**.
- CI builda o AOT uma vez; todos os passos/runners o usam via `ITA_ITAC_BIN`.
- Fix necessário: `ITA_COMPILER_LIB=compiler/lib` (sob AOT, `Platform.script` aponta pro binário, não
  achava `toml`).
- **Regra operacional:** **nunca** depender do JIT para medir ou iterar.
- **Débito de CI:** o oracle `js_parity` (dart2js × 33) domina o tempo (~11 min); o AOT não ajuda ali
  (custo é o dart2js) — mitigado por condicional de path-scope. Ver [[ita-alvo-js-dart2js]].
