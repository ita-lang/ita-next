---
name: audit-f1-f5-identity-adherence
description: Auditoria de identidade F1–F5 (2026-07-17) — veredito FIEL às ideias iniciais; placar por princípio e a watch-list de F6/F7 onde a visão pode ser traída na frente.
metadata:
  type: project
---

# Auditoria de identidade — F1–F5 (2026-07-17)

**Veredito:** FIEL. Nenhum princípio permanente violado. Placar: P4/P6/P7/P1/P2/P11/P9
honrados COM executor no código; P3 honrado sob RD-1; P5 honrado; P8/P10 ainda não
tangidos (fora do escopo F1–F7). Art. II honrado com tensões de F7 a vigiar.

**Why:** o dono pediu revisão minuciosa de aderência às ideias iniciais. As provas
materiais que dissolvem dúvida (verificadas, não inferidas):
- P4/ADR-0013: `type.dart` separa `TypeVar` (:445, "não sei") de `ErrorType` (:460,
  pós-erro) — SEM `DynamicType` na superfície. `dynamic` só existe como fato de emissão F7.
- P6: `@` erra no lexer — `lex-annotation-unsupported` (`lexer.dart:227`, testado
  `lexer_test.dart:289`, `grammar.ebnf:145`). Inferência sem anotação (bidirecional 009).
- P7: `Try` (o `?`) é nó CORE, baixa em F7 p/ `match => return .err` (013 §7.4e); `panic`
  → Kernel Throw INTERNO, zero `throw` de usuário. O `throw` em `desugar.dart:530` é ICE do
  compilador (StateError), não modelo de erro da linguagem.
- P2: `mut-field-on-struct` emitido (`collect.dart:305`) — struct imutável SEMPRE, o
  alinhamento que a 013 §12-1 exigiu está FEITO.
- P11: sem `build_runner` no `pubspec.yaml` (grep vazio); type-model materializado à mão.
- Art. IV-6 (data não é fonte): TODAS as atribuições ao dono no `lib/` carregam ponteiro
  de artefato (ADR/spec §); conclusões de agente assinam nome; a confissão em
  `type.dart:270-297` preservada como prova. O hábito de fabricar ruling foi corrigido.

**How to apply:** ao ser chamado para W3/revisão de F1–F5, tratar estes como CONFIRMADOS —
não reabrir. Focar a vigilância na frente (F6/F7), abaixo.

## Watch-list F6/F7 (onde a visão pode ser traída na frente)
1. **Box existencial + `any` (ADR-0017 §3, R2 marcado):** o box `Ord$Int` é maquinaria
   invisível — P4 SOB CARGA. É itaiano PORQUE `any` dá glifo à fronteira e P2 nega
   identidade a valor imutável. Mas os **4 canais observáveis** (==, is/match round-trip,
   borda `dart:` desembrulha, erro nunca vaza `Ord$Int`) fecham **por CORPUS, não por
   intuição** — é a doutrina [[doctrine-argumento-de-ausencia]]. Se um canal vazar, P4 quebra.
2. **async/await (013 §12-2, PENDENTE):** a lowering pode ser transformer do CFE que o Itá
   BYPASSA (família da armadilha do mixin). Verificar com `dart-vm-expert` ANTES de
   especificar — senão o `.dill` roda errado em silêncio. É guarda de Art. II ("usa a VM
   sem SER Dart": nenhum transformer do CFE roda — 013 §7.1 INVARIANTE, CA13 negativo).
3. **Sistema de efeitos (ADR-0018, stub `proposed`):** o dono está "REAL inclinado". Quando
   vier, a anotação de efeito NÃO pode virar `@decorator` (P6 veta p/ sempre) — tem de ser
   keyword/forma, como `any` foi. Débito com endereço, não bloqueia nada.
4. **Régua do custo (ADR-0017 §4):** "absorve-se custo onde a alternativa barata esconde
   semântica; cede-se representação onde a observável não muda". Reforça
   [[doctrine-vm-data-reinforces]]: o front-end (decl + semântica observável) é protegido;
   só representação (Grupo B) se cede. Vigiar que F7 não inverta isso.
