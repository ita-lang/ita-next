// ===========================================================================
// core_check.dart — Assertion pass de boa-formação do CORE (Fase 3, spec 007 §5.4).
// ===========================================================================
//
// Percorre a árvore PÓS-desugar e coleta qualquer nó-açúcar que tenha sobrevivido.
// É o preço de NÃO duplicar a hierarquia (a invariante "açúcar não sobrevive à
// Fase 3" não é estática — é checada por este walk; trade-off aceito, Dragon 5.3).
// Análogo ao blocker de boa-formação da Fase 2.
//
// Açúcar rastreado (spec 007 §5.2 / tasks T007): `??`/`|>`/`>>` (Binary),
// `OptChain`, `ForceUnwrap`, `WhereExpr`, if-let (`IfExpr` com `binding != null`).
// RETIDOS (NÃO acusados): `Try`, `CopyWith`, `Binary.pow`, if-expr booleano
// (`IfExpr` sem binding), `GuardLetStmt`, `ForStmt` (sync/async — baixa p/
// `ForInStatement` do Kernel no codegen; ruling do dono 2026-07-12) — decisões da Fase 3.
// ===========================================================================

import 'package:ita_next_compiler/frontend/parser/ast.dart';

/// Um nó-açúcar que sobreviveu ao desugaring (kind = tag + span do fonte).
class SugarResidue {
  final String kind;
  final int offset;
  final int length;
  const SugarResidue(this.kind, this.offset, this.length);

  @override
  String toString() => '$kind @$offset+$length';
}

/// Coleta todo açúcar residual na árvore [p] (vazio = core bem-formado).
List<SugarResidue> findResidualSugar(Program p) {
  final out = <SugarResidue>[];
  _CoreChecker(out).program(p);
  return out;
}

/// Falha (StateError) se qualquer nó-açúcar sobreviveu à Fase 3.
void assertCoreForm(Program p) {
  final residues = findResidualSugar(p);
  if (residues.isNotEmpty) {
    throw StateError(
      'Fase 3: açúcar sobreviveu ao desugaring: ${residues.join(', ')}',
    );
  }
}

// ===========================================================================
// Walker — desce em TUDO (inclusive closures/matches e os Expr embutidos em
// patterns: `LiteralPattern`/`RangePattern`) e acusa açúcar.
//
// SEM base de traversal comum, de propósito (ruling do dono 2026-07-14). Existem
// 4 switches exaustivos sobre `Expr` no front-end e eles PARECEM boilerplate
// duplicado, mas divergem justamente nos nós que importam:
//   este       — desce em Closure e acusa açúcar residual;
//   _scanExpr  — PARA em Closure (fronteira de `$k`);
//   _freeRefs  — desce em Closure carregando shadowing;
//   resolver   — desce abrindo escopo.
// Uma base com recursão default esconderia essa divergência e, pior, custaria a
// exaustividade estática do `switch` sobre `sealed` (ast.dart / CI 5.2.1): hoje
// um nó novo em `Expr` quebra a compilação nos 4 passes e força uma decisão
// consciente em cada um. Não unificar é a escolha; reavaliar só se os passes
// convergirem de verdade.
// ===========================================================================

class _CoreChecker {
  final List<SugarResidue> out;
  _CoreChecker(this.out);

  void program(Program p) {
    for (final n in p.body) {
      node(n);
    }
  }

  void node(AstNode n) {
    if (n is Decl) {
      decl(n);
    } else if (n is Stmt) {
      stmt(n);
    } else if (n is Expr) {
      expr(n);
    } else if (n is Block) {
      block(n);
    }
  }

  void decl(Decl d) {
    switch (d) {
      case ImportDecl():
      case ErrorDecl():
        break;
      case FnDecl n:
        fnDecl(n);
      case FieldDecl n:
        if (n.defaultValue != null) expr(n.defaultValue!);
      case InitDecl n:
        _params(n.params);
        block(n.body);
      case StructDecl n:
        n.members.forEach(decl);
      case ClassDecl n:
        n.members.forEach(decl);
      case EnumDecl n:
        for (final c in n.cases) {
          _params(c.payload);
        }
        n.members.forEach(decl);
      case TraitDecl n:
        n.members.forEach(decl);
      case ImplDecl n:
        n.members.forEach(decl);
      case ExtensionDecl n:
        n.members.forEach(decl);
      case ActorDecl n:
        n.members.forEach(decl);
      case OperatorDecl n:
        fnDecl(n.fn);
    }
  }

  void fnDecl(FnDecl n) {
    _params(n.params);
    if (n.body != null) fnBody(n.body!);
  }

  void _params(List<Param> ps) {
    for (final p in ps) {
      if (p.defaultValue != null) expr(p.defaultValue!);
    }
  }

  void fnBody(FnBody b) {
    switch (b) {
      case ExprBody n:
        expr(n.e);
      case BlockBody n:
        block(n.b);
    }
  }

  void block(Block b) {
    for (final s in b.stmts) {
      stmt(s);
    }
  }

  void stmt(Stmt s) {
    switch (s) {
      case BreakStmt():
      case ContinueStmt():
      case ErrorStmt():
        break;
      case LetStmt n:
        pattern(n.target);
        if (n.value != null) expr(n.value!);
      case ReturnStmt n:
        if (n.value != null) expr(n.value!);
      case IfStmt n:
        expr(n.cond);
        block(n.then);
        if (n.orElse != null) _else(n.orElse!);
      case GuardStmt n:
        expr(n.cond);
        block(n.orElse);
      case GuardLetStmt n:
        // RETIDO (não é açúcar da Fase 3). Só desce nos filhos.
        pattern(n.target);
        expr(n.value);
        if (n.condition != null) expr(n.condition!);
        block(n.orElse);
      case WhileStmt n:
        expr(n.cond);
        block(n.body);
      case ForStmt n:
        // RETIDO como core (ruling do dono 2026-07-12): baixa p/ `ForInStatement`
        // do Kernel no codegen. NÃO é açúcar residual. Só desce nos filhos.
        pattern(n.target);
        expr(n.iterable);
        block(n.body);
      case EmitStmt n:
        expr(n.value);
      case ExprStmt n:
        expr(n.expr);
      case BlockStmt n:
        block(n.block);
    }
  }

  void _else(Else e) {
    switch (e) {
      case ElseIf n:
        stmt(n.ifStmt);
      case ElseBlock n:
        block(n.block);
    }
  }

  void expr(Expr e) {
    switch (e) {
      case IntLit():
      case FloatLit():
      case BoolLit():
      case NilLit():
      case Ident():
      case SelfExpr():
      case EnumShorthand():
      case ErrorExpr():
        break;
      case Str n:
        for (final p in n.parts) {
          if (p is StrInterp) expr(p.expr);
        }
      case Binary n:
        if (n.op == BinaryOp.coalesce ||
            n.op == BinaryOp.pipe ||
            n.op == BinaryOp.compose) {
          out.add(SugarResidue(_binaryKind(n.op), n.offset, n.length));
        }
        expr(n.left);
        expr(n.right);
      case Unary n:
        expr(n.operand);
      case Await n:
        expr(n.operand);
      case Spawn n:
        expr(n.operand);
      case Panic n:
        expr(n.operand);
      case Assign n:
        expr(n.target);
        expr(n.value);
      case Call n:
        expr(n.callee);
        for (final a in n.args) {
          expr(a.value);
        }
      case Member n:
        expr(n.receiver);
      case OptChain n:
        out.add(SugarResidue('opt-chain', n.offset, n.length));
        expr(n.receiver);
      case Index n:
        expr(n.receiver);
        expr(n.index);
      case TupleIndex n:
        expr(n.receiver);
      case ForceUnwrap n:
        out.add(SugarResidue('force-unwrap', n.offset, n.length));
        expr(n.operand);
      case Try n:
        // RETIDO. Só desce.
        expr(n.operand);
      case CopyWith n:
        // RETIDO. Só desce.
        expr(n.receiver);
        for (final f in n.fields) {
          expr(f.value);
        }
      case Closure n:
        // Closure implícita é permitida no core (aridade contextual, Fase 5).
        _params(n.params);
        fnBody(n.body);
      case IfExpr n:
        if (n.binding != null) {
          out.add(SugarResidue('if-let-expr', n.offset, n.length));
        }
        expr(n.subject);
        expr(n.then);
        expr(n.orElse);
      case MatchExpr n:
        expr(n.scrutinee);
        for (final a in n.arms) {
          pattern(a.pattern);
          if (a.guard != null) expr(a.guard!);
          expr(a.body);
        }
      case TupleExpr n:
        n.elements.forEach(expr);
      case ListExpr n:
        n.elements.forEach(expr);
      case MapExpr n:
        for (final en in n.entries) {
          expr(en.key);
          expr(en.value);
        }
      case RangeExpr n:
        expr(n.start);
        expr(n.end);
      case WhereExpr n:
        out.add(SugarResidue('where', n.offset, n.length));
        expr(n.value);
        for (final b in n.bindings) {
          stmt(b);
        }
    }
  }

  /// Patterns embutem `Expr` em `LiteralPattern`/`RangePattern` — e Expr pode
  /// ser açúcar (`match x { "${a ?? b}" => … }`). Sem descer aqui, açúcar dentro
  /// de pattern passaria em silêncio: o dump sai com `??` e o check aprova.
  void pattern(Pattern p) {
    switch (p) {
      case BindPattern():
      case WildcardPattern():
      case RestPattern():
      case ErrorPattern():
        break;
      case LiteralPattern n:
        expr(n.literal);
      case RangePattern n:
        expr(n.start);
        expr(n.end);
      case EnumPattern n:
        n.subpatterns.forEach(pattern);
      case ListPattern n:
        n.elements.forEach(pattern);
      case RecordPattern n:
        _fieldPatterns(n.fields);
      case StructPattern n:
        _fieldPatterns(n.fields);
    }
  }

  void _fieldPatterns(List<FieldPattern> fields) {
    for (final f in fields) {
      if (f.pattern != null) pattern(f.pattern!);
    }
  }

  String _binaryKind(BinaryOp op) => switch (op) {
    BinaryOp.coalesce => '??',
    BinaryOp.pipe => '|>',
    BinaryOp.compose => '>>',
    _ => op.name,
  };
}
