// ===========================================================================
// scope.dart — Pilha de escopos + resultado da resolução (Fase 4, spec 008).
// ===========================================================================
//
// Materialização À MÃO do artefato `compiler/docs/spec/binding.md` (P11 /
// ADR-0010: zero codegen). A disciplina de escopo espelha o oracle `ita/`
// (`semantic/scope.dart`) mas produz [ResolvedName] em vez de tipos.
//
// Fundamentação: Crafting Interpreters cap 11 (resolver estático, split
// declare/define) · Dragon 2.7.1 (tabela de símbolos encadeada = pilha) ·
// 1.6.3 (escopo léxico / shadowing). Side-table por identidade: ADR-0004.
//
// A RESOLUÇÃO vive numa side-table `Map.identity<AstNode, ResolvedName>` (o nó
// de USO `Ident`/`SelfExpr` como chave); a AST NUNCA é mutada. O valor aponta o
// nó-BINDER (não só `hops` como no Lox 11.4): o alvo é o Dart Kernel, que
// referencia variáveis POR OBJETO (`VariableGet(VariableDeclaration)`) — modelo
// rustc (`Res::Local`/`DefId`). O `hops` permanece (contrato ADR-0011 +
// detecção de captura).
// ===========================================================================

import 'package:ita_next_compiler/frontend/parser/ast.dart';

// ---------------------------------------------------------------------------
// ResolvedName — o valor da side-table (§5.1).
// ---------------------------------------------------------------------------

/// A que declaração um uso de nome (`Ident`/`SelfExpr`) se liga. `sealed` →
/// `switch` exaustivo de graça (CI 5.2.1).
sealed class ResolvedName {
  const ResolvedName();
}

/// Nome LOCAL: liga ao nó-binder ([BindPattern]/[Param]/[RestPattern]), com
/// [hops] = nº de escopos léxicos entre o uso e o binder (0 = mesmo escopo,
/// Dragon 1.6.3) e [captured] = o uso cruza uma fronteira de função/closure.
///
/// [captured] é DIAGNÓSTICO (Grupo B): a Dart VM faz closure-conversion nativa,
/// o Kernel referencia o `VariableDeclaration` externo direto — F4 só sinaliza,
/// não materializa upvalues (diverge do clox).
///
/// [binder] é `Object` (não `AstNode`) porque [Param] carrega span mas NÃO é um
/// `AstNode` nesta materialização (é um produto — ast.dart §"Produtos"); é o
/// binder correto de um parâmetro. Use [binderOffset] para o span.
final class LocalRes extends ResolvedName {
  final Object binder; // BindPattern | RestPattern | Param
  final int hops;
  final bool captured;
  const LocalRes(this.binder, this.hops, this.captured);
}

/// Nome TOP-LEVEL (letrec de módulo, §0.5-3): liga à declaração
/// ([FnDecl]/`Struct`/`Class`/`Enum`/`Trait`/`Actor`Decl ou o binder de um
/// `let`/`var` global). Sem `hops` — o escopo de módulo é a raiz (globais não
/// são "capturados" no sentido de closure).
final class TopLevelRes extends ResolvedName {
  final AstNode decl;
  const TopLevelRes(this.decl);
}

/// `self`: liga ao receptor sintético do método — o nó da declaração de tipo
/// envolvente ([StructDecl]/[ClassDecl]/[EnumDecl]/[TraitDecl]/[ActorDecl]) ou o
/// `target` de um [ImplDecl]/[ExtensionDecl].
final class SelfRes extends ResolvedName {
  final AstNode receiver;
  const SelfRes(this.receiver);
}

/// Offset (byte) do nó-binder, seja ele `AstNode` ou [Param] (produto que
/// carrega span mas não é `AstNode`). Usado pelo dump do `resolve --dump`.
int binderOffset(Object binder) => switch (binder) {
  AstNode n => n.offset,
  Param p => p.offset,
  _ => -1,
};

/// Serializa um [ResolvedName] para o `resolve --dump` (formato determinístico,
/// documentado em `binding.md` §Observável):
///   `->L<binderOffset>^<hops>[*]`  local ( `*` = capturado, cruza fn/closure )
///   `->T<declOffset>`              top-level (letrec de módulo)
///   `->S<receiverOffset>`          self (método)
///   `->?`                          não resolvido (erro `unresolved-name`/self-fora)
String formatResolution(ResolvedName? r) => switch (r) {
  LocalRes l => '->L${binderOffset(l.binder)}^${l.hops}${l.captured ? '*' : ''}',
  TopLevelRes t => '->T${t.decl.offset}',
  SelfRes s => '->S${s.receiver.offset}',
  null => '->?',
};

// ---------------------------------------------------------------------------
// Scope — a tabela de símbolos encadeada (Dragon 2.7.1).
// ---------------------------------------------------------------------------

/// Entrada da tabela: o nó-binder + o estado declare/define (CI 11.3.2). Um
/// símbolo não-[ready] existe mas ainda não pode ser lido — é o que pega
/// `let a = a` (`read-in-own-initializer`).
class ScopeEntry {
  final Object binder;
  bool ready;
  ScopeEntry(this.binder, this.ready);
}

/// Um escopo léxico: seus símbolos + link para o pai. O aninhamento forma uma
/// pilha (Dragon 2.7.1). A busca (feita pelo [Resolver], que conta `hops`) sobe
/// a cadeia; o mais interno vence (shadowing, Dragon 1.6.3).
class Scope {
  final Scope? parent;

  /// Fronteira de função/closure — usada p/ detectar CAPTURA (um uso cujo
  /// binder está acima desta fronteira cruzou-a → variável capturada).
  final bool isFnBoundary;

  /// Escopo raiz de módulo — os nomes aqui são [TopLevelRes] (letrec), sem
  /// `hops` e imunes ao `read-in-own-initializer`.
  final bool isModule;

  final Map<String, ScopeEntry> _symbols = {};

  Scope(this.parent, {this.isFnBoundary = false, this.isModule = false});

  /// Declara [name] neste escopo. Retorna `false` se já existia LOCALMENTE
  /// (redeclaração no mesmo escopo → `duplicate-declaration`; o chamador emite o
  /// erro). NÃO olha os pais — shadowing aninhado é permitido.
  bool declare(String name, Object binder, {required bool ready}) {
    if (_symbols.containsKey(name)) return false;
    _symbols[name] = ScopeEntry(binder, ready);
    return true;
  }

  /// Marca [name] como pronto (fim do split declare/define, CI 11.3.2).
  void define(String name) {
    _symbols[name]?.ready = true;
  }

  /// Busca [name] APENAS neste escopo (a subida pela cadeia + contagem de `hops`
  /// é do [Resolver], que precisa saber ONDE parou).
  ScopeEntry? lookupLocal(String name) => _symbols[name];
}
