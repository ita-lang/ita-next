# ADR-0004: Fase semântica via side-table (type-checker, rota rustc)

- **Status:** Accepted · ⚠️ **parcialmente superseded pelo [[ADR-0013]]** (2026-07-15) — **só** a regra de
  ouro `UnknownType → dynamic` foi revogada; **todo o resto deste ADR segue em vigor** (side-table
  `Map.identity`, rota rustc, AST imutável, pacote `semantic/`, IR adiada) e é reafirmado lá.
- **Data:** 2026-07-06
- **Relacionados:** [[ADR-0001]] (performance vem de codegen tipado, não de backend nativo), [[ADR-0007]] (é a Fase 4 / Cap 6, único P0). Fonte: [[ita-compilador-sem-fase-semantica]].

## Contexto

Até o M1, **não existia fase de análise semântica** entre parser e codegen: o `codegen.dart` gerava
Kernel direto do AST. Consequência — "fortemente tipada" era decorativa; quem "tipava" era a Dart VM
lançando `NoSuchMethodError` em runtime (`let x: Int = "hello"` passava no `check`). Daí a família de
bugs "compila mas roda errado": `**` virando `*`, divisão `/` de Float truncando, copy-with no-op em
struct não-`let`, e exaustividade de `match` não enforçada.

## Decisão

**Introduzir uma fase semântica baseada em side-table**, rota estilo rustc (`TypeckResults` → IR):

- **Side-table** `Map.identity()` nó→`ResolvedType` — a AST **imutável permanece intacta** (sem
  reescrever nós). HM modesto; regra de ouro **`UnknownType` → `dynamic`** onde a inferência não é confiável.
  > ⚠️ **A regra de ouro foi REVOGADA pelo [[ADR-0013]] (2026-07-15)** para o `ita-next`: falha de
  > inferência é **`cannot-infer`** (erro), e `dynamic` não é tipo de superfície. Motivo: ela colide com o
  > [[ADR-0007]] (*"Kernel tipado é a única alavanca; ~7,7× = o custo do dinamismo"*), e no oracle produziu
  > um `Unknown` curinga-bidirecional que **nunca erra** — 4 regras checadas em 1355 linhas. Os "Débitos
  > abertos" listados abaixo eram o sintoma. **O resto deste ADR permanece em vigor.**
- Pacote `compiler/lib/semantic/` (`resolved_type`/`symbol`/`scope`/`type_resolver`/`type_table`/
  `analyzer`/`type_checker`); `SemanticAnalyzer.run(Program) → AnalysisResult`.
- **IR própria (Fase 4c) adiada:** a performance veio da side-table + TFA do AOT, sem IR intermediária.

## Consequências

- **Gate ligado** nos 3 call-sites de `itac.dart` (compile/check/compileQuiet): erros estilo Rust/Elm
  (span + dica), zero falsos-positivos na suíte.
- **Bugs mortos ao vivo:** `2**3`→8, `a/b` de Float inferido→3.5, copy-with (`.{x:99}`→99),
  exaustividade de `match`. 4 dos 5 bugs originais fechados.
- **Perf recuperada via side-table:** tipar só os locais (Int/Float/Bool/String inferidos) deu **~16×**
  no AOT — o TFA devirtualiza os `DynamicInvocation` quando o receiver tem tipo concreto.
- **Débitos abertos:** type-args de generics não instanciados (`_inferCall`), pattern literal casando
  braço errado. As 3 fatias mergeadas no `main` (PRs #4/#5/#6).
