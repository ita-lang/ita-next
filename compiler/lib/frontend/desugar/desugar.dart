// ===========================================================================
// desugar.dart — Fase 3 (Desugaring / lowering), spec 007.
// ===========================================================================
//
// Tradução AST→AST CANÔNICA sobre a MESMA hierarquia `sealed` de `ast.dart`
// (Dragon 5.3 — um 2º walk SDD não exige um 2º tipo de nó; NÃO um HIR paralelo,
// P11). Transformer visitor POST-ORDER (Dragon 5.2): filhos canônicos antes do
// pai, resolvendo o aninhamento (`a |> b where {…}`). Passe ÚNICO e idempotente:
// nenhuma reescrita produz nó-açúcar, logo um walk basta e `desugar ∘ desugar =
// desugar` (as saídas são só nós core).
//
// TYPE-AGNOSTIC (ADR-0011, correção da spec 007 §10): copy-with, currying e `**`
// NÃO expandem aqui (precisam de tipo → Fases 4/5/7). `Try` permanece core
// (early-return excede `=> expr`, RD-1). `GuardLetStmt` idem (ver decisão abaixo).
//
// SPANS (M1 / DWARF): TODO nó sintetizado herda offset+length do açúcar-fonte;
// os pós-fixos sintetizados herdam também `opOffset`. Desugar que zera span
// quebra stack-trace AOT — é requisito duro (spec 007 §5.2/CA11).
//
// GENSYM reservado (§5.3): `$` + tag-alfabética + contador POR TAG (`$x0`, `$c0`,
// `$it0`). Lexicamente inatingível (o léxico só gera `$`+dígitos p/ shorthand, ou
// IDENT começando por letra/`_`) → zero-captura por construção (Kohlbecker 1986).
// ===========================================================================

import 'package:ita_next_compiler/frontend/parser/ast.dart';
import 'package:ita_next_compiler/frontend/parser/pattern_vars.dart';

/// Ponto de entrada puro: AST bruta (Fase 2) → AST canônica (Fase 3).
Program desugarProgram(Program program) => Desugarer().run(program);

// ===========================================================================
// Desugarer — o transformer.
// ===========================================================================

class Desugarer {
  // Gensym: contador independente por tag (`x`, `c`, `it`) para que o 1º de cada
  // tipo seja `$…0` (espelha CA1/CA4). Reiniciado a cada passe (instância nova);
  // como o 2º passe não acha açúcar, não aloca gensym → dump idêntico (idempotente).
  final Map<String, int> _counters = {};

  String _gensym(String tag) {
    final n = _counters[tag] ?? 0;
    _counters[tag] = n + 1;
    return '\$$tag$n';
  }

  Program run(Program p) =>
      Program(p.body.map(_topNode).toList(), p.offset, p.length);

  // O topo carrega Decl | Stmt (o parser só enxerta esses). Defensivo: devolve o
  // nó cru se vier outra coisa (nunca acontece com a AST da Fase 2).
  AstNode _topNode(AstNode n) {
    if (n is Decl) return _decl(n);
    if (n is Stmt) return _stmt(n);
    return n;
  }

  // --- declarações (pass-through; só desce nos Expr internos) ----------------

  Decl _decl(Decl d) => switch (d) {
    FnDecl n => _fnDecl(n),
    FieldDecl n => FieldDecl(
      n.isPublic,
      n.isMutable,
      n.name,
      n.type,
      n.defaultValue == null ? null : _expr(n.defaultValue!),
      n.offset,
      n.length,
    ),
    InitDecl n =>
      InitDecl(n.isPublic, _params(n.params), _block(n.body), n.offset, n.length),
    StructDecl n => StructDecl(
      n.isPublic,
      n.name,
      n.generics,
      n.traits,
      n.members.map(_decl).toList(),
      n.offset,
      n.length,
    ),
    ClassDecl n => ClassDecl(
      n.isPublic,
      n.name,
      n.generics,
      n.superclass,
      n.traits,
      n.members.map(_decl).toList(),
      n.offset,
      n.length,
    ),
    EnumDecl n => EnumDecl(
      n.isPublic,
      n.name,
      n.generics,
      n.cases.map(_enumCase).toList(),
      n.members.map(_decl).toList(),
      n.offset,
      n.length,
    ),
    TraitDecl n => TraitDecl(
      n.isPublic,
      n.name,
      n.generics,
      n.members.map(_decl).toList(),
      n.offset,
      n.length,
    ),
    ImplDecl n => ImplDecl(
      n.trait,
      n.target,
      n.members.map(_decl).toList(),
      n.offset,
      n.length,
    ),
    ExtensionDecl n => ExtensionDecl(
      n.target,
      n.traits,
      n.members.map(_decl).toList(),
      n.offset,
      n.length,
    ),
    ActorDecl n => ActorDecl(
      n.isPublic,
      n.name,
      n.members.map(_decl).toList(),
      n.offset,
      n.length,
    ),
    OperatorDecl n => OperatorDecl(
      n.symbol,
      n.fixity,
      n.precedence,
      n.associativity,
      _fnDecl(n.fn),
      n.offset,
      n.length,
    ),
    ImportDecl n => n,
    ErrorDecl n => n,
  };

  FnDecl _fnDecl(FnDecl n) => FnDecl(
    n.isPublic,
    n.isStatic,
    n.isOverride,
    n.asyncMarker,
    n.name,
    n.generics,
    _params(n.params),
    n.returnType,
    n.body == null ? null : _fnBody(n.body!),
    n.offset,
    n.length,
  );

  EnumCase _enumCase(EnumCase c) => EnumCase(c.name, _params(c.payload));

  List<Param> _params(List<Param> ps) => ps.map(_param).toList();

  Param _param(Param p) => Param(
    p.label,
    p.name,
    p.type,
    p.defaultValue == null ? null : _expr(p.defaultValue!),
    p.offset,
    p.length,
  );

  FnBody _fnBody(FnBody b) => switch (b) {
    ExprBody n => ExprBody(_expr(n.e)),
    BlockBody n => BlockBody(_block(n.b)),
  };

  Block _block(Block b) => Block(b.stmts.map(_stmt).toList(), b.offset, b.length);

  // --- statements ------------------------------------------------------------

  Stmt _stmt(Stmt s) => switch (s) {
    LetStmt n => LetStmt(
      n.isVar,
      _pattern(n.target),
      n.type,
      n.value == null ? null : _expr(n.value!),
      n.offset,
      n.length,
    ),
    ReturnStmt n =>
      ReturnStmt(n.value == null ? null : _expr(n.value!), n.offset, n.length),
    IfStmt n => IfStmt(
      _expr(n.cond),
      _block(n.then),
      n.orElse == null ? null : _else(n.orElse!),
      n.offset,
      n.length,
    ),
    GuardStmt n => GuardStmt(_expr(n.cond), _block(n.orElse), n.offset, n.length),
    // guard-let RETIDO como core (ver nota no topo do arquivo): a continuação +
    // else-divergente são STATEMENTS, não cabem em `=> expr` (RD-1, mesma fronteira
    // do `Try`). Só desce nos Expr internos.
    GuardLetStmt n => GuardLetStmt(
      _pattern(n.target),
      _expr(n.value),
      n.condition == null ? null : _expr(n.condition!),
      _block(n.orElse),
      n.offset,
      n.length,
    ),
    WhileStmt n => WhileStmt(_expr(n.cond), _block(n.body), n.offset, n.length),
    // `for` RETIDO como core (ruling do dono 2026-07-12): o Dart Kernel tem
    // `ForInStatement` nativo — a VM itera de graça (Grupo B), não vale lowerar
    // (Dragon 6.1: não desaçucarar além do que o backend oferece; CI 9.5.1 só
    // lowera por falta de primitivo no tree-walker). Só desce em iterable/body;
    // `isAwait` preservado. O protocolo Itá-próprio (trait Iterator) é débito.
    ForStmt n => ForStmt(
      n.isAwait,
      _pattern(n.target),
      _expr(n.iterable),
      _block(n.body),
      n.offset,
      n.length,
    ),
    BreakStmt n => n,
    ContinueStmt n => n,
    EmitStmt n => EmitStmt(_expr(n.value), n.offset, n.length),
    ExprStmt n => ExprStmt(_expr(n.expr), n.offset, n.length),
    BlockStmt n => BlockStmt(_block(n.block), n.offset, n.length),
    ErrorStmt n => n,
  };

  Else _else(Else e) => switch (e) {
    ElseIf n => ElseIf(_stmt(n.ifStmt) as IfStmt),
    ElseBlock n => ElseBlock(_block(n.block)),
  };

  // --- expressões (as reescritas §5.2 vivem aqui) ----------------------------

  Expr _expr(Expr e) => switch (e) {
    IntLit n => n,
    FloatLit n => n,
    Str n => Str(n.parts.map(_strPart).toList(), n.offset, n.length),
    BoolLit n => n,
    NilLit n => n,
    Ident n => _ident(n),
    SelfExpr n => n,
    EnumShorthand n => n,
    ErrorExpr n => n,
    Binary n => switch (n.op) {
      BinaryOp.coalesce => _coalesce(n), // a ?? b
      BinaryOp.pipe => _pipe(n), //         x |> f(a)
      BinaryOp.compose => _compose(n), //   f >> g
      _ => Binary(n.op, _expr(n.left), _expr(n.right), n.offset, n.length),
    },
    Unary n => Unary(n.op, _expr(n.operand), n.offset, n.length),
    Await n => Await(_expr(n.operand), n.offset, n.length),
    Spawn n => Spawn(_expr(n.operand), n.offset, n.length),
    Panic n => Panic(_expr(n.operand), n.offset, n.length),
    // Cadeias pós-fixas: `_postfix` empurra os pós-fixos externos a um `?.` p/
    // dentro do braço `.some` (senão o `.none` viraria `.none()`/`.none.c`/…).
    Assign n => _assign(n),
    Call n => _postfix(n),
    Member n => _postfix(n),
    OptChain n => _postfix(n), // a?.b (+ pós-fixos sobre a cadeia)
    Index n => _postfix(n),
    TupleIndex n => _postfix(n),
    ForceUnwrap n => _forceUnwrap(n), // a!
    // RETIDO: Try baixa no codegen (Fase 7). Só desce no operando.
    Try n => Try(_expr(n.operand), n.opOffset, n.offset, n.length),
    // RETIDO: copy-with é type-directed (enumera campos → Fase 5/7). Só desce.
    CopyWith n => _postfix(n),
    Closure n => _closure(n),
    IfExpr n => n.binding == null
        // if-EXPRESSÃO booleana = CORE (mapeia p/ ConditionalExpression do Kernel;
        // reduzir a match forçaria a máquina de decisão da Fase 6 sobre um ternário
        // trivial — net-negativo, P4). Só desce nos ramos.
        ? IfExpr(
            null,
            _expr(n.subject),
            _expr(n.then),
            _expr(n.orElse),
            n.offset,
            n.length,
          )
        // if-let = AÇÚCAR → match .some/.none (ramos já são Expr, sem problema RD-1).
        : _ifLet(n),
    MatchExpr n =>
      MatchExpr(_expr(n.scrutinee), n.arms.map(_arm).toList(), n.offset, n.length),
    TupleExpr n => TupleExpr(n.elements.map(_expr).toList(), n.offset, n.length),
    ListExpr n => ListExpr(n.elements.map(_expr).toList(), n.offset, n.length),
    MapExpr n => MapExpr(n.entries.map(_mapEntry).toList(), n.offset, n.length),
    RangeExpr n =>
      RangeExpr(n.inclusive, _expr(n.start), _expr(n.end), n.offset, n.length),
    WhereExpr n => _where(n), // V where { … }
  };

  /// Uso de shorthand param na grafia canônica: `$01` → `$1`, `$007` → `$7`.
  /// O `$k` é notação de ÍNDICE e o índice é numérico — mesma normalização que o
  /// léxico já faz em `01`/`007` (intLiteral 1/7). [_closure] nomeia o param
  /// sintético pelo decimal canônico, então sem isto `{ $01 }` declararia `$1` e
  /// usaria `$01` → `unresolved-name`. Grafias misturadas (`{ $01 + $1 }`) ficam
  /// no MESMO param. Span preservado (é o mesmo token-fonte).
  Ident _ident(Ident n) {
    final index = _dollarIndex(n.name);
    if (index == null) return n; // IDENT comum ou gensym (`$x0`) — intocado
    final canonical = '\$$index';
    return canonical == n.name ? n : Ident(canonical, n.offset, n.length);
  }

  StrPart _strPart(StrPart p) => switch (p) {
    StrLit _ => p,
    StrInterp n => StrInterp(_expr(n.expr)),
  };

  Arg _arg(Arg a) => Arg(a.label, _expr(a.value));

  FieldInit _fieldInit(FieldInit f) => FieldInit(f.name, _expr(f.value));

  MapEntryNode _mapEntry(MapEntryNode e) =>
      MapEntryNode(_expr(e.key), _expr(e.value), e.offset, e.length);

  MatchArm _arm(MatchArm a) => MatchArm(
    _pattern(a.pattern),
    a.guard == null ? null : _expr(a.guard!),
    _expr(a.body),
  );

  // --- patterns --------------------------------------------------------------

  /// Patterns são estrutura, mas dois deles embutem `Expr`: `LiteralPattern` e
  /// `RangePattern`. O vetor de açúcar hoje é a STRING interpolada do literal
  /// (`match x { "${a ?? b}" => … }`) — a grammar §pattern só admite INT nas
  /// pontas do range, então `RangePattern` é sempre IntLit na prática; o walk
  /// cobre os dois porque o TIPO permite Expr e a gramática pode crescer.
  ///
  /// Sem descer aqui, o `??` sobrevive dentro da pattern e a invariante "nenhum
  /// açúcar sobrevive à Fase 3" quebra (o `core_check` desce em patterns pelo
  /// mesmo motivo — senão a violação passa em silêncio).
  ///
  /// Os binders (`BindPattern`/`RestPattern`) e o `WildcardPattern` são folhas
  /// sem Expr; os compostos só recursam.
  Pattern _pattern(Pattern p) => switch (p) {
    BindPattern _ || WildcardPattern _ || RestPattern _ || ErrorPattern _ => p,
    LiteralPattern n => LiteralPattern(_expr(n.literal), n.offset, n.length),
    RangePattern n => RangePattern(
      n.inclusive,
      _expr(n.start),
      _expr(n.end),
      n.offset,
      n.length,
    ),
    EnumPattern n => EnumPattern(
      n.variant,
      n.subpatterns.map(_pattern).toList(),
      n.offset,
      n.length,
    ),
    ListPattern n =>
      ListPattern(n.elements.map(_pattern).toList(), n.offset, n.length),
    RecordPattern n =>
      RecordPattern(n.fields.map(_fieldPattern).toList(), n.offset, n.length),
    StructPattern n => StructPattern(
      n.typeName,
      n.fields.map(_fieldPattern).toList(),
      n.hasRest,
      n.offset,
      n.length,
    ),
  };

  FieldPattern _fieldPattern(FieldPattern f) => FieldPattern(
    f.name,
    f.pattern == null ? null : _pattern(f.pattern!),
  );

  // =========================================================================
  // Reescritas §5.2. Cada nó sintetizado herda o span do açúcar-fonte.
  // =========================================================================

  /// `a ?? b` → `match a { .some($x) => $x, .none => b }`. (oracle _compileNilCoalesce)
  Expr _coalesce(Binary n) {
    final a = _expr(n.left);
    final b = _expr(n.right);
    final x = _gensym('x');
    return _match(n, a, [
      _someArm(n, x, _idn(n, x)),
      _noneArm(n, b),
    ]);
  }

  /// Desaçucara uma cadeia pós-fixa (`Call`/`Member`/`Index`/`TupleIndex`/
  /// `CopyWith`/`OptChain`). O nó base — `a?.b` — reescreve para
  /// `match a { .some($x) => $x.b, .none => .none }` (spec §1, modelo Swift).
  ///
  /// O ponto sutil é o `?.` NÃO ser desaçucarado isoladamente: um pós-fixo aplicado
  /// à cadeia (`a?.b()`, `a?.b.c`, `a?.b[i]`) tem de cair DENTRO do braço `.some` —
  /// senão o braço `.none` receberia `()`/`.c`/`[i]` e viraria miscompile
  /// (`.none()`, `.none.c`, `.none[i]`). Por isso coletamos os pós-fixos EXTERNOS ao
  /// `?.` (do mais externo ao mais interno) e os reaplicamos sobre `$x.membro`.
  ///
  /// Cadeias `a?.b?.c` continuam matches ANINHADOS (o `?.` externo é o primeiro
  /// nó visto; seu receptor `a?.b` desaçucara recursivamente): o `.none` do interno
  /// propaga sobre o resultado (Option) — semanticamente correto (short-circuit 1×).
  ///
  /// SEM `?.` na spine, reconstrói idêntico ao passe direto — MESMA árvore e MESMA
  /// ordem de gensym: o primary desaçucara ANTES dos frames (que desaçucaram os
  /// sub-nós independentes na reaplicação), espelhando "receptor antes de args".
  /// `(a ?? b).c` cai aqui: o `.none` do `??` devolve VALOR, não é o `.none` do `?.`.
  Expr _postfix(Expr e, [List<Expr Function(Expr)>? seed]) {
    // Reconstrutores dos pós-fixos externos, do mais externo ao mais interno.
    final frames = seed ?? <Expr Function(Expr)>[];
    var cur = e;
    while (true) {
      switch (cur) {
        case OptChain n:
          final recv = _expr(n.receiver);
          final x = _gensym('x');
          Expr some = Member(_idn(n, x), n.name, n.opOffset, n.offset, n.length);
          for (final f in frames.reversed) {
            some = f(some); // reaplica os externos DENTRO do `.some`
          }
          return _match(n, recv, [
            _someArm(n, x, some),
            _noneArm(n, EnumShorthand('none', n.offset, n.length)),
          ]);
        case Call n:
          frames.add(
            (r) =>
                Call(r, n.args.map(_arg).toList(), n.opOffset, n.offset, n.length),
          );
          cur = n.callee;
        case Member n:
          frames.add((r) => Member(r, n.name, n.opOffset, n.offset, n.length));
          cur = n.receiver;
        case Index n:
          frames.add(
            (r) => Index(r, _expr(n.index), n.opOffset, n.offset, n.length),
          );
          cur = n.receiver;
        case TupleIndex n:
          frames.add((r) => TupleIndex(r, n.index, n.opOffset, n.offset, n.length));
          cur = n.receiver;
        case CopyWith n:
          frames.add(
            (r) => CopyWith(
              r,
              n.fields.map(_fieldInit).toList(),
              n.opOffset,
              n.offset,
              n.length,
            ),
          );
          cur = n.receiver;
        default:
          // primary sem `?.`: desaçucara e reaplica os frames por FORA.
          Expr acc = _expr(cur);
          for (final f in frames.reversed) {
            acc = f(acc);
          }
          return acc;
      }
    }
  }

  /// `lval = v`: se `lval` tem `?.` na spine, o assign inteiro entra no braço
  /// `.some` (`a?.b = c` só escreve sob `.some`; `.none` → no-op). Reusa `_postfix`
  /// com o assign como frame mais externo do target — o `value` desaçucara por
  /// último, preservando "target antes de value".
  Expr _assign(Assign n) => _postfix(n.target, [
    (lval) => Assign(n.op, lval, _expr(n.value), n.offset, n.length),
  ]);

  /// `a!` → `match a { .some($x) => $x, .none => panic("force-unwrap on none") }`.
  Expr _forceUnwrap(ForceUnwrap n) {
    final v = _expr(n.operand);
    final x = _gensym('x');
    final panic = Panic(_str(n, 'force-unwrap on none'), n.offset, n.length);
    return _match(n, v, [
      _someArm(n, x, _idn(n, x)),
      _noneArm(n, panic),
    ]);
  }

  /// `if let P = e => t else f` → `match e { .some(P) => t, .none => f }`.
  /// A pattern do usuário `P` entra DIRETO como subpattern de `.some` (sem gensym
  /// — o binder já foi nomeado pelo usuário).
  Expr _ifLet(IfExpr n) {
    final subj = _expr(n.subject);
    final then = _expr(n.then);
    final orElse = _expr(n.orElse);
    return _match(n, subj, [
      MatchArm(
        EnumPattern('some', [_pattern(n.binding!)], n.offset, n.length),
        null,
        then,
      ),
      _noneArm(n, orElse),
    ]);
  }

  /// `V where { let x1 = e1; … }` → let-in por bind irrefutável ANINHADO, mas em
  /// ORDEM DE DEPENDÊNCIA (spec 006 §3.6: `where` é LETREC — ordem de avaliação =
  /// dependência, NÃO textual; o CA1 usa forward-ref `total` antes de `a`/`b`).
  ///
  /// A dependência é SINTÁTICA (cabe na Fase 3, sem binding completo): binding X
  /// depende de Y sse o valor de X referencia LIVREMENTE (respeitando shadowing
  /// léxico) um nome ligado por Y — scan de vars livres ∩ nomes-do-`where`.
  /// Topological-sort (Kahn; empate em ordem-fonte, determinístico). Usa os NOMES
  /// do usuário (sem gensym/substituição: renomear exigiria resolução de nomes,
  /// Fase 4). A análise só sombreia por binders CERTOS → no pior caso over-approxima
  /// (ciclo falso), nunca erra a ordem. Ciclo entre bindings é inválido (spec): o
  /// resto travado cai em ordem-fonte — o diagnóstico preciso de where-cíclico é
  /// pós-binding (precisa de escopos reais). Pureza dos bindings = Fase 6 (ADR-0011).
  Expr _where(WhereExpr n) {
    final lets = n.bindings;
    if (lets.isEmpty) return _expr(n.value);

    // Valores DESAÇUCARADOS + dono de cada nome (destructure liga vários).
    // `nameOwner`: nome → índice do binding. O parser garante nomes distintos
    // entre bindings (`where-duplicate-binding`), então o `putIfAbsent` nunca
    // desempata de fato — é só a forma de preencher o mapa.
    final values = <Expr>[];
    final nameOwner = <String, int>{};
    for (var i = 0; i < lets.length; i++) {
      final value = lets[i].value;
      // O parser exige init no binding do `where` (`where-binding-needs-value`,
      // grammar §whereBinding). Chegar aqui é AST malformada — bug do compilador,
      // não erro do usuário. Fabricar `nil` (o que se fazia antes) ligaria o nome
      // a nil real sob tipo não-opcional e violaria o invariante de nulidade.
      if (value == null) {
        throw StateError(
          'Fase 3: where-binding sem valor @${lets[i].offset} — o parser deveria '
          'ter barrado com where-binding-needs-value',
        );
      }
      values.add(_expr(value));
      final vars = <String>{};
      collectPatternVars(lets[i].target, vars);
      for (final nm in vars) {
        nameOwner.putIfAbsent(nm, () => i);
      }
    }
    final whereNames = nameOwner.keys.toSet();

    // deps[i] = bindings cujos nomes o valor de i referencia livremente (exceto i).
    final deps = <Set<int>>[];
    for (var i = 0; i < lets.length; i++) {
      final refs = <String>{};
      _freeRefs(values[i], whereNames, const <String>{}, refs);
      deps.add({
        for (final nm in refs)
          if (nameOwner[nm] != null && nameOwner[nm] != i) nameOwner[nm]!,
      });
    }

    // Kahn: coloca (outer→inner) quem tem TODAS as deps já colocadas; empate =
    // ordem-fonte. Resto travado (ciclo) → anexa em ordem-fonte.
    final placed = <int>[];
    final done = List<bool>.filled(lets.length, false);
    var progressed = true;
    while (placed.length < lets.length && progressed) {
      progressed = false;
      for (var i = 0; i < lets.length; i++) {
        if (done[i]) continue;
        if (deps[i].every((d) => done[d])) {
          placed.add(i);
          done[i] = true;
          progressed = true;
        }
      }
    }
    for (var i = 0; i < lets.length; i++) {
      if (!done[i]) placed.add(i);
    }

    // Aninha: 1º colocado = OUTER (visível a todos os internos); V no fundo.
    var result = _expr(n.value);
    for (final i in placed.reversed) {
      result = MatchExpr(
        values[i],
        [MatchArm(_pattern(lets[i].target), null, result)],
        n.offset,
        n.length,
      );
    }
    return result;
  }

  // --- vars livres ∩ nomes-do-where (análise sintática p/ a ordenação letrec) ----
  // DESCE em closures (captura de variável = dependência real), respeitando o
  // shadowing léxico (params de closure, patterns de arm/if-let/for, lets de bloco
  // EM ORDEM). Só coleta nomes em [whereNames] e NÃO em [shadowed]. Só sombreia por
  // binders CERTOS → over-approxima quando incerto (seguro: no máx. ciclo falso,
  // nunca ordem errada). [shadowed] é lido, nunca mutado (cópias locais).

  void _freeRefs(
    Expr e,
    Set<String> whereNames,
    Set<String> shadowed,
    Set<String> out,
  ) {
    switch (e) {
      case IntLit():
      case FloatLit():
      case BoolLit():
      case NilLit():
      case SelfExpr():
      case EnumShorthand():
      case ErrorExpr():
        break;
      case Ident n:
        if (whereNames.contains(n.name) && !shadowed.contains(n.name)) {
          out.add(n.name);
        }
      case Str n:
        for (final p in n.parts) {
          if (p is StrInterp) _freeRefs(p.expr, whereNames, shadowed, out);
        }
      case Binary n:
        _freeRefs(n.left, whereNames, shadowed, out);
        _freeRefs(n.right, whereNames, shadowed, out);
      case Unary n:
        _freeRefs(n.operand, whereNames, shadowed, out);
      case Await n:
        _freeRefs(n.operand, whereNames, shadowed, out);
      case Spawn n:
        _freeRefs(n.operand, whereNames, shadowed, out);
      case Panic n:
        _freeRefs(n.operand, whereNames, shadowed, out);
      case Assign n:
        _freeRefs(n.target, whereNames, shadowed, out);
        _freeRefs(n.value, whereNames, shadowed, out);
      case Call n:
        _freeRefs(n.callee, whereNames, shadowed, out);
        for (final a in n.args) {
          _freeRefs(a.value, whereNames, shadowed, out);
        }
      case Member n:
        _freeRefs(n.receiver, whereNames, shadowed, out);
      case OptChain n:
        _freeRefs(n.receiver, whereNames, shadowed, out);
      case Index n:
        _freeRefs(n.receiver, whereNames, shadowed, out);
        _freeRefs(n.index, whereNames, shadowed, out);
      case TupleIndex n:
        _freeRefs(n.receiver, whereNames, shadowed, out);
      case ForceUnwrap n:
        _freeRefs(n.operand, whereNames, shadowed, out);
      case Try n:
        _freeRefs(n.operand, whereNames, shadowed, out);
      case CopyWith n:
        _freeRefs(n.receiver, whereNames, shadowed, out);
        for (final f in n.fields) {
          _freeRefs(f.value, whereNames, shadowed, out);
        }
      case Closure n:
        // params ligam nomes no CORPO; defaults veem o escopo externo (não os params).
        final inner = <String>{...shadowed};
        for (final p in n.params) {
          if (p.defaultValue != null) {
            _freeRefs(p.defaultValue!, whereNames, shadowed, out);
          }
          inner.add(p.name);
        }
        _freeRefsFnBody(n.body, whereNames, inner, out);
      case IfExpr n:
        _freeRefs(n.subject, whereNames, shadowed, out);
        if (n.binding == null) {
          _freeRefs(n.then, whereNames, shadowed, out);
        } else {
          final inner = <String>{...shadowed};
          collectPatternVars(n.binding!, inner);
          _freeRefs(n.then, whereNames, inner, out);
        }
        _freeRefs(n.orElse, whereNames, shadowed, out);
      case MatchExpr n:
        _freeRefs(n.scrutinee, whereNames, shadowed, out);
        for (final a in n.arms) {
          final inner = <String>{...shadowed};
          collectPatternVars(a.pattern, inner);
          if (a.guard != null) _freeRefs(a.guard!, whereNames, inner, out);
          _freeRefs(a.body, whereNames, inner, out);
        }
      case TupleExpr n:
        for (final el in n.elements) {
          _freeRefs(el, whereNames, shadowed, out);
        }
      case ListExpr n:
        for (final el in n.elements) {
          _freeRefs(el, whereNames, shadowed, out);
        }
      case MapExpr n:
        for (final en in n.entries) {
          _freeRefs(en.key, whereNames, shadowed, out);
          _freeRefs(en.value, whereNames, shadowed, out);
        }
      case RangeExpr n:
        _freeRefs(n.start, whereNames, shadowed, out);
        _freeRefs(n.end, whereNames, shadowed, out);
      case WhereExpr n:
        // Defensivo (pós-desugar não há WhereExpr): os bindings ligam nomes.
        final inner = <String>{...shadowed};
        for (final b in n.bindings) {
          collectPatternVars(b.target, inner);
        }
        for (final b in n.bindings) {
          if (b.value != null) {
            _freeRefs(b.value!, whereNames, inner, out);
          }
        }
        _freeRefs(n.value, whereNames, inner, out);
    }
  }

  void _freeRefsFnBody(
    FnBody b,
    Set<String> whereNames,
    Set<String> shadowed,
    Set<String> out,
  ) {
    switch (b) {
      case ExprBody n:
        _freeRefs(n.e, whereNames, shadowed, out);
      case BlockBody n:
        _freeRefsBlock(n.b, whereNames, shadowed, out);
    }
  }

  void _freeRefsBlock(
    Block b,
    Set<String> whereNames,
    Set<String> shadowed,
    Set<String> out,
  ) {
    final local = <String>{...shadowed};
    for (final s in b.stmts) {
      _freeRefsStmt(s, whereNames, local, out);
      // após a declaração, o nome ligado sombreia o RESTO do bloco (ordem léxica).
      if (s is LetStmt) collectPatternVars(s.target, local);
      if (s is GuardLetStmt) collectPatternVars(s.target, local);
    }
  }

  void _freeRefsStmt(
    Stmt s,
    Set<String> whereNames,
    Set<String> shadowed,
    Set<String> out,
  ) {
    switch (s) {
      case BreakStmt():
      case ContinueStmt():
      case ErrorStmt():
        break;
      case LetStmt n:
        // `let` não-recursivo: valor no escopo ANTES do bind (o shadow do próprio
        // nome é aplicado pelo _freeRefsBlock DEPOIS desta stmt).
        if (n.value != null) _freeRefs(n.value!, whereNames, shadowed, out);
      case ReturnStmt n:
        if (n.value != null) _freeRefs(n.value!, whereNames, shadowed, out);
      case IfStmt n:
        _freeRefs(n.cond, whereNames, shadowed, out);
        _freeRefsBlock(n.then, whereNames, shadowed, out);
        if (n.orElse != null) _freeRefsElse(n.orElse!, whereNames, shadowed, out);
      case GuardStmt n:
        _freeRefs(n.cond, whereNames, shadowed, out);
        _freeRefsBlock(n.orElse, whereNames, shadowed, out);
      case GuardLetStmt n:
        _freeRefs(n.value, whereNames, shadowed, out);
        if (n.condition != null) {
          // o refino `&&` vê o bind (spec 005 §3.1b: `guard let v = opt && v > 0`).
          final inner = <String>{...shadowed};
          collectPatternVars(n.target, inner);
          _freeRefs(n.condition!, whereNames, inner, out);
        }
        _freeRefsBlock(n.orElse, whereNames, shadowed, out); // else NÃO vê o bind
      case WhileStmt n:
        _freeRefs(n.cond, whereNames, shadowed, out);
        _freeRefsBlock(n.body, whereNames, shadowed, out);
      case ForStmt n:
        // `for` é retido como core; o target liga no corpo (não na iterável).
        _freeRefs(n.iterable, whereNames, shadowed, out);
        final inner = <String>{...shadowed};
        collectPatternVars(n.target, inner);
        _freeRefsBlock(n.body, whereNames, inner, out);
      case EmitStmt n:
        _freeRefs(n.value, whereNames, shadowed, out);
      case ExprStmt n:
        _freeRefs(n.expr, whereNames, shadowed, out);
      case BlockStmt n:
        _freeRefsBlock(n.block, whereNames, shadowed, out);
    }
  }

  void _freeRefsElse(
    Else e,
    Set<String> whereNames,
    Set<String> shadowed,
    Set<String> out,
  ) {
    switch (e) {
      case ElseIf n:
        _freeRefsStmt(n.ifStmt, whereNames, shadowed, out);
      case ElseBlock n:
        _freeRefsBlock(n.block, whereNames, shadowed, out);
    }
  }

  /// `f >> g` → `($c) => g(f($c))` (`$c` gensym reservado). (oracle _compileCompose)
  Expr _compose(Binary n) {
    final f = _expr(n.left);
    final g = _expr(n.right);
    final c = _gensym('c');
    // `$c` é 100% sintético (não existe no fonte) → span zero-width no offset do `>>`.
    final param = Param(null, c, null, null, n.offset, 0);
    final inner = Call(f, [Arg(null, _idn(n, c))], n.offset, n.offset, n.length);
    final body = Call(g, [Arg(null, inner)], n.offset, n.offset, n.length);
    return Closure(
      AsyncMarker.sync,
      true,
      [param],
      null,
      ExprBody(body),
      n.offset,
      n.length,
    );
  }

  /// `x |> f(a)` → `f(x, a)` (x = 1º posicional). `x |> f` (rhs não-Call) → `f(x)`.
  /// Rewrite ESTRUTURAL, type-agnostic — o dispatch static/dynamic é da codegen.
  Expr _pipe(Binary n) {
    final value = _expr(n.left);
    final rhs = _expr(n.right);
    if (rhs is Call) {
      // Preserva o callee e os args do rhs; injeta `value` na frente. O `opOffset`
      // real do `(` do rhs é mantido (DWARF aponta pro seletor verdadeiro).
      return Call(
        rhs.callee,
        [Arg(null, value), ...rhs.args],
        rhs.opOffset,
        n.offset,
        n.length,
      );
    }
    // rhs é Ident/Member/… → aplica como `rhs(value)`; `(` sintético no offset do `|>`.
    return Call(rhs, [Arg(null, value)], n.offset, n.offset, n.length);
  }

  /// Closure `{ $0 … }` (params implícitos) → params explícitos, aridade =
  /// maxIndex(`$k` no corpo)+1 (scan SINTÁTICO — o contexto/aridade real é Fase 5).
  /// SEM `$k`: mantém implícita (aridade genuinamente contextual, ex.: `map { g() }`
  /// exige 1 arg mas usa 0 — forçar arity-0 seria errado). O scan NÃO entra em
  /// closures aninhadas (cada uma tem seu escopo de `$k`).
  ///
  /// ORDEM (crítica): o scan roda no body BRUTO, ANTES do desugar. Reescritas
  /// que embrulham em closure (`>>` → `($c) => g(f($c))`) moveriam o `$k` para
  /// dentro de uma fronteira de closure — e o scan PARA nessas fronteiras. Com
  /// o scan depois, `{ $0 >> f }` via aridade 0 e deixava `$0` unbound.
  Expr _closure(Closure n) {
    if (n.hasExplicitParams) {
      return Closure(
        n.asyncMarker,
        true,
        _params(n.params),
        n.returnType,
        _fnBody(n.body),
        n.offset,
        n.length,
      );
    }
    final found = <int, Ident>{};
    _scanFnBody(n.body, found); // BRUTO — ver nota de ORDEM acima
    final body = _fnBody(n.body);
    if (found.isEmpty) {
      return Closure(
        n.asyncMarker,
        false,
        const <Param>[],
        n.returnType,
        body,
        n.offset,
        n.length,
      );
    }
    final maxIdx = found.keys.reduce((a, b) => a > b ? a : b);
    final synth = <Param>[];
    for (var i = 0; i <= maxIdx; i++) {
      final occ = found[i]; // 1ª ocorrência real do `$i` no corpo (span DWARF)
      final off = occ?.offset ?? n.offset;
      final len = occ?.length ?? 0;
      synth.add(Param(null, '\$$i', null, null, off, len));
    }
    return Closure(
      n.asyncMarker,
      true,
      synth,
      n.returnType,
      body,
      n.offset,
      n.length,
    );
  }

  // --- helpers de síntese (span herdado do açúcar) --------------------------

  MatchExpr _match(AstNode span, Expr scrut, List<MatchArm> arms) =>
      MatchExpr(scrut, arms, span.offset, span.length);

  MatchArm _someArm(AstNode span, String bindName, Expr body) => MatchArm(
    EnumPattern(
      'some',
      [BindPattern(bindName, span.offset, span.length)],
      span.offset,
      span.length,
    ),
    null,
    body,
  );

  MatchArm _noneArm(AstNode span, Expr body) => MatchArm(
    EnumPattern('none', const <Pattern>[], span.offset, span.length),
    null,
    body,
  );

  Ident _idn(AstNode span, String name) =>
      Ident(name, span.offset, span.length);

  Str _str(AstNode span, String text) =>
      Str([StrLit(text)], span.offset, span.length);

  // =========================================================================
  // Scan sintático de `$k` (para a aridade da closure shorthand). Read-only;
  // PARA nas fronteiras de closure aninhada. Roda sobre a árvore BRUTA (pré-
  // desugar), logo precisa cobrir também os nós-açúcar e os Expr embutidos em
  // patterns — ver a nota de ORDEM em `_closure`.
  // =========================================================================

  void _scanFnBody(FnBody b, Map<int, Ident> out) {
    switch (b) {
      case ExprBody n:
        _scanExpr(n.e, out);
      case BlockBody n:
        _scanBlock(n.b, out);
    }
  }

  void _scanBlock(Block b, Map<int, Ident> out) {
    for (final s in b.stmts) {
      _scanStmt(s, out);
    }
  }

  void _scanStmt(Stmt s, Map<int, Ident> out) {
    switch (s) {
      case BreakStmt():
      case ContinueStmt():
      case ErrorStmt():
        break;
      case LetStmt n:
        _scanPattern(n.target, out);
        if (n.value != null) _scanExpr(n.value!, out);
      case ReturnStmt n:
        if (n.value != null) _scanExpr(n.value!, out);
      case IfStmt n:
        _scanExpr(n.cond, out);
        _scanBlock(n.then, out);
        if (n.orElse != null) _scanElse(n.orElse!, out);
      case GuardStmt n:
        _scanExpr(n.cond, out);
        _scanBlock(n.orElse, out);
      case GuardLetStmt n:
        _scanPattern(n.target, out);
        _scanExpr(n.value, out);
        if (n.condition != null) _scanExpr(n.condition!, out);
        _scanBlock(n.orElse, out);
      case WhileStmt n:
        _scanExpr(n.cond, out);
        _scanBlock(n.body, out);
      case ForStmt n:
        _scanPattern(n.target, out);
        _scanExpr(n.iterable, out);
        _scanBlock(n.body, out);
      case EmitStmt n:
        _scanExpr(n.value, out);
      case ExprStmt n:
        _scanExpr(n.expr, out);
      case BlockStmt n:
        _scanBlock(n.block, out);
    }
  }

  void _scanElse(Else e, Map<int, Ident> out) {
    switch (e) {
      case ElseIf n:
        _scanStmt(n.ifStmt, out);
      case ElseBlock n:
        _scanBlock(n.block, out);
    }
  }

  void _scanExpr(Expr e, Map<int, Ident> out) {
    switch (e) {
      case IntLit():
      case FloatLit():
      case BoolLit():
      case NilLit():
      case SelfExpr():
      case EnumShorthand():
      case ErrorExpr():
        break;
      case Ident n:
        final idx = _dollarIndex(n.name);
        if (idx != null) out.putIfAbsent(idx, () => n);
      case Closure():
        break; // fronteira: `$k` aninhado pertence à closure interna
      case Str n:
        for (final p in n.parts) {
          if (p is StrInterp) _scanExpr(p.expr, out);
        }
      case Binary n:
        _scanExpr(n.left, out);
        _scanExpr(n.right, out);
      case Unary n:
        _scanExpr(n.operand, out);
      case Await n:
        _scanExpr(n.operand, out);
      case Spawn n:
        _scanExpr(n.operand, out);
      case Panic n:
        _scanExpr(n.operand, out);
      case Assign n:
        _scanExpr(n.target, out);
        _scanExpr(n.value, out);
      case Call n:
        _scanExpr(n.callee, out);
        for (final a in n.args) {
          _scanExpr(a.value, out);
        }
      case Member n:
        _scanExpr(n.receiver, out);
      case OptChain n:
        _scanExpr(n.receiver, out);
      case Index n:
        _scanExpr(n.receiver, out);
        _scanExpr(n.index, out);
      case TupleIndex n:
        _scanExpr(n.receiver, out);
      case ForceUnwrap n:
        _scanExpr(n.operand, out);
      case Try n:
        _scanExpr(n.operand, out);
      case CopyWith n:
        _scanExpr(n.receiver, out);
        for (final f in n.fields) {
          _scanExpr(f.value, out);
        }
      case IfExpr n:
        if (n.binding != null) _scanPattern(n.binding!, out);
        _scanExpr(n.subject, out);
        _scanExpr(n.then, out);
        _scanExpr(n.orElse, out);
      case MatchExpr n:
        _scanExpr(n.scrutinee, out);
        for (final a in n.arms) {
          _scanPattern(a.pattern, out);
          if (a.guard != null) _scanExpr(a.guard!, out);
          _scanExpr(a.body, out);
        }
      case TupleExpr n:
        for (final el in n.elements) {
          _scanExpr(el, out);
        }
      case ListExpr n:
        for (final el in n.elements) {
          _scanExpr(el, out);
        }
      case MapExpr n:
        for (final en in n.entries) {
          _scanExpr(en.key, out);
          _scanExpr(en.value, out);
        }
      case RangeExpr n:
        _scanExpr(n.start, out);
        _scanExpr(n.end, out);
      case WhereExpr n:
        _scanExpr(n.value, out);
        for (final b in n.bindings) {
          _scanStmt(b, out);
        }
    }
  }

  /// `$k` também conta dentro de pattern — a STRING interpolada de um
  /// `LiteralPattern` carrega Expr (`{ match y { "${$0}" => … } }`). Sem descer
  /// aqui, esse `$0` não entraria na aridade e ficaria unbound.
  void _scanPattern(Pattern p, Map<int, Ident> out) {
    switch (p) {
      case BindPattern():
      case WildcardPattern():
      case RestPattern():
      case ErrorPattern():
        break;
      case LiteralPattern n:
        _scanExpr(n.literal, out);
      case RangePattern n:
        _scanExpr(n.start, out);
        _scanExpr(n.end, out);
      case EnumPattern n:
        for (final s in n.subpatterns) {
          _scanPattern(s, out);
        }
      case ListPattern n:
        for (final el in n.elements) {
          _scanPattern(el, out);
        }
      case RecordPattern n:
        _scanFieldPatterns(n.fields, out);
      case StructPattern n:
        _scanFieldPatterns(n.fields, out);
    }
  }

  void _scanFieldPatterns(List<FieldPattern> fields, Map<int, Ident> out) {
    for (final f in fields) {
      if (f.pattern != null) _scanPattern(f.pattern!, out);
    }
  }

  /// Índice de um param shorthand: `$0`→0, `$12`→12; `$c0`/`$it0`/`$`/IDENT → null
  /// (o léxico só produz `$`+dígitos p/ shorthand; o resto é gensym reservado).
  ///
  /// O léxico garante `índice <= maxDollarIndex` (`lex-dollar-index-range`), o
  /// que limita a `maxDollarIndex+1` os `Param`s que [_closure] sintetiza — sem
  /// essa guarda, `{ $3000000 }` alocaria 3M de `Param`s (~210 MB).
  static int? _dollarIndex(String name) {
    if (name.length < 2 || name.codeUnitAt(0) != 0x24 /* $ */) return null;
    return int.tryParse(name.substring(1));
  }
}
