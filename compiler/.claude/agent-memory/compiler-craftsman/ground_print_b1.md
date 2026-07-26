---
name: ground-print-b1
description: Passo B1 da F7 — `print` no chão (F4 GroundRes + F5 _groundType); shadowing como escopo-prelúdio por fallback; débito §7.6 destino M5
metadata:
  type: project
---

# B1 — `print` no chão (spec 013 §7.6, ligando o front-end à F7)

Fato: `fn main() { print("olá") }` parava em `unresolved-before-check` (F4 não
resolvia `print`). B1 põe `print` no chão como 1 built-in FECHADO, das duas
pontas. Objetivo: hello passa F1→F6 verde. Débito DECLARADO, não design (mesma
taxonomia do `Ops(+)`, spec 009 §4.9; doutrina do chão = `[[chao-vs-biblioteca]]`
da memória de projeto; irmão do `[[ground-builtins-012a]]`, que é o chão de
MEMBROS, este é o chão de I/O em posição de valor).

**Why:** sem `print` nenhum `.tu` de verdade chega ao emitter B2 — é a menor
superfície de I/O, o que destrava o Passo B inteiro.

**How to apply:** quando mexer em F4 lookup ou F5 `_call`, lembrar que o chão é o
escopo mais externo (fallback), não um `ResolvedName` mágico no `_call`.

## O desenho (o que escolhi, e a alternativa rejeitada)

1. **F4 — variante nova `GroundRes(name)`** em `scope.dart` (sealed). Carrega só
   o `name` (String), NÃO um `AstNode` — não há decl. É a face-NOME.
2. **F4 — prelúdio por FALLBACK, não por Scope real** (`resolver.dart`
   `_lookupIdent`): a cadeia de escopos falha → `return _ground(use.name)`
   (`_groundNames = {'print'}`). Isto É o shadowing Swift: `fn print`/`let print`
   do usuário está no módulo/local, achado ANTES → vence; sem colisão, sem
   `duplicate-declaration` (o chão NUNCA vira `ScopeEntry`).
   - **Rejeitado: prelúdio como `Scope` raiz abaixo do módulo.** Mais "textbook"
     (Dragon 2.7.1, tabela encadeada), mas PIOR: forçaria special-case no
     `binder as AstNode` (l.118) E no `LocalRes` (l.119, ground não é local) —
     MAIS casos, e tentaria contar `hops` através dele. O fallback é mais simples
     E mais honesto: o chão é categoricamente ≠ escopo léxico (zero AST binder).
3. **F5 — face-TIPO `_groundType(name)`** em `check.dart`: tabela FECHADA →
   `print` = `FunctionType.positional([String], Void)`. `_ident` ganha
   `GroundRes r => _groundType(r.name)`. Daí o `_call` consome pelo caminho
   NORMAL: `_synth(callee)` = FunctionType → `_matchArgs` → `_check(arg, String)`
   → não-String vira `type-mismatch` (String-only, zero coerção, ruling §12-4);
   rende Void. **Zero ramo especial no `_call`** — a exigência §7.8/§4.5 (sem
   exceção-não-checada) cai de graça.
4. **Contrato F4×F5 (ADR-0011) EXPLÍCITO:** `_groundNames` (F4) e `_groundType`
   (F5) são as duas faces e não podem divergir. Se divergirem, F5 falha ALTO
   (`else`-error 6.5.2, como o `_topLevelType`), nunca `ErrorType` que
   esconderia bug nosso como erro do usuário.

## Exaustividade tocada (a variante nova cobra os switches sealed)
- `scope.dart formatResolution` → `GroundRes g => '->G${g.name}'` (dump `->Gprint`).
- `check.dart _ident` (tinha `_`; adicionei explícito antes do catch-all).
- `flow.dart _use` (sealed+null, sem default) → `case GroundRes _: break` (não é
  `var` rastreado; como Top/Self).
- `check.dart _assignTarget` (tem `default`) → `print = x` cai em
  `invalid-assign-target`. Correto, sem mudança.

Nenhum golden de conformance muda (só match de "blueprint"; nenhum `print(`).

## Fronteira / handoff
- **NÃO toquei o emitter (B2).** `resolvedCalls[printCall]` fica gravado com o
  FunctionType sintético (sem decl) — o B2 reconhece o callee ground via
  `GroundRes` na `resolution` e emite `print` do `dart:core`. É trabalho do
  `dart-vm-expert`/B2.
- Divergência-de-Swift honesta: Swift faria overload set com o stdlib `print`;
  Itá NÃO tem overload (011 §12-4) ⟹ user `fn print` SOMBREIA por inteiro. É o
  modelo correto pro Itá, forçado pela doutrina no-overload.

Arquivos: `binding/scope.dart` (GroundRes + dump), `binding/resolver.dart`
(_lookupIdent fallback + _ground/_groundNames), `semantic/check.dart` (_ident +
_groundType), `analysis/flow.dart` (_use). Testes: `resolver_test.dart` (grupo
chão), `check_test.dart` (grupo §7.6).
