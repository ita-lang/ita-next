// ===========================================================================
// check.dart — Fatia B da Fase 5: Check bidirecional (spec 009 §4.3/§4.4/§5.4-B).
// ===========================================================================
//
// Materialização À MÃO da spec `009-semantic-types` (P11 / ADR-0010).
//
// BIDIRECIONAL, e isso está NO LIVRO — não é preferência (§4.4):
//  • **6.5.1** já parte o mundo nos dois modos: *"A verificação de tipo pode
//    assumir duas formas: síntese e inferência. A síntese constrói o tipo de uma
//    expressão a partir dos tipos de suas subexpressões … A inferência determina
//    o tipo de uma construção a partir do modo como ela é usada."* = synth/check.
//  • **Ex. 6.5.2** descreve o algoritmo literalmente: *"sintetizar … de baixo
//    para cima e, quando o tipo único da expressão geral for determinado,
//    prossiga de cima para baixo"*.
//  • **5.1.1** dá a mecânica e AUTORIZA: atributo sintetizado (filhos→pai) vs
//    herdado (pai/irmãos→filho), e *"permitimos que um atributo sintetizado no
//    nó N seja definido em termos dos atributos HERDADOS do próprio N"*.
//  • **5.2 (L-atribuída)** é por que roda em **1 walk**, sem ponto-fixo.
//
// HM foi recusado (§4.4) — 6.5.4 é para ML, *"que não exige que os nomes sejam
// declarados"*; o Itá anota a borda (§0.5-1: dentro infere, borda anota).
//
// O MODO `check` É A IMPLEMENTAÇÃO DO INVARIANTE DE NULIDADE: `nil` não
// SINTETIZA — só se checa contra `T?` (§4.6). O `NilType` do oracle é o sintoma
// de não haver modo checking.
//
// Falha de inferência é **`cannot-infer`** (ADR-0013) — nunca `dynamic`.
// ===========================================================================

import 'package:ita_next_compiler/frontend/binding/scope.dart';
import 'package:ita_next_compiler/frontend/parser/ast.dart' as ast;
import 'package:ita_next_compiler/frontend/semantic/collect.dart';
import 'package:ita_next_compiler/frontend/semantic/type.dart';
import 'package:ita_next_compiler/frontend/semantic/type_table.dart';
import 'package:ita_next_compiler/frontend/semantic/unify.dart';

/// Assinaturas dos operadores primitivos — o `Ops(sym)` do §4.3.
///
/// ⚠️ **DÉBITO declarado, não design** (clarify 2026-07-15, ruling do dono). É a
/// mágica que o §4.9 acusa: o compilador sabendo de assinaturas que nenhum código
/// Itá escreveu. Hoje é inevitável — a stdlib **não declara** `operator +` (zero
/// ocorrências) e no oracle `Int+Int` é `k.Name('+')` cru no codegen
/// (`codegen.dart:3006`). **Destino: migrar para `.tu` no M5** (des-Dartificação),
/// cumprindo o MANIFESTO §Norte. A migração é localizada: `Ops(sym)` perde o ∪.
///
/// Match **EXATO** — sem coerção (§4.5) não há ranking nem "melhor match"
/// (§4.9). Zero coerção também mantém o Itá **fora do `num`** do Dart, que é
/// onde o unboxing morre (§4.5, reforço de backend).
final Map<ast.BinaryOp, List<(Type, Type, Type)>> _primitiveOps = {
  ast.BinaryOp.add: const [
    (IntType(), IntType(), IntType()),
    (FloatType(), FloatType(), FloatType()),
    (StringType(), StringType(), StringType()), // concatenação
  ],
  ast.BinaryOp.sub: const [
    (IntType(), IntType(), IntType()),
    (FloatType(), FloatType(), FloatType()),
  ],
  ast.BinaryOp.mul: const [
    (IntType(), IntType(), IntType()),
    (FloatType(), FloatType(), FloatType()),
  ],
  ast.BinaryOp.div: const [
    (IntType(), IntType(), IntType()),
    (FloatType(), FloatType(), FloatType()),
  ],
  ast.BinaryOp.mod: const [
    (IntType(), IntType(), IntType()),
    (FloatType(), FloatType(), FloatType()),
  ],
  ast.BinaryOp.pow: const [
    (IntType(), IntType(), IntType()),
    (FloatType(), FloatType(), FloatType()),
  ],
};

/// Comparações: operandos de tipo **idêntico** → `Bool` (§4.8
/// `comparison-type-mismatch`). Coerente com join=identidade + zero coerção:
/// `1 == "a"` é erro.
const _comparisonOps = {
  ast.BinaryOp.eq,
  ast.BinaryOp.ne,
  ast.BinaryOp.lt,
  ast.BinaryOp.gt,
  ast.BinaryOp.le,
  ast.BinaryOp.ge,
};

/// `&&`/`||` exigem **exatamente** `Bool` — sem truthy (§4.8 `not-bool`).
const _logicalOps = {ast.BinaryOp.and, ast.BinaryOp.or};

/// Roda as fatias A **e** B sobre a AST canônica (pós-desugar, pós-bind).
CheckResult checkTypes(
  ast.Program program,
  Map<ast.AstNode, ResolvedName> resolution,
) {
  final (collector, collected) = runCollector(program);
  final c = Checker(collector, collected, resolution);
  c.run(program);
  // `collector.errors` (a lista VIVA), não `collected.errors` (o snapshot da
  // fatia A): o checker faz o collector resolver as anotações que A2 não viu (as
  // de `let`/`var`), e essas podem gerar `unknown-type`/`redundant-optional`
  // NOVOS. Ler o snapshot os perderia em silêncio.
  final errors = [...collector.errors, ...c.errors]
    ..sort((a, b) => a.offset.compareTo(b.offset));
  // As tabelas do checker SAEM daqui. Antes o `Checker` era descartado nesta
  // linha, levando junto `exprTypes`/`resolvedMembers`/`binderTypes`: a F5
  // computava o contrato da F7 e o jogava fora.
  return CheckResult(
    program,
    collected.types,
    errors,
    collected.annotations,
    exprTypes: c.exprTypes,
    resolvedMembers: c.resolvedMembers,
    resolvedCalls: c.resolvedCalls,
    binderTypes: c.binderTypes,
  );
}

class Checker {
  /// A fatia A. Além da tabela, o **resolvedor de anotações**: A2 só percorre
  /// assinaturas, então o `String` de `let x: String = e` só é resolvido aqui.
  final Collector _collector;
  final CollectResult _collected;
  final Map<ast.AstNode, ResolvedName> _resolution;
  final List<CheckError> errors = [];

  /// `<Expr, Type>` — side-table nº1 (§7). Consumidores: F7 (Kernel tipado — a
  /// alavanca do ADR-0007) e F6. **Totalidade** é invariante (§7-4): todo nó de
  /// expressão tem entrada, e `typeOf` FALHA se não tiver — o oracle faz
  /// `?? const UnknownType()`, um default que esconde buraco.
  final Map<ast.Expr, Type> exprTypes = Map.identity();

  /// `<Member, ResolvedMember>` — **side-table nº3** (§7): *"a F5 não produz só
  /// tipos: produz **resolução**"*. É o que a F7 lê para emitir `InstanceGet`/
  /// `InstanceInvocation` com o `interfaceTarget` — que o Kernel exige
  /// (non-nullable `Reference`), sob pena de cair em `DynamicGet`.
  final Map<ast.Member, ResolvedMember> resolvedMembers = Map.identity();

  /// `<Call, ResolvedCall>` — **side-table nº5** (§7): slot, type-args e a
  /// assinatura substituída. Vê [ResolvedCall] para por que cada um é
  /// irrecuperável do lado da F7.
  final Map<ast.Call, ResolvedCall> resolvedCalls = Map.identity();

  /// Tipo de cada binder (param/`let`), para o `Ident` resolver — e **side-table
  /// nº6** (§7): `VariableDeclaration.type` é non-nullable no Kernel, e sem esta
  /// tabela a F7 só teria `dynamic` para pôr ali (ADR-0013 o proíbe). Não é
  /// derivável de [exprTypes]: destructuring, param de closure inferido,
  /// `guard let` e binder de arm não têm nó de expressão que carregue o tipo.
  final Map<Object, Type> binderTypes = Map.identity();

  /// Tipo de retorno da fn corrente — o `Try` (`?`) é regra **não-local**
  /// (§5.4): exige que a fn envolvente retorne `Result<_,E>`.
  Type? _currentFnReturn;

  Checker(this._collector, this._collected, this._resolution);

  TypeTable get _types => _collected.types;

  void run(ast.Program p) {
    for (final node in p.body) {
      if (node is ast.Decl) _decl(node);
      if (node is ast.Stmt) _stmt(node);
    }
  }

  // --- declarações ---------------------------------------------------------

  /// ⚠️ **Switch EXAUSTIVO — nunca `default`.** [ast.Decl] é `sealed`, e isso é
  /// exaustividade de graça: o analyzer cobra o case que faltar. A versão
  /// anterior tinha `default: break` e **engoliu QUATRO decls em silêncio** —
  /// `ExtensionDecl`, `ImplDecl`, `OperatorDecl` e `InitDecl`. O `resolver.dart`
  /// (`_topDecl`, l.186) sempre foi exaustivo: **mesma base, duas políticas** —
  /// a F4 pegaria uma decl nova, a F5 a engolia.
  ///
  /// É a MESMA lição da spec 006, na mesma base: lá o `op:string` virou enum
  /// fechado porque *"perde exaustividade — esquecer `??` compilava mudo"*. Foi
  /// paga no parser e desfeita aqui.
  ///
  /// **Não-objetivo DECLARADO vira escopo; não-declarado vira buraco.** Por isso
  /// cada `break` abaixo diz de quem é.
  void _decl(ast.Decl d) {
    switch (d) {
      case ast.FnDecl n:
        _fnDecl(n);
      // Os `<T>` do TIPO em escopo enquanto se checa os membros dele.
      //
      // ⚠️ Sem isto, `struct Box<T> { fn get() -> T => self.v }` dava
      // `unknown-type` no próprio `T`: o **collect** resolvia (ele empurra o
      // escopo), mas o **checker RE-RESOLVE** as anotações (`_annotated`) e não
      // empurrava nada. Campo funcionava (o checker não o re-resolve); método,
      // não. ⟹ **método de tipo genérico nunca funcionou** — mesma classe do bug
      // de `fn` genérica achado na fatia C.
      case ast.StructDecl n:
        _withGenerics(n, n.generics, () => _members(n.members));
      case ast.ClassDecl n:
        _withGenerics(n, n.generics, () => _members(n.members));
      case ast.EnumDecl n:
        _withGenerics(n, n.generics, () => _members(n.members));
      case ast.TraitDecl n:
        _withGenerics(n, n.generics, () => _members(n.members));
      case ast.ActorDecl n:
        _members(n.members); // `actorDecl` não tem genericParams na gramática
      // **spec 011** — `extension`/`impl` contribuem para a tabela do ALVO, e
      // o corpo deles vê os generics DELE (*"extension é o corpo do tipo,
      // escrito noutro lugar — vê o que o corpo vê"*).
      case ast.ExtensionDecl n:
        _contributionBody(n.target, n.members);
      case ast.ImplDecl n:
        _contributionBody(n.target, n.members);
      // **spec 012** — `OperatorDecl` traz overload ⟹ Ex. 6.5.2 (dois percursos)
      // ⟹ ameaça o 1-walk da §5.2. Item próprio, de propósito.
      case ast.OperatorDecl():
        break;
      // **spec 011** — o `init` memberwise é DESTA fase, não da F3.
      //
      // ⚠️ A spec 005 §3.6 diz *"a política por-kind … é da **Fase 3**"*, e eu
      // li isso como "desugar". **Errado — é numeração VELHA** (a 005 é de
      // 2026-07-11; o ADR-0011, que numerou 3=Desugaring / 5=Semântica, é de
      // 2026-07-10). As palavras dela são inequívocas: o título da §3.6 é *"O
      // que sobra para a **SEMÂNTICA**"*, o subtítulo é *"deferidas ao
      // **binder/type-checker**"*, e os vizinhos na mesma lista são *"deve ser
      // `Bool`"* e *"traits devem ser traits"* — type-checking puro, que o
      // desugar (type-agnostic) não faz. A spec 007 nunca o reivindicou.
      case ast.InitDecl():
        break;
      // Sem corpo de VALOR a checar aqui.
      case ast.FieldDecl():
      case ast.ImportDecl():
      case ast.ErrorDecl():
        break;
    }
  }

  /// Idem: exaustivo sobre `sealed`. Ver a nota de [_decl].
  void _members(List<ast.Decl> ms) {
    for (final m in ms) {
      switch (m) {
        case ast.FnDecl n:
          _fnDecl(n);
        case ast.FieldDecl n:
          // Default de campo: checa contra o tipo anotado (§4.4 — campo anota).
          if (n.defaultValue != null) {
            _check(n.defaultValue!, _annotated(n.type));
          }
        // **F3** (ver [_decl]).
        case ast.InitDecl():
          break;
        // **spec 012** (ver [_decl]).
        case ast.OperatorDecl():
          break;
        // Aninhados dentro de um corpo de tipo: a gramática de `typeBody` não os
        // admite (`member ::= "pub"? (fnDecl | initDecl | field)`), então são
        // inalcançáveis. Listados porque `sealed` cobra — e é o ponto.
        case ast.StructDecl():
        case ast.ClassDecl():
        case ast.EnumDecl():
        case ast.TraitDecl():
        case ast.ActorDecl():
        case ast.ExtensionDecl():
        case ast.ImplDecl():
        case ast.ImportDecl():
        case ast.ErrorDecl():
          break;
      }
    }
  }

  void _fnDecl(ast.FnDecl n) {
    // Os `<T, U>` da PRÓPRIA fn em escopo enquanto se resolve a assinatura e o
    // corpo — senão `fn mapa<T, U>(xs: List<T>)` dá `unknown-type` no `T`.
    _collector.pushGenericScope(n, n.generics);
    _fnDeclInner(n);
    _collector.popGenericScope();
  }

  void _fnDeclInner(ast.FnDecl n) {
    // **Borda anota** (§0.5-1/§4.4): param sem tipo é `missing-param-annotation`
    // — a gramática NÃO fecha isso (`Param.type` é `TypeNode?`), então é a F5.
    // Escopado a declaração NOMEADA: `Closure.params` DEVE inferir do contexto.
    for (final p in n.params) {
      if (p.type == null) {
        _errAt('missing-param-annotation', p.offset, p.length);
        binderTypes[p] = const ErrorType();
      } else {
        binderTypes[p] = _annotated(p.type!);
      }
      if (p.defaultValue != null) {
        _check(p.defaultValue!, binderTypes[p]!);
      }
    }
    if (n.body == null) return; // assinatura de trait: só os defaults

    // `-> T` ausente = **Void** ("não rende valor"), nunca "infira pra mim"
    // (§4.4/§4.8): `fn f() => 5` cai em `type-mismatch` de graça.
    final ret = n.returnType == null
        ? const VoidType()
        : _annotated(n.returnType!);
    final saved = _currentFnReturn;
    _currentFnReturn = ret;
    _fnBody(n.body!, ret);
    _currentFnReturn = saved;
  }

  void _fnBody(ast.FnBody b, Type ret) {
    switch (b) {
      case ast.ExprBody n:
        if (ret is VoidType) {
          _synth(n.e); // corpo-expressão de fn Void: só tipa, não compara
        } else {
          _check(n.e, ret);
        }
      case ast.BlockBody n:
        _block(n.b);
    }
  }

  // --- statements ----------------------------------------------------------

  void _stmt(ast.Stmt s) {
    switch (s) {
      case ast.LetStmt n:
        _letStmt(n);
      case ast.ReturnStmt n:
        if (n.value != null) {
          _check(n.value!, _currentFnReturn ?? const ErrorType());
        }
      case ast.ExprStmt n:
        final t = _synth(n.expr);
        // **must-use = ERRO** (§0.5-6, ruling do dono): `Result` descartado no
        // chão é exceção não-checada com passos extras — pior que try/catch,
        // porque um throw ao menos é alto. Foi o arrependimento nº1 do Rust ter
        // feito warning; o Itá é mais estrito porque P7 é princípio PERMANENTE,
        // não convenção de biblioteca. O escape é explícito e greppável:
        // `let _ = f()` (o `_` é `WildcardPattern` — não passa por aqui).
        //
        // NÃO se estende a `Option`: ausência não é erro; inutilidade é
        // dead-code (F6).
        if (t is BuiltinType && t.kind == BuiltinKind.result) {
          _err('unused-result', n.expr);
        }
      case ast.BlockStmt n:
        _block(n.block);
      case ast.IfStmt n:
        _checkCondition(n.cond);
        _block(n.then);
        if (n.orElse != null) _else(n.orElse!);
      case ast.WhileStmt n:
        _checkCondition(n.cond);
        _block(n.body);
      case ast.GuardStmt n:
        _checkCondition(n.cond);
        _block(n.orElse);
      case ast.GuardLetStmt n:
        _guardLet(n);
      case ast.EmitStmt n:
        _synth(n.value);
      case ast.ForStmt _:
        // **Ruling §12-D da spec 011 (dono, 2026-07-15): não tipar, e DIZER.**
        // Tipar o binder exigiria a tabela `List<T>→T`, que o **§12-4 da 009**
        // recusou como *"a mágica que §4.5/§8.3 recusam"* — e o ruling do chão
        // (§12-2 da 010) **NÃO o revoga**: são tabelas diferentes (o chão são
        // membros/operadores; `for` é contrato de ITERAÇÃO, e o §4.6.1 não o
        // lista). O `for` é, aliás, o **exemplo canônico** da doutrina do
        // privilégio: *"o `MyType` dele nunca ganha `for`, e nenhuma linha de
        // Itá conserta"*. O protocolo de iteração é **M5** (ADR-0012 §C-9).
        //
        // Até lá: **erro declarado**. A §12-4 já dizia em texto *"até lá,
        // `itac check` é incompleto para `for`"* — o código não dizia. Agora diz.
        _errAt('for-binder-unsupported', s.offset, 3); // `for`
      // Sem tipo a atribuir: `break`/`continue` não rendem valor, e o
      // `ErrorStmt` já foi reportado pelo parser (M2). **Listados, não
      // engolidos** — ver a nota de [_decl] sobre o `default` que sumiu.
      case ast.BreakStmt():
      case ast.ContinueStmt():
      case ast.ErrorStmt():
        break;
    }
  }

  void _else(ast.Else e) {
    switch (e) {
      case ast.ElseIf n:
        _stmt(n.ifStmt);
      case ast.ElseBlock n:
        _block(n.block);
    }
  }

  void _block(ast.Block b) {
    for (final s in b.stmts) {
      _stmt(s);
    }
  }

  /// Condição de `if`/`while`/`guard` exige **exatamente** `Bool` — sem truthy
  /// (§4.8 `not-bool`). *"O Itá não tem coerção truthy/falsy"* — nullity-invariant.
  void _checkCondition(ast.Expr e) {
    final t = _synth(e);
    if (t is! BoolType && t is! ErrorType) _err('not-bool', e);
  }

  void _letStmt(ast.LetStmt n) {
    // `let` exige `= e` (parser: `let-requires-value`); `var` pode ser slot.
    if (n.value == null) {
      final t = n.type == null ? const ErrorType() : _annotated(n.type!);
      if (n.type == null) _err('cannot-infer', n); // `var z` nu (§12-7)
      _bindPattern(n.target, t);
      return;
    }
    if (n.type != null) {
      // Anotado: o valor CHECA contra a anotação — é aqui que
      // `let x: String = nil` vira `nil-under-non-optional` (o MANDATO da fase).
      final declared = _annotated(n.type!);
      _check(n.value!, declared);
      _bindPattern(n.target, declared);
    } else {
      // Sem anotação: SINTETIZA (§4.4 — `let` local infere).
      final t = _synth(n.value!);
      _bindPattern(n.target, t);
    }
  }

  /// `guard let v = opt else {…}` — **DESESTRUTURAÇÃO, não narrowing** (§4.6):
  /// `v` é binder NOVO com o payload; `opt` continua `T?`, intocado. Cai da regra
  /// de tipo do pattern; não precisa de máquina de fluxo.
  void _guardLet(ast.GuardLetStmt n) {
    final subject = _synth(n.value);
    if (subject is OptionalType) {
      _bindPattern(n.target, subject.inner); // o NOME NOVO é a honestidade (P4)
    } else if (subject is! ErrorType) {
      _err('guard-let-on-non-optional', n.value);
      _bindPattern(n.target, const ErrorType());
    }
    if (n.condition != null) _checkCondition(n.condition!);
    _block(n.orElse);
  }

  /// Liga os binders de um pattern contra o tipo do escrutínio.
  ///
  /// ⚠️ **Switch EXAUSTIVO — `Pattern` é `sealed`.** A versão anterior tinha
  /// `default: break` e engolia **8 das 10 variantes**: o binder ficava sem
  /// tipo, virava `ErrorType` no `_ident`, e o `ErrorType` é absorvente ⟹
  /// **`match e { .a(v) => v + "string" }` passava SEM ERRO**. É a mesma doença
  /// do `_decl`/`_stmt`/`_topLevelType`: catch-all sobre `sealed`.
  ///
  /// A informação de que isto precisa — variantes e campos — **é a `record(t)`
  /// (6.3.6) que a fatia A já construiu**. Por isso é desta spec: mesma tabela
  /// do `_member`.
  void _bindPattern(ast.Pattern p, Type t) {
    switch (p) {
      case ast.BindPattern _:
        binderTypes[p] = t;
      case ast.WildcardPattern _:
        break;

      // `.ok(v)` / `.some(v)` — **o idioma do P7**, e o mais usado da língua.
      case ast.EnumPattern n:
        _bindEnumPattern(n, t);

      // `P { x, y }` — campos por nome; a `record(t)` os tem.
      case ast.StructPattern n:
        _bindFieldPatterns(n.fields, t, n);
      case ast.RecordPattern n:
        _bindFieldPatterns(n.fields, t, n);

      // Não ligam nome nenhum — nada a tipar aqui. O VALOR deles (o literal, os
      // extremos do range) é checado onde o pattern é usado; a exaustividade é
      // **F6** (009 §4.7).
      case ast.LiteralPattern():
      case ast.RangePattern():
      case ast.ErrorPattern(): // já reportado pelo parser (M2)
        break;

      // **spec 012** — `[a, b, ..rest]` precisa do elemento de `List<T>`, que é
      // membro de built-in (§1.3-1). Declarado, não engolido.
      case ast.ListPattern():
      case ast.RestPattern():
        _errAt('pattern-binder-unsupported', p.offset, p.length);
    }
  }

  /// `.variante(sub…)` contra o tipo do escrutínio.
  void _bindEnumPattern(ast.EnumPattern n, Type t) {
    // `T?` é `Option` (ruling 2026-07-12): `.some(v)` liga `v : T`; `.none` nada.
    if (t is OptionalType) {
      if (n.variant == 'some' && n.subpatterns.length == 1) {
        _bindPattern(n.subpatterns.single, t.inner);
      } else if (n.variant != 'none') {
        _errAt('unknown-variant', n.offset, n.length);
      }
      return;
    }
    if (t is ErrorType) return;

    // **`Result<T,E>`** — é `BuiltinType`, não `NamedType`, então não tem
    // `TypeInfo`. E `match r { .ok(v) => …, .err(e) => … }` é **o idioma que o
    // ruling §12-1 acabou de tornar o único** (os 5 métodos hard-coded morreram;
    // o idioma é `match`/`if let`). Deixá-lo de fora seria matar o P7 no lugar
    // onde ele vive. `Σ(Result) = {ok, err}`.
    if (t is BuiltinType && t.kind == BuiltinKind.result) {
      final i = switch (n.variant) { 'ok' => 0, 'err' => 1, _ => -1 };
      if (i < 0) {
        _errAt('unknown-variant', n.offset, n.length);
        return;
      }
      if (n.subpatterns.length != 1) {
        _errAt('pattern-arity-mismatch', n.offset, n.length);
        return;
      }
      _bindPattern(n.subpatterns.single, t.args[i]);
      return;
    }

    if (t is! NamedType) {
      _errAt('variant-against-non-enum', n.offset, n.length);
      return;
    }
    final info = _types.of(t.decl);
    if (info == null || info.kind != TypeKind.enum_) {
      _errAt('variant-against-non-enum', n.offset, n.length);
      return;
    }
    final v = (info.variants ?? const <VariantInfo>[])
        .where((x) => x.name == n.variant)
        .firstOrNull;
    if (v == null) {
      _errAt('unknown-variant', n.offset, n.length);
      return;
    }
    if (v.payload.length != n.subpatterns.length) {
      _errAt('pattern-arity-mismatch', n.offset, n.length);
      return;
    }
    // Substitui os type-args do enum: `Result<Int,String>.ok(v)` ⟹ `v : Int`.
    final subst = _substOf(info, t.args);
    for (var i = 0; i < n.subpatterns.length; i++) {
      _bindPattern(n.subpatterns[i], substitute(v.payload[i], subst));
    }
  }

  /// `P { x: a, y: b }` — cada campo contra o tipo declarado dele.
  ///
  /// ⚠️ **O shorthand `P { x, y }` NÃO é tipável, e a causa é o débito D4 da
  /// F4.** O `FieldPattern` **não é um `AstNode`** (não tem span nem identidade
  /// própria), então o `_declareFieldPattern` (`resolver.dart:595`) declara o
  /// binder no **nó-pattern ENVOLVENTE** — *"a precisão fina de destructuring
  /// por RECORD é débito"*. ⟹ `x` e `y` de `P { x, y }` resolvem para a **MESMA
  /// chave**, e uma chave não carrega dois tipos. Fingir aqui daria a `y` o tipo
  /// de `x` **em silêncio** — pior que recusar.
  ///
  /// A forma explícita (`P { x: a }`) funciona: o subpattern é um nó com
  /// identidade. **Destravar o shorthand é dar identidade ao `FieldPattern` —
  /// trabalho de F4/AST, não desta spec.**
  void _bindFieldPatterns(List<ast.FieldPattern> fs, Type t, ast.Pattern at) {
    if (t is ErrorType) return;
    if (t is! NamedType) {
      _errAt('destructure-on-non-aggregate', at.offset, at.length);
      return;
    }
    final info = _types.of(t.decl);
    final fields = info?.fields;
    if (fields == null) {
      _errAt('destructure-on-non-aggregate', at.offset, at.length);
      return;
    }
    final subst = _substOf(info!, t.args);
    for (final f in fs) {
      final fi = fields.where((x) => x.name == f.name).firstOrNull;
      if (fi == null) {
        _errAt('unknown-field', at.offset, at.length);
        continue;
      }
      if (f.pattern == null) {
        // Shorthand: binder sem identidade (débito D4 da F4) — ver nota acima.
        _errAt('pattern-binder-unsupported', at.offset, at.length);
        continue;
      }
      _bindPattern(f.pattern!, substitute(fi.type, subst));
    }
  }

  /// `generics(D) := args` — a substituição que instancia os campos/payloads.
  Map<TypeParamType, Type> _substOf(TypeInfo info, List<Type> args) {
    if (info.generics.isEmpty || args.length != info.generics.length) return const {};
    return {
      for (var i = 0; i < info.generics.length; i++)
        TypeParamType(info.decl, info.generics[i]): args[i],
    };
  }

  // --- modo SYNTH (⇒) — bottom-up ------------------------------------------

  /// `Γ ⊢ e ⇒ T`. Regra do 6.5.1.
  Type _synth(ast.Expr e) {
    final t = _synthInner(e);
    exprTypes[e] = t; // totalidade (§7-4)
    return t;
  }

  Type _synthInner(ast.Expr e) => switch (e) {
    ast.IntLit _ => const IntType(),
    ast.FloatLit _ => const FloatType(),
    ast.BoolLit _ => const BoolType(),
    ast.Str _ => const StringType(),
    // **`nil` NÃO SINTETIZA** — só checa contra `T?` (§4.6). É o modo `check`
    // implementando o invariante: `let x = nil` ⟹ `cannot-infer`, nunca `Nil`,
    // nunca `dynamic` (ADR-0013). O `NilType` do oracle é o sintoma de não ter
    // modo checking.
    ast.NilLit _ => _cannotInfer(e),
    ast.Ident n => _ident(n),
    ast.Call n => _call(n),
    ast.Binary n => _binary(n),
    ast.Unary n => _unary(n),
    ast.Try n => _try(n),
    ast.IfExpr n => _ifExpr(n),
    ast.MatchExpr n => _matchExpr(n),
    ast.Member n => _member(n),
    ast.CopyWith n => _copyWith(n),
    ast.SelfExpr n => _self(n),
    ast.Closure n => _closureSynth(n),
    ast.Panic _ => const NeverType(), // P3: `panic` é expressão de tipo bottom
    ast.ErrorExpr _ => const ErrorType(), // já reportado pelo parser (M2)
    // Fatia C/D (contextual/genéricos) — §12-2. Não inventar `dynamic` aqui:
    // `cannot-infer` é a resposta honesta até a fatia chegar.
    _ => _cannotInfer(e),
  };

  Type _cannotInfer(ast.Expr e) {
    _err('cannot-infer', e);
    return const ErrorType();
  }

  /// `Γ ⊢ (x: T₁, …) => e ⇒ (T₁,…,Tₙ) → synth(e)` — **a closure SEM buraco
  /// SINTETIZA** (§4.2.1). É a divisão bidirecional clássica: *o que não tem
  /// buraco, sintetiza*; só o param sem tipo é o buraco que o contexto preenche.
  ///
  /// Antes da fatia C isto caía no default e virava `cannot-infer` — um "não
  /// consigo" **FALSO**: `(x: Int) -> Int => x` está inteiramente anotado e não
  /// precisa de contexto nenhum. Idem `() => 5` (zero params).
  Type _closureSynth(ast.Closure n) {
    if (_isCheckingOnly(n)) return _cannotInfer(n); // tem buraco: precisa de ⇐

    final params = <Type>[];
    for (final p in n.params) {
      final t = _annotated(p.type!); // `_isCheckingOnly` garante o não-nulo
      binderTypes[p] = t;
      params.add(t);
    }

    final declaredRet = n.returnType == null ? null : _annotated(n.returnType!);
    final Type ret;
    switch (n.body) {
      case ast.ExprBody b:
        if (declaredRet != null) {
          _check(b.e, declaredRet);
          ret = declaredRet;
        } else {
          ret = _synth(b.e); // o corpo-expressão é a única fonte do retorno
        }
      case ast.BlockBody b:
        // RD-1: bloco não rende ⟹ sem `-> T` explícito o retorno é Void.
        final saved = _currentFnReturn;
        ret = declaredRet ?? const VoidType();
        _currentFnReturn = ret;
        _block(b.b);
        _currentFnReturn = saved;
    }
    // Closure é **posicional pura** — a superfície não tem label ali
    // (`closure ::= "(" paramList ")" …`, e o call-site é `f(g)`, não `f(g: …)`).
    return FunctionType.positional(
      params,
      ret,
      isAsync: n.asyncMarker != ast.AsyncMarker.sync,
    );
  }

  /// `s.{ x: 1 }` — **copy-with**. Item 3 da spec 011 (dívida da 010 §4.4).
  ///
  /// Tipo do resultado = **tipo do receptor**; cada override checa (`⇐`) contra
  /// o tipo **declarado** do campo, com os type-args do receptor substituídos.
  /// Exige `record(t)` (6.3.6) — a mesma tabela do `_member`.
  ///
  /// ## Só `struct` — e aqui está a única tensão de princípio da spec
  ///
  /// `class` ⟶ **erro** (`ita-visionary`), por três razões, e a 3ª é do dono:
  ///
  /// 1. **Identidade sem glifo.** `c.{ x: 1 }` faz nascer uma **segunda
  ///    identidade**, e o operador não diz isso. Mesma sintaxe, dois
  ///    significados, distinguidos por um fato que está **noutro arquivo** (a
  ///    decl). É a fronteira de **P2** (*"nunca ambíguo"*).
  /// 2. **Slicing.** `d : A` estaticamente, `D` dinamicamente ⟹ copy-with pelo
  ///    tipo **estático** produz um `A` e **fatia** o objeto. "Compila mas roda
  ///    errado".
  /// 3. **Fura o `init`** — **ADR-0012 #1, do dono**: *"`class` usa `init`
  ///    explícito quando há **estado a validar/normalizar**"*. Copy-with
  ///    **bypassa o `init`** ⟹ é a **porta dos fundos para o invariante que o
  ///    `init` existe para guardar**.
  ///
  /// **O código é `copywith-on-reference-type`, não `-on-non-aggregate`** — este
  /// **mentiria**: a `class` **é** agregado; o que ela não é é **VALOR**. O
  /// código ensina P2.
  ///
  /// *(`s.{ }` vazio: pergunta morta — `postfixOp ::= "." "{" fieldInit ("," fieldInit)* "}"`
  /// exige 1+. **Não parseia.**)*
  Type _copyWith(ast.CopyWith n) {
    final recv = _synth(n.receiver);
    if (recv is ErrorType) return recv;

    if (recv is! NamedType) {
      for (final f in n.fields) { _synth(f.value); }
      _err('copywith-on-non-aggregate', n);
      return const ErrorType();
    }
    final info = _types.of(recv.decl);
    if (info == null || info.fields == null) {
      for (final f in n.fields) { _synth(f.value); }
      _err('copywith-on-non-aggregate', n);
      return const ErrorType();
    }
    // A checagem de KIND vem primeiro: as razões 1 (identidade sem glifo) e 2
    // (slicing) são independentes, e o `copywith-on-reference-type` continua
    // ensinando P2 com footing próprio.
    if (info.kind != TypeKind.struct_) {
      for (final f in n.fields) { _synth(f.value); }
      _err('copywith-on-reference-type', n);
      return const ErrorType();
    }

    // **`copywith-on-custom-init`** — a razão 3, agora DENTRO do `struct`.
    //
    // Se o `init` veio do CORPO, ele matou o memberwise (diretriz Swift), e o
    // único construtor **valida**. Copy-with teria de construir com todos os
    // campos ⟹ ou bypassa a validação, ou não existe construtor para chamar. A
    // F5 estava licenciando um programa **INEMITÍVEL**.
    //
    // É a **razão 3** que baniu copy-with em `class` — *"copy-with bypassa o
    // `init` ⟹ é a porta dos fundos para o invariante que o `init` existe para
    // guardar"* — aparecendo dentro do `struct`. Ela vale por construção, então
    // é **entailment** dos rulings do dono (diretriz Swift + ADR-0012 #1), não
    // ruling novo.
    //
    // > **A doutrina que saiu disto, e vale além do copy-with:** o pecado não é
    // > *"duas portas para o tipo"* — é **o compilador abrir uma que o usuário
    // > fechou**. É o que separa o all-fields sintetizado (proibido) do `init`
    // > em `extension` (legítimo — ali a porta nunca foi fechada).
    //
    // O escape é o do próprio dono: **escreva o `init` numa `extension`** — ela
    // PRESERVA o memberwise. O hint o ensina, no padrão do `member-on-optional`.
    if (info.initFromBody) {
      for (final f in n.fields) { _synth(f.value); }
      _err('copywith-on-custom-init', n);
      return const ErrorType();
    }

    final subst = _substOf(info, recv.args);
    for (final f in n.fields) {
      final fi = info.fields!.where((x) => x.name == f.name).firstOrNull;
      if (fi == null) {
        _synth(f.value); // totalidade (§7-4)
        _errAt('unknown-field', f.value.offset, f.value.length);
        continue;
      }
      _check(f.value, substitute(fi.type, subst));
    }
    return recv; // o resultado é do MESMO tipo do receptor
  }

  /// `self` — o tipo envolvente, com os generics DELE.
  ///
  /// ⚠️ **`SelfExpr` tinha ZERO menções no checker** ⟹ `self` era `cannot-infer`,
  /// e todo `self.x`/`self.f()` morria. A F4 **já entregava** a resolução
  /// (`SelfRes(receiver)`, com a chave sendo o próprio `SelfExpr`) — a F5 é que
  /// não lia. É o contrato F4→F5 do ADR-0011 (*"a Fase 5 consome isso e **não
  /// reconstrói escopo**"*) sendo cumprido pela metade.
  ///
  /// `self` em `struct Stack<T>` é `Stack<T>` — os generics ficam como
  /// [TypeParamType] (a LIGADA, não var fresca): dentro do corpo, `T` é rígido.
  Type _self(ast.SelfExpr n) {
    final res = _resolution[n];
    if (res is! SelfRes) {
      _err('self-outside-method', n); // a F4 já reporta; aqui é rede
      return const ErrorType();
    }
    // ⚠️ **`SelfRes.receiver` tem DUAS formas — e é o contrato F4×F5.**
    //
    // Para `struct`/`class`/`enum`/`trait`/`actor` a F4 passa a **decl**
    // (`_resolveMembers(n.members, n)`); para **`extension`/`impl` ela passa o
    // `n.target`, que é um `TypeNode`** (`resolver.dart:203-204`). A tabela é
    // chaveada por **decl** ⟹ `_types.of(TypeNode)` dava `null` ⟹ `ErrorType`
    // **absorvente** ⟹ **todo `self.x`/`self.f()` dentro de `extension` passava
    // SEM CHECAGEM**, e o teste disso ficava **verde por acidente**
    // (`extension Stack { fn eu() -> Int => self }` era silêncio).
    //
    // A §3.2 da própria spec escreveu a instrução que este código não seguia:
    // *"a F5 tem de fazer `resolveTypeNode(target)` → `NamedType(decl, …)` →
    // `types.of(decl)`"*. Era a doença do catch-all sobrevivendo **dentro do
    // passe que a caçou**.
    final decl = _selfDecl(res.receiver);
    if (decl == null) return const ErrorType(); // o collect já reportou
    final info = _types.of(decl);
    if (info == null) return const ErrorType();
    return NamedType(decl, info.kind, [
      for (final g in info.generics) TypeParamType(decl, g),
    ]);
  }

  /// Normaliza as duas formas do `SelfRes.receiver` (ver [_self]).
  ast.AstNode? _selfDecl(ast.AstNode receiver) {
    if (receiver is! ast.NamedType) return receiver; // já é a decl
    return _types.declNamed(receiver.name); // `extension`/`impl`: era o alvo
  }

  Type _ident(ast.Ident n) {
    final res = _resolution[n];
    return switch (res) {
      LocalRes r => binderTypes[r.binder] ?? const ErrorType(),
      TopLevelRes r => _topLevelType(r.decl, n),
      _ => const ErrorType(),
    };
  }

  /// [at] é o nó de USO — o span de `no-init` é dele, não da decl.
  Type _topLevelType(ast.AstNode decl, [ast.AstNode? at]) => switch (decl) {
    // O escopo dos generics da CALLEE tem de estar aberto aqui também: este é o
    // caminho do `_call`, e ele lê a assinatura de OUTRA fn (letrec de módulo —
    // a chamada não está dentro do `_fnDecl` dela). Sem isto, `mapa(xs) { … }`
    // resolveria `List<T>` com o `T` fora de escopo.
    ast.FnDecl n => _withGenerics(n, n.generics, () => FunctionType(
      [
        for (final p in n.params)
          ParamType(
            p.type == null ? const ErrorType() : _annotated(p.type!),
            label: p.label ?? p.name, // o label é como o call-site o chama
            hasDefault: p.defaultValue != null,
          ),
      ],
      n.returnType == null ? const VoidType() : _annotated(n.returnType!),
      isAsync: n.asyncMarker != ast.AsyncMarker.sync,
      // O prefixo ∀ — a lista DECLARADA, na ordem em que o usuário a escreveu.
      quantifiers: [for (final g in n.generics) TypeParamType(n, g.name)],
    )),
    // ⚠️ **A F4 põe o BINDER, não o `LetStmt`.** `_declareTopLevel` →
    // `_declarePattern` → `_declareName(n.name, n, …)` com `n` = `BindPattern`
    // (`resolver.dart:146-149`), e o doc de `TopLevelRes` (`scope.dart:51-54`) o
    // diz: *"ou **o binder** de um `let`/`var` global"*.
    //
    // O arm `ast.LetStmt` era **código morto**, e o `BindPattern` caía no
    // `throw` abaixo ⟹ **`let x = 5` + `let y = x` DERRUBAVA o compilador**. Eu
    // escrevi o switch contra o contrato que IMAGINEI da F4, não contra o que a
    // `resolver.dart` implementa — e ficou verde porque nenhum teste e nenhum
    // `.tu` do corpus referenciava um global.
    //
    // (O arm do `LetStmt`, se vivesse, estaria **errado** para `let (a, b) = …`:
    // daria a `a` o tipo da tupla inteira.)
    ast.BindPattern _ => binderTypes[decl] ?? const ErrorType(),

    // **Nome de TIPO em posição de valor = referência ao CONSTRUTOR.**
    //
    // ⚠️ Aqui morava o **último catch-all vivo** — `_ => const ErrorType()` —, e
    // ele era a mesma doença do `default: break`, só que pior: o `ErrorType` é
    // **absorvente por anti-cascata**, então o buraco virava **silêncio**:
    //
    // ```
    // struct P { x: Int, y: Int }
    // let n: Int = P(x: 1, y: 2)   // ⟶ SEM ERRO. Um `P` num `Int`.
    // P()                          // ⟶ SEM ERRO
    // P(zz: 9)                     // ⟶ SEM ERRO
    // ```
    ast.StructDecl _ || ast.ClassDecl _ || ast.EnumDecl _ ||
    ast.TraitDecl _ || ast.ActorDecl _ => _constructorType(decl, at),

    // **`else error`, e o erro é ALTO** (6.5.2: *"else error"* — um default pode
    // ser `error`, **nunca um valor**). Mas não é `CheckError`: chegar aqui é
    // **violação do contrato F4×F5** — a F4 resolveu um nome para uma decl que a
    // F5 não sabe tipar. **Não há nada que o usuário conserte**, então falhar
    // baixo (devolvendo `ErrorType`) esconderia bug NOSSO como erro dele.
    _ => throw StateError(
      'contrato F4×F5: TopLevelRes aponta ${decl.runtimeType}, '
      'que a F5 não sabe tipar (offset ${decl.offset})',
    ),
  };

  /// `P` como valor ⟹ a assinatura do `init` (memberwise ou explícito).
  Type _constructorType(ast.AstNode decl, ast.AstNode? at) {
    final info = _types.of(decl);
    if (info == null) return const ErrorType();
    final init = info.init;
    if (init == null) {
      // **`class` sem `init` explícito** (ruling do dono): não ganha memberwise.
      // Dar-lhe o memberwise apagaria o contraste que o ADR-0012 #1 criou de
      // propósito (`struct` = concisão; `class` = init quando há estado a
      // validar), e abriria a pergunta feia de memberwise + herança — que o
      // Swift responde com designated/convenience/required init, exatamente a
      // complexidade que o Itá recusa.
      //
      // O erro é no **USO**, não na decl: uma classe base tem campos e **nunca é
      // construída** — errar na decl seria falso-positivo.
      if (at != null) _err('no-init', at);
      return const ErrorType();
    }
    return init;
  }

  T _withGenerics<T>(ast.AstNode owner, List<ast.GenericParam> gs, T Function() f) {
    if (gs.isEmpty) return f();
    _collector.pushGenericScope(owner, gs);
    final r = f();
    _collector.popGenericScope();
    return r;
  }

  /// Corpo de `extension`/`impl` — os generics são os do **ALVO**, e a dona do
  /// [TypeParamType] é a decl dele (o `T` aqui é o MESMO `T` de lá).
  ///
  /// ⚠️ **Contrato F4×F5:** o `resolver.dart:203-204` passa `n.target`, que é um
  /// **`TypeNode`**, não a decl — a F5 tem de resolvê-lo até a tabela.
  void _contributionBody(ast.TypeNode target, List<ast.Decl> members) {
    if (target is! ast.NamedType) return; // o collect já reportou
    final decl = _types.declNamed(target.name);
    if (decl == null) return; // idem (`unknown-type`)
    final info = _types.of(decl)!;
    if (info.generics.isEmpty) {
      _members(members);
      return;
    }
    _collector.pushGenericScopeNamed(decl, info.generics);
    _members(members);
    _collector.popGenericScope();
  }

  /// Aplicação — **fatias D + C**. A regra do livro (6.8): *"if f tem tipo s → t
  /// and x tem tipo s, then f(x) tem tipo t"*.
  ///
  /// A assinatura é INSTANCIADA (6.5.4: *"em cada uso … substituímos as
  /// variáveis ligadas por novas variáveis"*) e os args casam contra os params
  /// via Alg. 6.19. Sem let-generalization (§4.4).
  ///
  /// **DUAS RODADAS** (spec 010 §4.3) — e é o coração da fatia C. A versão
  /// anterior fazia `[for (final a in n.args) _synth(a.value)]`, sintetizando
  /// TODOS os args antes de unificar: uma closure `{ $0*2 }` nunca chegava a
  /// receber contexto, porque `_synth` de closure é `cannot-infer`.
  ///
  /// **A fundação é 5.2.5, não 6.5.5** — o store da unificação é *efeito
  /// colateral*, e o livro manda *"restringir as ordens de avaliação permitidas
  /// … adicionando **arestas implícitas** no grafo de dependência"*. As arestas
  /// são estas duas rodadas; sem declará-las, a SDD fica subdeterminada.
  ///
  /// **Continua 1 walk** (5.2.2): cada nó é visitado uma vez — só não da
  /// esquerda para a direita. Não é worklist nem ponto-fixo (isso quebraria o
  /// invariante da §5.2 e traria o `expression too complex` do Swift antigo).
  /// [expected] presente ⟹ o `_check` está descendo, e o retorno pode ser
  /// determinado por ele. Ver [_callExpected].
  /// Os `init` candidatos quando o callee é um **nome de tipo** — o primário
  /// (memberwise ou do corpo) **mais** os de `extension`.
  ///
  /// ⚠️ **Co-requisito DURO do `copywith-on-custom-init`**, não item separado: o
  /// hint dele manda *"escreva o `init` numa `extension`"*, e o `extensionInits`
  /// era **dado morto** (escrito no collect, lido por ninguém) ⟹ o usuário
  /// moveria o init e levaria `argument-label-mismatch` na chamada. **Fecharia a
  /// porta e trancaria a saída.**
  ///
  /// **A seleção é por LABEL, e isso NÃO é o Ex. 6.5.2.** Overload de método foi
  /// barrado (ruling §12-4) porque *"sintetize um conjunto de tipos possíveis de
  /// baixo para cima e … prossiga de cima para baixo"* = **dois percursos**. Aqui
  /// o discriminador são os **labels**, que são **sintáticos** — conhecidos no
  /// call-site **sem tipar os args**. Nenhum nó é revisitado ⟹ o **1-walk
  /// sobrevive**.
  List<FunctionType> _initCandidates(ast.Expr callee) {
    if (callee is! ast.Ident) return const [];
    final res = _resolution[callee];
    if (res is! TopLevelRes) return const [];
    final info = _types.of(res.decl);
    if (info == null) return const [];
    return [if (info.init != null) info.init!, ...info.extensionInits];
  }

  Type _call(ast.Call n, [Type? expected]) {
    // Construtor com MAIS de um `init` (primário + os de `extension`): escolhe
    // pelos labels, que são sintáticos. Ver [_initCandidates].
    final cands = _initCandidates(n.callee);
    // **`isNotEmpty`, não `> 1`** — com `> 1`, uma `class` cujo ÚNICO `init` vem de
    // `extension` caía no caminho sem override e morria em `no-init`: `class` nunca
    // ganha memberwise (ruling do dono), então `cands.length == 1` e a porta não
    // abria. Era **fechar a porta e trancar a saída** — o mesmo pecado que o
    // `copywith-on-custom-init` acusa —, e uma `class` com estado a validar é
    // exatamente o caso do ADR-0012 #1.
    //
    // O ruling do dono (*"`init` no CORPO mata o memberwise; em `extension` o
    // PRESERVA"*) não decidia este caso — as duas cláusulas pressupõem que o tipo
    // TEM memberwise, e `class` não tem. Quem decide é o **ADR-0012 A1**, anterior:
    // o critério é **explícito × sintetizado** (não *onde se escreve*), e ele
    // **nomeia `extension`** entre os corpos que admitem `InitDecl`. Um `init` de
    // extension é explícito — o usuário escreveu cada param.
    //
    // Seguro com 1 candidato: `pick ?? cands.first` devolve exatamente o que o
    // `_synth` devolveria. Com `cands` vazio segue caindo no `no-init` legítimo.
    if (cands.isNotEmpty) {
      final labels = [for (final a in n.args) a.label];
      final pick = cands.where((c) => _labelsFit(labels, c.params)).firstOrNull;
      // Nenhum casa ⟹ reporta contra o PRIMÁRIO, que é o que o usuário espera.
      return _callInner(n, expected, pick ?? cands.first);
    }
    return _callInner(n, expected);
  }

  /// Os labels do call-site cabem nesta assinatura? (Só forma — nada de tipos.)
  bool _labelsFit(List<String?> labels, List<ParamType> params) {
    var pi = 0;
    for (final l in labels) {
      while (pi < params.length && l != null && params[pi].label != l) {
        if (!params[pi].hasDefault) return false;
        pi++;
      }
      if (pi >= params.length) return false;
      if (l != null && params[pi].label != l) return false;
      pi++;
    }
    while (pi < params.length) {
      if (!params[pi].hasDefault) return false;
      pi++;
    }
    return true;
  }

  /// [override] presente ⟹ o callee é um nome de tipo com vários `init`, e a
  /// seleção por label já escolheu qual. Ver [_call].
  Type _callInner(ast.Call n, [Type? expected, FunctionType? override]) {
    final calleeT = override ?? _synth(n.callee);
    if (override != null) exprTypes[n.callee] = override; // totalidade (§7-4)

    if (calleeT is ErrorType) {
      for (final a in n.args) { _synth(a.value); } // totalidade (§7-4)
      return calleeT;
    }
    if (calleeT is! FunctionType) {
      _err('not-callable', n);
      for (final a in n.args) { _synth(a.value); }
      return const ErrorType();
    }

    // **Casamento arg→param por LABEL** (item 0). Antes era por POSIÇÃO, e os
    // labels eram decorativos: `div(den: 2, num: 10)` ligava `num=2, den=10`
    // **em silêncio**.
    final slot = _matchArgs(n, calleeT.params);
    if (slot == null) {
      for (final a in n.args) { _synth(a.value); }
      return const ErrorType();
    }

    // Instancia as variáveis LIGADAS da assinatura por variáveis NOVAS — e só
    // as do **prefixo ∀**. O que estiver fora dele é RÍGIDO (`FunctionType.quantifiers`).
    final u = Unifier();
    final (type: inst, vars: freshVars) = u.instantiate(calleeT);

    // **R0 — o `expected` desce no RETORNO** (spec 011 §4.6).
    //
    // `Stack.nova()` usa o `T` **sem receptor e sem args**: não há de onde
    // extraí-lo por síntese. É o **`[]` com outro nome** — vacuidade do 6.5.1 —,
    // e o `T` vem do CONTEXTO: `let s: Stack<Int> = Stack.nova()`.
    //
    // ⚠️ **Sem isto, o built-in ganhava contexto e o tipo do usuário NÃO**:
    // `var xs: List<Int> = []` passava e `let s: Stack<Int> = Stack.nova()` dava
    // `cannot-infer`. Isso é a **face 1 do teste do privilégio** (010 §3.2),
    // literal, no código — e a §4.6 desta spec avisou: *"declarar não-objetivo
    // aqui é declarar um PRIVILÉGIO DE BUILT-IN"*.
    //
    // **Não atravessa fronteira de declaração** (a regra-mãe): a assinatura de
    // `nova` está **anotada** (`-> Stack<T>`, o usuário a escreveu). Não
    // inferimos a assinatura a partir do uso — **instanciamos uma assinatura
    // DECLARADA**, que é o que a fatia D já faz em todo call. E **não é HM**:
    // dar `Stack<α>` sem contexto seria 6.5.4 + let-generalization, recusado.
    //
    // **É uma aresta implícita a mais** (5.2.5), e ela vem ANTES das rodadas de
    // args — o `expected` é irmão à esquerda do call inteiro, não dos args.
    // O livro a teria de graça: o Alg. 6.16 não precisa de `expected` porque o
    // store dele é **global**; o nosso `Unifier()` é **local por `_call`**, então
    // unificar `expected` com `inst.ret` devolve a restrição que lá seria
    // ambiente. Fundamento: **6.5.4 / Alg. 6.19**.
    if (expected != null && _hasTypeVar(inst.ret)) {
      u.unify(inst.ret, expected); // falha aqui não é erro: os args ainda falam
    }

    // --- R1: args que TÊM regra de síntese ----------------------------------
    // O critério é SINTÁTICO (a forma de introdução), não "closures por último".
    final deferred = <int>[];
    var hadError = false;
    for (var i = 0; i < n.args.length; i++) {
      if (_isCheckingOnly(n.args[i].value)) {
        deferred.add(i);
        continue;
      }
      // Resolve com o que os args ANTERIORES já ligaram: em
      // `f<T>(a: T, b: List<T>)`, o arg 0 liga `T` e o param 1 vira `List<Int>`.
      final want = u.resolve(inst.params[slot[i]].type);

      // **UNIFICAÇÃO É IGUALDADE — não é `≤`.** Este `if` conserta um bug que
      // saiu na fatia D: o `_call` unificava TODO arg, e `unify(Voa, Ave)`
      // compara `identical(decl)` e falha. Resultado: **subsunção nunca era
      // consultada em posição de argumento** ⟹ `class D : A` não passava em
      // `f(a: A)`, e — pior — `fn f(x: Int?)` **não podia ser chamada com `5`**,
      // porque `T ≤ T?` é subsunção. A regra do próprio invariante de nulidade
      // não valia no lugar onde ela mais aparece. Passava em `let x: Int? = 5`
      // (que vai por `_check`) e falhava em `f(5)`: mesma regra, dois resultados.
      //
      // O corte é principiado, não remendo: **type var ⟹ unificar** (é o que
      // RESOLVE o `T`, Alg. 6.19); **sem type var ⟹ checar** (é o mode-switch, e
      // subsunção é o ÚNICO ponto onde `≤` entra — §4.3, Pierce & Turner §3).
      if (_hasTypeVar(want)) {
        final at = _synth(n.args[i].value);
        if (!u.unify(want, at)) {
          _err('type-mismatch', n.args[i].value);
          hadError = true;
        }
      } else {
        final before = errors.length;
        _check(n.args[i].value, want);
        if (errors.length != before) hadError = true;
      }
    }

    // --- R2: formas checking-only → `_check` contra o param JÁ substituído ---
    for (final i in deferred) {
      final arg = n.args[i].value;
      final want = u.resolve(inst.params[slot[i]].type);

      // **Closure é o caso fino, e o `mapa<T,U>` o expõe.** Em
      // `mapa(xs) { $0 + 1 }`, a R1 fixa `T := Int` mas deixa `α_U` LIVRE — o
      // `U` só é determinado pelo CORPO. Exigir `want` inteiro determinado aqui
      // seria `cannot-infer` num caso que a inferência alcança: o que a closure
      // precisa receber são os **params**; o retorno ela **rende**.
      if (arg is ast.Closure && want is FunctionType) {
        if (want.params.any((p) => _hasTypeVar(p.type))) {
          _err('cannot-infer', arg); // aí sim: o param é o buraco
          exprTypes[arg] = const ErrorType();
          hadError = true;
          continue;
        }
        _closureAgainst(arg, want, u); // o `u` deixa o corpo RESOLVER o retorno
        continue;
      }

      // Demais formas checking-only (`nil`/`[]`/`{}`/`.variant`): não rendem
      // nada de que unificar, então precisam do tipo INTEIRO determinado.
      // O erro é NAQUELE arg (não no call inteiro) — é onde se conserta.
      if (_hasTypeVar(want)) {
        _err('cannot-infer', arg);
        exprTypes[arg] = const ErrorType();
        hadError = true;
        continue;
      }
      _check(arg, want);
    }

    // **Ordem-FONTE** (§4.3 / CA51) já é garantida pelo `checkTypes`, que ordena
    // TUDO por offset ao juntar `collector.errors` + `c.errors`. As 2 rodadas
    // visitam fora da ordem textual; a ordenação global é o que reconcilia — não
    // precisa de máquina local (a versão anterior tinha uma, redundante).
    if (hadError) return const ErrorType();

    // Se sobrou variável, a inferência não alcançou: **`cannot-infer`**, nunca
    // `dynamic` (ADR-0013).
    //
    // **A totalidade é sobre `S`, não sobre `S(ret)`.** O guarda antigo olhava só
    // o retorno resolvido e deixava passar dois casos que viram buraco no contrato
    // §7 assim que os `typeArgs` forem emitidos: o **quantificador fantasma**
    // (`fn f<T>() -> Int` — `T` não ocorre em lugar nenhum) e o **`T` que só
    // aparece num param omitido por default** (`fn f<T>(x: T = …)` chamada `f()`
    // ⟹ o `slot` não o cobre e `α` nunca unifica).
    //
    // Checar as vars é **estritamente mais forte** e **subsume** o check do
    // retorno: no universo deste `Unifier`, as ÚNICAS `TypeVar` são as que o
    // `instantiate` cunhou (todo outro `_call` tem `Unifier` próprio, e resolve ou
    // erra antes de devolver) ⟹ sobrar variável em qualquer lugar ⟺ sobrar em
    // `freshVars`.
    if (freshVars.any((v) => _hasTypeVar(u.resolve(v)))) {
      _err('cannot-infer', n);
      return const ErrorType();
    }

    // **Os deferidos são re-resolvidos aqui, e sem isto a tabela nº1 FURA.**
    //
    // O `_closureAgainst` grava `exprTypes[closure] = expected` **antes** de o
    // corpo resolver as variáveis: em `mapa(xs: nums) { $0 + 1 }` **sem anotação**
    // no `let` (que é o que desliga o R0), o `α_U` só é ligado pelo corpo, DEPOIS.
    // ⟹ `exprTypes[closure]` ficava `(Int) -> α1` — uma `TypeVar` viva na
    // side-table que a F7 lê. O `type.dart` já diz que *"`TypeVar` deve sumir até o
    // fim"* e o ADR-0013 #4 é literal: *"deve estar resolvido no fim; se sobrou ⟹
    // `cannot-infer`"*.
    //
    // Aqui não é escolha, é **registro**: o guarda acima já provou que não sobrou
    // variável — a entrada é que estava obsoleta. Com anotação o R0 fixava tudo
    // antes e o furo não aparecia; por isso estava verde.
    for (final i in deferred) {
      final a = n.args[i].value;
      final t = exprTypes[a];
      if (t != null) exprTypes[a] = u.resolve(t);
    }

    // **Side-table nº5.** Só no caminho de SUCESSO: registrar sob erro entregaria
    // à F7 um `ResolvedCall` com buraco dentro, que é pior que a ausência.
    //
    // `typeArgs` sai na ordem do prefixo ∀ porque é a ordem em que o `instantiate`
    // cunhou as vars — a correspondência posição-no-∀ ↔ variável **é** o `S` do
    // 6.5.5, e ter um dono só (o `Unifier`) é o que a torna confiável.
    final resolved = u.resolve(inst);
    resolvedCalls[n] = ResolvedCall(
      slot,
      [for (final v in freshVars) u.resolve(v)],
      resolved as FunctionType,
    );
    return resolved.ret;
  }

  /// Casa cada **arg** com o **param** dele — spec 011, item 0.
  ///
  /// Devolve `argIndex → paramIndex`, ou `null` se falhou (e já reportou).
  ///
  /// ## O bug que isto mata
  ///
  /// O `_call` ligava por **POSIÇÃO** e ignorava os labels. Não era lacuna de
  /// tipo: era **programa errado em silêncio**.
  ///
  /// ```
  /// fn div(num: Int, den: Int) -> Int => num
  /// div(den: 2, num: 10)   // ⟶ SEM ERRO, e liga num=2, den=10
  /// ```
  ///
  /// O usuário escreve `den: 2, num: 10` e recebe o inverso — **os labels
  /// mentiam**. Também: `fn f(x: Int = 1)` chamada `f()` dava `arity-mismatch`
  /// FALSO (o default não era omissível), e `f(zz: 1)` (label inexistente)
  /// passava.
  ///
  /// ## A regra: **ordem obrigatória, defaults saltáveis** (Swift)
  ///
  /// Diretriz do dono (2026-07-15): *"se tiver divergência ou indecisão, a
  /// maneira que o Swift trabalha é a diretriz"*. E aqui há divergência real —
  /// **Dart deixa reordenar named args; Swift não** (*"argument 'num' must
  /// precede argument 'den'"*). Seguimos o Swift: o label **confirma**, não
  /// **reordena**. É mais simples de ler (a chamada espelha a assinatura) e não
  /// abre a pergunta "qual ordem o leitor deve assumir".
  ///
  /// Param com default é **omissível** — e é assim que se salta.
  ///
  /// ⚠️ **O livro não cobre param nomeado**: 6.3.1 modela param como produto
  /// cartesiano (posição pura) e o Alg. 6.16 assume unário. Regra nossa.
  List<int>? _matchArgs(ast.Call n, List<ParamType> params) {
    final slot = <int>[];
    var pi = 0;
    for (final arg in n.args) {
      // Avança os params com default até achar o do label pedido.
      while (pi < params.length &&
          arg.label != null &&
          params[pi].label != arg.label) {
        if (!params[pi].hasDefault) {
          // Saltou um param OBRIGATÓRIO ⟹ ou o label está fora de ordem, ou
          // falta um arg. Os dois são o mesmo erro do ponto de vista do
          // usuário: a chamada não espelha a assinatura.
          _err('argument-label-mismatch', arg.value);
          return null;
        }
        pi++;
      }
      if (pi >= params.length) {
        // Ou sobrou arg, ou o label não existe.
        _err(arg.label == null ? 'arity-mismatch' : 'unknown-label', arg.value);
        return null;
      }
      if (arg.label != null && params[pi].label != arg.label) {
        _err('unknown-label', arg.value);
        return null;
      }
      slot.add(pi);
      pi++;
    }
    // Os params que sobraram têm de ser todos omissíveis.
    while (pi < params.length) {
      if (!params[pi].hasDefault) {
        _err('missing-argument', n);
        return null;
      }
      pi++;
    }
    return slot;
  }

  /// Uma forma é ***checking-only*** quando **não tem regra de síntese**: só
  /// existe no modo `⇐` (spec 010 §4.1). **Uma regra, DOIS fundamentos:**
  ///
  /// - `[]`/`{}` — **6.5.1, vacuidade**: a síntese *"constrói o tipo … a partir
  ///   dos tipos de suas **subexpressões**"*; zero subexpressões ⟹ não há de que
  ///   construir. É **definicional**, não política.
  /// - `nil`/`.variant` — **§4.9, o glifo PEDE**. Aqui a vacuidade seria razão
  ///   FALSA: `.v` também tem zero subexpressões, mas o que o impede de
  ///   sintetizar é o nome da variante não determinar o enum — se só um enum no
  ///   escopo tivesse `.none`, sintetizar seria possível. **Não fazer é
  ///   política**, e a política é a §4.9. Escrito como "definicional", o
  ///   `.variant` cairia no dia em que alguém propusesse *"só um enum tem
  ///   `.none`, deixa sintetizar"* — a vacuidade não barra isso; a §4.9 barra.
  ///
  /// Closure entra **condicionalmente** (§4.2.1): quem tem todos os params
  /// tipados **sintetiza** — não é buraco, é assinatura completa.
  bool _isCheckingOnly(ast.Expr e) => switch (e) {
    ast.NilLit _ => true,
    ast.EnumShorthand _ => true,
    ast.ListExpr n => n.elements.isEmpty,
    ast.MapExpr n => n.entries.isEmpty,
    // Pós-F3 a closure tem duas formas, e as duas são buraco:
    //  • `!hasExplicitParams` ⟹ params VAZIOS e **aridade contextual**. A F3 o
    //    deixa assim de propósito — o comentário dela é normativo: *"SEM `$k`:
    //    mantém implícita … `map { g() }` exige 1 arg mas usa 0 — **forçar
    //    arity-0 seria errado**"*. Tratá-la como aridade 0 aqui seria desfazer
    //    a decisão da F3 no andar de cima.
    //  • `hasExplicitParams` + algum param sem tipo ⟹ o tipo é que falta.
    ast.Closure n => !n.hasExplicitParams || n.params.any((p) => p.type == null),
    _ => false,
  };

  /// [p] ocorre em [t]? **Filtro sobre lista conhecida, não descoberta de
  /// prefixo** — ver `_staticMember` para por que a distinção importa.
  bool _occursIn(TypeParamType p, Type t) => switch (t) {
    TypeParamType x => x == p,
    OptionalType n => _occursIn(p, n.inner),
    NamedType n => n.args.any((a) => _occursIn(p, a)),
    BuiltinType n => n.args.any((a) => _occursIn(p, a)),
    FunctionType n =>
      n.params.any((x) => _occursIn(p, x.type)) || _occursIn(p, n.ret),
    TupleType n => n.elements.any((e) => _occursIn(p, e)),
    _ => false,
  };

  bool _hasTypeVar(Type t) => switch (t) {
    TypeVar _ => true,
    OptionalType n => _hasTypeVar(n.inner),
    NamedType n => n.args.any(_hasTypeVar),
    BuiltinType n => n.args.any(_hasTypeVar),
    FunctionType n => n.params.any((p) => _hasTypeVar(p.type)) || _hasTypeVar(n.ret),
    TupleType n => n.elements.any(_hasTypeVar),
    _ => false,
  };

  /// §4.3 + §4.9: match **EXATO** em `Ops(sym)`; sem coerção não há ranking.
  Type _binary(ast.Binary n) {
    final l = _synth(n.left);
    final r = _synth(n.right);
    if (l is ErrorType || r is ErrorType) return const ErrorType();

    if (_logicalOps.contains(n.op)) {
      if (l is! BoolType) _err('not-bool', n.left);
      if (r is! BoolType) _err('not-bool', n.right);
      return const BoolType();
    }
    if (_comparisonOps.contains(n.op)) {
      if (l != r) _err('comparison-type-mismatch', n);
      return const BoolType();
    }
    final table = _primitiveOps[n.op];
    if (table != null) {
      for (final (a, b, out) in table) {
        if (l == a && r == b) return out;
      }
      // Aqui morreria a coerção: `1 + 1.0` não casa nenhuma linha (§4.5 — e
      // "widening preserva" é FALSO no Itá: Int é 64-bit, Double tem 53 de
      // mantissa). `Ops` do usuário (`OperatorDecl`) é fatia C/D.
      _err('no-operator-for-types', n);
      return const ErrorType();
    }
    return _cannotInfer(n);
  }

  Type _unary(ast.Unary n) {
    final t = _synth(n.operand);
    if (t is ErrorType) return t;
    return switch (n.op) {
      ast.UnaryOp.not => () {
        if (t is! BoolType) _err('not-bool', n.operand);
        return const BoolType();
      }(),
      ast.UnaryOp.neg => () {
        if (t is! IntType && t is! FloatType) _err('no-operator-for-types', n);
        return t;
      }(),
    };
  }

  /// `?` — regra **NÃO-LOCAL** (§5.4), e é o que fecha **P7** nesta fase:
  /// operando `Result<T,E>` → `T`, **e** a fn envolvente tem de retornar
  /// `Result<_,E>` com **`E` IDÊNTICO**.
  ///
  /// **Sem `From` automático** (§0.5-6): o `From` implícito do Rust é o único
  /// ponto onde ele fura o próprio "sem conversão implícita" — maquinaria
  /// invisível rodando em **todo** `?`. Divergência de `E` é `error-type-mismatch`,
  /// hint `.mapErr()`. Custa ergonomia; P4 ganha.
  ///
  /// **Propagação automática NÃO é mágica — é o oposto dela:** o glifo `?` está
  /// no caractere exato onde a propagação acontece. A mágica é o try/catch, onde
  /// a AUSÊNCIA de marca significa "isto pode lançar".
  Type _try(ast.Try n) {
    final operand = _synth(n.operand);
    final ret = _currentFnReturn;

    // Lado 1 — a fn envolvente: `?` é early-return de `.err(e)`; sem `Result` no
    // retorno não há para onde retornar.
    if (ret == null || ret is! BuiltinType || ret.kind != BuiltinKind.result) {
      _err('try-outside-result-fn', n);
      return const ErrorType();
    }
    if (operand is ErrorType) return operand;

    // Lado 2 — o operando: `e?` sobre não-`Result` (§4.8 `try-on-non-result`).
    if (operand is! BuiltinType || operand.kind != BuiltinKind.result) {
      _err('try-on-non-result', n.operand);
      return const ErrorType();
    }

    // `E` IDÊNTICO — sem `From` (§0.5-6).
    final operandErr = operand.args[1];
    final fnErr = ret.args[1];
    if (operandErr != fnErr) {
      _err('error-type-mismatch', n);
      return const ErrorType();
    }
    return operand.args[0]; // `Result<T,E>` → T
  }

  /// **Join = identidade + bottom** (§4.3). NÃO é o LUB: síntese nunca inventa
  /// supertipo — o supertipo só entra por subsunção contra um esperado que o
  /// usuário declarou. É o que evita o `lub(Integer,String)` do Java.
  Type _join(Type a, Type b, ast.Expr at) {
    if (a is ErrorType || b is ErrorType) return const ErrorType();
    if (a is NeverType) return b; // P3 + TAPL §15.4: um braço que DIVERGE não
    if (b is NeverType) return a; //   impõe restrição sobre o resultado
    if (a == b) return a;
    _err('branch-type-mismatch', at);
    return const ErrorType();
  }

  Type _ifExpr(ast.IfExpr n) {
    if (n.binding != null) return _cannotInfer(n); // if-let: fatia C
    _checkCondition(n.subject);
    return _join(_synth(n.then), _synth(n.orElse), n);
  }

  Type _matchExpr(ast.MatchExpr n) {
    final subject = _synth(n.scrutinee);
    // Exaustividade é **F6** (§4.7) — aqui o join dos braços **e os binders**.
    Type? acc;
    for (final arm in n.arms) {
      // ⚠️ Isto **não existia**: o `_matchExpr` nunca ligava o pattern, então
      // `match e { .a(v) => v + "string" }` passava SEM ERRO — o `v` ficava sem
      // tipo, virava `ErrorType` no `_ident`, e o `ErrorType` é absorvente.
      // `match` é o construto do P7; ele estava efetivamente sem checagem.
      _bindPattern(arm.pattern, subject);
      if (arm.guard != null) _checkCondition(arm.guard!);
      final t = _synth(arm.body);
      acc = acc == null ? t : _join(acc, t, n);
    }
    return acc ?? const ErrorType();
  }

  /// `.field`/`.método` é **type-directed** (contrato 008 §5.4) e exige a
  /// resolução de membro — fatia **C**. O que fecha AQUI é o mandato da nulidade:
  Type _member(ast.Member n) {
    // **`Stack.new()`** — receptor é NOME DE TIPO, não valor. É o qualificador
    // do 1.6.1 Ex. 1.3: *"static refere-se **não ao escopo** … torna x uma
    // variável de classe"*. Uma tabela só (1.6.4); o que muda é o receptor.
    final asType = _receiverAsTypeName(n.receiver);
    if (asType != null) return _staticMember(n, asType);

    final recv = _synth(n.receiver);
    // **`member-on-optional`** (§4.6): `T?` tem **Σ_membros = ∅** — nenhuma API
    // de instância. O `!= nil` segue legal; o erro nasce no `.foo()`, ensinando
    // o idioma (`if let x = x { … }`). É o melhor momento pedagógico da língua.
    //
    // O ruling §12-1 (spec 011) o CONFIRMOU: os 5 métodos hard-coded de
    // `Option`/`Result` morreram, e o idioma é `match`/`if let`. `opt.map(f)`
    // segue erro **por decisão de identidade**, não por falta.
    if (recv is OptionalType) {
      _err('member-on-optional', n);
      return const ErrorType();
    }
    if (recv is ErrorType) return recv;

    // Membro de BUILT-IN: `xs.length` existe — nós é que não o modelamos.
    // `unknown-member` MENTIRIA. **012** (§4.7).
    if (recv is BuiltinType || _isPrimitive(recv)) {
      _err('builtin-member-unsupported', n);
      return const ErrorType();
    }

    final r = _lookup(recv, n.name, n);
    if (r == null) {
      _err('unknown-member', n);
      return const ErrorType();
    }
    if (r.isStatic) {
      _err('static-via-instance', n); // `s.new()` — `new` é do TIPO
      return const ErrorType();
    }
    resolvedMembers[n] = r;
    return r.type;
  }

  bool _isPrimitive(Type t) =>
      t is IntType || t is FloatType || t is BoolType || t is StringType;

  /// O receptor é o NOME de um tipo (`Stack.new()`)? Devolve o tipo dele.
  Type? _receiverAsTypeName(ast.Expr e) {
    if (e is! ast.Ident) return null;
    final res = _resolution[e];
    if (res is! TopLevelRes) return null;
    final info = _types.of(res.decl);
    if (info == null) return null;
    // O tipo do receptor-como-tipo: `Stack` ⟹ `Stack<α…>` com os generics
    // ainda LIVRES — quem os determina é o contexto (§4.6). É o `[]` com outro
    // nome: zero args ⟹ nada de que sintetizar (vacuidade, 6.5.1).
    return NamedType(res.decl, info.kind, [
      for (final g in info.generics) TypeParamType(res.decl, g),
    ]);
  }

  /// Membro alcançado por **NOME DE TIPO** (`Stack.nova()`), não por valor.
  ///
  /// **É aqui que o prefixo ∀ do TIPO entra** — e é o que separa este caminho do
  /// `x.m()`. Com receptor-valor (`s: Stack<Int>`), os generics da classe já foram
  /// **fixados** pelo `_substOf(info, recv.args)` no `_lookup`, e o que sobra livre
  /// é rígido. Aqui não: o [_receiverAsTypeName] produz `Stack<T>` com o `T` ainda
  /// LIVRE — **este sítio É a instanciação da classe**. Logo o ∀ do call é
  /// `[∀ do tipo] ++ [∀ do método]`, e os `owner.args` **são** o ∀ do tipo.
  ///
  /// Sem isto o CA73 regride: `Stack.nova()` só tipava porque o `_freeParams`
  /// varria a assinatura e pegava aquele `T` por acidente. O acidente acertava
  /// aqui e errava no `self.set(x: 5)` — mesmo mecanismo, dois resultados. Era o
  /// **trocadilho de representação**: `TypeParamType` servia de "rígido" E de
  /// "buraco". O prefixo desfaz o trocadilho.
  Type _staticMember(ast.Member n, Type owner) {
    exprTypes[n.receiver] = owner;
    final r = _lookup(owner, n.name, n);
    if (r == null) {
      _err('unknown-member', n);
      return const ErrorType();
    }
    if (!r.isStatic) {
      _err('instance-via-type', n); // `Stack.push(x)` — `push` é da INSTÂNCIA
      return const ErrorType();
    }
    resolvedMembers[n] = r;
    final t = r.type;
    if (owner is NamedType && t is FunctionType) {
      // **Só os que OCORREM.** `static fn versao() -> Int` num `Stack<T>` não
      // menciona o `T`: quantificá-lo criaria uma variável que nada pode
      // determinar ⟹ `cannot-infer` num programa legítimo e **inexprimível** (não
      // há turbofish — GRAMMAR §6). E do lado do Kernel seria pior: a lowering
      // certa de `versao` tem `function.typeParameters == []`, logo emitir 1
      // type-arg violaria a aridade que o `verifier.dart:1305-1314` cobra.
      //
      // Filtrar aqui **não** reabre o buraco do `_freeParams`: aquele varria a
      // assinatura para **descobrir** o prefixo, e no caminho de receptor-VALOR
      // (`self.set(x: 5)`) o `T` é rígido e não devia ser descoberto. Aqui o
      // prefixo é **conhecido** (`owner.args`) e o receptor é NOME DE TIPO — este
      // sítio é a instanciação da classe, por construção. A ordem é a de
      // `info.generics`, preservada.
      final donos = [
        for (final a in owner.args)
          if (a is TypeParamType && _occursIn(a, t)) a,
      ];
      if (donos.isNotEmpty) {
        return FunctionType(
          t.params,
          t.ret,
          isAsync: t.isAsync,
          quantifiers: [...donos, ...t.quantifiers],
        );
      }
    }
    return t;
  }

  /// **Σ_membros** — o walk do **1.6.4**: *"Em analogia com a estrutura de
  /// blocos, o escopo de uma declaração do membro x em uma classe C se estende a
  /// qualquer subclasse C', **exceto se C' tiver uma declaração local com o
  /// mesmo nome x**"*. É a regra de aninhamento mais interno (1.6.3) aplicada à
  /// cadeia de herança em vez da pilha de blocos — o `Env.get` da **Fig. 2.37**
  /// com `prev` = superclasse. **Isso É o `override`. Zero invenção.**
  ///
  /// | Nível | Quem | Colisão |
  /// | :-: | :-- | :-- |
  /// | **0** | campos + métodos próprios **+ `extension`/`impl`** | `duplicate-member` (A3, ruling §12-3) |
  /// | **1+** | superclasse + defaults de trait | **`ambiguous-member`** (diamante) |
  ///
  /// **Não inventar precedência entre trait e superclasse** — o livro não dá, e
  /// qualquer escolha seria mágica (P4).
  ResolvedMember? _lookup(Type recv, String name, ast.Member at) {
    if (recv is! NamedType) return null;
    final info = _types.of(recv.decl);
    if (info == null) return null;

    // **Substituição COMPOSTA ao subir** — `generics(D) := args` do RECEPTOR.
    final subst = _substOf(info, recv.args);

    // --- nível 0 ------------------------------------------------------------
    final f = (info.fields ?? const <FieldInfo>[])
        .where((x) => x.name == name)
        .firstOrNull;
    if (f != null) {
      // Campo é sempre do PRÓPRIO tipo: `extension` não adiciona armazenamento
      // (6.3.4 — largura/offset fecham na decl).
      return ResolvedMember(
        name, substitute(f.type, subst), recv, f.decl, false,
        origin: recv.decl,
      );
    }
    final m = info.methods.where((x) => x.name == name).firstOrNull;
    if (m != null) {
      return ResolvedMember(
        name, substitute(m.sig, subst), recv, m.decl, m.isStatic,
        origin: m.origin, // era descartado — o furo era de PROPAGAÇÃO
      );
    }

    // --- nível 1+ : herdados ------------------------------------------------
    // A substituição é aplicada ANTES de subir: `class D<T> : A<T>` com
    // `D<Int>` ⟹ sobe-se em `A<Int>`, não em `A<T>`. Sem isto, o `T` chegaria
    // livre no nível de cima (seria o 3º bug da série "generic não substituído").
    final sources = [for (final s in info.sources) substitute(s, subst)];
    final hits = <ResolvedMember>[];
    for (final s in sources) {
      final r = _lookup(s, name, at);
      if (r != null) hits.add(r);
    }
    if (hits.isEmpty) return null;
    if (hits.length > 1) {
      // Diamante: dois herdados DISTINTOS com o mesmo nome. Precedência entre
      // trait e superclasse não existe no livro — inventá-la seria mágica.
      final distinct = {for (final h in hits) h.decl};
      if (distinct.length > 1) {
        _err('ambiguous-member', at);
        return null;
      }
    }
    return hits.first;
  }

  // --- modo CHECK (⇐) — top-down -------------------------------------------

  /// `Γ ⊢ e ⇐ T`. **É aqui que o invariante de nulidade vive** (§4.6): `nil` só
  /// existe neste modo, e só contra `OptionalType`.
  void _check(ast.Expr e, Type expected) {
    // `nil` NÃO sintetiza (§4.3): a regra é `Γ ⊢ nil ⇐ OptionalType(T)`.
    if (e is ast.NilLit) {
      if (expected is! OptionalType && expected is! ErrorType) {
        // O MANDATO da fase (nullity-invariant.md, decisão de dono 2026-07-11):
        // `nil` é ausência INTENCIONAL e só é legal sob `T?`.
        _err('nil-under-non-optional', e);
        exprTypes[e] = const ErrorType();
        return;
      }
      exprTypes[e] = expected;
      return;
    }

    // **Closure com param sem tipo é CHECKING-ONLY** (§4.2.1): os params herdam
    // o esperado. É a produção `E → { $0 … }` da §5.1 — atributo HERDADO (5.1.1).
    if (e is ast.Closure && _isCheckingOnly(e)) {
      _closureAgainst(e, expected);
      return;
    }

    // Literais de coleção VAZIOS: a §4.1 dá o tipo por contexto.
    if ((e is ast.ListExpr && e.elements.isEmpty) ||
        (e is ast.MapExpr && e.entries.isEmpty)) {
      exprTypes[e] = expected;
      return;
    }

    // **Chamada em posição de CHECK**: o `expected` desce no retorno (§4.6).
    // É o que faz `let s: Stack<Int> = Stack.nova()` tipar — e o que impede o
    // built-in de ter um poder que o tipo do usuário não tem (face 1).
    if (e is ast.Call) {
      final got = _call(e, expected);
      exprTypes[e] = got;
      if (got is ErrorType || expected is ErrorType) return;
      if (!_isSubtype(got, expected)) _err('type-mismatch', e);
      return;
    }

    // **`.variant`** — o `.` é o glifo cuja ÚNICA função é delegar ao contexto
    // (§4.9: *"resolução contextual é legítima quando o glifo a PEDE"*).
    //
    // ⚠️ O fundamento aqui **não é a vacuidade** do 6.5.1 (010 §4.1, Fundamento
    // B): `.v` também tem zero subexpressões, mas o que o impede de sintetizar
    // é **o nome da variante não determinar o enum** — se só um enum no escopo
    // tivesse `.none`, sintetizar seria possível. **Não fazer é POLÍTICA**, e a
    // política é a §4.9. (Usar a vacuidade aqui nos desarmaria no dia em que
    // alguém propusesse *"só um enum tem `.none`, deixa sintetizar"*.)
    if (e is ast.EnumShorthand) {
      _enumShorthand(e, expected);
      return;
    }

    final actual = _synth(e);
    if (actual is ErrorType || expected is ErrorType) return;
    // **Subsunção — o ÚNICO ponto onde `≤` é consultado** (§4.3; Pierce & Turner
    // TOPLAS 2000 §3). Espalhar `isSubtype` pelo checker é como se produz
    // checker inconsistente.
    if (!_isSubtype(actual, expected)) _err('type-mismatch', e);
  }

  /// `Γ ⊢ .v ⇐ E`, com `v ∈ Σ(E)` — spec 010 §4.1 / 011.
  ///
  /// **`T?` é `Option`** (ruling do dono 2026-07-12: `Option<T>` ≡ `T?`, `nil` =
  /// `.none`), então `.none` contra `OptionalType` é legal. Isso **não** conflita
  /// com o `member-on-optional`: aquele é sobre **membros** (`.foo()`) — API de
  /// instância; este é sobre **variante**, que é construção, não chamada.
  void _enumShorthand(ast.EnumShorthand n, Type expected) {
    exprTypes[n] = expected;
    if (expected is ErrorType) return;

    if (expected is OptionalType) {
      // `Σ(Option) = {some, none}`. O `.some(v)` leva payload ⟹ é um `Call`,
      // não chega aqui nu.
      if (n.variant != 'none') _err('unknown-variant', n);
      return;
    }
    if (expected is! NamedType) {
      _err('variant-against-non-enum', n);
      return;
    }
    final info = _types.of(expected.decl);
    if (info == null || info.kind != TypeKind.enum_) {
      _err('variant-against-non-enum', n);
      return;
    }
    final vs = info.variants ?? const <VariantInfo>[];
    final v = vs.where((x) => x.name == n.variant).firstOrNull;
    if (v == null) {
      _err('unknown-variant', n);
      return;
    }
    // Variante COM payload exige args ⟹ tem de ser `Call`, não shorthand nu.
    if (v.payload.isNotEmpty) _err('variant-needs-payload', n);
  }

  /// `Γ ⊢ (x, …) => e ⇐ (T₁,…,Tₙ) → U` — **os params HERDAM** (§4.2.1).
  ///
  /// ⚠️ **A restrição normativa do 5.1.1** (a primeira metade da frase, que a
  /// 009 §5.1 omitiu ao citar): *"**não permitimos que um atributo herdado no nó
  /// N seja definido em termos dos valores dos atributos de seus filhos**, [mas]
  /// permitimos que um atributo sintetizado no nó N seja definido em termos dos
  /// valores dos atributos herdados do próprio nó N"*. ⟹ **`expected` NÃO pode
  /// ser derivado do corpo da closure** — nada de espiar o corpo para descobrir
  /// o tipo do param.
  /// [u] presente ⟹ estamos dentro de um `_call` e o **retorno esperado pode
  /// ainda ser variável** — o corpo é quem a resolve (ver R2 do [_call]).
  void _closureAgainst(ast.Closure n, Type expected, [Unifier? u]) {
    exprTypes[n] = expected;
    if (expected is! FunctionType) {
      _err('closure-against-non-function', n);
      _closureParams(n, const []);
      return;
    }
    // **Aridade contextual** (§12-A, respondido pela própria F3): closure sem
    // `$k` chega com `hasExplicitParams: false` e params vazios — ela ADOTA a
    // aridade esperada e ignora os args. É o `map { g() }` do comentário da F3:
    // *"exige 1 arg mas usa 0 — forçar arity-0 seria errado"*. Não há binder a
    // ligar (o corpo não referencia param nenhum), então só o corpo desce.
    if (!n.hasExplicitParams && n.params.isEmpty) {
      _closureBodyOrSynth(n, expected, u);
      return;
    }

    // Com `$k`, a aridade veio do scan sintático da F3 (teto `$255` no léxico).
    // A F3 é infalível aqui — a fatia C confia e não revalida.
    if (n.params.length != expected.params.length) {
      _err('closure-arity-mismatch', n);
      _closureParams(n, const []);
      return;
    }
    _closureParams(n, [for (final p in expected.params) p.type]);

    _closureBodyOrSynth(n, expected, u);
  }

  /// O corpo, nos dois modos possíveis de retorno.
  void _closureBodyOrSynth(ast.Closure n, FunctionType expected, Unifier? u) {
    // Retorno AINDA variável (só ocorre sob `u`): o corpo **sintetiza** e
    // unifica. É o `U` de `mapa<T,U>` — a closure é a única fonte dele.
    if (u != null && _hasTypeVar(expected.ret)) {
      final body = n.body;
      if (body is ast.ExprBody) {
        final got = _synth(body.e);
        if (!u.unify(expected.ret, got)) _err('type-mismatch', body.e);
      } else {
        // RD-1: corpo-bloco não rende ⟹ nada de que inferir o retorno. (Pós-F3
        // só sobra bloco MULTI-statement — o de 1 expressão já virou `ExprBody`.)
        _err('cannot-infer', n);
      }
      return;
    }
    _closureBody(n, expected.ret);
  }

  /// Liga cada param: **anotado é VERIFICADO; sem tipo HERDA** (§4.2.1).
  void _closureParams(ast.Closure n, List<Type> want) {
    for (var i = 0; i < n.params.length; i++) {
      final p = n.params[i];
      final inherited = i < want.length ? want[i] : const ErrorType();
      if (p.type == null) {
        binderTypes[p] = inherited;
      } else {
        final declared = _annotated(p.type!);
        binderTypes[p] = declared;
        // Param anotado NÃO herda: ele é contrato, e contrato se confere.
        if (i < want.length && declared != inherited && inherited is! ErrorType) {
          _errAt('param-type-mismatch', p.offset, p.length);
        }
      }
    }
  }

  void _closureBody(ast.Closure n, Type ret) {
    final saved = _currentFnReturn;
    _currentFnReturn = ret;
    switch (n.body) {
      case ast.ExprBody b:
        // No modo `⇐` o corpo é CHECADO contra o retorno — não sintetizado-e-
        // comparado. É o que faz corpo `nil`/`[]`/`.variant` funcionar.
        if (ret is VoidType) {
          _synth(b.e);
        } else {
          _check(b.e, ret);
        }
      case ast.BlockBody b:
        // RD-1: bloco NÃO rende. O corpo-bloco de closure não é confrontado com
        // o retorno — quem confronta é `return` (e "todo caminho retorna?" é F6).
        _block(b.b);
    }
    _currentFnReturn = saved;
  }

  /// A relação `≤` do §4.2b — nominal e **DECLARADA**. `struct` é final (P2:
  /// subtipagem de valor é slicing); variância **invariante** (covariância em
  /// container mutável é insound — o array store do Java).
  bool _isSubtype(Type sub, Type sup) {
    if (sub == sup) return true;
    if (sub is ErrorType || sup is ErrorType) return true; // absorvente
    if (sub is NeverType) return true; // bottom — só nesta direção
    if (sup is OptionalType) {
      // `T ≤ T?` — o modificador admite o valor (§4.6).
      return sub is OptionalType ? false : _isSubtype(sub, sup.inner);
    }
    if (sub is FunctionType && sup is FunctionType) {
      // **`s → t`** (6.3.1). Sem este arm, função ≤ função só existia via `==` do
      // topo — e como o `==` de `ParamType` carregava o `label`, **nenhuma função
      // nomeada casava com um tipo-função anotado** (`_topLevelType` dá
      // `label: 'x'`; `(Int) -> Int` nasce `positional`). Ordem superior só
      // funcionava com closure.
      //
      // **INVARIANTE nos params e no retorno**, por enquanto — mesma disciplina do
      // `_argsConform` e pelo mesmo motivo: co/contravariância de função é ruling
      // futuro, não subproduto deste fix, e monotonia manda começar restrito
      // (relaxar depois preserva todo programa válido; apertar depois quebra).
      // Este é o ponto único que aquele ruling substituiria.
      return sub == sup;
    }
    if (sub is NamedType && sup is NamedType) {
      // `class D : Animal` ⟹ `D ≤ Animal` (`struct` nunca herda); conformance de
      // trait é declaração de intenção (ADR-0012 A2).
      //
      // **O alcance daqui e o do `_lookup` têm de COINCIDIR** — e "coincidir"
      // nunca foi sobre CÓDIGO, é sobre o conjunto ALCANÇÁVEL. As duas perguntas
      // têm álgebras diferentes (o `_lookup` é *"que membro este nome denota?"* —
      // mais-interno vence, 1.6.4, + `ambiguous-member` no diamante; este é um
      // predicado puro), então fundi-las exigiria parametrizar o monoide do
      // resultado. O ponto único correto é **a aresta já instanciada**
      // ([_superTypesOf]): a `sources` dá a lista, ela dá a lista SUBSTITUÍDA.
      //
      // Recursão na própria cabeça, sobre o pai **instanciado** ⟹ os args são
      // comparados **a cada hop** e a transitividade (S-Trans) sai de graça.
      // Isto é subtipagem ALGORÍTMICA — **lacuna declarada do Dragon** (o livro
      // não tem trait/interface nem regra de subsunção): Pierce, TAPL 15.2 /
      // Fig. 15-3.
      //
      // Sem guarda de ciclo: a A3 cortou as arestas (Fig. 2.37).
      if (_sameApplication(sub, sup)) return true;
      for (final s in _superTypesOf(sub)) {
        if (_isSubtype(s, sup)) return true; // o pai já vem INSTANCIADO
      }
      return false;
    }
    return false;
  }

  /// Duas aplicações do MESMO construtor.
  ///
  /// Deliberadamente redundante com o `sub == sup` do topo do [_isSubtype] — e a
  /// redundância **é a costura**: sob variância, `==` deixa de ser a regra dos
  /// args e **só este ponto muda**.
  bool _sameApplication(NamedType a, NamedType b) =>
      identical(a.decl, b.decl) && _argsConform(a.args, b.args);

  /// A regra dos type-args — **o ponto único da variância** (§4.2b: hoje
  /// **INVARIANTE** ⟹ `==` par a par).
  ///
  /// **Aqui mora a prova de terminação do [_isSubtype], e ela é CONDICIONAL:**
  /// com invariância, `_argsConform` **não recursa** (`==` estrutural, decidível)
  /// ⟹ nunca se desce nos args ⟹ a medida é a **profundidade do DAG de decls**,
  /// que a A3 garante acíclico (`_checkInheritanceCycles` corta). O crescimento
  /// do TIPO (`List<List<…>>`) é irrelevante: `class C<T> : D<C<C<T>>>` sobe
  /// C→D, compara por `==`, e D não tem pai. Fim.
  ///
  /// ⚠️ **No dia em que a variância entrar, esta prova cai:** `A<X> ≤ A<Y>` vira
  /// consulta recursiva a `≤`, a medida some, e nominal + variância + herança
  /// **expansiva** é **INDECIDÍVEL** (Kennedy & Pierce 2007, *"On Decidability of
  /// Nominal Subtyping with Variance"*). O requisito passa a ser o **teste de
  /// herança expansiva** (Viroli 2000) — que é o que C#/.NET e a JVM fazem.
  /// Quem mexer aqui paga essa conta.
  bool _argsConform(List<Type> a, List<Type> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// As arestas para cima de um tipo **APLICADO** — a [TypeInfo.sources]
  /// **substituída**. É onde o [_isSubtype] e o `_lookup` coincidem **por
  /// construção**.
  ///
  /// **Substituir é o que faltava**, e era o furo: o walk antigo comparava só
  /// decls (`identical`) e **descartava os args** ⟹ `class D : A<Int>` satisfazia
  /// `A<String>`. O `_lookup` já fazia certo (*"`class D<T> : A<T>` com `D<Int>`
  /// ⟹ sobe-se em `A<Int>`, não em `A<T>`"*) — eu unifiquei o ALCANCE dos dois
  /// walks e os deixei divergir na SUBSTITUIÇÃO.
  ///
  /// **Passa pelo `substitute`, nunca mapeia à mão** (spec 009 §4.6, condição 1):
  /// ele roteia pelo smart constructor `optional()`. Sem isso, `class D<T> : A<T?>`
  /// com `D<String?>` daria `A<String??>` em vez de `A<String?>`, e a subsunção
  /// para `A<String?>` seria **FALSA** — programa legítimo rejeitado, mudo, e sem
  /// conserto do lado do usuário (não há turbofish — GRAMMAR §6).
  List<NamedType> _superTypesOf(NamedType t) {
    final info = _types.of(t.decl);
    if (info == null) return const [];
    final subst = _substOf(info, t.args);
    return [
      for (final s in info.sources)
        if (substitute(s, subst) case NamedType n) n,
    ];
  }

  /// Resolve a anotação — via o [Collector], porque A2 só viu as ASSINATURAS.
  /// Sem isto, `let x: String = nil` receberia `ErrorType` (absorvente) e o
  /// `nil-under-non-optional` — o MANDATO da fase — falharia em silêncio.
  Type _annotated(ast.TypeNode n) => _collector.resolveTypeNode(n);

  void _err(String code, ast.AstNode at) =>
      _errAt(code, at.offset, at.length);

  /// `Param` carrega span (D2) mas **não é `AstNode`** — mesma família do
  /// `FieldPattern` (débito D4 da F4). Daí a sobrecarga por span cru.
  void _errAt(String code, int offset, int length) =>
      errors.add(CheckError(code, offset, length));
}
