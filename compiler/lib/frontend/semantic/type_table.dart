// ===========================================================================
// type_table.dart — Tabela de tipos + resultado da Fase 5 (spec 009 §7).
// ===========================================================================
//
// Materialização À MÃO da spec `009-semantic-types` §7 (P11 / ADR-0010).
//
// Dragon 6.3.6: *"um tipo registro tem a forma record(t), onde t é um objeto de
// tabela de símbolos"* — a tabela é **parte do tipo**, não um índice lateral.
//
// SIDE-TABLE por identidade (`Map.identity`), AST imutável — ADR-0004 (a parte
// NÃO revogada pelo ADR-0013). São QUATRO artefatos, não um (§7):
//   1. <Expr, Type>                      → F7 (Kernel tipado) e F6
//   2. TypeTable (decl → info)           → F6 (Σ da exaustividade) e F7 (copy-with)
//   3. <nó, ResolvedMember>              → a resolução TYPE-DIRECTED (contrato 008 §5.4)
//   4. <TypeNode, Type>                  → dump e assinaturas
//
// A F5 **não produz só tipos: produz resolução**. E `typeOf` **FALHA** se não
// houver entrada — o oracle faz `_types[node] ?? const UnknownType()`
// (`type_table.dart:46`), um default que ESCONDE buraco: se a F7 pede tipo e
// recebe default silencioso, o `dynamic` volta pela porta dos fundos (ADR-0013).
// ===========================================================================

import 'package:ita_next_compiler/frontend/parser/ast.dart' as ast;
import 'package:ita_next_compiler/frontend/semantic/type.dart';

/// Erro semântico (EN kebab-case + span) — espelha `BindingError` da F4.
/// (`CheckError`, não `TypeError`: este último é do `dart:core`.)
class CheckError {
  final String code;
  final int offset;
  final int length;

  /// `true` para diagnóstico não-fatal. Hoje só `wildcard-covers-known-variants`
  /// (§12-6): o ÚNICO aviso sobre código legal — restrito a enum fechado, porque
  /// ao ADICIONAR uma variante o `_` a engole em silêncio e a exaustividade (uma
  /// promessa da linguagem, §4.7) deixa de proteger.
  final bool isWarning;

  const CheckError(this.code, this.offset, this.length, {this.isWarning = false});

  String format() => 'check-error: $code @$offset+$length';

  @override
  String toString() => format();
}

/// Um campo de `struct`/`class` — ORDEM importa (§8.2: o codegen enumera para o
/// construtor, o copy-with e o `==`/`hashCode` estruturais).
class FieldInfo {
  final String name;
  final Type type;
  final bool isMutable;
  final ast.FieldDecl decl;
  const FieldInfo(this.name, this.type, this.isMutable, this.decl);
}

/// Um método na tabela do tipo — spec 011 §3.2.
///
/// **Método mora na MESMA tabela do campo**, e isso é literal no livro (2.7 §1):
/// *"uma classe teria sua própria tabela, com uma entrada para cada **campo e
/// método**"*. Não há tabela de métodos separada.
///
/// [origin] é a decl que **CONTRIBUIU** o método — o próprio tipo, ou um
/// `extension`/`impl`. **Não é luxo:** é o que faz o `duplicate-member` apontar o
/// `extension` ofensor (e não o tipo, que é inocente), e o que a F7 vai precisar
/// para saber de onde baixar o `Procedure`.
class MethodInfo {
  final String name;
  final FunctionType sig;

  /// **Qualificador, não tabela** (Dragon 1.6.1, Ex. 1.3: *"static refere-se
  /// **não ao escopo** da variável, mas sim à capacidade de o compilador
  /// determinar a localização… torna x uma **variável de classe**"*). O escopo
  /// dos membros é um só (1.6.4); o que muda é o receptor: `Stack.new()` tem
  /// receptor = **nome de tipo**; `s.push()` tem receptor = **valor**.
  final bool isStatic;

  final ast.FnDecl decl;

  /// A decl que contribuiu: o próprio tipo, ou o `extension`/`impl`.
  final ast.AstNode origin;

  const MethodInfo(this.name, this.sig, this.isStatic, this.decl, this.origin);
}

/// O que o `.x`/`.f()` resolveu — **side-table nº3** do §7 (*"a F5 não produz só
/// tipos: produz **resolução**"*), consumida pela F7.
///
/// [ownerType] é o tipo **onde o membro foi ENCONTRADO**, já com os type-args
/// substituídos — pode não ser o tipo do receptor (herança). A F7 precisa dele
/// para saber de qual classe baixar o membro.
///
/// ⚠️ **A F5 resolve a ASSINATURA pelo tipo ESTÁTICO — não a implementação.**
/// Dragon 1.6.5, Ex. 1.8: *"Normalmente, é impossível saber durante a compilação
/// se x será da classe C ou da subclasse D… **Somente no momento da execução é
/// que pode ser decidida qual definição de m é a correta.**"* A seleção da
/// implementação é vtable da Dart VM = **Grupo B**. [decl] apontar para a decl do
/// tipo estático está **certo**, não é aproximação.
class ResolvedMember {
  final String name;
  final Type type;
  final Type ownerType;
  final ast.AstNode decl;
  final bool isStatic;
  const ResolvedMember(this.name, this.type, this.ownerType, this.decl, this.isStatic);
}

/// Uma variante de `enum` + o payload. O conjunto delas é o **Σ** que a F6 usa
/// para a exaustividade (contrato §4.7).
///
/// ⚠️ `EnumCase` **não é `AstNode`** e não tem span (mesma limitação do `FieldPattern`
/// — débito D4 da F4). Diagnósticos sobre um case caem no span do `EnumDecl`.
class VariantInfo {
  final String name;
  final List<Type> payload;
  const VariantInfo(this.name, this.payload);
}

/// O que a F5 sabe sobre um tipo declarado. Preenchido em duas etapas (A1 planta
/// a cabeça; A2 preenche o corpo) — é o que permite tipos **mutuamente
/// recursivos** (Dragon 6.3.1, box *"Nomes de tipo e tipos recursivos"*: o grafo
/// tem ciclos), pelo mesmo motivo do letrec de módulo da F4.
class TypeInfo {
  final ast.AstNode decl;
  final String name;
  final TypeKind kind;

  /// Parâmetros genéricos da DECL (`struct Box<T>`) — são da **fatia A** (A2 não
  /// resolve as anotações da stdlib sem eles: `Option<T>` 33×, `List<T>` em
  /// tudo). O que é da fatia D é só a **unificação** de type-args em aplicação.
  final List<String> generics;

  /// `null` até A2 preencher (A1 só planta a cabeça).
  List<FieldInfo>? fields;
  List<VariantInfo>? variants;

  /// Métodos — os próprios **e os contribuídos por `extension`/`impl`** (§3.1).
  /// Diferente de [fields]/[variants], começa **vazia e não-nula**: `extension`
  /// pode contribuir para um tipo que não declarou método nenhum, e a ordem de
  /// contribuição é irrelevante (5.2.5 + Ex. 5.10: *"as entradas podem ser
  /// atualizadas em **qualquer ordem**"* — campos e métodos são inserções
  /// **disjuntas**).
  final List<MethodInfo> methods = [];

  /// O `init` **primário** — memberwise sintetizado (`struct` sem `init`) ou o
  /// explícito do CORPO. Ruling do dono, spec 005 §10 + 011 §12.
  ///
  /// `null` para `class` sem `init` explícito ⟹ **inconstruível** (`no-init` no
  /// USO): dar-lhe memberwise apagaria o contraste do ADR-0012 #1.
  FunctionType? init;

  /// `init`s vindos de `extension` — **adicionais**, não substitutos.
  ///
  /// **Diretriz Swift do dono (2026-07-15):** `init` no CORPO **mata** o
  /// memberwise (*"é possível que você esteja fazendo trabalho especial que o
  /// default desconhece"*); `init` numa **`extension`** o **preserva**. É o
  /// escape canônico — a extension é o glifo que diz *"estou ADICIONANDO, não
  /// substituindo"*. Sem ele, quem precisa de um 2º construtor perde o
  /// memberwise inteiro.
  final List<FunctionType> extensionInits = [];

  /// Supertipo (`class D : Animal`) e conformances — a relação `≤` do §4.2b.
  Type? superclass;
  List<Type> traits;

  TypeInfo(this.decl, this.name, this.kind, {this.generics = const []})
    : traits = [];

  @override
  String toString() {
    final g = generics.isEmpty ? '' : '<${generics.join(", ")}>';
    return '${kind.name.replaceAll("_", "")} $name$g';
  }
}

/// Tabela de tipos: `decl → TypeInfo`, **por identidade** (ADR-0004).
class TypeTable {
  final Map<ast.AstNode, TypeInfo> _byDecl = Map.identity();

  /// Nomes do módulo → decl. É o namespace de TIPO, que a F4 deliberadamente
  /// NÃO resolve (contrato 008 §5.4: *"o namespace de TIPO … é inseparável do
  /// reticulado de tipos; o oracle já o faz em F5"*).
  final Map<String, ast.AstNode> _byName = {};

  void put(TypeInfo info) {
    _byDecl[info.decl] = info;
    _byName[info.name] = info.decl;
  }

  TypeInfo? of(ast.AstNode decl) => _byDecl[decl];
  ast.AstNode? declNamed(String name) => _byName[name];
  bool get isEmpty => _byDecl.isEmpty;
  Iterable<TypeInfo> get all => _byDecl.values;

  /// Dump determinístico (observável da fatia A — `itac check --dump-types`).
  /// Ordem-fonte via `offset` para o golden ser estável.
  String dump() {
    final infos = _byDecl.values.toList()
      ..sort((a, b) => a.decl.offset.compareTo(b.decl.offset));
    return infos.map(_dumpOne).join('\n');
  }

  String _dumpOne(TypeInfo i) {
    final parts = <String>[i.toString()];
    if (i.superclass != null) parts.add(': ${i.superclass}');
    for (final t in i.traits) {
      parts.add('+ $t');
    }
    for (final f in i.fields ?? const <FieldInfo>[]) {
      parts.add('\n  ${f.isMutable ? "var" : "let"} ${f.name}: ${f.type}');
    }
    for (final v in i.variants ?? const <VariantInfo>[]) {
      final p = v.payload.isEmpty ? '' : '(${v.payload.join(", ")})';
      parts.add('\n  case ${v.name}$p');
    }
    if (i.init != null) parts.add('\n  init${_sig(i.init!)}');
    // Ordem-FONTE pelo offset da decl que contribuiu — o `extension` pode estar
    // longe do tipo, e o golden tem de ser estável.
    final ms = i.methods.toList()
      ..sort((a, b) => a.decl.offset.compareTo(b.decl.offset));
    for (final m in ms) {
      final st = m.isStatic ? 'static ' : '';
      // A ORIGEM aparece quando não é o próprio tipo: é o que torna a
      // contribuição do `extension` VISÍVEL no observável (P4).
      final from = identical(m.origin, i.decl) ? '' : ' [via ${_originOf(m.origin)}]';
      parts.add('\n  $st${m.name}${_sig(m.sig)}$from');
    }
    return parts.join(' ').replaceAll(' \n', '\n');
  }

  String _sig(FunctionType f) => '(${f.params.join(", ")}) -> ${f.ret}';

  String _originOf(ast.AstNode o) => switch (o) {
    ast.ExtensionDecl _ => 'extension',
    ast.ImplDecl n => n.trait == null ? 'impl' : 'impl-trait',
    _ => 'decl',
  };
}

/// O resultado da Fase 5 (§7). Empacota as 4 side-tables + os erros.
///
/// A fatia **A** entrega [types] e [errors]; as tabelas de expressão chegam com
/// a fatia **B**.
class CheckResult {
  final ast.Program program;
  final TypeTable types;
  final List<CheckError> errors;

  /// `<TypeNode, Type>` — o que cada ANOTAÇÃO virou (§7-4). Dump e assinaturas.
  final Map<ast.TypeNode, Type> annotations;

  CheckResult(this.program, this.types, this.errors, this.annotations);

  /// Só o que ABORTA o pipeline — warnings (§12-6) não contam.
  bool get hasErrors => errors.any((e) => !e.isWarning);
}
