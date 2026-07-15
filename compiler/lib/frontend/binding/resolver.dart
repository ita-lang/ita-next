// ===========================================================================
// resolver.dart — Resolver visitor da Fase 4 (Binding), spec 008.
// ===========================================================================
//
// Passe estático 1-walk O(n) (CI 11.2.1) sobre a AST CANÔNICA (pós-desugar
// Fase 3). Liga cada uso de nome (`Ident`/`SelfExpr`) à sua declaração,
// gravando numa side-table `Map.identity<AstNode, ResolvedName>` — a AST NÃO é
// mutada (ADR-0004). Erros de binding vão para uma lista (estilo N2: não aborta
// no 1º; coleta e segue).
//
// Fundamentação:
//  - CI cap 11: pilha de escopos, split declare/define (11.3.2), fn ansiosa
//    (11.3.5), context-flags p/ return/break fora de contexto (11.5.1).
//  - Dragon 1.6.3 (escopo léxico estrito) / 2.7.1 (símbolos encadeados).
//  - Two-tier (§5.2): MÓDULO = declare-ALL-then-resolve (letrec, forward-ref);
//    BLOCO/FN = single-pass léxico (decl precede uso).
//
// FRONTEIRA F4↔F5 (contrato ADR-0011): resolve SÓ o namespace de VALOR com
// escopo léxico. NÃO resolve (type-directed → Fase 5): `Member.name`/`.field`/
// `.método`, `.variant`/`EnumShorthand`, aridade/overload, nomes de TIPO
// (`NamedType`/annotations/bounds/generics). Aqui, só o RECEPTOR e o callee-
// `Ident` de uma `Call` entram.
// ===========================================================================

import 'package:ita_next_compiler/frontend/parser/ast.dart';
import 'package:ita_next_compiler/frontend/binding/scope.dart';

/// Um erro de binding (type-agnostic). [code] é slug EN kebab-case (Const.
/// Art. IV). Formato canônico do dump: `resolve-error: <code> @<offset>+<length>`.
class BindingError {
  final String code;
  final int offset;
  final int length;
  const BindingError(this.code, this.offset, this.length);

  String format() => 'resolve-error: $code @$offset+$length';

  @override
  String toString() => format();
}

/// Resultado do binding: a árvore canônica + a side-table + os erros.
class ResolveResult {
  final Program program; // a AST canônica (pós-desugar) sobre a qual se resolveu
  final Map<AstNode, ResolvedName> resolution;
  final List<BindingError> errors;
  const ResolveResult(this.program, this.resolution, this.errors);
}

// ===========================================================================
// Resolver — o visitor.
// ===========================================================================

class Resolver {
  /// Side-table por identidade (ADR-0004). Chave = nó de USO (`Ident`|`SelfExpr`).
  final Map<AstNode, ResolvedName> resolution = Map.identity();

  /// Erros coletados (não aborta no 1º — estilo N2 das Fases 1/2).
  final List<BindingError> errors = [];

  late Scope _scope; // escopo corrente (topo da pilha)

  // Context-flags (CI 11.5.1). Salvos/restaurados nas fronteiras.
  bool _inLoop = false; // dentro do corpo de um while/for
  bool _inFn = false; //   dentro de um corpo de fn/closure/init
  AstNode? _selfType; //   nó do tipo envolvente (método) — null fora de método

  /// Ponto de entrada: resolve o [program] CANÔNICO (já desaçucarado).
  void run(Program program) {
    _scope = Scope(null, isModule: true);
    // Two-pass no módulo (letrec, §5.2): 1) declara TODOS os nomes top-level;
    // 2) resolve os corpos → recursão mútua / forward-ref (ordem textual não
    // importa; a ordem de inicialização em runtime é Fase 6).
    for (final n in program.body) {
      _declareTopLevel(n);
    }
    for (final n in program.body) {
      _resolveTopLevel(n);
    }
  }

  // -------------------------------------------------------------------------
  // Erros.
  // -------------------------------------------------------------------------

  void _error(String code, AstNode node) =>
      errors.add(BindingError(code, node.offset, node.length));

  void _errorSpan(String code, int offset, int length) =>
      errors.add(BindingError(code, offset, length));

  // -------------------------------------------------------------------------
  // Escopos.
  // -------------------------------------------------------------------------

  void _enterScope({bool isFnBoundary = false}) {
    _scope = Scope(_scope, isFnBoundary: isFnBoundary);
  }

  void _exitScope() {
    _scope = _scope.parent!;
  }

  /// Resolve um `Ident`: sobe a cadeia de escopos contando `hops` e detectando
  /// captura (cruzou fronteira de fn/closure). Retorna null = não-resolvido.
  ResolvedName? _lookupIdent(Ident use) {
    Scope? c = _scope;
    var hops = 0;
    var crossedFn = false;
    while (c != null) {
      final e = c.lookupLocal(use.name);
      if (e != null) {
        // `let a = a` (CI 11.3.2): o nome existe mas ainda não está pronto.
        // (No módulo tudo é letrec/pronto → não se aplica.)
        if (!e.ready && !c.isModule) {
          _error('read-in-own-initializer', use);
        }
        if (c.isModule) return TopLevelRes(e.binder as AstNode);
        return LocalRes(e.binder, hops, crossedFn);
      }
      if (c.isFnBoundary) crossedFn = true; // sair desta fn = capturar o de fora
      c = c.parent;
      if (c != null) hops++;
    }
    return null;
  }

  // -------------------------------------------------------------------------
  // Passada 1 do módulo — declare-ALL (letrec).
  // -------------------------------------------------------------------------

  void _declareTopLevel(AstNode n) {
    switch (n) {
      case FnDecl d:
        _declareGlobal(d.name, d, d.offset, d.length);
      case StructDecl d:
        _declareGlobal(d.name, d, d.offset, d.length);
      case ClassDecl d:
        _declareGlobal(d.name, d, d.offset, d.length);
      case EnumDecl d:
        _declareGlobal(d.name, d, d.offset, d.length);
      case TraitDecl d:
        _declareGlobal(d.name, d, d.offset, d.length);
      case ActorDecl d:
        _declareGlobal(d.name, d, d.offset, d.length);
      case LetStmt s:
        // `let`/`var` global: cada nome do pattern entra no módulo (ready — a
        // ordem de inicialização é Fase 6). Sem literais em let (irrefutável).
        _declarePattern(s.target, ready: true);
      // Impl/Extension NÃO declaram nome de valor (adicionam membros a um tipo);
      // Operator/Import/expr-stmt idem. Seus corpos são vistos na passada 2.
      default:
        break;
    }
  }

  void _declareGlobal(String name, AstNode binder, int offset, int length) {
    if (!_scope.declare(name, binder, ready: true)) {
      _errorSpan('duplicate-declaration', offset, length);
    }
  }

  // -------------------------------------------------------------------------
  // Passada 2 do módulo — resolve corpos.
  // -------------------------------------------------------------------------

  void _resolveTopLevel(AstNode n) {
    if (n is Decl) {
      _topDecl(n);
    } else if (n is Stmt) {
      _topStmt(n);
    }
  }

  void _topStmt(Stmt s) {
    // No módulo os binders de `let`/`var` já foram declarados (letrec) — só
    // resolvemos o valor (sem re-declarar, sem split). Os demais stmts (script
    // mode: if/while/for/expr…) seguem a via normal.
    if (s is LetStmt) {
      if (s.value != null) _expr(s.value!);
      return;
    }
    _stmt(s);
  }

  void _topDecl(Decl d) {
    switch (d) {
      case FnDecl n:
        _resolveFnDecl(n, selfType: null);
      case StructDecl n:
        _resolveMembers(n.members, n);
      case ClassDecl n:
        _resolveMembers(n.members, n);
      case EnumDecl n:
        _resolveEnumCases(n.cases);
        _resolveMembers(n.members, n);
      case TraitDecl n:
        _resolveMembers(n.members, n);
      case ActorDecl n:
        _resolveMembers(n.members, n);
      case ImplDecl n:
        _resolveMembers(n.members, n.target);
      case ExtensionDecl n:
        _resolveMembers(n.members, n.target);
      case OperatorDecl n:
        _resolveFnDecl(n.fn, selfType: null);
      // Sem corpo de VALOR a resolver aqui (tipos/imports/erros).
      case FieldDecl():
      case InitDecl():
      case ImportDecl():
      case ErrorDecl():
        break;
    }
  }

  /// Payload dos cases de um enum (`Some(v: Int = e)`). O case não tem corpo nem
  /// escopo — os params do payload só descrevem a FORMA do dado, e nada os
  /// referencia por nome aqui. O que há para ligar é o DEFAULT, e ele vê o
  /// escopo externo (mesma regra do default de param de fn), sem `self`: um case
  /// é construtor do próprio enum, não método de uma instância.
  void _resolveEnumCases(List<EnumCase> cases) {
    for (final c in cases) {
      for (final p in c.payload) {
        if (p.defaultValue != null) _expr(p.defaultValue!);
      }
    }
  }

  // -------------------------------------------------------------------------
  // Membros de tipo (métodos, init, defaults de campo) — `self` disponível.
  // -------------------------------------------------------------------------

  void _resolveMembers(List<Decl> members, AstNode selfType) {
    for (final m in members) {
      _resolveMember(m, selfType);
    }
  }

  void _resolveMember(Decl m, AstNode selfType) {
    switch (m) {
      case FnDecl n:
        // Método estático NÃO tem `self` (P4: sem mágica).
        _resolveFnDecl(n, selfType: n.isStatic ? null : selfType);
      case InitDecl n:
        final saved = _selfType;
        _selfType = selfType;
        _resolveFunction(n.params, BlockBody(n.body));
        _selfType = saved;
      case FieldDecl n:
        if (n.defaultValue != null) {
          final saved = _selfType;
          _selfType = selfType;
          _expr(n.defaultValue!);
          _selfType = saved;
        }
      case OperatorDecl n:
        _resolveFnDecl(n.fn, selfType: null);
      // Tipos aninhados / demais: defensivo, nada a ligar como valor aqui.
      case StructDecl():
      case ClassDecl():
      case EnumDecl():
      case TraitDecl():
      case ActorDecl():
      case ImplDecl():
      case ExtensionDecl():
      case ImportDecl():
      case ErrorDecl():
        break;
    }
  }

  void _resolveFnDecl(FnDecl n, {required AstNode? selfType}) {
    final saved = _selfType;
    _selfType = selfType;
    if (n.body == null) {
      // Assinatura de trait: não há corpo, logo nenhum escopo de params a abrir
      // — mas os DEFAULTS são expressões e resolvem como em qualquer fn (escopo
      // externo, `self` disponível). Sem isto, dar um corpo à assinatura mudava
      // se o default era checado: `fn f(x: Int = bogus)` passava batido e
      // `fn f(x: Int = bogus) => x` acusava.
      for (final p in n.params) {
        if (p.defaultValue != null) _expr(p.defaultValue!);
      }
    } else {
      _resolveFunction(n.params, n.body!);
    }
    _selfType = saved;
  }

  /// Resolve uma função/closure/init: um ÚNICO escopo (fronteira de fn) para os
  /// params + o corpo (params e locais do topo do corpo compartilham escopo —
  /// CI 11.4.1; não duplica escopo se o corpo é bloco). Defaults de param veem o
  /// escopo EXTERNO (não os params).
  void _resolveFunction(List<Param> params, FnBody body) {
    final savedLoop = _inLoop;
    final savedFn = _inFn;
    _inLoop = false; // break/continue NÃO cruzam fronteira de fn (CI 11.5.1)
    _inFn = true;

    for (final p in params) {
      if (p.defaultValue != null) _expr(p.defaultValue!); // escopo externo
    }

    _enterScope(isFnBoundary: true);
    for (final p in params) {
      if (!_scope.declare(p.name, p, ready: true)) {
        _errorSpan('duplicate-declaration', p.offset, p.length);
      }
    }
    switch (body) {
      case ExprBody b:
        _expr(b.e);
      case BlockBody b:
        _resolveStmts(b.b.stmts); // sem escopo extra: mesmo escopo dos params
    }
    _exitScope();

    _inLoop = savedLoop;
    _inFn = savedFn;
  }

  // -------------------------------------------------------------------------
  // Blocos / statements (single-pass léxico, Dragon 1.6.3).
  // -------------------------------------------------------------------------

  /// Bloco autônomo (`if`/`while`/`for`-body via caminhos próprios, bare-block):
  /// abre escopo-filho e resolve os stmts em ordem.
  void _block(Block b) {
    _enterScope();
    _resolveStmts(b.stmts);
    _exitScope();
  }

  void _resolveStmts(List<Stmt> stmts) {
    for (final s in stmts) {
      _stmt(s);
    }
  }

  void _stmt(Stmt s) {
    switch (s) {
      case LetStmt n:
        // Split declare/define (CI 11.3.2): declara NÃO-pronto → resolve value
        // (`let a = a` vira read-in-own-initializer) → define.
        _declarePattern(n.target, ready: false);
        if (n.value != null) _expr(n.value!);
        _definePattern(n.target);
      case ReturnStmt n:
        if (!_inFn) _error('return-outside-fn', n);
        if (n.value != null) _expr(n.value!);
      case IfStmt n:
        _expr(n.cond);
        _block(n.then);
        if (n.orElse != null) _else(n.orElse!);
      case GuardStmt n:
        _expr(n.cond);
        _block(n.orElse);
      case GuardLetStmt n:
        _guardLet(n);
      case WhileStmt n:
        _expr(n.cond);
        final saved = _inLoop;
        _inLoop = true;
        _block(n.body);
        _inLoop = saved;
      case ForStmt n:
        _forStmt(n);
      case BreakStmt n:
        if (!_inLoop) _error('break-outside-loop', n);
      case ContinueStmt n:
        if (!_inLoop) _error('continue-outside-loop', n);
      case EmitStmt n:
        if (!_inFn) _error('emit-outside-fn', n);
        _expr(n.value);
      case ExprStmt n:
        _expr(n.expr);
      case BlockStmt n:
        _block(n.block);
      case ErrorStmt():
        break;
    }
  }

  void _else(Else e) {
    switch (e) {
      case ElseIf n:
        _stmt(n.ifStmt);
      case ElseBlock n:
        _block(n.block);
    }
  }

  /// `guard let PAT = value [&& cond] else { … }` — ESCOPO DE CONTINUAÇÃO
  /// (Swift): o binder entra no escopo ATUAL a partir daqui (não num filho),
  /// para o RESTO do bloco. Ordem que dá a visibilidade certa:
  ///   1. `value` no escopo atual (target ainda não ligado);
  ///   2. `else` num escopo-filho, ANTES de ligar o target (else NÃO vê o bind);
  ///   3. liga o target no escopo atual (continuação);
  ///   4. `cond` (&&-refino) já com o target visível (spec 005 §3.1b).
  void _guardLet(GuardLetStmt n) {
    _expr(n.value);
    _block(n.orElse);
    _declarePattern(n.target, ready: true);
    if (n.condition != null) _expr(n.condition!);
  }

  /// `for PAT in iterable { body }` — `iterable` no escopo externo; um escopo-
  /// filho abriga o `target` + o corpo (retido como core, baixa p/
  /// `ForInStatement` do Kernel).
  void _forStmt(ForStmt n) {
    _expr(n.iterable);
    _enterScope();
    _declarePattern(n.target, ready: true);
    final saved = _inLoop;
    _inLoop = true;
    _resolveStmts(n.body.stmts);
    _inLoop = saved;
    _exitScope();
  }

  // -------------------------------------------------------------------------
  // Expressões (o walk de valor).
  // -------------------------------------------------------------------------

  void _expr(Expr e) {
    switch (e) {
      case IntLit():
      case FloatLit():
      case BoolLit():
      case NilLit():
      case ErrorExpr():
        break;
      // `.variant` é resolvido por CONTEXTO/tipo (Fase 5) — não aqui.
      case EnumShorthand():
        break;
      case Ident n:
        final r = _lookupIdent(n);
        if (r == null) {
          _error('unresolved-name', n); // ausência na side-table = `->?` no dump
        } else {
          resolution[n] = r;
        }
      case SelfExpr n:
        if (_selfType != null) {
          resolution[n] = SelfRes(_selfType!);
        } else {
          _error('self-outside-method', n);
        }
      case Str n:
        for (final p in n.parts) {
          if (p is StrInterp) _expr(p.expr);
        }
      case Binary n:
        _expr(n.left);
        _expr(n.right);
      case Unary n:
        _expr(n.operand);
      case Await n:
        _expr(n.operand);
      case Spawn n:
        _expr(n.operand);
      case Panic n:
        _expr(n.operand);
      case Assign n:
        // `assign-to-immutable` é type-directed (`obj.field=`) → Fase 5/6.
        _expr(n.target);
        _expr(n.value);
      case Call n:
        _expr(n.callee); // callee-`Ident` É valor; aridade/overload = Fase 5
        for (final a in n.args) {
          _expr(a.value); // labels de arg NÃO são nomes de valor
        }
      case Member n:
        _expr(n.receiver); // `.name` = Fase 5 (precisa do tipo do receptor)
      case OptChain n:
        _expr(n.receiver); // (desaçucarado; defensivo) `.name` = Fase 5
      case Index n:
        _expr(n.receiver);
        _expr(n.index);
      case TupleIndex n:
        _expr(n.receiver); // `.N` = Fase 5
      case ForceUnwrap n:
        _expr(n.operand); // (desaçucarado; defensivo)
      case Try n:
        _expr(n.operand);
      case CopyWith n:
        _expr(n.receiver);
        for (final f in n.fields) {
          _expr(f.value); // NOMES de campo = Fase 5; só os VALORES são valor
        }
      case Closure n:
        _resolveFunction(n.params, n.body); // `self` preservado (captura)
      case IfExpr n:
        _ifExpr(n);
      case MatchExpr n:
        _matchExpr(n);
      case TupleExpr n:
        n.elements.forEach(_expr);
      case ListExpr n:
        n.elements.forEach(_expr);
      case MapExpr n:
        for (final en in n.entries) {
          _expr(en.key);
          _expr(en.value);
        }
      case RangeExpr n:
        _expr(n.start);
        _expr(n.end);
      case WhereExpr n:
        _where(n); // (desaçucarado; defensivo)
    }
  }

  void _ifExpr(IfExpr n) {
    _expr(n.subject);
    if (n.binding == null) {
      _expr(n.then); // if-EXPRESSÃO booleana (core)
    } else {
      // if-let não deveria sobreviver ao desugar; defensivo (liga PAT no `then`).
      _enterScope();
      _declarePattern(n.binding!, ready: true);
      _expr(n.then);
      _exitScope();
    }
    _expr(n.orElse);
  }

  void _matchExpr(MatchExpr n) {
    _expr(n.scrutinee);
    for (final arm in n.arms) {
      _enterScope(); // 1 escopo-filho por braço
      _declarePattern(arm.pattern, ready: true);
      if (arm.guard != null) _expr(arm.guard!);
      _expr(arm.body);
      _exitScope();
    }
  }

  void _where(WhereExpr n) {
    _enterScope();
    for (final b in n.bindings) {
      _declarePattern(b.target, ready: true);
    }
    for (final b in n.bindings) {
      if (b.value != null) _expr(b.value!);
    }
    _expr(n.value);
    _exitScope();
  }

  // -------------------------------------------------------------------------
  // Patterns — declaração de binders (destructuring liga vários) + define.
  // -------------------------------------------------------------------------

  /// Declara TODO nome ligado por [p] no escopo corrente. Em patterns de MATCH
  /// (refutáveis), os sub-`Expr` de literais/ranges são USOS de valor e são
  /// resolvidos aqui. Em `let` (irrefutável) não há literais → só binders.
  void _declarePattern(Pattern p, {required bool ready}) {
    switch (p) {
      case BindPattern n:
        _declareName(n.name, n, n.offset, n.length, ready);
      case RestPattern n:
        if (n.name != null) _declareName(n.name!, n, n.offset, n.length, ready);
      case WildcardPattern():
      case ErrorPattern():
        break;
      case LiteralPattern n:
        _expr(n.literal);
      case RangePattern n:
        _expr(n.start);
        _expr(n.end);
      case EnumPattern n:
        for (final s in n.subpatterns) {
          _declarePattern(s, ready: ready);
        }
      case ListPattern n:
        for (final el in n.elements) {
          _declarePattern(el, ready: ready);
        }
      case RecordPattern n:
        for (final f in n.fields) {
          _declareFieldPattern(f, n, ready);
        }
      case StructPattern n:
        for (final f in n.fields) {
          _declareFieldPattern(f, n, ready);
        }
    }
  }

  /// Campo de record/struct-pattern. Homônimo (`{ x }`, pattern null) liga `x`;
  /// como o `FieldPattern` não é um nó com span próprio, o binder cai no nó-
  /// pattern envolvente [fallback] (limitação documentada — a precisão fina de
  /// destructuring por RECORD é débito; LIST-pattern dá binders distintos).
  void _declareFieldPattern(FieldPattern f, AstNode fallback, bool ready) {
    if (f.pattern == null) {
      _declareName(f.name, fallback, fallback.offset, fallback.length, ready);
    } else {
      _declarePattern(f.pattern!, ready: ready);
    }
  }

  void _declareName(
    String name,
    Object binder,
    int offset,
    int length,
    bool ready,
  ) {
    if (!_scope.declare(name, binder, ready: ready)) {
      _errorSpan('duplicate-declaration', offset, length);
    }
  }

  /// Marca todos os nomes de [p] como prontos (fim do split, só usado no `let`).
  void _definePattern(Pattern p) {
    switch (p) {
      case BindPattern n:
        _scope.define(n.name);
      case RestPattern n:
        if (n.name != null) _scope.define(n.name!);
      case WildcardPattern():
      case ErrorPattern():
      case LiteralPattern():
      case RangePattern():
        break;
      case EnumPattern n:
        for (final s in n.subpatterns) {
          _definePattern(s);
        }
      case ListPattern n:
        for (final el in n.elements) {
          _definePattern(el);
        }
      case RecordPattern n:
        for (final f in n.fields) {
          _defineFieldPattern(f);
        }
      case StructPattern n:
        for (final f in n.fields) {
          _defineFieldPattern(f);
        }
    }
  }

  void _defineFieldPattern(FieldPattern f) {
    if (f.pattern == null) {
      _scope.define(f.name);
    } else {
      _definePattern(f.pattern!);
    }
  }
}
