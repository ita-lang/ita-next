---
name: phase7-f7-identity-audit
description: Auditoria de identidade da F7 (codegen) em 2026-07-29 — 8 vereditos + os 3 padrões sistêmicos (ordem funcional invertida, ruling sem artefato, declaração que só existiu na conversa).
metadata:
  type: project
---

# Auditoria de identidade da F7 — 2026-07-29

Provocada pelo dono: *"errou em julgamentos em relação à idealização da linguagem, fez
coisas de qualquer maneira, teve alucinações"*. Auditei 8 decisões de identidade tomadas
pela orquestração durante a emissão (`codegen/lib/emit.dart`, specs/013).

## Vereditos (curtos — o raciocínio está no ADR/spec citado)

1. **`while`/`break`/`continue` — LEGÍTIMO, e não era decisão dele.** Já estava em
   `grammar.ebnf:245,270`, `ast.asdl:91,93,94`, F4 (`resolver.dart:393-395`
   `break-outside-loop`), F6 (`flow.dart:416`) e **spec 013 §7.4-e nomeia `while`**.
   P5 diz *"funcional é o caminho NATURAL"*, não exclusivo; o catálogo não-fazer
   ([[identity-yield-and-nao-fazer]]) nunca listou laço. Gabarito
   `L_break: while (c) { L_cont: { corpo } }` é técnica, não identidade.
2. **`if` de bloco → `IfStatement` — LEGÍTIMO.** RD-1 + `ast.asdl:88` (`IfStmt` ≠ `IfExpr`).
3. **`-7 % 3 = 2` — PRECISA DE RULING DO DONO.** Precedente direto: a **spec 001** existe
   porque *"largura de Int e overflow especificados, não herança silenciosa do Dart"* (P4).
   Ela cobre overflow/`Bits.*` e **não** cobre sinal em `%`/`~/`. Agravante achado:
   `div→~/` (trunca p/ zero) e `mod→%` (Dart nunca dá negativo) ⟹
   `a == (a div b)*b + (a mod b)` **FALHA** (`-7 div 3 = -2`, `-7 mod 3 = 2` ⟹ `-4`).
   Não é semântica a documentar: é **incoerência entre dois operadores da mesma linguagem**.
4. **Restrição do corpo de `init` (só `self.campo = e`) — VIOLAÇÃO.** (i) ⚠️ **âncora
   corrigida em 2026-07-29:** a frase *"`init` **explícito** quando há estado a
   validar/normalizar"* é do **ADR-0012 §A-1** e da **spec 005 §10** (`spec.md:130`) —
   **não** da §3.6 (`spec.md:109-113`, cujos 3 itens são outra coisa). O veredito não muda;
   a citação estava pescada por saliência (R8, cometido por mim). Ver
   [[phase7-init-body-restoration]]; (ii) é ICE sobre programa legal
   ([[doctrine-ice-nao-e-cerca]]); (iii) **a razão real é outra**: `check.dart:293` e `:315`
   têm `case ast.InitDecl(): break;` ⟹ **a F5 NÃO checa corpo de `init`**. A F7 emite de
   subárvore não-tipada, e a premissa da §0.6 ("entrada F5+F6-verde") não vale ali.
5. **`ItaResult` com payload `Object` non-nullable — VIOLAÇÃO (não-provada como sound).**
   Classe é da spec 013 §7.4-c ✅; não-genérica é fatia ✅. Mas **ADR-0013 §3 crava
   `Object?` como o fallback da F7** (*"mesmo lá, `Object?` > `dynamic`"*) e §4 o legitima
   como topo. `Object` non-nullable não representa `Result<String?, E>` — e a linguagem
   TEM `T?`. O comentário afirma *"perde precisão, não soundness"* sem prova.
6. **Nomes sintéticos com `$` — LEGÍTIMO e bem-fundado.** `grammar.ebnf:38-40`:
   `ID_CONT = [A-Za-z0-9_]` ⟹ `$` é **inforjável**; F3 já usa (`desugar.dart:21`,
   *"lexicamente inatingível"*). O `_` do oracle é forjável (`Forma_circulo` é IDENT legal).
   Falta só **registrar** em spec: hoje a convenção só vive em comentário.
7. **`optional-in-interpolation` — regra CERTA, procedimento VIOLADO.** A exceção "para
   debug" é **recusada**: reintroduz `null` (palavra do Dart) na saída de quem escreveu
   `nil` e cria regra dependente de contexto invisível (P4). O fixture empobrecido se
   resolve imprimindo o **desembrulho** (`x ?? "…"` / `match`) — que a fatia de `match`
   já destravou. Mas: **Art. IV-6(a)/(c)** — 3 sítios citam *"ruling do dono, 2026-07-28"*
   com **data e nenhum artefato**, e o ruling não está em spec/ADR nenhum.
8. **Sistêmico — ver abaixo.**

## Os 3 padrões que atravessam tudo (a resposta à acusação do dono)

**A. Ordem invertida contra o P5.** `codegen/lib/emit.dart` tem **zero** `ast.Closure`
(`Closure` existe em `ast.asdl:158`) ⟹ valor-função, `|>`, `>>`, trailing-closure,
currying **não compilam**. E **LT-F7c** (CA de 2+ closures) está `[ ]` em `tasks.md`,
apesar de a própria §"Ordem e gate final" mandá-la **antes do grosso da §7.4**.
Consequência dupla: (1) o subconjunto executável do Itá hoje é *laço imperativo +
mutação*, numa linguagem cujo P5 é funcional-first; (2) o `_LocalFunctionIdAssigner` —
*"a lição mais cara do projeto"* — só é exercido por teste sintético, nunca por programa.

**B. Ruling na voz do dono sem artefato** — reincidência do que o ADR-0014/0016 já
puniu ([[../../../.claude/projects: nao-escrever-na-voz-do-dono]]). Sítios:
`check.dart:829`, `option_nullable.tu:8`, `check_test.dart:1989`.

**C. Declaração que só existiu na conversa.** `plano-auditoria.md` §Status está **vazio**
(os lotes rodaram — os fixtures existem); `arith_int.tu` só tem `7 % 2`; `tasks.md` não
tem LT para a auditoria (para em LT-F7n). Logo *"comportamento a documentar"* não
documentou nada ([[doctrine-declaracao-sobrevive-ao-tick-verde]]).

## Fila que ficou para o dono
`%`/`~/` com negativos (par coerente: truncado × floored × euclidiano) · corpo de `init`
(o que o Itá garante de ordem/validação) · assentar `optional-in-interpolation` em
spec 009/010 §12-N.

**Relacionadas:** [[doctrine-ice-nao-e-cerca]], [[audit-f1-f5-identity-adherence]],
[[identity-yield-and-nao-fazer]], [[doctrine-declaracao-sobrevive-ao-tick-verde]].
