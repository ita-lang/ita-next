# Grammar delta — Fase 2 (Sintaxe → AST) · spec 004

> **Phase 1 do `/speckit-plan` (surface delta).** Declara a **seção "Syntactic grammar"** que a Fase 2
> acrescenta ao `ita-next/compiler/docs/spec/grammar.ebnf` (abaixo da "Lexical grammar" da Fase 1), em
> **W3C EBNF** (ADR-0010), reconciliada com o `GRAMMAR.md` §2–§6 do `ita/` (fonte **normativa** de sintaxe).
> **Não recopia** o `GRAMMAR.md`; declara a **disciplina de tradução**, os **apertos/consertos** (§0.6) e os
> **deltas tree-sitter**. As produções completas em W3C EBNF são **entregues na Fatia 3** (o arquivo
> `grammar.ebnf` §Syntactic); aqui fica o contrato.

---

## 1. Disciplina de tradução (`GRAMMAR.md` "EBNF-ish" → W3C EBNF)

| Aspecto | `GRAMMAR.md` §2–§6 | `grammar.ebnf` §Syntactic (W3C EBNF) |
| :-- | :-- | :-- |
| Definição | `=` | `::=` |
| Terminais | `"fn"`, `IDENT` | `"fn"`, `IDENT` (mesmos; `IDENT`/`INT`/… vêm da seção Lexical) |
| Precedência de expressão | **fora da EBNF** (tabela de binding-power §4.2) | **igual** — a EBNF traz só o esqueleto (`expression`/`unary`/`postfix`/`primary`); a escada de 13 níveis vive na tabela §4.2, **referenciada** em comentário (P4: forçá-la na EBNF geraria a "torre ilegível" que o próprio `GRAMMAR.md` recusa) |
| Regex de terminal | `/…/` | classes W3C (`[a-z]`, `#xN`, `A - B`) — já na seção Lexical |
| Comentário | `//` / nota | `(* … *)` |

**Invariante:** onde o `grammar.ebnf` **APERTA** o `GRAMMAR.md` (conserta um débito), a divergência é
**anotada em comentário** na produção — mesma convenção da seção Lexical (Fase 1).

---

## 2. Produções-âncora (esqueleto W3C EBNF)

Tradução direta do `GRAMMAR.md` §2–§6 (referência; o arquivo final detalha cada não-terminal):

```ebnf
program        ::= declaration* "eof"

declaration    ::= "pub"? topLevelDecl
                 | statement
topLevelDecl   ::= fnDecl | "async" fnDecl | "stream" fnDecl
                 | actorDecl | structDecl | classDecl | enumDecl
                 | traitDecl | implDecl | extensionDecl | importDecl | operatorDecl

(* Expressão: esqueleto; a precedência real está na tabela de binding-power §4.2. *)
expression     ::= assignment ( "where" "{" statement* "}" )?
unary          ::= ( "!" | "-" | "~" ) unary
                 | ( "await" | "spawn" ) unary            (* §0.6 Q4 — ver §3.2 *)
                 | postfix
postfix        ::= primary postfixOp*
postfixOp      ::= "(" argList ")" trailingClosure?       (* trailing: MESMA LINHA — ver §3.4 *)
                 | "." "{" copyField ( "," copyField )* "}"
                 | "." INT
                 | "." IDENT trailingClosure?
                 | "?." IDENT
                 | "[" expression "]"
                 | "!" | "?"
primary        ::= "async" closure
                 | "panic" "(" expression ")"
                 | "await" "race" "(" exprList ")"
                 | "await" "all" "(" exprList ")"
                 | INT | FLOAT | STRING | MULTILINE_STRING
                 | "true" | "false" | "nil" | IDENT | "self"
                 | parenOrClosure | listLiteral | mapLiteral | matchExpr | ifExpr
                 | "." IDENT ( "(" ( expression ( "," expression )* )? ")" )?

type           ::= "mut" type
                 | "async" type
                 | "(" ( type ( "," type )* ","? )? ")" ( "->" type )? "?"?
                 | IDENT ( "<" type ( "," type )* ">" )? "?"?
pattern        ::= "_" | enumPat | listPat | structPat | rangeOrLit | IDENT
```

> `STRING` na §Syntactic **não** é opaca: expande para `strPart*` (partes ordenadas — §3.5 abaixo), pois a
> Fase 2 parseia a interpolação em parse-time.

---

## 3. Apertos/consertos sobre o `GRAMMAR.md` (§0.6) — anotados na EBNF

Cada um vira um comentário `(* APERTA §… : … *)` na produção correspondente.

### 3.1 `pub` sem sentido → erro (Q3)
```ebnf
(* APERTA §2: "pub" é ERRO em impl/extension/import/operator (parse-error: meaningless-pub).
   O GRAMMAR.md consome-e-ignora; o ita-next rejeita. Válido só em fn/struct/class/enum/trait. *)
declaration    ::= "pub"? topLevelDecl | statement
```
A EBNF não expressa a restrição (é semântica de posição); fica como **error production** no parser + nota.

### 3.2 `await`/`spawn` no nível unário (Q4)
`GRAMMAR.md` §4.1 lista `await`/`spawn` em `primary` (ligam à direita, guloso no oracle). A §Syntactic
**move-os para `unary`** (ligam no nível 12), consertando `await a + b` = `(await a) + b`:
```ebnf
unary          ::= ( "!" | "-" | "~" ) unary
                 | ( "await" | "spawn" ) unary            (* APERTA §4.2: prefixos ligam no unário, não gulosos *)
                 | postfix
```
`await race(…)`/`await all(…)`/`panic(…)`/`async`-closure continuam em `primary` (têm delimitador próprio).

### 3.3 Range não-associativo (CA10)
```ebnf
(* APERTA §4.2 (nível 8, não-assoc): a..b..c é parse-error: range-non-associative.
   O GRAMMAR.md marca "não-assoc" mas o oracle não emite o erro; o ita-next emite. *)
rangeExpr      ::= addition ( ( ".." | "..=" ) addition )?    (* NO máx. 1 operador de range *)
```

### 3.4 Trailing-closure exige mesma linha (CA13) + supressão na condição (CA21)
Não é expressável em CFG pura — é **estado de parser** (documentado, não gramatical):
```ebnf
trailingClosure ::= block
(* CONTEXTO (não-CFG): "block" só vira trailing-closure se o "(" / "." estiver na MESMA LINHA do
   operando (usa Token.line). Na CONDIÇÃO de if/while/for/match a trailing-closure é SUPRIMIDA
   (o "{" abre o corpo); "guard" NÃO suprime (assimetria §0.6). O oracle tem bug: não checa linha
   em f(args){} — o ita-next conserta. *)
```

### 3.5 Interpolação em parse-time (CA20)
```ebnf
(* APERTA §1: STRING expande para partes ordenadas em parse-time (não deferida ao codegen). *)
stringExpr     ::= '"' strPart* '"'
strPart        ::= STRING_CHUNK                            (* trecho literal, escapes já decodificados *)
                 | "${" expression "}"                     (* interpolação — só em STRING, não MULTILINE *)
```

### 3.6 Bloco-nu não é expressão (Q1)
`BlockExpr` **removido**. `block` só aparece em posição de statement / corpo / trailing-closure — **nunca**
como alternativa de `primary`. A EBNF de `primary` (§2) **não lista** `block`. O `{` em posição de
expressão só pode ser `mapLiteral` ou `trailingClosure` (§3.4).

---

## 4. Deltas tree-sitter (Apêndice A do `GRAMMAR.md`) — **registrados**

A gramática `tree-sitter-ita` é **derivada** (o parser é normativo). Esta fase **registra** os deltas; a
correção no repo `tree-sitter-ita` é trabalho separado (não bloqueia a Fase 2):

| Área | Divergência tree-sitter | Ação registrada |
| :-- | :-- | :-- |
| Precedência | binários achatados num nível único | alinhar à escada §4.2 (13 níveis) |
| Construções | faltam map literal, tuplas, async closure, `static fn`, `?.`, `await race`, force-unwrap `!` | adicionar |
| Rigidez | struct forçava campos-antes-métodos; class 1 conformance; `var` sem destructure | flexibilizar |
| `>>` | tratado como binário genérico | marcar como **compose** (nunca shift) |
| `break`/`continue` | ausentes | adicionar (já implementados no compilador — M2) |
| **novos (Fase 2)** | — | registrar `meaningless-pub`, range não-assoc, `await`/`spawn` unário, interpolação com partes, bloco-nu não-expr |

---

## 5. Reconciliação e escopo

- **Artefato final:** `ita-next/compiler/docs/spec/grammar.ebnf` ganha a seção **"7.5 → 8. SYNTACTIC
  GRAMMAR"** (numeração após a Lexical), com as produções completas + os comentários de aperto acima.
  Entregue na **Fatia 3** (Declarações & reconciliação).
- **Fonte-da-verdade:** o **parser** (`ast.dart`/`parser.dart` do `ita-next`) é normativo; `grammar.ebnf` e
  tree-sitter são **derivados/reconciliados**. Precedência da constituição: `GRAMMAR.md` (§2–§6) rege a
  forma; onde a Fase 2 **conserta** um débito, o golden (`conformance-cases.md`) e o comentário EBNF marcam.
- **Fora de escopo:** railroad diagrams (opcional, ADR-0010) e a correção no repo `tree-sitter-ita` — podem
  vir depois sem bloquear o DoD da 004.
