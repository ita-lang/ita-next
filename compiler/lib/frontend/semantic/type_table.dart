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
    return parts.join(' ').replaceAll(' \n', '\n');
  }
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
