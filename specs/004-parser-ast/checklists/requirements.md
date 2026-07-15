# Checklist de Qualidade da Spec: Sintaxe completa → AST (Fase 2)

**Propósito**: validar completude e qualidade da spec (RFC de linguagem) antes de planejar
**Criado**: 2026-07-10
**Spec**: [../spec.md](../spec.md)

## Qualidade do conteúdo

- [x] Segue o `spec-template.md` (RFC multi-fase); fases não tocadas (léxico/tipos/SDD/fluxo/codegen/runtime) **removidas** (sem "N/A"); +§A artefatos
- [x] §1 tem motivação + exemplo `.tu` **antes → depois** (tokens → AST) e não-objetivos
- [x] Prosa PT-BR; identificadores em `backticks`; erros internos EN kebab-case (`parse-error: expected-token`, `range-non-associative`)
- [x] §3 Sintaxe cita o cap. do Dragon Book (`[cap 4.2–4.4, 5.3]`) + ref. de impl. CI cap 6 (Pratt)

## Completude da RFC

- [x] Nenhum marcador [NEEDS CLARIFICATION] — a sintaxe é **bem-definida** pela fonte-da-verdade (`GRAMMAR.md` §2–§6 + parser do `ita/`)
- ~~§4 Especificação formal (regras de tipo)~~ — **N/A**: sintaxe não toca tipo/semântica. O artefato formal desta fase é `ast.asdl` (ASDL) + `grammar.ebnf` §Syntactic (W3C EBNF) — presente na §A
- ~~§7.3 por alvo (VM/AOT/JS)~~ — **N/A**: parser é agnóstico de alvo (não toca codegen)
- [x] §3 declara as produções (referencia o `GRAMMAR.md` normativo), a precedência (§3.2), ambiguidades/cantos (§3.3) e a adequação descendente (§3.4)
- [x] §9 checklist de completude (Apêndice A — `parser`/`ast`) coerente com a fase
- [x] Escopo delimitado (só sintaxe→AST); compat/oracle (§10) e alternativas descartadas (parser gerado — veta P11) registradas
- [x] Sem §8 runtime (parser não depende da VM)

## Prontidão

- [x] CA1–CA18 testáveis: cada um é um `.tu` → AST esperada (`.ast`) ou erro de parse com span
- [x] CAs verificáveis por `itac parse --dump` + `dart test`; **oracle = `GRAMMAR.md` §2–§6 + parser do `ita/`** (o MCP `ita` não dumpa AST — nota em §10)
- [x] Constitution check (§0.5) sem conflito — P4 (gramática documentada), P11 (parser à mão; ASDL→dart dev-time/commitado), P6, P3
- [x] DoD coerente com CI (conformance de parsing + unit + benchmark de compile-time)

## Nota — validação do parser

- Como no léxico (Fase 1), o parser é validado contra a **spec** (`grammar.ebnf`/`GRAMMAR.md` §2–§6) e o
  **`ast.dart`/`parser.dart` do `ita/`** (referência de comportamento), pois o MCP `ita` executa programas,
  não expõe dump de AST. Explícito na §10.
- O formato exato do dump `.ast` (S-expression determinística) fecha no `/speckit-plan`.

## Resultado

- **Status: `clarified` — todos os itens ✓** (§4/§7.3 N/A justificado: sintaxe não toca tipo/codegen; os
  artefatos formais são `ast.asdl` + `grammar.ebnf` §Syntactic). Pronta para `/speckit-plan`.
