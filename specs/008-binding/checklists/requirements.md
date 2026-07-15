# Checklist de Qualidade da Spec: Fase 4 — Binding

**Propósito**: validar a spec (RFC de fase) antes de implementar
**Criado**: 2026-07-12
**Spec**: [spec.md](../spec.md)

## Qualidade do conteúdo
- [x] Segue o template (fase §5 SDD/atributos; demais removidas)
- [x] §1 motivação + `.tu` antes→depois + não-objetivos
- [x] PT-BR; identificadores em `backticks`; erros EN kebab-case
- [x] Fundamentação citada (CI cap 11, Dragon 1.6/2.7/5)

## Completude da RFC
- [x] Sem [NEEDS CLARIFICATION]; rulings de identidade cravados (§0.5) e de escopo de fase decididos (§5.5)
- [x] Estrutura da side-table decidida (nó-binder + hops; por identidade) com trade-off vs Lox
- [x] Contrato F4↔F5 preciso (§5.4) — honra ADR-0011
- [x] Erros de binding enumerados com fase (F4 vs F5/F6)
- [x] Riscos (guard-let continuação, self, gensyms, ordem 3→4→5) tratados

## Prontidão
- [x] CAs testáveis (12 CAs: `.resolve` + `.errors`)
- [x] Validáveis via `itac resolve --dump` (padrão das Fases 1-3)
- [x] AST imutável preservada (side-table, ADR-0004) — não anota nós
- [x] Constitution check sem conflito (namespace unificado = P4)

## Notas
Ponto de atenção: o `guard let` como escopo de continuação e o letrec de módulo (forward-ref) são os casos que mais divergem do "bloco cria escopo" padrão — CA3 e CA10 os travam.
