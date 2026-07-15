# Checklist de Qualidade da Spec: Completar superfície declarativa da Fase 2

**Propósito**: validar completude e qualidade da spec (RFC de linguagem) antes de planejar
**Criado**: 2026-07-11
**Spec**: [spec.md](../spec.md)

## Qualidade do conteúdo

- [x] Segue o `spec-template.md` (RFC multi-fase); seções de fase não tocadas REMOVIDAS (só §3 tocada; §2/§4/§5/§6/§7/§8 removidas)
- [x] §1 tem motivação + exemplo `.tu` **antes → depois** e não-objetivos
- [x] Prosa em PT-BR; identificadores em `backticks`; erros internos em EN kebab-case
- [x] Cada fase preenchida cita o capítulo do Dragon Book (§3 → cap 4.2–4.3)

## Completude da RFC

- [x] Nenhum marcador [NEEDS CLARIFICATION] remanescente (rulings de dono cravados em §10)
- [x] §4 (Formal) — dispensável: mudança é sintática (não altera regra de tipo); semântica deferida (§3.6)
- [x] Codegen (§7) não tocado — sem paridade VM×JS nesta fase
- [x] Regras declaradas de forma não-ambígua (produções EBNF + variantes de nó)
- [x] §9 checklist coerente com a fase tocada (parser/inter/asdl/grammar/corpus)
- [x] Escopo delimitado (§1 não-objetivos); compat/migração (§10) e alternativas registradas
- [x] Sem premissas de runtime (§8 removida — não depende da VM)

## Prontidão

- [x] Cada CA de §11 é **testável** e vira caso `.tu`→`.ast` no corpus (7 CAs concretos)
- [x] CAs validáveis via `itac parse --dump` (Fase 2 não tem MCP-run; oracle = parser do `ita/`)
- [x] Constitution check (§0.5) sem conflito com princípio permanente (veredito ita-visionary)
- [x] DoD coerente com o CI (conformance + unit + analyze)

## Notas

Todos os itens passam. §4/§7/§8 legitimamente ausentes (mudança sintática pura, sem codegen/runtime).
Pronto para plan → tasks → implement.
