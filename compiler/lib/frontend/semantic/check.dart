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
  return CheckResult(program, collected.types, errors, collected.annotations);
}

class Checker {
  /// A fatia A. Além da tabela, o **resolvedor de anotações**: A2 só percorre
  /// assinaturas, então o `String` de `let x: String = e` só é resolvido aqui.
  final Collector _collector;
  final CheckResult _collected;
  final Map<ast.AstNode, ResolvedName> _resolution;
  final List<CheckError> errors = [];

  /// `<Expr, Type>` — side-table nº1 (§7). Consumidores: F7 (Kernel tipado — a
  /// alavanca do ADR-0007) e F6. **Totalidade** é invariante (§7-4): todo nó de
  /// expressão tem entrada, e `typeOf` FALHA se não tiver — o oracle faz
  /// `?? const UnknownType()`, um default que esconde buraco.
  final Map<ast.Expr, Type> exprTypes = Map.identity();

  /// Tipo de cada binder (param/`let`), para o `Ident` resolver.
  final Map<Object, Type> _binderTypes = Map.identity();

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

  void _decl(ast.Decl d) {
    switch (d) {
      case ast.FnDecl n:
        _fnDecl(n);
      case ast.StructDecl n:
        _members(n.members);
      case ast.ClassDecl n:
        _members(n.members);
      case ast.EnumDecl n:
        _members(n.members);
      case ast.TraitDecl n:
        _members(n.members);
      case ast.ActorDecl n:
        _members(n.members);
      default:
        break;
    }
  }

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
        default:
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
        _binderTypes[p] = const ErrorType();
      } else {
        _binderTypes[p] = _annotated(p.type!);
      }
      if (p.defaultValue != null) {
        _check(p.defaultValue!, _binderTypes[p]!);
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
        // Não-objetivo desta spec (ruling §12-4): tipar o binder exigiria uma
        // tabela hard-coded (`List<T>→T`…) — a mágica que §4.5/§8.3 recusam. O
        // trait `Iterator` (`next() -> Option<T>`) é spec própria (fatia D).
        break;
      default:
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

  void _bindPattern(ast.Pattern p, Type t) {
    switch (p) {
      case ast.BindPattern _:
        _binderTypes[p] = t;
      case ast.WildcardPattern _:
        break;
      default:
        // Destructure com tipo é fatia C/D (precisa dos campos/args do tipo).
        break;
    }
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
      _binderTypes[p] = t;
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
    return FunctionType(params, ret, isAsync: n.asyncMarker != ast.AsyncMarker.sync);
  }

  Type _ident(ast.Ident n) {
    final res = _resolution[n];
    return switch (res) {
      LocalRes r => _binderTypes[r.binder] ?? const ErrorType(),
      TopLevelRes r => _topLevelType(r.decl),
      _ => const ErrorType(),
    };
  }

  Type _topLevelType(ast.AstNode decl) => switch (decl) {
    // O escopo dos generics da CALLEE tem de estar aberto aqui também: este é o
    // caminho do `_call`, e ele lê a assinatura de OUTRA fn (letrec de módulo —
    // a chamada não está dentro do `_fnDecl` dela). Sem isto, `mapa(xs) { … }`
    // resolveria `List<T>` com o `T` fora de escopo.
    ast.FnDecl n => _withGenerics(n, n.generics, () => FunctionType(
      [for (final p in n.params) p.type == null ? const ErrorType() : _annotated(p.type!)],
      n.returnType == null ? const VoidType() : _annotated(n.returnType!),
      isAsync: n.asyncMarker != ast.AsyncMarker.sync,
    )),
    ast.LetStmt n => _binderTypes[n.target] ?? const ErrorType(),
    _ => const ErrorType(),
  };

  T _withGenerics<T>(ast.AstNode owner, List<ast.GenericParam> gs, T Function() f) {
    if (gs.isEmpty) return f();
    _collector.pushGenericScope(owner, gs);
    final r = f();
    _collector.popGenericScope();
    return r;
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
  Type _call(ast.Call n) {
    final calleeT = _synth(n.callee);

    if (calleeT is ErrorType) {
      for (final a in n.args) { _synth(a.value); } // totalidade (§7-4)
      return calleeT;
    }
    if (calleeT is! FunctionType) {
      _err('not-callable', n);
      for (final a in n.args) { _synth(a.value); }
      return const ErrorType();
    }

    // **Aridade** (§4.8) — o oracle NÃO checa isto (`type_checker.dart:156`:
    // *"Conservador: NÃO valida aridade nem labels nesta fatia"*).
    if (n.args.length != calleeT.params.length) {
      _err('arity-mismatch', n);
      for (final a in n.args) { _synth(a.value); }
      return const ErrorType();
    }

    // Instancia as variáveis LIGADAS da assinatura por variáveis NOVAS.
    final u = Unifier();
    final inst = u.instantiate(calleeT, _freeParams(calleeT)) as FunctionType;

    // --- R1: args que TÊM regra de síntese → `_synth` + `unify` --------------
    // O critério é SINTÁTICO (a forma de introdução), não "closures por último".
    final deferred = <int>[];
    final errors = <(String, ast.Expr)>[]; // adiados p/ sair em ordem-FONTE
    for (var i = 0; i < n.args.length; i++) {
      if (_isCheckingOnly(n.args[i].value)) {
        deferred.add(i);
        continue;
      }
      final at = _synth(n.args[i].value);
      if (!u.unify(inst.params[i], at)) {
        errors.add(('type-mismatch', n.args[i].value));
      }
    }

    // --- R2: formas checking-only → `_check` contra o param JÁ substituído ---
    for (final i in deferred) {
      final arg = n.args[i].value;
      final want = u.resolve(inst.params[i]);

      // **Closure é o caso fino, e o `mapa<T,U>` o expõe.** Em
      // `mapa(xs) { $0 + 1 }`, a R1 fixa `T := Int` mas deixa `α_U` LIVRE — o
      // `U` só é determinado pelo CORPO. Exigir `want` inteiro determinado aqui
      // seria `cannot-infer` num caso que a inferência alcança: o que a closure
      // precisa receber são os **params**; o retorno ela **rende**.
      if (arg is ast.Closure && want is FunctionType) {
        if (want.params.any(_hasTypeVar)) {
          errors.add(('cannot-infer', arg)); // aí sim: o param é o buraco
          exprTypes[arg] = const ErrorType();
          continue;
        }
        _closureAgainst(arg, want, u); // o `u` deixa o corpo RESOLVER o retorno
        continue;
      }

      // Demais formas checking-only (`nil`/`[]`/`{}`/`.variant`): não rendem
      // nada de que unificar, então precisam do tipo INTEIRO determinado.
      // O erro é NAQUELE arg (não no call inteiro) — é onde se conserta.
      if (_hasTypeVar(want)) {
        errors.add(('cannot-infer', arg));
        exprTypes[arg] = const ErrorType();
        continue;
      }
      _check(arg, want);
    }

    // **Ordem-FONTE** (§4.3 / CA51): as 2 rodadas visitam fora da ordem textual,
    // mas a ordem que o usuário LÊ é a do arquivo. É o contrato da 009 §11.
    errors.sort((a, b) => a.$2.offset.compareTo(b.$2.offset));
    for (final (code, at) in errors) { _err(code, at); }
    if (errors.isNotEmpty) return const ErrorType();

    final ret = u.resolve(inst.ret);
    // Se sobrou variável, a inferência não alcançou: **`cannot-infer`**, nunca
    // `dynamic` (ADR-0013). Ex.: retorno genérico não determinado pelos args.
    if (_hasTypeVar(ret)) {
      _err('cannot-infer', n);
      return const ErrorType();
    }
    return ret;
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

  /// As variáveis LIGADAS (∀) que aparecem numa assinatura.
  List<TypeParamType> _freeParams(Type t) {
    final out = <TypeParamType>{};
    void walk(Type x) {
      switch (x) {
        case TypeParamType p:
          out.add(p);
        case OptionalType n:
          walk(n.inner);
        case NamedType n:
          n.args.forEach(walk);
        case BuiltinType n:
          n.args.forEach(walk);
        case FunctionType n:
          n.params.forEach(walk);
          walk(n.ret);
        case TupleType n:
          n.elements.forEach(walk);
        default:
          break;
      }
    }

    walk(t);
    return out.toList();
  }

  bool _hasTypeVar(Type t) => switch (t) {
    TypeVar _ => true,
    OptionalType n => _hasTypeVar(n.inner),
    NamedType n => n.args.any(_hasTypeVar),
    BuiltinType n => n.args.any(_hasTypeVar),
    FunctionType n => n.params.any(_hasTypeVar) || _hasTypeVar(n.ret),
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
    _synth(n.scrutinee);
    // Exaustividade é **F6** (§4.7) — aqui só o join dos braços.
    Type? acc;
    for (final arm in n.arms) {
      if (arm.guard != null) _checkCondition(arm.guard!);
      final t = _synth(arm.body);
      acc = acc == null ? t : _join(acc, t, n);
    }
    return acc ?? const ErrorType();
  }

  /// `.field`/`.método` é **type-directed** (contrato 008 §5.4) e exige a
  /// resolução de membro — fatia **C**. O que fecha AQUI é o mandato da nulidade:
  Type _member(ast.Member n) {
    final recv = _synth(n.receiver);
    // **`member-on-optional`** (§4.6): `T?` tem **Σ_membros = ∅** — nenhuma API
    // de instância. O `!= nil` segue legal; o erro nasce no `.foo()`, ensinando
    // o idioma (`if let x = x { … }`). É o melhor momento pedagógico da língua.
    if (recv is OptionalType) {
      _err('member-on-optional', n);
      return const ErrorType();
    }
    if (recv is ErrorType) return recv;
    return _cannotInfer(n); // resolução de membro: fatia C
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

    final actual = _synth(e);
    if (actual is ErrorType || expected is ErrorType) return;
    // **Subsunção — o ÚNICO ponto onde `≤` é consultado** (§4.3; Pierce & Turner
    // TOPLAS 2000 §3). Espalhar `isSubtype` pelo checker é como se produz
    // checker inconsistente.
    if (!_isSubtype(actual, expected)) _err('type-mismatch', e);
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
    _closureParams(n, expected.params);

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
        _binderTypes[p] = inherited;
      } else {
        final declared = _annotated(p.type!);
        _binderTypes[p] = declared;
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
    if (sub is NamedType && sup is NamedType) {
      // `class D : Animal` ⟹ `D ≤ Animal`. `struct` nunca herda.
      var cur = _types.of(sub.decl);
      while (cur != null) {
        final s = cur.superclass;
        if (s is! NamedType) break;
        if (identical(s.decl, sup.decl)) return true;
        cur = _types.of(s.decl);
      }
      // Conformance de trait é declaração de intenção (ADR-0012 A2).
      final info = _types.of(sub.decl);
      for (final t in info?.traits ?? const <Type>[]) {
        if (t is NamedType && identical(t.decl, sup.decl)) return true;
      }
    }
    return false;
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
