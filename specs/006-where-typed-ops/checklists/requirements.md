# Checklist de Qualidade da Spec: where-expr + operadores tipados

**Propósito**: validar completude da spec (RFC) antes de planejar
**Criado**: 2026-07-11
**Spec**: [spec.md](../spec.md)

## Qualidade do conteúdo
- [x] Segue o template; fases não tocadas removidas (só §3 + §5)
- [x] §1 motivação + `.tu` antes→depois + não-objetivos
- [x] PT-BR; identificadores em `backticks`; erros EN kebab-case (`where-binding-not-let`)
- [x] Fases citam Dragon Book (§3 → 4.2–4.3; §5 → 5.1)

## Completude da RFC
- [x] Nenhum [NEEDS CLARIFICATION]; ruling de dono (`where` puro) cravado em §10
- [x] §4 dispensável — mudança sintática/modelagem, não altera regra de tipo; semântica deferida (§3.6)
- [x] Codegen não tocado; §7-nota deixa claro que é preparação Fase 3
- [x] Regras não-ambíguas (produções + variantes de enum listadas)
- [x] Escopo delimitado; alternativas descartadas registradas

## Prontidão
- [x] CAs testáveis (5 CAs: `.tu`→`.ast`, `// EXPECT`, unit de exaustividade)
- [x] CA4 exige goldens antigos INALTERADOS (invariante de migração)
- [x] Constitution check (§0.5) sem conflito
- [x] DoD coerente com CI

## Notas
Ponto de atenção crítico: a migração de operadores para enum NÃO pode mudar o dump — CA4 e a DoD travam "goldens 001–005 inalterados".
