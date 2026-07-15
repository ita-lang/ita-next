# Checklist de Qualidade da Spec: Semântica de largura de `Int` e operações bitwise

**Propósito**: validar completude e qualidade da spec (RFC de linguagem) antes de planejar
**Criado**: 2026-07-10
**Spec**: [../spec.md](../spec.md)

## Qualidade do conteúdo

- [x] Segue o `spec-template.md` (RFC técnico multi-fase); seções de fase não tocadas foram REMOVIDAS (§5 SDD, §6 fluxo removidas; §2/§3 marcadas condicionais a Q2)
- [x] §1 tem motivação + exemplo `.tu` **antes → depois** e não-objetivos
- [x] Prosa em PT-BR; identificadores em `backticks`; erros internos em EN kebab-case (`int-overflow`, `int-literal-out-of-range`)
- [x] Cada fase preenchida cita o capítulo do Dragon Book (§4 `[cap 6.3, 6.5]`, §7 `[cap 6.2, 8.1]`, §8 `[cap 7.1]`)

## Completude da RFC

- [x] Nenhum marcador [NEEDS CLARIFICATION] remanescente — **3 resolvidos** (Q1/Q2/Q3, 2026-07-10; ver §0.6 da spec)
- [x] §4 (Especificação formal) presente — a mudança toca semântica de tipo
- [x] Comportamento por alvo (VM/AOT/JS) declarado em §7.3; paridade VM×JS marcada
- [x] Regras/tipos em notação premissa/conclusão (§4.2)
- [x] §9 checklist de completude (Apêndice A) coerente com as fases tocadas
- [x] Escopo delimitado; compatibilidade/migração (§10) e alternativas descartadas registradas
- [x] Premissas de runtime (§8) declaram apenas dependência da Dart VM, sem reespecificá-la

## Prontidão

- [x] Cada CA de §11 é **testável** e vira caso `.tu` no corpus (CA1–CA6 com saída/erro esperado)
- [x] CAs validáveis ao vivo via MCP `ita` (CA1/CA2/CA4 independem de decisão; CA3/CA5/CA6 dependem de Q1/Q3)
- [x] Constitution check (§0.5) sem conflito com princípio permanente
- [x] Definition of Done coerente com CI (conformance + unit + benchmark)

## Resultado

- **Status: `clarified` — todos os itens ✓.** As 3 clarificações foram resolvidas pelo dono em 2026-07-10 (§0.6 da spec):
  - **Q1** = `Int` 64-bit canônico; JS best-effort documentado (custo zero). → §4.1, §7.3, §10, CA3/CA6.
  - **Q2** = manter só a API `Bits.*`; §2/§3 fora de escopo.
  - **Q3** = wrap silencioso documentado; não-breaking. → §4.5, CA5.
- **Conclusão da mudança:** majoritariamente **documentação normativa** (largura/overflow no `LANGUAGE_SPEC`/`GRAMMAR.md`) + **casos de conformância** que exercitam o gap ≥ 2³¹ (marcados como divergência documentada). Sem mudança de codegen/runtime.
- **Pronta para `/speckit-plan`.**
