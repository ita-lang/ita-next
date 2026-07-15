# Checklist de Qualidade da Spec: Fase 3 — Desugaring

**Propósito**: validar completude da spec (RFC de fase) antes de implementar
**Criado**: 2026-07-12
**Spec**: [spec.md](../spec.md)

## Qualidade do conteúdo
- [x] Segue o template (fase §5 SDD/desugaring; demais fases removidas)
- [x] §1 motivação + `.tu` antes→depois + não-objetivos
- [x] PT-BR; identificadores em `backticks`; gensym/erros nomeados
- [x] Fundamentação citada (Dragon 5.3, CI 9.5.1) em cada regra

## Completude da RFC
- [x] Sem [NEEDS CLARIFICATION]; rulings de dono cravados (§0.5, §10)
- [x] Catálogo §5.2 completo: cada açúcar → forma canônica + fundamentação
- [x] Fronteiras explícitas (copy-with/currying/`**`/`Try` fora); correção ao ADR-0011 registrada
- [x] Modelo arquitetural decidido (AST→AST canônica, não HIR paralelo) com trade-offs
- [x] Higiene (gensym reservado) e spans tratados como requisitos duros

## Prontidão
- [x] CAs testáveis (11 CAs: dump `.desugar` + idempotência + span)
- [x] Validáveis via `itac desugar --dump` (padrão das Fases 1-2)
- [x] Nós-alvo (`.some`/`.none` pattern, closure, while) confirmados na AST da Fase 2
- [x] Constitution check sem conflito (P4 resolvido: dump expõe a expansão)

## Notas
Ponto de atenção: idempotência (CA10) e span-no-range (CA11) são os invariantes que travam regressão. O `?` é retido como `Try` core — não é açúcar da Fase 3.
