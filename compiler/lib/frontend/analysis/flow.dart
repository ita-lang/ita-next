// ===========================================================================
// flow.dart — Fase 6, 1º lote: o flow-walk (spec 014 §2–§3).
// ===========================================================================
//
// Materialização À MÃO da spec `014-flow-check` §2/§3 (P11 / ADR-0010). A
// TÉCNICA é SDD **L-atribuída** em UM walk (Dragon 5.2.4/5.5 — o mesmo
// fundamento do `check.dart`); as REGRAS são norma, não livro-texto:
//
//  • **JLS §14.21** — `completesNormally` por indução ESTRUTURAL, e
//    reachability como o DUAL dele (`stmt[i+1]` é alcançável sse `stmt[i]`
//    é alcançável ∧ completa). Sem CFG, sem ponto-fixo: Dragon 9.2 é
//    otimização-grade e só paga com goto/labels, que o Itá não tem.
//  • **JLS §8.4.7** — `missing-return`: erro se o corpo-bloco PODE completar
//    e a fn declara retorno. CA2/CA21 (`panic` como corpo) são CONSEQUÊNCIA,
//    não caso especial: `Never` não completa e o predicado nem dispara.
//  • **JLS §16** — definite assignment, SÓ para `var` (009 §12-7 matou a
//    metade definitely-unassigned: `let` nasce ligado — `let-requires-value`
//    no parser). DA-após-stmt-que-não-completa é verdade VÁCUA (⊤), e o ⊤
//    nunca é estado armazenado: é o elemento neutro do ∩, representado por
//    omissão (braço que não completa não participa da interseção).
//  • Lacunas assinadas na spec (Art. IV-6b): Never-reachability = precedente
//    Kotlin `Nothing` · `guard-must-exit` = Swift TSPL "Early Exit" (ruling
//    §12-3) · DA×closures = C# spec (anonymous functions).
//
// UM walk, TRÊS fatos entrelaçados (§2, parecer W1): `completesNormally` é o
// atributo SINTETIZADO (`bool` cru por stmt — dos três fatos é o único puro);
// DA é estado do walker mutado in-place com cópia explícita em branch; e
// reachability é DERIVADO na costura da sequência (o caller decide, não o
// nó). Um record `(completes, da, reachable)` obrigaria cópia de set a CADA
// stmt — custo sem retorno; a mutação disciplinada é o desenho do próprio
// javac (`Flow.java`).
//
// INVARIANTES de implementação (violar = bug, não opinião):
//  • **I1** — a F6 caminha `check.program`, NUNCA re-desugara: as side-tables
//    são `Map.identity` sobre os nós DA árvore canônica (ADR-0004); um
//    `desugarProgram` novo produziria nós novos e toda consulta erraria em
//    silêncio.
//  • **I2** — consulta a side-table FALHA alto (`StateError`): totalidade é
//    invariante da nº1 (009 §7-4); default silencioso é a doença do oracle.
//  • **I3** — a F6 só roda sobre F5 LIMPA (o gate mora no driver): `ErrorType`
//    nas tabelas envenenaria Never-reachability e o predicado de retorno.
//  • Corolário de I2+I3: o walk SÓ desce onde a F5 tipou. Corpos que a F5
//    declaradamente ainda não cobre (`InitDecl` — `check.dart` §_members;
//    `OperatorDecl` — spec 012; defaults de payload de enum-case) ficam FORA
//    deste lote: descer neles consultaria a nº1 em nós que ela não tem e
//    estouraria I2 em programa verde. Quando a F5 os cobrir, o walk liga.
// ===========================================================================

import 'package:ita_next_compiler/frontend/binding/scope.dart';
import 'package:ita_next_compiler/frontend/parser/ast.dart' as ast;
import 'package:ita_next_compiler/frontend/semantic/type.dart';
import 'package:ita_next_compiler/frontend/semantic/type_table.dart';

/// Erro de fluxo (EN kebab-case + span) — espelha `CheckError`/`BindingError`.
/// Formato canônico do dump: `flow-error: <code> @<offset>+<length>`.
class FlowError {
  final String code;
  final int offset;
  final int length;
  const FlowError(this.code, this.offset, this.length);

  String format() => 'flow-error: $code @$offset+$length';

  @override
  String toString() => format();
}

/// O resultado da F6 — o contrato que a **F7** lê (spec 014 §7). O padrão da
/// 011: a fase NÃO joga fora o que a próxima precisa.
class FlowResult {
  /// Ordenados por offset (a ordem que o usuário lê — espelha `check.dart`).
  final List<FlowError> errors;

  /// **Side-table nº8** — `completesNormally` por corpo-BLOCO. Chave: o nó
  /// DONO do corpo (`FnDecl | Closure` neste lote; `InitDecl` quando a F5
  /// cobrir init — ver o corolário de I2+I3 no cabeçalho), por identidade.
  ///
  /// Só corpos `BlockBody` têm entrada — corpo `=>` nunca "cai do fim" (RD-1;
  /// a F7 emite `ReturnStatement(expr)` direto, registrar seria ruído). É o
  /// fato que a F7 lê para o **throw defensivo de fim-de-corpo** (013 §0.6: o
  /// verifier do Kernel não checa queda-do-fim; a VM devolveria null
  /// implícito). A F7 NÃO recomputa (ADR-0004).
  ///
  /// Totalidade: garantida em programa VERDE (todo BlockBody alcançado tem
  /// entrada). Com erro, parcial por design — código morto não é walkado (a
  /// mecânica anticascata abaixo) e a F7 nunca lê (gate).
  final Map<ast.AstNode, bool> completesNormally;

  FlowResult(this.errors, this.completesNormally);

  bool get hasErrors => errors.isNotEmpty;
}

/// Roda a F6 sobre uma F5 **limpa** (I3 — quem garante é o driver).
///
/// [resolution] vem da F4: o `CheckResult` não a carrega (só as nº1–nº7), e o
/// DA precisa de `Ident → LocalRes(binder, hops, captured)`. Achado de
/// plumbing registrado no blueprint da 014 (o desenho deste walk:
/// `specs/014-flow-check/blueprint-flow-walk.md`, §14-L1 — toda referência
/// "blueprint §N" neste arquivo aponta para ele): a F7 vai precisar do MESMO mapa
/// (emitir `VariableGet(VariableDeclaration)` exige `Ident → binder`) — quando
/// a spec da F7 aterrissar, promover `resolution` a campo do contrato.
FlowResult analyzeFlow(
  CheckResult check,
  Map<ast.AstNode, ResolvedName> resolution,
) {
  final w = _FlowWalker(check, resolution);
  w.run(check.program);
  w.errors.sort((a, b) => a.offset.compareTo(b.offset));
  return FlowResult(w.errors, w.completesNormally);
}

/// Contexto do loop MAIS PRÓXIMO (spec 014 §2, linha do `while`): o "tem
/// break ligado" é flag sintetizado na própria descida — nada de re-resolver.
/// Entrar em corpo de `while`/`for` empilha um novo; fronteira de closure
/// ZERA (o espelho em-fase do corte da F4, `resolver.dart` §_resolveFunction:
/// `break` não cruza fronteira de fn).
class _LoopCtx {
  bool sawBreak = false;

  /// Snapshot do DA em cada `break` — JLS §16.2.10: V é DA após `while true`
  /// sse DA antes de CADA break (o caminho cond-false não existe).
  final List<Set<Object>> breakDAs = [];
}

class _FlowWalker {
  final CheckResult _check;
  final Map<ast.AstNode, ResolvedName> _resolution;

  final List<FlowError> errors = [];

  /// A nº8 (saída) — ver [FlowResult.completesNormally].
  final Map<ast.AstNode, bool> completesNormally = Map.identity();

  /// Domínio do DA: binders de `var` rastreados (JLS §16 SÓ para `var` — 009
  /// §12-7). Chave = o nó-binder (`BindPattern`), identidade — EXATAMENTE o
  /// domínio de `LocalRes.binder` e da nº6. `Object` e não `AstNode` porque
  /// `Param` não é AstNode (mas Param nunca entra: param nasce ligado).
  ///
  /// Escopo é GRÁTIS: identidade de nó é única por declaração, e um binder de
  /// bloco morto léxico não é referenciável fora dele (F4 garantiu) — entradas
  /// "vazadas" são inertes. Nenhuma pilha de escopos na F6.
  final Set<Object> _domain = Set.identity();

  /// Definitely-assigned corrente. Mutado in-place (GEN só ADICIONA — o
  /// conjunto é monótono dentro de um caminho); cópia explícita em branch.
  Set<Object> _da = Set.identity();

  /// Anticascata do código morto: UM erro por região. Setado ao reportar;
  /// limpo quando um stmt COMPLETA na costura (região fechada), no início de
  /// cada corpo e ao FECHAR cada sub-região de branch/loop/closure — a morte
  /// só ATRAVESSA fronteira de bloco NU (`BlockStmt`: mesma região dinâmica),
  /// nunca de branch (regiões distintas: `if c { return; x } else { return;
  /// y }` acusa x E y — dois pecados, dois spans).
  bool _unreachableReported = false;

  _LoopCtx? _loop;

  _FlowWalker(this._check, this._resolution);

  void _err(String code, ast.AstNode node) =>
      errors.add(FlowError(code, node.offset, node.length));

  /// Consulta à **nº1** com falha-alta (I2) — o mesmo contrato do `typeOf` da
  /// F5: totalidade é invariante; `?? default` é a doença do oracle.
  Type _typeOf(ast.Expr e) {
    final t = _check.exprTypes[e];
    if (t == null) {
      throw StateError(
        'F6: nº1 sem entrada para ${e.runtimeType} @${e.offset}+${e.length} — '
        'walk consultando nó fora da árvore canônica (I1/I2)',
      );
    }
    return t;
  }

  /// Consulta à **nº4** com falha-alta (I2) — toda anotação de assinatura foi
  /// resolvida pela fatia A da F5.
  Type _annotated(ast.TypeNode n) {
    final t = _check.annotations[n];
    if (t == null) {
      throw StateError(
        'F6: nº4 sem entrada para a anotação @${n.offset}+${n.length} (I2)',
      );
    }
    return t;
  }

  // --- topo ------------------------------------------------------------------

  void run(ast.Program p) {
    for (final node in p.body) {
      if (node is ast.Decl) _decl(node);
      // `Stmt` top-level: o initializer de `let` global é do CONST-EVAL (spec
      // 014 §5 — lote seguinte, modelo D); `var` global e statement solto já
      // morreram na FORMA (`mutable-global`/`top-level-statement`, F5 §1) —
      // o gate I3 impede que cheguem aqui.
    }
  }

  /// Dispatcher de decls — vale para topo E para membros de corpo de tipo (a
  /// união de casos é a mesma; aninhamento ilegal nem parseia).
  ///
  /// ⚠️ Switch EXAUSTIVO — nunca `default` (a lição do `check.dart` §_decl:
  /// um `default: break` engoliu QUATRO decls em silêncio). Cada `break`
  /// abaixo diz de quem é.
  void _decl(ast.Decl d) {
    switch (d) {
      case ast.FnDecl n:
        _fnDecl(n);
      case ast.StructDecl n:
        _members(n.members);
      case ast.ClassDecl n:
        _members(n.members);
      // Defaults de payload de enum-case: a F5 NÃO os tipa hoje (o checker só
      // desce em `members`) ⟹ walkar estouraria I2 em programa verde — ver o
      // corolário no cabeçalho. Ligam junto com a cobertura da F5.
      case ast.EnumDecl n:
        _members(n.members);
      case ast.TraitDecl n:
        _members(n.members);
      case ast.ActorDecl n:
        _members(n.members);
      case ast.ImplDecl n:
        _members(n.members);
      case ast.ExtensionDecl n:
        _members(n.members);
      // **spec 012** — a F5 ainda não tipa o corpo de `OperatorDecl` (item
      // próprio, de propósito — `check.dart` §_decl). Mesmo corolário: a nº1
      // não tem os nós de lá; o flow-walk do operador liga com a 012.
      case ast.OperatorDecl():
        break;
      // **Corpo de `init` é lacuna DECLARADA da F5** (spec 011 — o memberwise
      // é sintetizado; o corpo do `init` explícito não é checado ainda). O
      // blueprint pede o walk + nº8 aqui, mas descer num corpo que a F5 não
      // tipou estoura I2 no primeiro `ExprStmt` de um programa verde. Quando
      // o `init` entrar na F5, este case vira o walk (sem `missing-return` —
      // `init` não tem returnType; nº8 sim).
      case ast.InitDecl():
        break;
      // Default de campo: `self` proibido (§9) + walk como expr.
      case ast.FieldDecl n:
        _fieldDecl(n);
      // Sem corpo de VALOR a analisar.
      case ast.ImportDecl():
      case ast.ErrorDecl():
        break;
    }
  }

  void _members(List<ast.Decl> ms) {
    for (final m in ms) {
      _decl(m);
    }
  }

  /// Unidade de análise: cada corpo top-level começa do zero — `_domain`/`_da`
  /// vazios, `_loop = null`, região limpa. Closures NÃO são unidades
  /// separadas: são walked INLINE dentro do corpo que as cria, porque o DA
  /// delas herda o ponto de criação (C# spec — ver [_closure]).
  void _reset() {
    _domain.clear();
    _da = Set<Object>.identity();
    _loop = null;
    _unreachableReported = false;
  }

  void _fnDecl(ast.FnDecl n) {
    // Defaults de param avaliam em escopo EXTERNO (`resolver.dart`
    // §_resolveFunction) — estado isolado por default. A F5 os checa
    // (`check.dart` §_fnDeclInner) ⟹ nº1 total, pode descer. Vale também para
    // assinatura de trait (corpo null): os defaults existem do mesmo jeito.
    // (`self` em default de PARÂMETRO é a lacuna §14-L3 do blueprint — sem
    // assento normativo; roteada, não é deste lote.)
    for (final p in n.params) {
      if (p.defaultValue != null) {
        _reset();
        _expr(p.defaultValue!);
      }
    }
    final body = n.body;
    if (body == null) return; // assinatura de trait: só os defaults

    _reset();
    switch (body) {
      // RD-1: `=>` rende — nunca "cai do fim". Nem nº8, nem missing-return.
      case ast.ExprBody b:
        _expr(b.e);
      case ast.BlockBody b:
        final completes = _stmts(b.b.stmts);
        completesNormally[n] = completes; // nº8
        // JLS §8.4.7 verbatim: erro se o corpo PODE completar e a fn declara
        // retorno. `-> T` ausente = Void (nada a checar); `-> Never` ENTRA
        // (spec §3). `async` entra (cair do fim completaria o Future com null
        // — o veneno do ADR-0013); `asyncStar` é ISENTO (stream fn rende por
        // `emit`; fim-de-corpo fecha o stream — precedente gerador Dart/Java).
        if (completes &&
            n.returnType != null &&
            _annotated(n.returnType!) is! VoidType &&
            n.asyncMarker != ast.AsyncMarker.asyncStar) {
          _err('missing-return', n);
        }
    }
  }

  /// `self` em default de campo é dívida da F6 (008 §133, ledger (h) da spec):
  /// a F4 o RESOLVE de propósito (`resolver.dart` §_resolveMember seta
  /// `_selfType` antes do default) — a proibição é NOSSA. O Kernel não tem
  /// `this` em initializer de campo.
  ///
  /// Reconhecimento SINTÁTICO — scan da subárvore por nós `SelfExpr`. É
  /// completo porque `self` é sempre explícito no Itá (P4): a F4 não injeta
  /// campos no escopo léxico, logo todo acesso a estado da instância passa por
  /// um `SelfExpr` físico. Closures dentro do default idem (o `this` também
  /// não existe lá no Kernel — a captura não salva). Erro por OCORRÊNCIA,
  /// span no próprio `self` (pecados distintos, spans precisos; a regra
  /// "um-por-região" é do código morto, não daqui).
  void _fieldDecl(ast.FieldDecl n) {
    final dv = n.defaultValue;
    if (dv == null) return;
    _scanExpr(dv, (e) {
      if (e is ast.SelfExpr) _err('self-in-field-default', e);
    });
    // E o walk normal (domínio vazio): closures no default ganham nº8 e o
    // predicado de retorno. A F5 checa o default contra o tipo anotado ⟹ nº1
    // total aqui.
    _reset();
    _expr(dv);
  }

  // --- costura de sequência (JLS §14.21 — reachability é o dual) --------------

  /// Itera a sequência; quando `s_i` não completa e existe `s_{i+1}`, acusa
  /// `unreachable-code` UMA vez por região e PARA de walkar o resto (irmãos
  /// mortos não são visitados: zero erros aninhados, zero DA fantasma, zero
  /// flowFacts de código morto). Retornar `false` é a VERDADE — o bloco não
  /// completa; é o que faz `fn f() -> Int { return 1; junk }` acusar SÓ
  /// unreachable, nunca missing-return junto: removido o morto, o programa
  /// fica verde — o erro segue o fix.
  bool _stmts(List<ast.Stmt> stmts) {
    for (var i = 0; i < stmts.length; i++) {
      if (_stmt(stmts[i])) {
        _unreachableReported = false; // região fechada
        continue;
      }
      if (i + 1 < stmts.length && !_unreachableReported) {
        _err('unreachable-code', stmts[i + 1]);
        _unreachableReported = true;
      }
      return false;
    }
    return true; // sequência vazia completa
  }

  /// `completesNormally` por statement — a tabela nó→regra da spec §2, por
  /// indução estrutural (JLS §14.21). Switch EXAUSTIVO sobre o `sealed Stmt`.
  bool _stmt(ast.Stmt s) {
    switch (s) {
      // `let x = panic("TODO")` é o idioma de rascunho irmão do CA21 — mesma
      // tabela nº1, mesmo precedente Kotlin já assinado (`val x = TODO()`).
      // `let` sem valor não existe (`let-requires-value`); `var` sem valor só
      // declara — completa e povoa o domínio do DA.
      case ast.LetStmt n:
        if (n.value != null) _expr(n.value!);
        if (n.isVar) _domainBinder(n.target, bound: n.value != null);
        return n.value == null || _typeOf(n.value!) is! NeverType;

      case ast.ReturnStmt n:
        if (n.value != null) _expr(n.value!); // o valor avalia ANTES (§14.21)
        return false;

      case ast.IfStmt n:
        return _ifStmt(n);

      // O guard em si SEMPRE completa (a continuação é o caminho
      // cond-verdadeira); a obrigação é do ELSE — ver [_guardElse].
      case ast.GuardStmt n:
        _expr(n.cond);
        _guardElse(n.orElse);
        return true;

      // O binder do guard-let é `let` — fora do domínio DA.
      case ast.GuardLetStmt n:
        _expr(n.value);
        if (n.condition != null) _expr(n.condition!); // o `&&`-refino
        _guardElse(n.orElse);
        return true;

      case ast.WhileStmt n:
        return _whileStmt(n);

      case ast.ForStmt n:
        return _forStmt(n);

      case ast.BreakStmt _:
        final ctx = _loop;
        if (ctx == null) {
          // F4 garantiu break-em-loop (`break-outside-loop`, context-flags do
          // CI 11.5.1) — chegar aqui é bug do walk, não do programa (I2).
          throw StateError('F6: BreakStmt sem loop envolvente sobreviveu à F4');
        }
        ctx.sawBreak = true;
        ctx.breakDAs.add(_copy(_da)); // JLS §16.2.10 — ver [_whileStmt]
        return false;

      case ast.ContinueStmt _:
        return false;

      // Mesma regra type-informed da linha do ExprStmt (spec §2).
      case ast.EmitStmt n:
        _expr(n.value);
        return _typeOf(n.value) is! NeverType;

      // A linha da spec §2: `ExprStmt(e)` completa sse `tipo(e) ≠ Never` —
      // cobre `panic(...)` e todo Never derivado (match cujos braços
      // divergem). Fronteira DELIBERADA (JLS-fiel): Never ANINHADO em
      // subexpressão NÃO propaga — `x = panic("b")` tem `tipo(Assign) = Void`
      // ⟹ completa (o throw dentro de expressão não conta no §14.21; propagar
      // seria a análise de CFG de expressão do Kotlin — outra classe de
      // custo). Consequência aceita: `fn f() -> Int { x = panic("b") }` acusa
      // missing-return — falso-positivo benigno; o fix (panic direto) é
      // trivial e o Java faz igual. §14-L4: recusa com fundamento, registrada
      // para não reabrir por acidente.
      case ast.ExprStmt n:
        _expr(n.expr);
        return _typeOf(n.expr) is! NeverType;

      // Bloco nu = a MESMA região dinâmica (§ do campo [_unreachableReported]):
      // a morte atravessa — `{ return; x } y` é UMA região, UM erro (em x).
      // Sem gestão de escopo: chaves por identidade tornam saída de escopo
      // grátis (ver [_domain]).
      case ast.BlockStmt n:
        return _stmts(n.block.stmts);

      // Defensivo: inalcançável na F6 — o driver aborta em erro de parse.
      case ast.ErrorStmt _:
        return true;
    }
  }

  /// `if`: completa sse `¬hasElse ∨ C(then) ∨ C(else)` — if-sem-else completa
  /// SEMPRE (o carve-out deliberado do JLS §14.21). Branch-merge do DA por ∩
  /// sobre os braços que completam (⊤ por omissão); o caminho cond-false de um
  /// if-sem-else participa com o DA de ENTRADA.
  bool _ifStmt(ast.IfStmt n) {
    _expr(n.cond);
    final entry = _da;
    Set<Object>? merged;
    void arm(Set<Object> da) =>
        merged = merged == null ? da : _intersect(merged!, da);

    _da = _copy(entry);
    final thenCompletes = _stmts(n.then.stmts);
    if (thenCompletes) arm(_da);
    _unreachableReported = false; // braço é região própria — não vaza

    final orElse = n.orElse;
    var elseCompletes = true;
    if (orElse == null) {
      arm(entry); // caminho cond-false
    } else {
      _da = _copy(entry);
      elseCompletes = switch (orElse) {
        // else-if recursa como statement — o if aninhado gerencia os próprios
        // braços a partir DESTA cópia de entrada.
        ast.ElseIf e => _stmt(e.ifStmt),
        ast.ElseBlock e => _stmts(e.block.stmts),
      };
      if (elseCompletes) arm(_da);
      _unreachableReported = false;
    }
    // Nenhum braço completa ⟹ o stmt não completa e o caller PARA — o
    // "estado ⊤" nunca vive (o reticulado inteiro sem classe de reticulado).
    _da = merged ?? entry;
    return thenCompletes || elseCompletes;
  }

  /// O MESMO predicado `completesNormally`, sítio novo (Swift TSPL Early
  /// Exit, ruling §12-3): `C(orElse) == true ⟹ guard-must-exit`, span no
  /// bloco else — o sítio do pecado (CA4). O DA do else é DESCARTADO: o else
  /// não completa (ou acabou de errar) — contribuição vácua.
  void _guardElse(ast.Block orElse) {
    final entry = _da;
    _da = _copy(entry);
    final elseCompletes = _stmts(orElse.stmts);
    _da = entry;
    _unreachableReported = false;
    if (elseCompletes) _err('guard-must-exit', orElse);
  }

  /// `while` completa SEMPRE (o corpo pode rodar 0× ⟹ DA-após = DA-após-cond,
  /// JLS §16.2.10), EXCETO cond `BoolLit(true)` SINTÁTICO sem break ligado ao
  /// loop (carve-out assinado da spec §2 — o JLS usa const-expr; o Itá não tem
  /// const-fold, restringe a literal; o desugar não toca literais, o nó chega
  /// intacto). Para o while-true destravado: DA-após = ∩ dos snapshots de
  /// break (§16.2.10 — o caminho cond-false não existe), que é o que deixa
  /// verde o idioma `var x: Int; while true { x = f(); break }; usa(x)`.
  bool _whileStmt(ast.WhileStmt n) {
    _expr(n.cond);
    final entry = _da;
    final saved = _loop;
    final ctx = _LoopCtx();
    _loop = ctx; // empilha ⟹ break liga ao loop MAIS PRÓXIMO de graça
    _da = _copy(entry);
    _stmts(n.body.stmts); // o completes do CORPO não decide o do while
    _unreachableReported = false;
    _loop = saved;

    final cond = n.cond;
    if (cond is ast.BoolLit && cond.value) {
      if (!ctx.sawBreak) {
        _da = entry;
        return false; // CA5: loop infinito — o que vem depois é inalcançável
      }
      var acc = ctx.breakDAs.first;
      for (var i = 1; i < ctx.breakDAs.length; i++) {
        acc = _intersect(acc, ctx.breakDAs[i]);
      }
      _da = acc;
      return true;
    }
    // While comum: a interseção colapsaria em DA-após-cond (todo snapshot ⊇
    // DA-do-início-do-corpo = DA-após-cond) — não computa.
    _da = entry;
    return true;
  }

  /// `for` completa sempre (pode rodar 0×; sem const-análise de iterable). O
  /// target é `let` per-iteração — fora do domínio DA. Hoje a F5 barra `for`
  /// inteiro (`for-binder-unsupported`, ruling §12-D da 011 — o protocolo de
  /// iteração é M5) ⟹ este case espera o destrave; correto se um dia retido.
  bool _forStmt(ast.ForStmt n) {
    _expr(n.iterable);
    final entry = _da;
    final saved = _loop;
    _loop = _LoopCtx();
    _da = _copy(entry);
    _stmts(n.body.stmts);
    _unreachableReported = false;
    _loop = saved;
    _da = entry;
    return true;
  }

  // --- expressões --------------------------------------------------------------

  /// Recursão estrutural em ORDEM DE AVALIAÇÃO (receptor→args, left→right) +
  /// os casos especiais (Ident/Assign/Closure/IfExpr/MatchExpr). Switch
  /// EXAUSTIVO sobre o `sealed Expr` — nunca `default` (a lição do
  /// `check.dart`).
  ///
  /// **Por que `&&`/`||` não precisam de cópias**: os conjuntos bivalentes
  /// when-true/when-false do JLS §16.1 existiam por Assign-dentro-de-Bool;
  /// `Assign : Void` (ruling §12-2) torna isso erro de TIPO na F5 — a maior
  /// economia da spec, colhida aqui. Açúcar que nunca chega pós-desugar
  /// (coalesce/pipe/compose, if-let, opt-chain, force-unwrap, where) fica no
  /// switch pela totalidade — inofensivo se morto, correto se um dia retido.
  void _expr(ast.Expr e) {
    switch (e) {
      case ast.IntLit _:
      case ast.FloatLit _:
      case ast.BoolLit _:
      case ast.NilLit _:
      case ast.SelfExpr _:
      case ast.EnumShorthand _:
      case ast.ErrorExpr _:
        break;

      // Interpolação LÊ as vars — os usos contam para o DA. A F5 sintetiza
      // cada parte (nº1 total — o dedo na F5 do W3 da 014: `check.dart`,
      // `_str`; antes `Str ⟹ StringType` direto, e um `${if …}`/`${match …}`
      // aqui dentro estourava o falha-alto I2 em programa verde).
      case ast.Str n:
        for (final p in n.parts) {
          if (p is ast.StrInterp) _expr(p.expr);
        }

      case ast.Ident n:
        _use(n);

      case ast.Binary n:
        _expr(n.left);
        _expr(n.right);
      case ast.Unary n:
        _expr(n.operand);
      case ast.Await n:
        _expr(n.operand);
      case ast.Spawn n:
        _expr(n.operand);
      case ast.Panic n:
        _expr(n.operand);

      case ast.Assign n:
        _assign(n);

      case ast.Call n:
        _expr(n.callee);
        for (final a in n.args) {
          _expr(a.value);
        }
      case ast.Member n:
        _expr(n.receiver);
      case ast.OptChain n:
        _expr(n.receiver);
      case ast.Index n:
        _expr(n.receiver);
        _expr(n.index);
      case ast.TupleIndex n:
        _expr(n.receiver);
      case ast.ForceUnwrap n:
        _expr(n.operand);
      case ast.Try n:
        _expr(n.operand);
      case ast.CopyWith n:
        _expr(n.receiver);
        for (final f in n.fields) {
          _expr(f.value);
        }

      case ast.Closure n:
        _closure(n);
      case ast.IfExpr n:
        _ifExpr(n);
      case ast.MatchExpr n:
        _matchExpr(n);

      case ast.TupleExpr n:
        for (final el in n.elements) {
          _expr(el);
        }
      case ast.ListExpr n:
        for (final el in n.elements) {
          _expr(el);
        }
      case ast.MapExpr n:
        for (final entry in n.entries) {
          _expr(entry.key);
          _expr(entry.value);
        }
      case ast.RangeExpr n:
        _expr(n.start);
        _expr(n.end);

      case ast.WhereExpr n:
        for (final b in n.bindings) {
          if (b.value != null) _expr(b.value!);
        }
        _expr(n.value);
    }
  }

  /// Checagem de USO (spec §3): `var` rastreado fora do conjunto DA é
  /// `use-before-assign` — ou `capture-before-assign` se o uso cruzou
  /// fronteira de fn (o flag da F4 é o detector; zero re-resolução). Com o
  /// pre-scan de [_closure] pagando a obrigação na criação, o braço
  /// `captured` aqui é rede de segurança. `TopLevelRes`/`SelfRes`: nada — o
  /// modelo D matou DA de global (spec §5).
  void _use(ast.Ident n) {
    switch (_resolution[n]) {
      case LocalRes r:
        if (_domain.contains(r.binder) && !_da.contains(r.binder)) {
          _err(r.captured ? 'capture-before-assign' : 'use-before-assign', n);
        }
      case TopLevelRes _:
      case SelfRes _:
        break;
      case null:
        // F4 resolve todo Ident de programa verde — buraco aqui é I1/I2.
        throw StateError('F6: Ident @${n.offset}+${n.length} sem resolução da F4');
    }
  }

  /// `Assign` no DA: target-Ident de `=` puro NÃO é uso; `+=`/`-=`/`*=`/`/=`
  /// LÊ antes de escrever (JLS §16.1.8) ⟹ o target é USO (checa) e depois
  /// GEN. Alvo `Member`: o RECEPTOR avalia (o seletor não é uso de local).
  /// Qualquer outro alvo morreu na F5 (`invalid-assign-target`) — gate I3; a
  /// recursão estrutural fica de defensiva.
  void _assign(ast.Assign n) {
    final target = n.target;
    if (target is ast.Ident) {
      if (n.op != ast.AssignOp.assign) _use(target);
    } else {
      _expr(target);
    }
    _expr(n.value);
    // GEN: binder de `var` no domínio entra no DA. Monótono — nunca remove.
    if (target is ast.Ident) {
      final r = _resolution[target];
      if (r is LocalRes && _domain.contains(r.binder)) _da.add(r.binder);
    }
  }

  /// if-EXPRESSÃO (`binding == null` sempre — if-let desugara para match).
  /// Merge ∩ com braço-Never = ⊤ (neutro, por omissão): um braço que DIVERGE
  /// não restringe o DA do caminho que sobrevive.
  void _ifExpr(ast.IfExpr n) {
    _expr(n.subject);
    final entry = _da;
    Set<Object>? merged;

    _da = _copy(entry);
    _expr(n.then);
    if (_typeOf(n.then) is! NeverType) merged = _da;

    _da = _copy(entry);
    _expr(n.orElse);
    if (_typeOf(n.orElse) is! NeverType) {
      merged = merged == null ? _da : _intersect(merged, _da);
    }
    // Ambos Never ⟹ o próprio if-expr é Never via join e a regra de STATEMENT
    // já corta — o valor de _da aqui nunca é lido num caminho vivo.
    _da = merged ?? entry;
  }

  /// `match`: braço é EXPRESSÃO (RD-1) — `return` nunca ocorre dentro dele.
  /// DA-após = ∩ sobre os braços com `tipo(body) ≠ Never` (braço que diverge
  /// é vácuo); todos Never ⟹ o match é Never via join (`check.dart` §_join) e
  /// a regra de statement corta. Guard em cópia descartada — é Bool, e
  /// `Assign : Void` barra GEN lá dentro de qualquer forma. Binders de
  /// pattern são `let` — fora do domínio.
  void _matchExpr(ast.MatchExpr n) {
    _expr(n.scrutinee);
    final entry = _da;
    Set<Object>? merged;
    for (final arm in n.arms) {
      if (arm.guard != null) {
        _da = _copy(entry);
        _expr(arm.guard!);
      }
      _da = _copy(entry);
      _expr(arm.body);
      if (_typeOf(arm.body) is! NeverType) {
        merged = merged == null ? _da : _intersect(merged, _da);
      }
    }
    _da = merged ?? entry;
  }

  /// Closure — a criação cria OBRIGAÇÃO de DA (spec §2/§3; C# spec, DA ×
  /// anonymous functions: *o DA de uma variável externa no início do corpo =
  /// o DA no ponto de criação; atribuições lá dentro não fluem para fora* — a
  /// closure roda em momento arbitrário, ou nunca).
  ///
  /// 1. **Pre-scan de obrigação**: coleta `{binder → Ident de menor offset}`
  ///    para todo Ident da subárvore com `LocalRes(captured: true) ∧ binder ∈
  ///    domínio` — o flag da F4 é o detector de captura (`crossedFn` liga ao
  ///    cruzar `isFnBoundary`); zero re-resolução. Binder ∉ DA ⟹
  ///    `capture-before-assign`, UM por binder por closure, span no PRIMEIRO
  ///    Ident capturador (apontar o Ident nomeia a variável de graça; a
  ///    closure inteira seria muda). A obrigação vale para QUALQUER ocorrência
  ///    capturada, inclusive write-only — delta anotado vs C# (§14-L2 do
  ///    blueprint): mais estrita E mais simples (captura no Kernel é por
  ///    referência de contexto — a célula É usada); relaxar depois é
  ///    backwards-compatible.
  /// 2. **Anticascata**: TODOS os binders capturados entram numa CÓPIA do DA —
  ///    o erro já foi dado na criação; o corpo não re-acusa uso a uso.
  /// 3. **Corpo** sobre a cópia (DA inicial = ponto de criação), com `_loop`
  ///    ZERADO — `break` não cruza fronteira de fn (espelho em-fase do corte
  ///    da F4): um `while { break }` interno à closure não destrava o
  ///    while-true externo.
  /// 4. **Descarte**: restaura DA e loop — assign lá dentro NÃO flui (CA7).
  ///
  /// Aninhamento sem contagem dupla: o pre-scan da closure EXTERNA já vê os
  /// Idents profundos (captura transitiva — `captured` é true neles também) e
  /// o passo 2 os põe em DA antes de o walk chegar à closure interna; locais
  /// da externa capturados pela interna só entram no domínio quando o walk da
  /// externa os declara — a obrigação deles é checada na criação da INTERNA.
  void _closure(ast.Closure n) {
    final firstUse = Map<Object, ast.Ident>.identity();
    _scanBody(n.body, (e) {
      if (e is! ast.Ident) return;
      final r = _resolution[e];
      if (r is! LocalRes || !r.captured || !_domain.contains(r.binder)) return;
      final cur = firstUse[r.binder];
      if (cur == null || e.offset < cur.offset) firstUse[r.binder] = e;
    });
    for (final entry in firstUse.entries) {
      if (!_da.contains(entry.key)) _err('capture-before-assign', entry.value);
    }

    final savedDa = _da;
    final savedLoop = _loop;
    _da = _copy(savedDa)..addAll(firstUse.keys);
    _loop = null;
    switch (n.body) {
      // RD-1: `=>` rende — sem nº8, sem predicado.
      case ast.ExprBody b:
        _expr(b.e);
      case ast.BlockBody b:
        final completes = _stmts(b.b.stmts);
        completesNormally[n] = completes; // nº8 — a F7 emite FunctionNode
        // Closure É fn (spec §3): o buraco de soundness de cair do fim com
        // retorno non-Void é idêntico. O retorno vem da nº1: `exprTypes`
        // de closure é FunctionType por totalidade — qualquer outra coisa em
        // programa verde é bug (I2).
        final t = _typeOf(n);
        if (t is! FunctionType) {
          throw StateError(
            'F6: nº1 deu $t para Closure @${n.offset}+${n.length} — '
            'esperava FunctionType (I2)',
          );
        }
        if (completes &&
            t.ret is! VoidType &&
            n.asyncMarker != ast.AsyncMarker.asyncStar) {
          _err('missing-return', n);
        }
    }
    _unreachableReported = false; // a região da closure não vaza ao criador
    _da = savedDa;
    _loop = savedLoop;
  }

  // --- domínio DA ---------------------------------------------------------------

  /// Popula o domínio com os binders de um `var` — a MESMA recursão do
  /// `_mutableBinder` da F5 (Bind/Enum/Struct/Record), pelo mesmo motivo: é o
  /// conjunto exato dos alvos legais de `Assign`. Com valor ⟹ também DA.
  void _domainBinder(ast.Pattern p, {required bool bound}) {
    switch (p) {
      case ast.BindPattern _:
        _domain.add(p);
        if (bound) _da.add(p);
      case ast.EnumPattern n:
        for (final sub in n.subpatterns) {
          _domainBinder(sub, bound: bound);
        }
      case ast.StructPattern n:
        for (final f in n.fields) {
          if (f.pattern != null) _domainBinder(f.pattern!, bound: bound);
        }
      case ast.RecordPattern n:
        for (final f in n.fields) {
          if (f.pattern != null) _domainBinder(f.pattern!, bound: bound);
        }
      // Wildcard/Literal/Range não ligam nome; List/Rest são
      // `pattern-binder-unsupported` na F5 (débito D4) — nada a marcar.
      case ast.WildcardPattern _:
      case ast.LiteralPattern _:
      case ast.RangePattern _:
      case ast.ListPattern _:
      case ast.RestPattern _:
      case ast.ErrorPattern _:
        break;
    }
  }

  Set<Object> _copy(Set<Object> s) => Set<Object>.identity()..addAll(s);

  /// ∩ manual para preservar a disciplina de identidade (o `intersection` do
  /// SDK não promete o tipo de igualdade do resultado). Sets são pequenos
  /// (vars vivos por corpo) — O(|domínio|) por merge é ruído.
  Set<Object> _intersect(Set<Object> a, Set<Object> b) {
    final out = Set<Object>.identity();
    for (final x in a) {
      if (b.contains(x)) out.add(x);
    }
    return out;
  }

  // --- varredura SINTÁTICA da subárvore (ordem-fonte) ----------------------------
  // Dois clientes: o §9 (SelfExpr em default de campo — por ocorrência) e o
  // pre-scan de capturas do [_closure] (por criação). É varredura de FORMA:
  // visita TODO nó de expressão, inclusive código morto e corpos de closures
  // aninhadas (captura transitiva). Patterns ficam de fora — não contêm uso
  // de nome (literal/range de pattern são literais por construção do parser).

  void _scanExpr(ast.Expr e, void Function(ast.Expr) f) {
    f(e);
    switch (e) {
      case ast.IntLit _:
      case ast.FloatLit _:
      case ast.BoolLit _:
      case ast.NilLit _:
      case ast.Ident _:
      case ast.SelfExpr _:
      case ast.EnumShorthand _:
      case ast.ErrorExpr _:
        break;
      case ast.Str n:
        for (final p in n.parts) {
          if (p is ast.StrInterp) _scanExpr(p.expr, f);
        }
      case ast.Binary n:
        _scanExpr(n.left, f);
        _scanExpr(n.right, f);
      case ast.Unary n:
        _scanExpr(n.operand, f);
      case ast.Await n:
        _scanExpr(n.operand, f);
      case ast.Spawn n:
        _scanExpr(n.operand, f);
      case ast.Panic n:
        _scanExpr(n.operand, f);
      // O target ENTRA no scan — é o que faz a obrigação de captura valer
      // também para a ocorrência write-only (ver [_closure], passo 1).
      case ast.Assign n:
        _scanExpr(n.target, f);
        _scanExpr(n.value, f);
      case ast.Call n:
        _scanExpr(n.callee, f);
        for (final a in n.args) {
          _scanExpr(a.value, f);
        }
      case ast.Member n:
        _scanExpr(n.receiver, f);
      case ast.OptChain n:
        _scanExpr(n.receiver, f);
      case ast.Index n:
        _scanExpr(n.receiver, f);
        _scanExpr(n.index, f);
      case ast.TupleIndex n:
        _scanExpr(n.receiver, f);
      case ast.ForceUnwrap n:
        _scanExpr(n.operand, f);
      case ast.Try n:
        _scanExpr(n.operand, f);
      case ast.CopyWith n:
        _scanExpr(n.receiver, f);
        for (final fi in n.fields) {
          _scanExpr(fi.value, f);
        }
      case ast.Closure n:
        _scanBody(n.body, f);
      case ast.IfExpr n:
        _scanExpr(n.subject, f);
        _scanExpr(n.then, f);
        _scanExpr(n.orElse, f);
      case ast.MatchExpr n:
        _scanExpr(n.scrutinee, f);
        for (final arm in n.arms) {
          if (arm.guard != null) _scanExpr(arm.guard!, f);
          _scanExpr(arm.body, f);
        }
      case ast.TupleExpr n:
        for (final el in n.elements) {
          _scanExpr(el, f);
        }
      case ast.ListExpr n:
        for (final el in n.elements) {
          _scanExpr(el, f);
        }
      case ast.MapExpr n:
        for (final entry in n.entries) {
          _scanExpr(entry.key, f);
          _scanExpr(entry.value, f);
        }
      case ast.RangeExpr n:
        _scanExpr(n.start, f);
        _scanExpr(n.end, f);
      case ast.WhereExpr n:
        for (final b in n.bindings) {
          if (b.value != null) _scanExpr(b.value!, f);
        }
        _scanExpr(n.value, f);
    }
  }

  void _scanBody(ast.FnBody b, void Function(ast.Expr) f) {
    switch (b) {
      case ast.ExprBody n:
        _scanExpr(n.e, f);
      case ast.BlockBody n:
        _scanBlock(n.b, f);
    }
  }

  void _scanBlock(ast.Block b, void Function(ast.Expr) f) {
    for (final s in b.stmts) {
      _scanStmt(s, f);
    }
  }

  void _scanStmt(ast.Stmt s, void Function(ast.Expr) f) {
    switch (s) {
      case ast.LetStmt n:
        if (n.value != null) _scanExpr(n.value!, f);
      case ast.ReturnStmt n:
        if (n.value != null) _scanExpr(n.value!, f);
      case ast.IfStmt n:
        _scanExpr(n.cond, f);
        _scanBlock(n.then, f);
        if (n.orElse != null) _scanElse(n.orElse!, f);
      case ast.GuardStmt n:
        _scanExpr(n.cond, f);
        _scanBlock(n.orElse, f);
      case ast.GuardLetStmt n:
        _scanExpr(n.value, f);
        if (n.condition != null) _scanExpr(n.condition!, f);
        _scanBlock(n.orElse, f);
      case ast.WhileStmt n:
        _scanExpr(n.cond, f);
        _scanBlock(n.body, f);
      case ast.ForStmt n:
        _scanExpr(n.iterable, f);
        _scanBlock(n.body, f);
      case ast.EmitStmt n:
        _scanExpr(n.value, f);
      case ast.ExprStmt n:
        _scanExpr(n.expr, f);
      case ast.BlockStmt n:
        _scanBlock(n.block, f);
      case ast.BreakStmt _:
      case ast.ContinueStmt _:
      case ast.ErrorStmt _:
        break;
    }
  }

  void _scanElse(ast.Else e, void Function(ast.Expr) f) {
    switch (e) {
      case ast.ElseIf n:
        _scanStmt(n.ifStmt, f);
      case ast.ElseBlock n:
        _scanBlock(n.block, f);
    }
  }
}
