# Checklist de Qualidade da Spec: Léxico completo + scaffold (Fase 1)

**Propósito**: validar completude da spec da Fase 1 antes de planejar
**Criado**: 2026-07-10
**Spec**: [../spec.md](../spec.md)

## Qualidade do conteúdo

- [x] Segue o `spec-template.md`; fases não tocadas (sintaxe/semântica/codegen) REMOVIDAS; +§S infra
- [x] §1 tem motivação + exemplo **antes → depois** (dump de `itac tokenize`) e não-objetivos
- [x] Prosa PT-BR; identificadores em `backticks`; erros internos EN kebab-case (`lex-unexpected-char`, `lex-unterminated-string`)
- [x] §2 Léxico cita o cap. do Dragon Book (`[cap 3.3]`) + ref. de impl. CI (`scanning.md`)

## Completude da RFC

- [x] Nenhum [NEEDS CLARIFICATION] — o léxico é **bem-definido** pela fonte-da-verdade (`GRAMMAR.md` §1 do `ita/`)
- ~~§4 Especificação formal (regras de tipo)~~ — **N/A**: léxico não toca tipo/semântica. O **artefato formal** do léxico é a `grammar.ebnf` (definições regulares, W3C EBNF — ADR-0010), presente na §Artefato
- ~~§7.3 por alvo (VM/AOT/JS)~~ — **N/A**: léxico é agnóstico de alvo (não toca codegen)
- [x] §2 declara todas as categorias de token de forma não-ambígua (defs regulares 2.1–2.7)
- [x] §9 checklist de completude (Apêndice A — `lexer`) coerente
- [x] Escopo delimitado (só léxico + infra); compat/oracle (§10) registrado
- [x] Sem §8 runtime (léxico não depende da VM)

## Prontidão

- [x] CA1–CA10 testáveis: cada um é um `.tu` → sequência de tokens esperada (ou erro léxico com linha)
- [x] CAs verificáveis por `itac tokenize` + `dart test`; **oracle = spec + léxico do `ita/`** (o MCP `ita` não dumpa tokens — nota em §10)
- [x] Constitution check (§0.5) sem conflito; scanner à mão (P11)
- [x] DoD coerente com CI (conformance de tokenização + unit + benchmark)

## Nota — validação do léxico

- Diferente das specs de codegen (validadas por MCP `ita` run), o léxico é validado contra a **spec**
  (`GRAMMAR.md` §1) e o **`lexer.dart`/`test_lexer.dart` do `ita/`** (referência de comportamento), pois o MCP
  `ita` executa programas, não expõe dump de tokens. Isso está explícito na §10.

## Resultado

- **Status: `clarified` — todos os itens ✓** (§4/§7.3 N/A justificado: léxico não toca tipo/codegen; o
  artefato formal é a `grammar.ebnf`). Pronta para `/speckit-plan`.
