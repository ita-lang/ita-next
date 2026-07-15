<!--
================================================================================
 TEMPLATE DE PLAN — Itá (plano de implementação de mudança de compilador)
================================================================================
 Gerado por `/speckit-plan`. Copiado para: specs/<NNN>-<short-name>/plan.md
 Pré-requisito: spec.md aprovada (status ≥ clarified) e Constitution check limpo.

 O plan é o "COMO" técnico — mas de alto nível, sem código. Ele mapeia a spec
 nas FASES do compilador que serão tocadas e nos arquivos reais de
 `compiler/lib/`, e fixa a estratégia de teste (corpus + MCP `ita` + paridade + CI).
 Regra YAGNI: não antecipe o que os CA da spec (§11) não exigem.
 Apague este bloco ao finalizar.
================================================================================
-->

# Plan <NNN>: <título da mudança>

> **Spec:** [`spec.md`](./spec.md) · **Status:** `draft` | `ready` · **Marco:** `<M4 | …>`

## 1. Resumo técnico

<!-- 3-5 frases: o que muda no compilador, por qual caminho, e o resultado observável. -->

## 2. Fases do compilador tocadas (ancoradas na spec)

<!-- Só as fases marcadas na spec §0. Para cada, os arquivos concretos e a mudança. -->

| Fase | Arquivo(s) `compiler/lib/…` | Mudança | Ref. spec |
| :-- | :-- | :-- | :-- |
| Léxico | `lexer/lexer.dart`, `lexer/token.dart` | <…> | §2 |
| Sintaxe | `parser/parser.dart`, `parser/ast.dart` | <…> | §3 |
| Semântica/Tipos | `semantic/type_checker.dart`, `semantic/type_resolver.dart` | <…> | §4 |
| SDD | `semantic/analyzer.dart` | <…> | §5 |
| Codegen | `codegen/codegen.dart` | <…> | §7 |

<!-- Remova as linhas de fase que a spec não toca. -->

## 3. Estratégia por alvo (se toca codegen)

<!-- Como cada alvo passa a se comportar; o que precisa de helper/lowering específico. -->

- **VM (JIT/AOT):** <…>
- **JS (dart2js):** <…> — paridade esperada (MATCH/NUM/…); helper de lowering se necessário.

## 4. Plano de teste (o gate)

- **Corpus de conformância:** casos `.tu` novos derivados dos CA (spec §11) — caminhos em `examples/` / `compiler/test/…`.
- **Testes unitários:** o que cobrir em `compiler/test/`.
- **Validação ao vivo:** via **MCP `ita`** (`compile`/`run`) — comportamento na VM.
- **Paridade VM×JS:** atualizar `compiler/test/js_parity/expected.txt` se o codegen muda.
- **CI:** conformance + unit + **benchmark de compile-time (`itac` AOT, sem regressão)**.

## 5. Ordem de ataque e dependências

<!-- Sequência das fases (ex.: tipo antes de codegen). Marque o que pode ir em paralelo. -->

1. <passo> — depende de: —
2. <passo> — depende de: 1

## 6. Riscos técnicos e mitigações

| Risco | Severidade | Mitigação |
| :-- | :-- | :-- |
| <risco de version-skew de Kernel / paridade / perf> | alta/média/baixa | <…> |

## 7. Constitution check (re-confirmação)

<!-- Reafirma que o COMO não viola nenhum princípio (ex.: nada de codegen em build-time,
     nada de annotation, interop dart: fino e enumerado). Conflito = bloqueio. -->

- Princípios reconfirmados: <lista>. Conflitos: <nenhum | descrever>.

## 8. Artefatos auxiliares (se necessários)

<!-- Notas de design, tabela de casos de conformância, esboço de regra formal.
     NÃO gerar contratos web/data-model — isto é um compilador. Remova se não houver. -->
