// emit.dart — o EMITTER da F7 (B2, CA1 mínimo). Anda o `CheckResult`
// (F5+F6-verde) e produz o `Component`: a AST REAL do Itá → Dart Kernel.
//
// ESCOPO: o **CA1** (`fn main() { print("olá, ${1 + 1}") }`, spec 013 §11) +
// a §7.4-a (interpolação, literais `Int`, aritmética de `Int`). Qualquer nó fora
// disso vira **ICE honesto** (`ice-codegen-*` com o nome do nó, §7.8) — NUNCA
// `dynamic`, NUNCA silêncio (ADR-0013). O mapa nó→Kernel:
//
//   FnDecl `main` (aridade 0, Void) → Procedure static top-level (mainMethod)
//   BlockBody                        → Block            (ExprBody → ICE)
//   ExprStmt                         → ExpressionStatement
//   Call(callee ⇒ GroundRes('print'))→ StaticInvocation.byReference(dart:core::print)
//   Str SEM interp                   → StringLiteral
//   Str COM interp                   → StringConcatenation (a parte não-String
//                                       ganha `toString()` implícito da VM — o nó
//                                       NÃO o representa; Grupo B)
//   IntLit                           → IntLiteral
//   BoolLit                          → BoolLiteral
//   Binary add/sub/mul/div/mod (Int) → InstanceInvocation de dart:core::num
//                                       (div → `~/`; pow → ICE)
//   Binary lt/gt/le/ge (Int/Float)   → InstanceInvocation de dart:core::num
//                                       (`<`/`>`/`<=`/`>=`; receptor não-numérico → ICE)
//   Binary eq/ne                     → EqualsCall / Not(EqualsCall) — `==` é nó
//                                       ESPECIAL no Kernel (não InstanceInvocation);
//                                       `interfaceTarget` = o `==` do tipo do receptor
//                                       (Int→num::==, String→String::==, Bool→Object::==)
//   Binary and/or                    → LogicalExpression (curto-circuito é do nó, Grupo B)
//   IfExpr (forma booleana)          → ConditionalExpression(cond, then, orElse, staticType)
//                                       (if-let, `binding != null` → ICE — fatia do `match`)
//
// O `print` é resolvido no [platform] carregado (a receita do `hello.dart`); o
// handoff do B1 é o callee: um `Ident` cuja `check.resolution[ident]` é a
// `GroundRes('print')` da F4 (`binding/scope.dart`).

import 'package:kernel/ast.dart' as k;

import 'package:ita_next_compiler/frontend/binding/scope.dart';
import 'package:ita_next_compiler/frontend/parser/ast.dart' as ast;
import 'package:ita_next_compiler/frontend/semantic/type.dart';
import 'package:ita_next_compiler/frontend/semantic/type_table.dart';

/// ICE de codegen (§7.8): impossibilidade INTERNA da emissão. A F7 **não tem
/// erro de usuário** — sua entrada é programa F5+F6-verde. Se isto dispara sobre
/// corpus, é bug de fase anterior que vazou, não input malformado.
class CodegenIce implements Exception {
  /// `ice-codegen-*`, EN kebab-case, com o nome do nó que abortou.
  final String code;
  final int offset;
  final int length;

  CodegenIce(this.code, this.offset, this.length);

  @override
  String toString() => 'ice: $code @$offset+$length';
}

Never _ice(String suffix, ast.AstNode node) =>
    throw CodegenIce('ice-codegen-$suffix', node.offset, node.length);

/// O que uma variante de `enum` SELADO virou (§7.4-c): a subclasse, seu
/// construtor, os campos do payload por NOME, e — só para variante sem payload —
/// o singleton estático.
class _Variant {
  final k.Class cls;
  final k.Constructor ctor;
  final Map<String, k.Field> fields;
  final k.Field? singleton;
  const _Variant(this.cls, this.ctor, this.fields, this.singleton);
}

/// Emite as libs do programa [check] (F5+F6-verde) e o `Procedure` de `main`,
/// resolvendo o interop enumerado `dart:core::print` (§8.2) contra o [platform]
/// carregado. O `finalizeProgram` fixa o `main` como `Component.mainMethod`.
///
/// [sourceUri] vira o `fileUri` dos nós (forward-compat span→stack-trace); o
/// default cobre o uso à mão / testes.
({List<k.Library> libs, k.Procedure main}) emitProgram(
  CheckResult check,
  k.Component platform, {
  Uri? sourceUri,
}) {
  final fileUri = sourceUri ?? Uri.parse('file:///main.tu');
  final libUri = Uri.parse('app:///main.dart');

  // A `Library` nasce ANTES do emitter porque `k.Name` a exige para todo nome
  // que começa com `_` (ver `_memberName`).
  final lib = k.Library(libUri, fileUri: fileUri);
  final emitter = _Emitter(
    check,
    _resolvePrintRef(platform),
    _resolveArithOps(platform),
    _resolveFloatDiv(platform),
    _resolveNegOp(platform),
    _resolveCmpOps(platform),
    _resolveEqualsOps(platform),
    _resolveCoreTypes(platform),
    _dartCoreClass(platform, 'Object'),
    lib,
    fileUri,
  );
  final emitted = emitter.emitTopLevel();
  for (final c in emitted.classes) {
    lib.addClass(c);
  }
  for (final p in emitted.procedures) {
    lib.addProcedure(p);
  }
  return (libs: [lib], main: emitted.main);
}

/// Acha `dart:core::print` no platform carregado (receita do `hello.dart` /
/// `generate_dill.dart` do oracle). Único built-in de I/O do chão (§7.6).
k.Reference _resolvePrintRef(k.Component platform) {
  final dartCore = platform.libraries
      .firstWhere((l) => l.importUri.toString() == 'dart:core');
  return dartCore.procedures
      .firstWhere((p) => p.name.text == 'print')
      .reference;
}

/// Resolve os aritméticos de `Int` da `_primitiveOps` (add/sub/mul/div/mod) →
/// o `Procedure` do operador no platform, de onde saem `interfaceTarget` +
/// `functionType` (o Kernel os exige non-nullable; sem eles a chamada cairia em
/// `DynamicInvocation`).
///
/// ⚠️ **Os operadores aritméticos de `int` são HERDADOS de `dart:core::num`** —
/// `int` só sobrescreve o `unary-` (int.dart:311). `+`/`-`/`*`/`%`/`/`/`~/` vivem
/// em `num` (num.dart:110-172), logo o interfaceTarget é o membro de `num` —
/// exatamente o que a CFE emitiria para `1 + 1`.
///
/// ⚠️ **`div` (`/`) do Itá é `Int → Int`** (F5 `_primitiveOps`), mas o
/// `num operator /` devolve **`double`** (num.dart:155). A divisão inteira que
/// devolve `int` é o `~/` (`num operator ~/`, num.dart:172). Por isso
/// `BinaryOp.div → ~/`, senão o resultado vazaria como `double` (quebra de tipo
/// e de paridade). Fonte: SDK pinado `.dart-sdk/3.12.2/.../core/num.dart`.
Map<ast.BinaryOp, k.Procedure> _resolveArithOps(k.Component platform) {
  final num = _dartCoreClass(platform, 'num');
  k.Procedure op(String symbol) => num.procedures.firstWhere(
        (p) => p.kind == k.ProcedureKind.Operator && p.name.text == symbol,
      );
  return {
    ast.BinaryOp.add: op('+'),
    ast.BinaryOp.sub: op('-'), // binário; o unário é `unary-` (names.dart:55) — não colide
    ast.BinaryOp.mul: op('*'),
    ast.BinaryOp.div: op('~/'), // o de **Int**; o de Float é `/` — ver [_resolveFloatDiv]
    ast.BinaryOp.mod: op('%'),
  };
}

/// O `/` de `dart:core::num` — o alvo do `div` quando os operandos são **Float**.
///
/// `div` é o ÚNICO aritmético cujo alvo Kernel depende do TIPO, porque a tabela
/// da F5 (`check.dart:65-68`) o admite nas DUAS formas:
///
///     div: (Int, Int) -> Int      ⟹  `~/`  (`num operator ~/` devolve **int**)
///     div: (Float, Float) -> Float ⟹  `/`   (`num operator /` devolve **double**)
///
/// Emitir `~/` para Float faria `7.0 / 2.0` render **3**, não `3.5` — o tipo
/// estático mentiria sobre o valor. É a MESMA armadilha que o `~/` de Int fecha,
/// na direção oposta: cada um dos dois operadores é o errado para o outro tipo.
/// Fonte: SDK pinado `.dart-sdk/3.12.2/.../core/num.dart:155` (`/`) e `:172` (`~/`).
k.Procedure _resolveFloatDiv(k.Component platform) =>
    _dartCoreClass(platform, 'num').procedures.firstWhere(
          (p) => p.kind == k.ProcedureKind.Operator && p.name.text == '/',
        );

/// O `unary-` de `dart:core::num` — nome DEDICADO (`names.dart:55`) para não
/// colidir com a subtração binária. É também o único aritmético que `int`
/// sobrescreve em vez de herdar (`int.dart:311`). Ver [_Emitter._unary].
k.Procedure _resolveNegOp(k.Component platform) =>
    _dartCoreClass(platform, 'num').procedures.firstWhere(
          (p) => p.kind == k.ProcedureKind.Operator && p.name.text == 'unary-',
        );

/// Resolve as comparações de ORDEM (`<`/`>`/`<=`/`>=`) → o `Procedure` do
/// operador em `dart:core::num` — **mesma receita/mesmo `InstanceInvocation` dos
/// aritméticos** (herdados por `int`/`double`). Os quatro vivem em `num`
/// (num.dart:217/224/231/238, devolvem `bool`); o `interfaceTarget` +
/// `functionType` saem daí (`bool Function(num)`). Fonte: SDK pinado
/// `.dart-sdk/3.12.2/.../core/num.dart`.
///
/// ⚠️ Só valem para receptor NUMÉRICO. `String < String` **não existe** no
/// Kernel (`String` não declara `<`); a F5 só cobra `comparison-type-mismatch`
/// (tipos iguais), não "tem operador". Um `<` de receptor não-numérico é ICE
/// (`ice-codegen-cmp-on-<Tipo>`) — nunca emitir um `<` que a VM rejeita.
Map<ast.BinaryOp, k.Procedure> _resolveCmpOps(k.Component platform) {
  final num = _dartCoreClass(platform, 'num');
  k.Procedure op(String symbol) => num.procedures.firstWhere(
        (p) => p.kind == k.ProcedureKind.Operator && p.name.text == symbol,
      );
  return {
    ast.BinaryOp.lt: op('<'),
    ast.BinaryOp.gt: op('>'),
    ast.BinaryOp.le: op('<='),
    ast.BinaryOp.ge: op('>='),
  };
}

/// Resolve o alvo do `==` (`EqualsCall.interfaceTarget`) POR TIPO de receptor.
/// `==` é nó ESPECIAL no Kernel (`EqualsCall`, expressions.dart:2471) e o
/// `interfaceTarget` é o `operator ==` **de interface** do tipo estático do
/// receptor — o que a CFE grava para `l == r` non-null:
///
///   - `Int`  → `num::==`    (`int` NÃO declara `==`; herda de `num`, num.dart:47)
///   - `Float`→ `num::==`    (idem `double`)
///   - `String`→ `String::==` (declara o seu, string.dart:244)
///   - `Bool` → `Object::==`  (`bool` NÃO declara `==`; herda de `Object`, object.dart:53)
///
/// A F5 aceita `l == r` de QUALQUER par de tipos idênticos, mas o emitter só sabe
/// baixar estes quatro escalares; receptor fora da tabela → ICE (o operando já
/// seria intraduzível). Fonte: SDK pinado `.dart-sdk/3.12.2/.../core/`.
Map<Type, k.Procedure> _resolveEqualsOps(k.Component platform) {
  k.Procedure eqOf(String className) =>
      _dartCoreClass(platform, className).procedures.firstWhere(
            (p) => p.kind == k.ProcedureKind.Operator && p.name.text == '==',
          );
  final numEq = eqOf('num');
  return {
    const IntType(): numEq,
    const FloatType(): numEq,
    const StringType(): eqOf('String'),
    const BoolType(): eqOf('Object'),
  };
}

k.Class _dartCoreClass(k.Component platform, String name) {
  final dartCore = platform.libraries
      .firstWhere((l) => l.importUri.toString() == 'dart:core');
  return dartCore.classes.firstWhere((c) => c.name == name);
}

/// Os tipos do CHÃO que a F7 sabe baixar (§7.4-a + `let`): os básicos `Int`/
/// `String`/`Bool` → `InterfaceType` **non-nullable** (ADR-0013) das classes de
/// `dart:core` resolvidas do [platform] (mesma receita do `print`/`num`); `Void`
/// → `VoidType`. A tabela é keyed pelos `Type` da F5 — que têm `==`/`hashCode`
/// de valor (`type.dart:82-128`), logo `const IntType()` casa qualquer `IntType`.
///
/// Tudo fora destes quatro é ICE honesto (`ice-codegen-type-<Tipo>`): o Kernel
/// exige `VariableDeclaration.type` non-nullable, e sem imagem aqui só sobraria
/// `dynamic` — a porta dos fundos que o ADR-0013 tranca.
Map<Type, k.DartType> _resolveCoreTypes(k.Component platform) {
  k.DartType iface(String name) =>
      k.InterfaceType(_dartCoreClass(platform, name), k.Nullability.nonNullable);
  return {
    const IntType(): iface('int'),
    const FloatType(): iface('double'), // `Float` do Itá ≡ `double` do Dart (IEEE-754 binary64)
    const StringType(): iface('String'),
    const BoolType(): iface('bool'),
    const VoidType(): const k.VoidType(),
  };
}

class _Emitter {
  final CheckResult check;
  final k.Reference printRef;

  /// `dart:core::num` operators (add/sub/mul/div→`~/`/mod), resolvidos 1× do
  /// platform. A `Str` interpolada NÃO precisa deles — a conversão para String é
  /// da VM (`StringBase._interpolate`), não uma call que emitimos.
  final Map<ast.BinaryOp, k.Procedure> arithOps;

  /// O `/` de `num` — alvo do `div` quando os operandos são **Float**. Ver
  /// [_resolveFloatDiv]: o `~/` de [arithOps] devolveria `int` e o tipo estático
  /// mentiria sobre o valor (`7.0 / 2.0` renderia 3).
  final k.Procedure floatDiv;

  /// O `unary-` de `num` — alvo do `-x`. Ver [_unary]: **não** é o `-` binário.
  final k.Procedure negOp;

  /// Comparações de ORDEM (`<`/`>`/`<=`/`>=`) → operador de `dart:core::num`,
  /// resolvidos 1×. Mesmo `InstanceInvocation` dos aritméticos. Ver [_resolveCmpOps].
  final Map<ast.BinaryOp, k.Procedure> cmpOps;

  /// `==` por tipo de receptor (Int/Float→`num::==`, String→`String::==`,
  /// Bool→`Object::==`), para o `interfaceTarget` do `EqualsCall`. Ver
  /// [_resolveEqualsOps].
  final Map<Type, k.Procedure> equalsOps;

  /// Os tipos do chão (`Int`/`String`/`Bool`/`Void`) → `DartType`, resolvidos 1×
  /// do platform. Ver [_resolveCoreTypes].
  final Map<Type, k.DartType> coreTypes;
  /// A `Library` do programa — necessária para nomes privados (ver [_memberName]).
  final k.Library lib;
  final Uri fileUri;

  /// **A 2ª side-table (LT-F7b): `binder → VariableDeclaration`-Kernel.** É da
  /// EMISSÃO — Nystrom §11.4, off-the-node e descartável —, campo de instância
  /// deste visitor. POPULADA quando `_let` baixa a decl (`_kernelDecls[binder] =
  /// varDecl`), CONSULTADA no uso (`_ident` → `VariableGet`).
  ///
  /// Chave `Map.identity` (não `==`): o binder é o `BindPattern` (`ast.dart:634`),
  /// que é o objeto para o qual o `LocalRes.binder` da F4 aponta (`scope.dart:45`)
  /// e a chave de `binderTypes` (nº6). Homônimos em escopos distintos são nós
  /// DISTINTOS — só a identidade os separa (mesma disciplina da `resolution`).
  ///
  /// ⚠️ Débito D4: no destructuring a chave vira `(binder, fieldName)` — fatia
  /// futura; hoje só `BindPattern` (uma variável, um binder).
  final Map<Object, k.VariableDeclaration> _kernelDecls = Map.identity();

  /// **`FnDecl` → `Procedure`** — o alvo do `StaticInvocation`. Preenchida no
  /// passo 1 de [emitTopLevel] (assinaturas) e consultada no passo 2 (corpos),
  /// que é o que faz recursão e forward-reference funcionarem.
  ///
  /// A chave é `Map.identity` pela mesma razão das outras: é o nó que a
  /// `TopLevelRes.decl` da F4 aponta, e identidade é o que separa homônimos.
  final Map<ast.FnDecl, k.Procedure> _procedures = Map.identity();

  /// A raiz implícita de toda `Class` que emitimos (§8.2 — `dart:core::Object` é
  /// interop ENUMERADO). O Kernel exige `supertype` non-null em classe concreta.
  final k.Class objectClass;

  /// **`StructDecl`/`ClassDecl` → `Class`**, e os dois satélites que a emissão de
  /// uso precisa: o `Constructor` (alvo do `ConstructorInvocation`) e os `Field`
  /// por nome (alvo do `InstanceGet`).
  ///
  /// Preenchidos no passo 1 de [emitTopLevel] — junto das assinaturas de `fn`, e
  /// pelo mesmo motivo: um `fn` pode receber/devolver um tipo declarado ABAIXO
  /// dele, e a `InterfaceType` precisa da `Class` já existindo.
  final Map<ast.AstNode, k.Class> _classes = Map.identity();
  final Map<ast.AstNode, k.Constructor> _constructors = Map.identity();
  final Map<ast.AstNode, Map<String, k.Field>> _fields = Map.identity();

  /// A classe de RUNTIME do `panic` (§7.4-f) — materializada sob demanda por
  /// [_panicCtor], para que programa sem `panic` não a carregue no `.dill`.
  k.Class? _panicClass;
  k.Constructor? _panicConstructor;

  /// **`EnumDecl` → variante → o que ela virou** (gabarito SELADO, §7.4-c).
  /// Vazio para enum sem payload, que usa constantes em [_fields].
  final Map<ast.AstNode, Map<String, _Variant>> _variants = Map.identity();

  /// **`TraitDecl` → requisito → `Procedure` abstrato** (§7.4-d). O conformer
  /// implementa cada um; o dispatch existencial aponta para eles.
  final Map<ast.AstNode, Map<String, k.Procedure>> _traitMembers = Map.identity();

  /// Métodos de instância emitidos, por tipo — o alvo do `v.metodo()`.
  final Map<ast.AstNode, Map<String, k.Procedure>> _methods = Map.identity();

  /// Corpos de método pendentes — emitidos no passo 2, junto dos de `fn`.
  final List<(ast.FnDecl, k.Procedure)> _methodBodies = [];

  /// Pilha de laços ABERTOS — o alvo de `break`/`continue`. Ver [_while].
  final List<({k.LabeledStatement brk, k.LabeledStatement cont, bool usedBrk, bool usedCont})> _loops = [];

  /// As subclasses de variante, na ordem de criação — entram na `Library` junto
  /// da base, e o CA10 as reconhece pelo prefixo `<Tipo>$`.
  final List<k.Class> _sealedVariants = [];

  /// O runtime de `Result` (§7.4-c), sob demanda — ver [_resultRuntime].
  ({k.Class base, k.Constructor okCtor, k.Field okValue, k.Constructor errCtor, k.Field errValue})?
      _resultParts;
  List<k.Class> _resultClasses = const [];

  _Emitter(
    this.check,
    this.printRef,
    this.arithOps,
    this.floatDiv,
    this.negOp,
    this.cmpOps,
    this.equalsOps,
    this.coreTypes,
    this.objectClass,
    this.lib,
    this.fileUri,
  );

  /// Nome de MEMBRO (campo, método) — **não** `k.Name(x)` cru.
  ///
  /// No Kernel, nome iniciado por `_` é PRIVADO e exige a `Library` que o
  /// declara: `Name(x)` sem ela estoura `Null check operator used on a null
  /// value` (`names.dart:40`) — um crash com stack trace, nem sequer um ICE.
  ///
  /// ⚠️ **No Itá o `_` não significa privado** — visibilidade é `pub`
  /// (`isPublic`), não convenção de sublinhado. Um campo `_x` é só um nome, e
  /// passar a library preserva esse nome; a privacidade Dart resultante é inócua
  /// (o programa é uma library só). O que NÃO se pode é deixar o crash de pé.
  k.Name _memberName(String name) =>
      k.Name(name, name.startsWith('_') ? lib : null);

  /// Emite os itens top-level em **DOIS PASSOS** — e a ordem não é estilo, é
  /// exigência do **letrec de módulo** (§0.5-3, o mesmo que a F4 implementa):
  ///
  ///   1. **assinaturas** — todo `FnDecl` vira um `Procedure` (params + retorno,
  ///      corpo vazio), registrado em [_procedures];
  ///   2. **corpos** — só então cada corpo é emitido.
  ///
  /// Um passo único quebraria em duas formas que o Itá permite: **recursão**
  /// (`fn fat(n) => fat(n-1)` precisa do próprio alvo antes de o corpo existir) e
  /// **forward-reference** (`main` chamando uma `fn` declarada ABAIXO dela). O
  /// `StaticInvocation.targetReference` é non-nullable — não há como "preencher
  /// depois".
  ///
  /// `main` é achado por nome; sua existência e assinatura já foram validadas
  /// pelo DRIVER (`compile.dart::checkMain`, §12-5) — os ICEs aqui são rede
  /// contra chamada direta da lib, não diagnóstico de usuário.
  ({
    List<k.Class> classes,
    List<k.Procedure> procedures,
    k.Procedure main,
  }) emitTopLevel() {
    final fns = <ast.FnDecl>[];
    final structs = <ast.StructDecl>[];
    final enums = <ast.EnumDecl>[];
    final classes = <ast.ClassDecl>[];
    final traits = <ast.TraitDecl>[];
    for (final item in check.program.body) {
      switch (item) {
        case ast.FnDecl f:
          fns.add(f);
        case ast.StructDecl s:
          structs.add(s);
        case ast.EnumDecl e:
          enums.add(e);
        case ast.ClassDecl c:
          classes.add(c);
        case ast.TraitDecl t:
          traits.add(t);
        default:
          _ice('toplevel-${item.runtimeType}', item); // class/trait/let global
      }
    }

    // Traits ANTES de tudo: o conformer os referencia em `implementedTypes`.
    for (final t in traits) {
      _trait(t);
    }
    // Passo 1a — os TIPOS primeiro: uma assinatura de `fn` pode mencionar um
    // `struct` declarado abaixo dela, e a `InterfaceType` precisa da `Class`.
    for (final s in structs) {
      _struct(s);
    }
    for (final e in enums) {
      _enum(e);
    }
    for (final c in classes) {
      _class(c);
    }
    // Passo 1b — assinaturas de `fn` (nada de corpo ainda).
    for (final fn in fns) {
      _procedures[fn] = _fnSignature(fn);
    }
    // Passo 2 — corpos, já podendo referenciar qualquer assinatura.
    for (final fn in fns) {
      _fnBody(fn, _procedures[fn]!);
    }
    for (final (m, proc) in _methodBodies) {
      _fnBody(m, proc);
    }

    final main = fns.where((f) => f.name == 'main').firstOrNull;
    if (main == null) {
      throw CodegenIce(
        'ice-codegen-missing-main',
        check.program.offset,
        check.program.length,
      );
    }
    return (
      classes: [
        for (final s in structs) _classes[s]!,
        for (final e in enums) _classes[e]!,
        for (final c in classes) _classes[c]!,
        for (final t in traits) _classes[t]!,
        ..._sealedVariants,
        // O runtime do `panic` entra SÓ se algum corpo o materializou.
        if (_panicClass != null) _panicClass!,
        ..._resultClasses,
      ],
      procedures: [for (final fn in fns) _procedures[fn]!],
      main: _procedures[main]!,
    );
  }

  /// `enum` COM payload → **classe selada + uma subclasse por variante**
  /// (§7.4-c: *sum type*), o gabarito que o `match` destrói por `IsExpression`.
  ///
  /// Base `abstract`, cada variante uma subclasse com os campos do payload
  /// (`final`, como em `struct` — variante é valor). Variante SEM payload dentro
  /// de um enum selado ganha subclasse **e** um `static final` singleton: sem
  /// ele, `.ponto` alocaria um objeto novo a cada uso e a comparação por
  /// identidade quebraria — mas o `match` usa `IsExpression`, então o singleton
  /// é economia, não correção.
  ///
  /// ⚠️ **`SuperInitializer` é OBRIGATÓRIO aqui**, diferente do `struct`: lá o
  /// supertype é `Object` e o Kernel sintetiza a chamada; aqui a superclasse é a
  /// nossa base, e o construtor dela precisa ser invocado explicitamente.
  ///
  /// ⚠️ **Nome sintético com `$`** (`Forma$circulo`): o Itá reserva `$` para
  /// sintéticos — o próprio desugaring gera binders `$x0` —, então não colide com
  /// nome de usuário. O oracle usa `_` (`Forma_circulo`), que um `struct
  /// Forma_circulo` colidiria em silêncio.
  void _enumSealed(ast.EnumDecl decl) {
    final base = k.Class(
      name: decl.name,
      isAbstract: true,
      fileUri: fileUri,
      supertype: objectClass.asThisSupertype,
    )..fileOffset = decl.offset;
    final baseCtor = k.Constructor(
      k.FunctionNode(k.EmptyStatement(), returnType: const k.VoidType()),
      name: k.Name(''),
      fileUri: fileUri,
    )..fileOffset = decl.offset;
    base.addConstructor(baseCtor);

    final variants = <String, _Variant>{};
    for (final c in decl.cases) {
      final vCls = k.Class(
        name: '${decl.name}\$${c.name}',
        fileUri: fileUri,
        // ⚠️ `base.asThisSupertype` NÃO serve aqui: ele lê `enclosingLibrary`,
        // e a base ainda não foi anexada à `Library` (isso só acontece no fim
        // de `emitTopLevel`). O `Supertype` direto não depende do enclosing —
        // e sem type-params na base, é exatamente o mesmo valor.
        supertype: k.Supertype(base, const []),
      )..fileOffset = decl.offset;

      final fields = <String, k.Field>{};
      final params = <k.VariableDeclaration>[];
      final initializers = <k.Initializer>[];
      for (final p in c.payload) {
        if (p.name.startsWith('_')) _ice('enum-private-payload-${c.name}', decl);
        final type = p.type == null
            ? _ice('enum-payload-untyped-${c.name}', decl)
            : _emitType(check.annotations[p.type!] ?? const ErrorType(), decl);
        final field = k.Field.immutable(
          _memberName(p.name),
          type: type,
          fileUri: fileUri,
        )..fileOffset = p.offset;
        vCls.addField(field);
        fields[p.name] = field;

        final param = k.VariableDeclaration(
          p.label ?? p.name,
          type: type,
          isRequired: p.defaultValue == null,
        )..fileOffset = p.offset;
        params.add(param);
        initializers.add(k.FieldInitializer(field, k.VariableGet(param)));
      }
      // O super vem DEPOIS dos campos: é a ordem que o Kernel espera.
      initializers.add(k.SuperInitializer(baseCtor, k.Arguments.empty()));

      final vCtor = k.Constructor(
        k.FunctionNode(
          k.EmptyStatement(),
          namedParameters: params,
          returnType: const k.VoidType(),
        ),
        name: k.Name(''),
        initializers: initializers,
        fileUri: fileUri,
      )..fileOffset = decl.offset;
      vCls.addConstructor(vCtor);

      // Variante sem payload: singleton, para `.ponto` não alocar por uso.
      k.Field? singleton;
      if (c.payload.isEmpty) {
        singleton = k.Field.immutable(
          _memberName(c.name),
          type: k.InterfaceType(vCls, k.Nullability.nonNullable),
          initializer: k.ConstructorInvocation(vCtor, k.Arguments([])),
          isStatic: true,
          isFinal: true,
          fileUri: fileUri,
        )..fileOffset = decl.offset;
        base.addField(singleton);
      }

      variants[c.name] = _Variant(vCls, vCtor, fields, singleton);
      _sealedVariants.add(vCls);
    }

    _classes[decl] = base;
    _constructors[decl] = baseCtor;
    _variants[decl] = variants;
  }

  /// A variante SELADA que um pattern nomeia, **no enum do SUBJECT**.
  ///
  /// ⚠️ Antes isto procurava em TODOS os enums emitidos e devolvia o primeiro
  /// que casasse o nome — e dois enums com uma variante homônima (`A.par` e
  /// `B.par`) faziam o segundo `match` usar a subclasse do PRIMEIRO. O `.dill`
  /// compilava, passava no verify, e explodia em runtime:
  /// *"type 'B$par' is not a subtype of type 'A$par' in type cast"*. Nome de
  /// variante é único DENTRO de um enum, não entre enums — a chave tem de
  /// incluir o tipo do escrutínio.
  _Variant? _sealedOf(ast.EnumPattern p, Type subjectType) {
    if (subjectType is! NamedType) return null;
    return _variants[subjectType.decl]?[p.variant];
  }

  /// `.variante` (enum do usuário, sem payload) → `StaticGet` da constante.
  ///
  /// O tipo vem da nº1 — é o esperado que a F5 fez descer (`.variante` é forma
  /// *checking-only*, §4.1: sem contexto ela nem tipa). Daí sai a decl, e da decl
  /// a `Class` que o passo 1a registrou.
  k.Expression _variantConst(ast.EnumShorthand s) {
    final type = check.exprTypes[s];
    if (type is! NamedType) _ice('variant-on-${type.runtimeType}', s);
    // Enum SELADO: a variante sem payload é o singleton da subclasse.
    final sealed = _variants[type.decl]?[s.variant];
    if (sealed != null) {
      final singleton = sealed.singleton;
      if (singleton == null) _ice('variant-needs-payload-${s.variant}', s);
      return k.StaticGet(singleton)..fileOffset = s.offset;
    }
    final field = _fields[type.decl]?[s.variant];
    if (field == null) _ice('variant-unknown-${s.variant}', s);
    return k.StaticGet(field)..fileOffset = s.offset;
  }

  /// `.variante(args)` → `ConstructorInvocation` da SUBCLASSE da variante.
  ///
  /// A F5 tipou o callee com a assinatura sintética da variante
  /// (`check.dart::_variantCtor`) e gravou o **slot** da nº5 — então os args
  /// entram named, pelos nomes do payload, exatamente como no `init` memberwise
  /// de `struct`.
  k.Expression _variantCall(ast.Call c, ast.EnumShorthand callee) {
    final type = check.exprTypes[c];
    // `Result` é do CHÃO (BuiltinType): `.ok(v)`/`.err(e)` constroem as classes
    // de runtime, não subclasses de uma decl do usuário.
    if (type is BuiltinType && type.kind == BuiltinKind.result) {
      final rt = _resultRuntime();
      final ctor = switch (callee.variant) {
        'ok' => rt.okCtor,
        'err' => rt.errCtor,
        _ => _ice('result-variant-${callee.variant}', c),
      };
      if (c.args.length != 1) _ice('result-arity', c);
      return k.ConstructorInvocation(
        ctor,
        k.Arguments([_expr(c.args.single.value)]),
      )..fileOffset = c.opOffset;
    }
    if (type is! NamedType) _ice('variant-call-on-${type.runtimeType}', c);
    final decl = type.decl;
    final v = _variants[decl]?[callee.variant];
    if (v == null) _ice('variant-call-unknown-${callee.variant}', c);

    final call = check.resolvedCalls[c];
    if (call == null) _ice('variant-call-unresolved', c);
    if (decl is! ast.EnumDecl) _ice('variant-call-nondecl', c);
    final payload =
        decl.cases.where((x) => x.name == callee.variant).single.payload;
    final slot = call.slot;
    if (slot.length != c.args.length) _ice('variant-call-slot-arity', c);

    final named = <k.NamedExpression>[];
    for (var i = 0; i < c.args.length; i++) {
      final pi = slot[i];
      if (pi < 0 || pi >= payload.length) _ice('variant-call-slot-range', c);
      final p = payload[pi];
      named.add(k.NamedExpression(p.label ?? p.name, _expr(c.args[i].value))
        ..fileOffset = c.args[i].value.offset);
    }
    return k.ConstructorInvocation(v.ctor, k.Arguments([], named: named))
      ..fileOffset = c.opOffset;
  }

  /// O default de um param → **`ConstantExpression`**, não a expressão comum.
  ///
  /// ⚠️ **A VM exige que default de parâmetro seja CONSTANTE**, e o nó tem de
  /// dizê-lo: emitir um `IntLiteral` cru faz a VM morrer no load com
  /// *"Not a constant expression: unexpected kernel tag SpecializedIntLiteral"*.
  /// Não é o verifier que reprova — é o carregador, em RUNTIME, depois de tudo
  /// passar. Foi assim que este caso apareceu.
  ///
  /// A restrição é do Dart e não tem contorno barato: é o preço de deixar a VM
  /// materializar o default (Grupo B) em vez de a F7 duplicar a expressão por
  /// call-site.
  ///
  /// Literais entram; qualquer outra expressão vira ICE HONESTO
  /// (`default-not-const`), porque a alternativa — materializar no call-site —
  /// é uma decisão de emissão que a §7.4-a **não** tomou (ela escolheu named +
  /// Grupo B, ruling §12-3).
  k.Expression _constDefault(ast.Expr e, ast.AstNode span) {
    final constant = switch (e) {
      ast.IntLit n => k.IntConstant(n.value),
      ast.FloatLit n => k.DoubleConstant(n.value),
      ast.BoolLit n => k.BoolConstant(n.value),
      ast.NilLit _ => k.NullConstant(),
      // `Str` SEM interpolação é literal; com interpolação não é constante.
      ast.Str s when s.parts.every((p) => p is ast.StrLit) => k.StringConstant([
          for (final p in s.parts)
            if (p is ast.StrLit) p.value,
        ].join()),
      _ => _ice('default-not-const-${e.runtimeType}', span),
    };
    return k.ConstantExpression(constant)..fileOffset = e.offset;
  }

  /// `trait` → **`abstract class`**; requisito → `Procedure` ABSTRATO (§7.4-d).
  ///
  /// É a base do dispatch existencial: `any Fala` vira `InterfaceType` do trait,
  /// e `v.som()` vira `InstanceInvocation` com `interfaceTarget` no procedure
  /// abstrato. **A vtable é Grupo B** — a VM resolve; nós só declaramos a forma.
  ///
  /// ⚠️ **A travessia `any` de fonte LOCAL é ZERO NÓ** (CA11, ADR-0017 §5): um
  /// `Pato` que conforma `Fala` já É um `Fala` no Kernel (está em
  /// `implementedTypes`), então passar um ao outro não emite box, cast nem
  /// wrapper. É o que o invariante de custo zero vigia.
  void _trait(ast.TraitDecl decl) {
    if (decl.generics.isNotEmpty) _ice('trait-generic', decl);

    final cls = k.Class(
      name: decl.name,
      isAbstract: true,
      fileUri: fileUri,
      supertype: objectClass.asThisSupertype,
    )..fileOffset = decl.offset;

    final requisitos = <String, k.Procedure>{};
    for (final m in decl.members) {
      if (m is! ast.FnDecl) _ice('trait-member-${m.runtimeType}', decl);
      if (m.body != null) _ice('trait-default-method', decl); // R3: fatia própria
      final proc = _methodSignature(m, decl, isAbstract: true);
      cls.addProcedure(proc);
      requisitos[m.name] = proc;
    }

    _classes[decl] = cls;
    _traitMembers[decl] = requisitos;
  }

  /// A assinatura de um método (de `trait`, `struct` ou `class`) → `Procedure`
  /// de instância. Mesma forma do `fn` top-level, menos o `isStatic`: params
  /// **named** (§12-3), retorno da anotação, `this` implícito.
  k.Procedure _methodSignature(
    ast.FnDecl fn,
    ast.AstNode owner, {
    required bool isAbstract,
  }) {
    if (fn.generics.isNotEmpty) _ice('method-generic', owner);
    if (fn.asyncMarker != ast.AsyncMarker.sync) _ice('method-async', owner);

    final named = <k.VariableDeclaration>[];
    for (final p in fn.params) {
      final type = check.binderTypes[p] ??
          (p.type == null ? null : check.annotations[p.type!]);
      if (type == null) _ice('method-param-untyped', owner);
      final def = p.defaultValue;
      final decl = k.VariableDeclaration(
        p.label ?? p.name,
        type: _emitType(type, owner),
        isRequired: def == null,
        initializer: def == null ? null : _constDefault(def, owner),
      )..fileOffset = p.offset;
      _kernelDecls[p] = decl;
      named.add(decl);
    }

    final returnType = fn.returnType == null
        ? const k.VoidType()
        : _emitType(check.annotations[fn.returnType!] ?? const VoidType(), owner);

    return k.Procedure(
      _memberName(fn.name),
      k.ProcedureKind.Method,
      k.FunctionNode(
        null, // corpo no passo 2 (ou nenhum, se abstrato)
        namedParameters: named,
        returnType: returnType,
      ),
      isAbstract: isAbstract,
      fileUri: fileUri,
    )..fileOffset = fn.offset;
  }

  /// `class` → `Class` de REFERÊNCIA, com `init` EXPLÍCITO (§7.4-c, **CA3**).
  ///
  /// **`class` nunca ganha memberwise** (ADR-0012 §A-1): sem `init` no corpo ela
  /// é INCONSTRUÍVEL, e é esse contraste com `struct` que dá conteúdo ao P2 — o
  /// glifo escolhe entre valor e referência, e cada um paga um preço diferente.
  ///
  /// Campo `var` baixa MUTÁVEL (`Field.mutable`, com setter), diferente do
  /// `struct`, onde o ruling §12-1 obriga todos a `final`. É a diferença
  /// observável entre os dois: referência pode mutar, valor não.
  ///
  /// ⚠️ **O corpo do `init` vira `initializers`, não statements** — e a razão é
  /// dura: no Kernel, campo `final` **só** pode ser atribuído em `initializers`;
  /// atribuí-lo no corpo é malformado. O Itá escreve `self.saldo = inicial`
  /// dentro do `init`, então cada `ExprStmt(Assign(Member(self, campo), e))` é
  /// convertido em `FieldInitializer`.
  ///
  /// A conversão exige que o corpo seja **só** atribuições a `self` — qualquer
  /// outro statement vira ICE (`init-body-<T>`). Não é preguiça: `FieldInitializer`
  /// roda ANTES do corpo, então misturar lógica entre as atribuições mudaria a
  /// ORDEM de avaliação em silêncio. Enquanto a fatia que ordena isso não existe,
  /// a restrição é declarada em vez de adivinhada.
  void _class(ast.ClassDecl decl) {
    if (decl.generics.isNotEmpty) _ice('class-generic', decl);

    // ⚠️ **O papel vem do KIND, não da POSIÇÃO** (ruling do dono, 2026-07-15).
    // O parser põe o 1º type após `:` em `superclass` — split posicional, e
    // portanto reversível —, mas `class Robo : Fala` tem um TRAIT ali. Quem
    // decide é o kind: trait ⟹ conformance; `class` ⟹ herança (fatia futura).
    final superType = decl.superclass;
    final conformances = <ast.TypeNode>[...decl.traits];
    if (superType != null) {
      final t = check.annotations[superType];
      final isTrait = t is NamedType &&
          check.types.of(t.decl)?.kind == TypeKind.trait_;
      if (!isTrait) _ice('class-superclass', decl); // herança real: fatia própria
      conformances.insert(0, superType);
    }

    final info = check.types.of(decl);
    if (info == null) _ice('class-untyped', decl);
    final fieldInfos = info.fields;
    if (fieldInfos == null) _ice('class-nofields', decl);

    final cls = k.Class(
      name: decl.name,
      fileUri: fileUri,
      supertype: objectClass.asThisSupertype,
      implementedTypes: _traitSupertypes(conformances, decl),
    )..fileOffset = decl.offset;

    final byName = <String, k.Field>{};
    for (final f in fieldInfos) {
      if (f.name.startsWith("_")) _ice("class-private-field", decl);
      final type = _emitType(f.type, decl);
      // `var` → mutável (tem setter); `let` → final. O sanitize confere a
      // coerência `isFinal ⟺ sem setter` depois.
      final field = f.isMutable
          ? k.Field.mutable(_memberName(f.name), type: type, fileUri: fileUri)
          : k.Field.immutable(_memberName(f.name), type: type, fileUri: fileUri);
      field.fileOffset = f.decl.offset;
      cls.addField(field);
      byName[f.name] = field;
    }
    _classes[decl] = cls;
    _fields[decl] = byName;

    final inits = [
      for (final m in decl.members)
        if (m is ast.InitDecl) m,
    ];
    if (inits.isEmpty) {
      // Inconstruível por construção (ADR-0012 §A-1) — a F5 acusa `no-init` no
      // USO, então um programa verde nunca chega aqui sem init.
      _ice('class-no-init', decl);
    }
    if (inits.length > 1) _ice('class-multi-init', decl); // extensionInits: fatia


    _constructors[decl] = _initCtor(inits.single, cls, byName, decl);
    _addMethods(decl, cls, decl.members);
  }

  /// O `init` explícito → `Constructor`, com o corpo convertido em
  /// `initializers`. Ver [_class] para a razão.
  k.Constructor _initCtor(
    ast.InitDecl init,
    k.Class cls,
    Map<String, k.Field> byName,
    ast.ClassDecl decl,
  ) {
    final params = <k.VariableDeclaration>[];
    for (final p in init.params) {
      // A nº6 (`binderTypes`) cobre binders de `let`/`match`/param de `fn`, mas
      // não os do `init` — para eles a fonte é a ANOTAÇÃO, que o `init` sempre
      // exige (não há inferência de param aqui).
      final type = check.binderTypes[p] ??
          (p.type == null ? null : check.annotations[p.type!]);
      if (type == null) _ice('init-param-untyped', decl);
      final def = p.defaultValue;
      final param = k.VariableDeclaration(
        p.label ?? p.name,
        type: _emitType(type, decl),
        isRequired: def == null,
        initializer: def == null ? null : _constDefault(def, decl),
      )..fileOffset = p.offset;
      _kernelDecls[p] = param;
      params.add(param);
    }

    final initializers = <k.Initializer>[];
    for (final s in init.body.stmts) {
      // O ÚNICO formato aceito: `self.campo = <expr>`.
      if (s is! ast.ExprStmt) _ice('init-body-${s.runtimeType}', decl);
      final e = s.expr;
      if (e is! ast.Assign || e.op != ast.AssignOp.assign) {
        _ice('init-body-${e.runtimeType}', decl);
      }
      final target = e.target;
      if (target is! ast.Member || target.receiver is! ast.SelfExpr) {
        _ice('init-target-${target.runtimeType}', decl);
      }
      final field = byName[target.name];
      if (field == null) _ice('init-field-${target.name}', decl);
      initializers.add(
        k.FieldInitializer(field, _expr(e.value))..fileOffset = s.offset,
      );
    }

    final ctor = k.Constructor(
      k.FunctionNode(
        k.EmptyStatement(),
        namedParameters: params,
        returnType: const k.VoidType(),
      ),
      name: k.Name(''),
      initializers: initializers,
      fileUri: fileUri,
    )..fileOffset = init.offset;
    cls.addConstructor(ctor);
    return ctor;
  }

  /// `enum` SEM payload → **`Class` com uma constante por variante** (§7.4-c).
  ///
  /// Cada variante vira um `static final` inicializado com o construtor privado
  /// da própria classe, então **cada uma é um objeto único** — e é isso que faz
  /// o `match` funcionar por igualdade de identidade (`Object::==`) sem precisar
  /// de tag, índice ou `IsExpression`.
  ///
  /// ⚠️ **Variante COM payload não chega aqui** — não porque a emissão não
  /// saiba, mas porque a **F5 não sabe CONSTRUIR uma**: `.circulo(raio: 2)` dá
  /// `cannot-infer` (o `_call` não resolve callee `EnumShorthand` com args).
  /// Sem construção não há valor a destruir, então o gabarito de classe selada +
  /// subclasse por variante (§7.4-e) espera essa fatia da F5. O ICE aqui nomeia
  /// a lacuna em vez de emitir uma classe que ninguém consegue instanciar.
  void _enum(ast.EnumDecl decl) {
    if (decl.generics.isNotEmpty) _ice('enum-generic', decl);
    if (decl.members.isNotEmpty) _ice('enum-methods', decl); // métodos: fatia própria

    // **DOIS gabaritos, por decisão da §7.4-c** — e a diferença não é
    // otimização: enum sem payload é um conjunto FECHADO de constantes, e
    // representá-lo como classe selada custaria uma alocação e um `is` por uso,
    // para modelar uma escolha que já é decidível por identidade.
    if (decl.cases.any((c) => c.payload.isNotEmpty)) {
      _enumSealed(decl);
      return;
    }

    final cls = k.Class(
      name: decl.name,
      fileUri: fileUri,
      supertype: objectClass.asThisSupertype,
    )..fileOffset = decl.offset;
    final selfType = k.InterfaceType(cls, k.Nullability.nonNullable);

    // Construtor sem args: só existe para dar identidade a cada constante.
    final ctor = k.Constructor(
      k.FunctionNode(k.EmptyStatement(), returnType: const k.VoidType()),
      name: k.Name(''),
      fileUri: fileUri,
    )..fileOffset = decl.offset;
    cls.addConstructor(ctor);

    final byName = <String, k.Field>{};
    for (final c in decl.cases) {
      final field = k.Field.immutable(
        _memberName(c.name),
        type: selfType,
        initializer: k.ConstructorInvocation(ctor, k.Arguments([])),
        isStatic: true,
        isFinal: true,
        fileUri: fileUri,
      )..fileOffset = decl.offset;
      cls.addField(field);
      byName[c.name] = field;
    }

    _classes[decl] = cls;
    _constructors[decl] = ctor;
    _fields[decl] = byName; // aqui os "campos" são as CONSTANTES das variantes
  }

  /// `struct` → `Class` com **todos os campos `final`** e um `Constructor`
  /// memberwise de params **named** (§7.4-c).
  ///
  /// **Todos final é RULING, não otimização** (§12-1, dono 2026-07-16): struct é
  /// imutável SEMPRE — campo `var` em struct já morre na F5
  /// (`mut-field-on-struct`). É o que torna a cópia-valor INOBSERVÁVEL: valor
  /// imutável não tem identidade a perder, então representar `struct` por
  /// referência no Kernel não quebra P2. Sem o ruling, a mesma emissão MATARIA o
  /// P2 em silêncio — o `.dill` faria sharing onde a linguagem promete cópia.
  ///
  /// O `Constructor` recebe `EmptyStatement` como corpo e faz o trabalho nos
  /// `initializers` (`FieldInitializer` por campo) — a forma que o Kernel exige
  /// para campo `final`, que não pode ser atribuído no corpo.
  ///
  /// **Sem `SuperInitializer` explícito**: o supertype é `Object`, cujo
  /// construtor não tem argumentos, e o Kernel o sintetiza. (Se um dia houver
  /// herança real — `class` com superclasse —, ele passa a ser obrigatório.)
  void _struct(ast.StructDecl decl) {
    if (decl.generics.isNotEmpty) _ice('struct-generic', decl); // ∀ é fatia própria

    final info = check.types.of(decl);
    if (info == null) _ice('struct-untyped', decl);
    final fieldInfos = info.fields;
    if (fieldInfos == null) _ice('struct-nofields', decl);
    // `init` do CORPO é a fatia do `init` explícito — hoje só o memberwise.
    if (info.initFromBody) _ice('struct-init-explicit', decl);

    final cls = k.Class(
      name: decl.name,
      fileUri: fileUri,
      supertype: objectClass.asThisSupertype,
      // **CONFORMANCE** (§7.4-d): o trait entra em `implementedTypes`, e é isso
      // que faz `Pato` JÁ SER um `Fala` no Kernel — a travessia existencial de
      // fonte local vira **zero nó** (CA11). Sem isto, passar um `Pato` para
      // `any Fala` exigiria box.
      implementedTypes: _traitSupertypes(decl.traits, decl),
    )..fileOffset = decl.offset;

    final byName = <String, k.Field>{};
    final params = <k.VariableDeclaration>[];
    final initializers = <k.Initializer>[];
    for (final f in fieldInfos) {
      // ⚠️ **Campo iniciado por `_` não tem imagem no memberwise.** No Itá o `_`
      // é só um nome (visibilidade é `pub`), mas no Dart um NAMED PARAMETER não
      // pode ser privado: o param sai manglado (`_x@21090877`) e nenhum
      // call-site o casa — a VM morre em runtime com `NoSuchMethodError`, DEPOIS
      // de o verifier aprovar o `.dill`. Fronteira honesta até haver mangling de
      // nome (o par campo-privado × param-público é decidível, mas é fatia
      // própria). Sem esta guarda, o erro cai no usuário como crash da VM.
      if (f.name.startsWith('_')) _ice('struct-private-field', decl);
      final field = k.Field.immutable(
        _memberName(f.name),
        type: _emitType(f.type, decl),
        fileUri: fileUri,
      )..fileOffset = f.decl.offset;
      cls.addField(field);
      byName[f.name] = field;

      // **CA2 — o default do campo vira `VariableDeclaration.initializer`, e
      // QUEM O MATERIALIZA É A VM** (§7.4-a, Grupo B). A F7 não duplica a
      // expressão por call-site: ela a emite UMA vez, no param, e o call-site
      // que salta simplesmente não manda o named.
      //
      // É o que fecha a decisão de named-params (§12-3): o slot da nº5
      // implementa *"ordem obrigatória, defaults saltáveis"* — `P(x: 1)` salta o
      // `y` —, e o posicional do Dart só corta do FIM. Com named, saltar é não
      // mandar; com posicional, a F7 teria de materializar o default aqui.
      //
      // O default NÃO pode referenciar `self` (o Kernel não tem `this` em
      // default) — a F6 já barra com `self-in-field-default`, então aqui a
      // expressão é sempre auto-contida.
      final defaultValue = f.decl.defaultValue;
      final param = k.VariableDeclaration(
        f.name,
        type: _emitType(f.type, decl),
        isRequired: defaultValue == null,
        initializer:
            defaultValue == null ? null : _constDefault(defaultValue, decl),
      )..fileOffset = f.decl.offset;
      params.add(param);
      initializers.add(k.FieldInitializer(field, k.VariableGet(param)));
    }

    final ctor = k.Constructor(
      k.FunctionNode(
        k.EmptyStatement(),
        namedParameters: params,
        // ⚠️ **`returnType` EXPLÍCITO.** O default do `FunctionNode` é
        // `DynamicType` — e um construtor com retorno `dynamic` viola o ADR-0013
        // sem mudar NADA no que o programa imprime. Foi exatamente assim que os
        // invariantes o pegaram, na primeira execução desta fatia. O oracle
        // (`ita/compiler/lib/codegen/codegen.dart:948`) também o omite: é o caso
        // literal de "portar a LIÇÃO, não o estilo" que a §11 manda.
        returnType: const k.VoidType(),
      ),
      name: k.Name(''), // construtor NÃO-nomeado: `P(...)`
      initializers: initializers,
      fileUri: fileUri,
    )..fileOffset = decl.offset;
    cls.addConstructor(ctor);

    _classes[decl] = cls;
    _constructors[decl] = ctor;
    _fields[decl] = byName;
    _addMethods(decl, cls, decl.members);
  }

  /// Os `trait` que uma decl conforma → `Supertype`, para `implementedTypes`.
  ///
  /// O trait tem de estar emitido (o passo 1 os faz ANTES de tudo). Um alvo que
  /// não seja `trait` é `class`-como-superclasse ou erro de fase anterior.
  List<k.Supertype> _traitSupertypes(List<ast.TypeNode> traits, ast.AstNode at) {
    final out = <k.Supertype>[];
    for (final t in traits) {
      final type = check.annotations[t];
      if (type is! NamedType) _ice('conformance-nonnamed', at);
      final cls = _classes[type.decl];
      if (cls == null) _ice('conformance-unemitted', at);
      if (!cls.isAbstract) _ice('conformance-nontrait', at);
      out.add(k.Supertype(cls, const []));
    }
    return out;
  }

  /// Métodos de instância de um `struct`/`class` → `Procedure` DENTRO da `Class`.
  ///
  /// ⚠️ **Todos dentro da `Class`, inclusive os de conformance** (§7.4-d): é o que
  /// faz o dispatch existencial funcionar por vtable (Grupo B) em vez de por
  /// tabela nossa. A nº3/`origin` diria quem contribuiu (inline × `impl` ×
  /// `extension`); hoje só inline chega aqui — `impl`/`extension` é o CA6.
  void _addMethods(ast.AstNode owner, k.Class cls, List<ast.Decl> members) {
    final byName = <String, k.Procedure>{};
    for (final m in members) {
      if (m is! ast.FnDecl) continue; // campos e `init` já foram
      final proc = _methodSignature(m, owner, isAbstract: false);
      cls.addProcedure(proc);
      byName[m.name] = proc;
      _methodBodies.add((m, proc));
    }
    _methods[owner] = byName;
  }

  /// A ASSINATURA de um `fn` top-level → `Procedure` **static** com corpo vazio.
  ///
  /// **Params baixam como `named` REQUIRED** — decisão da §7.4-a, confirmada pelo
  /// dono no §12-3. A razão é a regra do Itá, não preferência: o `_matchArgs`
  /// implementa *"ordem obrigatória, defaults saltáveis"* ⟹ `f(a, b=2, c)` aceita
  /// `f(a:1, c:3)`, saltando o param **do meio**; o posicional do Dart só corta do
  /// FIM (`requiredParameterCount`). Named é a única forma que preserva isso sem a
  /// F7 materializar defaults por call-site — com named, o default vive no
  /// `VariableDeclaration.initializer` e **a VM o materializa** (Grupo B).
  ///
  /// O nome do param no Kernel é o **label** (`p.label ?? p.name`): é por ele que
  /// o call-site chama, e é o que o matching named do Kernel casa. O corpo não se
  /// importa — referencia a `VariableDeclaration` por OBJETO (`VariableGet(decl)`),
  /// via [_kernelDecls], nunca por nome.
  k.Procedure _fnSignature(ast.FnDecl fn) {
    if (fn.generics.isNotEmpty) _ice('fn-generic', fn); // ∀ é fatia própria
    if (fn.asyncMarker != ast.AsyncMarker.sync) _ice('fn-async', fn); // §12-2

    final named = <k.VariableDeclaration>[];
    for (final p in fn.params) {
      final type = check.binderTypes[p];
      if (type == null) _ice('param-untyped', fn);
      // Default de param de `fn` é a MESMA peça do default de campo (§7.4-a,
      // ruling §12-3): `ConstantExpression` no `initializer`, e a VM
      // materializa. É o que permite `f(a: 1, c: 3)` saltar o `b` do MEIO —
      // o posicional do Dart só corta do fim.
      final def = p.defaultValue;
      final decl = k.VariableDeclaration(
        p.label ?? p.name,
        type: _emitType(type, fn),
        isRequired: def == null,
        initializer: def == null ? null : _constDefault(def, fn),
      )..fileOffset = p.offset;
      _kernelDecls[p] = decl; // o binder da F4 para um param É o próprio `Param`
      named.add(decl);
    }

    final returnType = fn.returnType == null
        ? const k.VoidType()
        : _emitType(check.annotations[fn.returnType!] ?? const VoidType(), fn);

    return k.Procedure(
      k.Name(fn.name),
      k.ProcedureKind.Method,
      k.FunctionNode(
        null, // corpo entra no passo 2
        namedParameters: named,
        returnType: returnType,
      ),
      isStatic: true,
      fileUri: fileUri,
    )..fileOffset = fn.offset;
  }

  /// O CORPO (passo 2). `=> expr` (RD-1: só a seta rende) vira `return expr` num
  /// `fn` que devolve valor, e mero `ExpressionStatement` num `Void` — onde um
  /// `return` de valor seria Kernel malformado.
  void _fnBody(ast.FnDecl fn, k.Procedure proc) {
    final isVoid = proc.function.returnType is k.VoidType;
    proc.function.body = switch (fn.body) {
      ast.BlockBody b => _block(b.b),
      ast.ExprBody e => k.Block([
          isVoid
              ? (k.ExpressionStatement(_expr(e.e))..fileOffset = e.e.offset)
              : (k.ReturnStatement(_expr(e.e))..fileOffset = e.e.offset),
        ])..fileOffset = fn.offset,
      null => _ice('abstract-fn', fn), // assinatura sem corpo (trait)
    };
    proc.function.body!.parent = proc.function;
  }

  k.Block _block(ast.Block b) =>
      k.Block([for (final s in b.stmts) _stmt(s)])..fileOffset = b.offset;

  k.Statement _stmt(ast.Stmt s) => switch (s) {
        ast.ExprStmt e =>
          k.ExpressionStatement(_expr(e.expr))..fileOffset = e.offset,
        ast.LetStmt l => _let(l),
        // `return` SEM valor num `fn` que devolve valor (e vice-versa) não chega
        // aqui: é a nº8 `flowFacts` da F6 (missing-return) que já reprovou.
        ast.ReturnStmt r => k.ReturnStatement(
            r.value == null ? null : _expr(r.value!),
          )..fileOffset = r.offset,
        ast.IfStmt f => _ifStmt(f),
        ast.WhileStmt w => _while(w),
        // `break`/`continue` sem label — o Kernel os quer com um `target`, e o
        // `ContinueSwitchStatement` é outra coisa. Ver [_loopControl].
        ast.BreakStmt b => _loopControl(b, isBreak: true),
        ast.ContinueStmt c => _loopControl(c, isBreak: false),
        _ => _ice('stmt-${s.runtimeType}', s),
      };

  /// `while` → `WhileStatement` (§7.4-e). Sem ele a linguagem **não tem
  /// iteração nenhuma** — o `for` é gated pela spec 012.
  ///
  /// ⚠️ **`break`/`continue` do Kernel exigem um ALVO.** Não existe `break`
  /// solto: `BreakStatement` recebe um `LabeledStatement`. E não existe
  /// `ContinueStatement` para laço — o `ContinueSwitchStatement` é outra coisa.
  /// O gabarito é o mesmo que a CFE usa:
  ///
  ///     L_break: while (c) { L_cont: { …corpo… } }
  ///       break    → BreakStatement(L_break)
  ///       continue → BreakStatement(L_cont)   // sai do CORPO, não do laço
  ///
  /// Os labels só são MATERIALIZADOS se o corpo os usar — um `while` sem
  /// `break`/`continue` sai como o nó puro, sem envelope. É o que evita dois nós
  /// por laço em todo programa que não precisa deles.
  k.Statement _while(ast.WhileStmt n) {
    final brk = k.LabeledStatement(null);
    final cont = k.LabeledStatement(null);
    _loops.add((brk: brk, cont: cont, usedBrk: false, usedCont: false));

    final body = _block(n.body);
    final frame = _loops.removeLast();

    // ⚠️ `LabeledStatement.body` é um CAMPO (`late Statement body`), não um
    // setter — atribuí-lo direto NÃO estabelece o `parent`. Só o construtor o
    // faz (`this.body = body..parent = this`). Fazer `label..body = x` deixa a
    // árvore com parent pendente, e o verify reprova com "Incorrect parent
    // pointer" — foi assim que este bug apareceu. Daí o `..parent =` explícito.
    k.Statement wrap(k.LabeledStatement label, k.Statement inner) {
      label.body = inner;
      inner.parent = label;
      return label..fileOffset = n.offset;
    }

    final inner = frame.usedCont ? wrap(cont, body) : body;
    final loop = k.WhileStatement(_expr(n.cond), inner)..fileOffset = n.offset;
    return frame.usedBrk ? wrap(brk, loop) : loop;
  }

  /// `break`/`continue` → `BreakStatement` para o label do laço mais interno.
  /// Ver [_while] para por que os dois viram `break` no Kernel.
  k.Statement _loopControl(ast.Stmt s, {required bool isBreak}) {
    if (_loops.isEmpty) {
      // Fora de laço — a F5/F6 deveria barrar; aqui é rede.
      _ice(isBreak ? 'break-outside-loop' : 'continue-outside-loop', s);
    }
    final i = _loops.length - 1;
    final f = _loops[i];
    _loops[i] = (
      brk: f.brk,
      cont: f.cont,
      usedBrk: f.usedBrk || isBreak,
      usedCont: f.usedCont || !isBreak,
    );
    return k.BreakStatement(isBreak ? f.brk : f.cont)..fileOffset = s.offset;
  }

  /// `if` STATEMENT → `IfStatement` (§7.4-e: *"nós diretos do Kernel"*).
  ///
  /// ⚠️ **Não confundir com o `if`-EXPR.** RD-1: só `=>` rende valor, então
  /// `if c => a else b` é a EXPRESSÃO (→ `ConditionalExpression`) e `if c { … }`
  /// é o STATEMENT (→ `IfStatement`, com blocos que não rendem). São nós
  /// diferentes do Kernel porque são construtos diferentes da linguagem — e o
  /// statement é a forma mais comum, que faltava.
  ///
  /// `else if` encadeia: o `ElseIf` carrega outro `IfStmt`, e a recursão o
  /// resolve como `otherwise` — a mesma forma que a cadeia teria escrita à mão.
  k.Statement _ifStmt(ast.IfStmt n) {
    final orElse = switch (n.orElse) {
      null => null,
      ast.ElseBlock e => _block(e.block),
      ast.ElseIf e => _stmt(e.ifStmt),
    };
    return k.IfStatement(_expr(n.cond), _block(n.then), orElse)
      ..fileOffset = n.offset;
  }

  /// `let`/`var` local COM valor e alvo `BindPattern` → uma `VariableDeclaration`
  /// no `Block` (o verifier a exige filha DIRETA de `Block`, `verifier.dart:1152`).
  ///
  ///   - `name`        = o `BindPattern.name`;
  ///   - `type`        = `_emitType` do tipo do binder (nº6) — non-nullable,
  ///                     ADR-0013; sem ela o Kernel poria `dynamic` (`type.dart`
  ///                     default do `VariableStatement`);
  ///   - `initializer` = emit do `value` (baixado ANTES de registrar o binder —
  ///                     um `let x = x` cairia em `ident-unbound`, não em silêncio);
  ///   - `isFinal`     = `!isVar` (`let`→final, `var`→mutável).
  ///
  /// ⚠️ **O `isFinal` de um LOCAL não interage com o passe `isFinal⟺setter` do
  /// sanitize:** aquele passe só reescreve `k.Field` (`sanitize.dart:83`), que tem
  /// `setterReference`; um `VariableStatement` local não é `Field` — o
  /// `OffsetNormalizer` NUNCA força `final` num `var` local. O `isFinal` que
  /// gravamos aqui é o que sai no `.dill`.
  ///
  /// ICE honesto para o resto (§7.8): `let` sem `value` (a forma `let x`), alvo
  /// não-`BindPattern` (destructuring/`_` — chave `(binder,fieldName)` é fatia
  /// futura), binder sem tipo (não devia, em programa verde).
  k.Statement _let(ast.LetStmt l) {
    final value = l.value;
    if (value == null) _ice('let-no-init', l); // `let x` / `var x: T`
    final target = l.target;
    if (target is! ast.BindPattern) {
      _ice('let-target-${target.runtimeType}', l); // destructuring / wildcard
    }
    final type = check.binderTypes[target];
    if (type == null) _ice('let-untyped', l); // binder sem tipo na nº6
    // `initializer` PRIMEIRO — antes de registrar o binder (auto-referência
    // vira ICE, não binding acidental).
    final init = _expr(value);
    final varDecl = k.VariableDeclaration(
      target.name,
      initializer: init,
      type: _emitType(type, l),
      isFinal: !l.isVar, // `let` → final; `var` → mutável (P1/P2)
    )..fileOffset = target.offset;
    _kernelDecls[target] = varDecl;
    return varDecl;
  }

  k.Expression _expr(ast.Expr e) => switch (e) {
        ast.Call c => _call(c),
        ast.Str s => _str(s),
        ast.IntLit i => k.IntLiteral(i.value)..fileOffset = i.offset,
        ast.FloatLit f => k.DoubleLiteral(f.value)..fileOffset = f.offset,
        ast.BoolLit b => k.BoolLiteral(b.value)..fileOffset = b.offset,
        // `nil` → `null` NATIVO. Não é `Option.none`: não existe classe para
        // construir (§7.4-c). A [nullity-invariant] segue intacta do outro lado
        // — `""`/`0`/`[]` continuam VALORES, e só `nil` é ausência.
        ast.NilLit n => k.NullLiteral()..fileOffset = n.offset,
        ast.Binary b => _binary(b),
        ast.IfExpr f => _ifExpr(f),
        ast.Ident id => _ident(id),
        ast.Assign a => _assign(a),
        ast.Member m => _member(m),
        ast.MatchExpr m => _matchExpr(m),
        ast.Unary u => _unary(u),
        ast.Panic p => _panic(p),
        ast.Try t => _try(t),
        // `self` → `this`. Só aparece dentro de método/`init`, e a F4 já o
        // resolveu (`SelfRes`) — chegar aqui fora de um deles seria bug de fase
        // anterior, não input ruim.
        ast.SelfExpr s => k.ThisExpression()..fileOffset = s.offset,
        // `.none` como VALOR (`EnumShorthand`) sob contexto opcional → `null`.
        // Aparece no desugar de `?.`, cujo braço-vazio rende `.none`, não `nil`.
        // Mesma emissão do `nil` porque é a mesma coisa: `Option` ≡ `T?`, e a
        // variante vazia é a ausência nativa (§7.4-c, custo zero).
        //
        // Fora de contexto opcional é variante de enum DO USUÁRIO — outra fatia.
        ast.EnumShorthand s
            when s.variant == 'none' && check.exprTypes[s] is OptionalType =>
          k.NullLiteral()..fileOffset = s.offset,
        // `.variante` de enum do usuário (sem payload) → a CONSTANTE estática.
        ast.EnumShorthand s => _variantConst(s),
        _ => _ice('expr-${e.runtimeType}', e),
      };

  /// Uso de nome LOCAL (`x` em `${x}` ou `x + 1`) → `VariableGet` da decl baixada
  /// pela 2ª side-table. O `interfaceTarget`/tipo estático saem do próprio
  /// `VariableDeclaration.type` (`VariableGet.getStaticTypeInternal`), Grupo B.
  ///
  /// Só `LocalRes` (F4) é CA aqui: `TopLevelRes` (chamar/ler `fn`/global como
  /// valor), `SelfRes` e `GroundRes` fora de callee ficam p/ depois → ICE.
  /// Binder resolvido mas sem decl no mapa = bug NOSSO (não `dynamic`) → ICE.
  k.Expression _ident(ast.Ident id) {
    final res = check.resolution[id];
    if (res is! LocalRes) _ice('ident-nonlocal', id); // TopLevel/Self/Ground
    final decl = _kernelDecls[res.binder];
    if (decl == null) _ice('ident-unbound', id); // binder verde sem decl baixada
    return k.VariableGet(decl)..fileOffset = id.offset;
  }

  /// Atribuição a uma variável LOCAL (`=`, `+=`, `-=`, `*=`, `/=`) → `VariableSet`.
  ///
  /// **É a outra metade do P1.** O `let`/`var` já baixava com o `isFinal` certo
  /// (§7.4-b), mas até aqui `var` compilava e **não mutava**: o glifo prometia
  /// mutação e a emissão não entregava.
  ///
  /// **A imutabilidade já foi cobrada pela F5** (`assign-to-immutable`, spec 014
  /// §1 — só binder `var` é slot legal), então não há re-checagem aqui. Se um
  /// `let` chegasse, seria bug de fase anterior — e o `isFinal=true` do próprio
  /// `VariableDeclaration` faria o verifier reprovar o `.dill`.
  ///
  /// **Composto** (`n += 1`) baixa como a forma expandida `n = n + 1`: o Kernel
  /// não tem nó de atribuição composta, e a F5 já validou os tipos pela MESMA
  /// tabela `_primitiveOps` (`check.dart:1629-1634` mapeia `AssignOp`→`BinaryOp`).
  /// O `/=` passa pelo [_arithOpFor] como qualquer `div` — a armadilha
  /// `~/`×`/` não pode ser fechada numa forma e reaberta na outra.
  ///
  /// ⚠️ O `VariableSet` do Kernel **rende o valor**; o `Assign` do Itá rende
  /// **`Void`** (spec 014 §12-2). Não há conflito: ele só aparece sob `ExprStmt`,
  /// e o `ExpressionStatement` descarta. Um `let y = (n = 2)` não chega aqui — a
  /// F5 o tiparia `Void` e o `let` seria erro.
  ///
  /// Alvo que não é `Ident` local (campo, índice) → ICE: `p.campo = 1` é a fatia
  /// de struct/class, `xs[i] = v` depende da 012.
  k.Expression _assign(ast.Assign a) {
    final target = a.target;
    // **`obj.campo = v` → `InstanceSet`** — a mutação de REFERÊNCIA (P2). Só
    // `class` chega aqui com campo mutável: em `struct` todo campo é `final`
    // (ruling §12-1) e a F5 já barrou com `assign-to-immutable`. O compound
    // (`c.n += 1`) reusa o mesmo caminho do local, lendo antes com `InstanceGet`.
    if (target is ast.Member) return _assignMember(a, target);
    if (target is! ast.Ident) _ice('assign-target-${target.runtimeType}', a);
    final res = check.resolution[target];
    if (res is! LocalRes) _ice('assign-nonlocal', a); // global/campo: fatia própria
    final decl = _kernelDecls[res.binder];
    if (decl == null) _ice('assign-unbound', a);

    final binop = switch (a.op) {
      ast.AssignOp.assign => null,
      ast.AssignOp.addAssign => ast.BinaryOp.add,
      ast.AssignOp.subAssign => ast.BinaryOp.sub,
      ast.AssignOp.mulAssign => ast.BinaryOp.mul,
      ast.AssignOp.divAssign => ast.BinaryOp.div,
    };

    final k.Expression value;
    if (binop == null) {
      value = _expr(a.value);
    } else {
      final op = _arithOpFor(binop, check.exprTypes[target]);
      value = k.InstanceInvocation(
        k.InstanceAccessKind.Instance,
        k.VariableGet(decl)..fileOffset = target.offset,
        op.name,
        k.Arguments([_expr(a.value)]),
        interfaceTarget: op,
        functionType: op.function.computeFunctionType(k.Nullability.nonNullable),
      )..fileOffset = a.offset;
    }
    return k.VariableSet(decl, value)..fileOffset = a.offset;
  }

  /// `obj.campo = v` (e `+=` e cia.) → `InstanceSet`.
  ///
  /// ⚠️ **Uma leitura NOVA por uso** no compound: `c.n += 1` lê e escreve o mesmo
  /// campo, e reusar o nó de leitura montaria árvore com dois pais — o bug que o
  /// `checkNoSharedNodes` passou a vigiar.
  k.Expression _assignMember(ast.Assign a, ast.Member target) {
    final resolved = check.resolvedMembers[target];
    if (resolved == null) _ice('assign-member-unresolved', a);
    final owner = resolved.ownerType;
    if (owner is! NamedType) _ice('assign-member-on-${owner.runtimeType}', a);
    final field = _fields[owner.decl]?[target.name];
    if (field == null) _ice('assign-member-${target.name}', a);

    k.Expression receiver() => _expr(target.receiver);

    final binop = switch (a.op) {
      ast.AssignOp.assign => null,
      ast.AssignOp.addAssign => ast.BinaryOp.add,
      ast.AssignOp.subAssign => ast.BinaryOp.sub,
      ast.AssignOp.mulAssign => ast.BinaryOp.mul,
      ast.AssignOp.divAssign => ast.BinaryOp.div,
    };

    final k.Expression value;
    if (binop == null) {
      value = _expr(a.value);
    } else {
      final op = _arithOpFor(binop, check.exprTypes[target]);
      value = k.InstanceInvocation(
        k.InstanceAccessKind.Instance,
        k.InstanceGet(
          k.InstanceAccessKind.Instance,
          receiver(),
          field.name,
          interfaceTarget: field,
          resultType: field.type,
        )..fileOffset = target.opOffset,
        op.name,
        k.Arguments([_expr(a.value)]),
        interfaceTarget: op,
        functionType: op.function.computeFunctionType(k.Nullability.nonNullable),
      )..fileOffset = a.offset;
    }

    return k.InstanceSet(
      k.InstanceAccessKind.Instance,
      receiver(),
      field.name,
      value,
      interfaceTarget: field,
    )..fileOffset = a.offset;
  }

  /// Tipo da F5 → `DartType` do Kernel, pela tabela [coreTypes] (os quatro do
  /// chão). [span] é o nó que porta o tipo (o `LetStmt`), para o ICE apontar. Todo
  /// tipo fora dos quatro → `ice-codegen-type-<Tipo>` (§7.8) — NUNCA `dynamic`.
  k.DartType _emitType(Type type, ast.AstNode span) {
    // **`Option<T>` ≡ `T?` → NULLABLE NATIVO do Kernel** (§7.4-c, spec 009 §8.4).
    // Não há classe `Option` no `.dill`: o opcional é a MESMA `DartType` do
    // interno com `Nullability.nullable`. É o CA10 — *custo zero* — e é o motivo
    // de o Itá poder ter `Option` sem pagar por ele: a Dart VM já tem nulidade
    // no sistema de tipos, e usá-la é herdar o Grupo B inteiro (unboxing,
    // null-check elidido pela TFA) em vez de reimplementá-lo.
    //
    // A idempotência (`T??` ≡ `T?`) vem de graça: o smart constructor `optional`
    // da F5 (`type.dart:211`) já a garante, então nunca chega um duplo aqui.
    if (type is OptionalType) {
      final inner = _emitType(type.inner, span);
      // `Void?` não tem imagem (e a F5 não o produz) — `withDeclaredNullability`
      // sobre `VoidType` devolveria algo sem sentido em vez de falhar.
      if (inner is k.VoidType) _ice('type-optional-void', span);
      return inner.withDeclaredNullability(k.Nullability.nullable);
    }
    // Tipo NOMINAL (`struct`/`class`) → `InterfaceType` da `Class` que o passo 1a
    // já registrou. Chega aqui antes da tabela porque `NamedType` carrega a decl,
    // não um valor — nenhuma chave fixa o alcançaria.
    // `Result<T,E>` → a classe de runtime (§7.4-c). Materializa sob demanda: uma
    // `fn` que DEVOLVE `Result` já precisa da classe, mesmo que o corpo ainda não
    // tenha construído nenhum.
    //
    // ⚠️ Os type-args são DESCARTADOS aqui — `ItaResult` é não-genérico e o
    // payload é `Object`. Não é preguiça: a emissão ainda não baixa type-params
    // (`fn-generic` é ICE), e usar `dynamic` para fingir genericidade violaria o
    // ADR-0013. `Object` perde precisão sem perder soundness, e o `as` do
    // destructuring devolve o tipo que a F5 provou. Quando ∀ nascer, `ItaResult`
    // ganha os dois type-params e este descarte sai.
    if (type is BuiltinType && type.kind == BuiltinKind.result) {
      return k.InterfaceType(_resultRuntime().base, k.Nullability.nonNullable);
    }
    if (type is NamedType) {
      if (type.args.isNotEmpty) _ice('type-generic', span); // ∀ é fatia própria
      final cls = _classes[type.decl];
      if (cls == null) _ice('type-unemitted-${type.kind.name}', span);
      return k.InterfaceType(cls, k.Nullability.nonNullable);
    }
    return coreTypes[type] ?? _ice('type-${type.runtimeType}', span);
  }

  /// Despacha o `Binary` pela FAMÍLIA do operador — cada família tem alvo Kernel
  /// distinto (spec 006 §5: o enum é TAG sintática, o nó é derivado por tipos):
  ///
  ///   - add/sub/mul/div/mod → `InstanceInvocation` de `num` (§7.4-a);
  ///   - lt/gt/le/ge         → `InstanceInvocation` de `num`, SÓ receptor numérico;
  ///   - eq/ne               → `EqualsCall` / `Not(EqualsCall)` (`==` é especial);
  ///   - and/or              → `LogicalExpression` (curto-circuito é do nó);
  ///   - pow/coalesce/pipe/compose → ICE (desugaring/call de fatia posterior).
  k.Expression _binary(ast.Binary b) {
    if (arithOps.containsKey(b.op)) return _numOp(b, _arithTarget(b));
    if (cmpOps.containsKey(b.op)) return _compare(b);
    if (b.op == ast.BinaryOp.eq || b.op == ast.BinaryOp.ne) return _equals(b);
    if (b.op == ast.BinaryOp.and || b.op == ast.BinaryOp.or) return _logical(b);
    return _ice('binary-${b.op.name}', b); // pow, ??, |>, >>
  }

  /// O `Procedure` de `num` para um aritmético. Todos são fixos por operador —
  /// **exceto `div`**, que despacha pelo TIPO: a tabela da F5 o admite como
  /// `(Int,Int)→Int` **e** `(Float,Float)→Float`, e os dois alvos do Kernel são
  /// diferentes (`~/` devolve `int`, `/` devolve `double`). Ver [_resolveFloatDiv].
  ///
  /// O tipo vem do operando ESQUERDO; a F5 já garantiu que os dois são idênticos
  /// (a tabela só tem linhas homogêneas). Tipo ausente ou fora de Int/Float não
  /// chega aqui — o par não casaria nenhuma linha e a F5 teria reprovado.
  k.Procedure _arithTarget(ast.Binary b) =>
      _arithOpFor(b.op, check.exprTypes[b.left]);

  /// A regra do `div` mora AQUI e em nenhum outro lugar — `n / 2` e `n /= 2`
  /// baixam pelo mesmo caminho, senão a armadilha do `~/`×`/` seria fechada numa
  /// forma e reaberta na outra.
  k.Procedure _arithOpFor(ast.BinaryOp op, Type? leftType) {
    if (op != ast.BinaryOp.div) return arithOps[op]!;
    return leftType is FloatType ? floatDiv : arithOps[ast.BinaryOp.div]!;
  }

  /// §7.4-a: operador de `dart:core::num` (aritmético OU comparação de ordem) →
  /// `InstanceInvocation`, com `interfaceTarget` + `functionType` resolvidos — o
  /// Kernel os exige (sem eles cairia em `DynamicInvocation`). O `name` sai do
  /// próprio `Procedure` (`+`/`~/`/`<`/…), então casa por construção com o
  /// `interfaceTarget`. `functionType` = `num Function(num)` (aritmético) ou
  /// `bool Function(num)` (comparação) — o `getStaticTypeInternal` do nó lê o
  /// `returnType` daí, logo o tipo estático fica correto sem esforço extra.
  k.Expression _numOp(ast.Binary b, k.Procedure op) => k.InstanceInvocation(
        k.InstanceAccessKind.Instance,
        _expr(b.left),
        op.name,
        k.Arguments([_expr(b.right)]),
        interfaceTarget: op,
        functionType: op.function.computeFunctionType(k.Nullability.nonNullable),
      )..fileOffset = b.offset;

  /// Comparação de ORDEM (`<`/`>`/`<=`/`>=`) → `InstanceInvocation` de `num`, mas
  /// **só se o receptor for numérico**. `String < String` passa a F5
  /// (`comparison-type-mismatch` só cobra tipos IGUAIS) mas NÃO existe no Kernel
  /// — emiti-lo faria a VM rejeitar. Receptor não-`Int`/`Float` → ICE honesto
  /// (`ice-codegen-cmp-on-<Tipo>`, §7.8), nunca um `<` inválido.
  k.Expression _compare(ast.Binary b) {
    final leftType = check.exprTypes[b.left];
    if (leftType is! IntType && leftType is! FloatType) {
      _ice('cmp-on-${leftType.runtimeType}', b);
    }
    return _numOp(b, cmpOps[b.op]!);
  }

  /// `==`/`!=` → `EqualsCall` (nó ESPECIAL do Kernel para `==` non-null,
  /// expressions.dart:2471) / `Not(EqualsCall)` — a própria doc do `Not`
  /// (`:3164`) diz que `!=` é desugarado assim. O `interfaceTarget` é o `==` de
  /// interface do tipo do RECEPTOR ([equalsOps]); `functionType` (`bool
  /// Function(Object)`) sai do mesmo `Procedure`, e o `getStaticTypeInternal` do
  /// nó lê seu `returnType` (`bool`).
  ///
  /// A F5 aceita `l == r` de qualquer par idêntico, mas só sabemos baixar os
  /// quatro escalares; receptor fora da [equalsOps] → ICE (`cmp-on-<Tipo>`).
  k.Expression _equals(ast.Binary b) {
    final leftType = check.exprTypes[b.left];
    // **`enum` SEM payload compara por IDENTIDADE** — cada variante é um
    // `static final` único, então `Object::==` é a semântica certa e completa.
    //
    // ⚠️ **`struct` NÃO entra aqui**, e a distinção é de PRINCÍPIO: struct é
    // VALOR (P2), logo `p1 == p2` tem de ser igualdade ESTRUTURAL (campo a
    // campo) — usar identidade faria duas cópias iguais compararem `false`, que
    // é exatamente a semântica de referência que o `struct` existe para negar.
    // O `==` estrutural sintetizado é fatia própria (§8.2 já o prevê); até lá,
    // ICE honesto em vez de uma resposta errada em silêncio.
    final op = leftType is NamedType && leftType.kind == TypeKind.enum_
        ? equalsOps[const BoolType()] // `Object::==`
        : equalsOps[leftType];
    if (op == null) _ice('cmp-on-${leftType.runtimeType}', b);
    final call = k.EqualsCall(
      _expr(b.left),
      _expr(b.right),
      functionType: op.function.computeFunctionType(k.Nullability.nonNullable),
      interfaceTarget: op,
    )..fileOffset = b.offset;
    return b.op == ast.BinaryOp.ne
        ? (k.Not(call)..fileOffset = b.offset)
        : call;
  }

  /// `&&`/`||` → `LogicalExpression` (expressions.dart:3231). O **curto-circuito
  /// é semântica do NÓ** (a VM o baixa para desvios no flowgraph) — não emitimos
  /// nada além da variante `AND`/`OR`; é Grupo B. Static type = `bool`
  /// (`getStaticTypeInternal`), garantido pela F5 (`not-bool` nos operandos).
  k.Expression _logical(ast.Binary b) {
    final logOp = b.op == ast.BinaryOp.and
        ? k.LogicalExpressionOperator.AND
        : k.LogicalExpressionOperator.OR;
    return k.LogicalExpression(_expr(b.left), logOp, _expr(b.right))
      ..fileOffset = b.offset;
  }

  /// `if SUBJECT => then else orElse` na **forma booleana** (`binding == null`,
  /// ast.dart:510) → `ConditionalExpression(cond, then, orElse, staticType)`
  /// (expressions.dart:3293). Ramos são EXPRESSÕES (RD-1, `=>`), `else`
  /// obrigatório → sempre há `otherwise`. O `staticType` (posicional obrigatório;
  /// o nó o devolve cru em `getStaticTypeInternal`) é o tipo do PRÓPRIO `IfExpr`
  /// = o join dos ramos que a F5 computou (`check.exprTypes[n]`), baixado por
  /// [_emitType] — non-nullable, ADR-0013; fora dos quatro do chão → ICE.
  ///
  /// **if-let** (`binding != null`) é desembrulho de PATTERN → ICE
  /// (`ice-codegen-if-let`), fatia do `match`. A F5 já o barra na síntese
  /// (`_ifExpr` → `_cannotInfer`), mas o guard aqui mantém a honestidade §7.8.
  k.Expression _ifExpr(ast.IfExpr n) {
    if (n.binding != null) _ice('if-let', n);
    final staticType = check.exprTypes[n];
    if (staticType == null) _ice('if-untyped', n); // defensivo: F5 é total (§7-4)
    return k.ConditionalExpression(
      _expr(n.subject),
      _expr(n.then),
      _expr(n.orElse),
      _emitType(staticType, n),
    )..fileOffset = n.offset;
  }

  /// Chamada → dispatch ESTÁTICO (`StaticInvocation`), nas duas formas que a F4
  /// distingue pelo callee:
  ///
  ///   - `GroundRes('print')` → o built-in do chão (§7.6), 1 posicional `String`;
  ///   - `TopLevelRes(FnDecl)` → `fn` do usuário, args **named** pelo slot da nº5.
  ///
  /// `TopLevelRes` para algo que não é `FnDecl` (construtor de struct/class) é
  /// fatia própria — ICE honesto, não um alvo chutado.
  k.Expression _call(ast.Call c) {
    final callee = c.callee;
    // `.variante(args)` — construção de variante de enum SELADO.
    if (callee is ast.EnumShorthand) return _variantCall(c, callee);
    // **`v.metodo(args)` — DISPATCH DE INSTÂNCIA** (§7.4-d). Quando o receptor é
    // `any Trait`, o `interfaceTarget` é o procedure ABSTRATO do trait e a VM
    // resolve por vtable (Grupo B) — é o CA4. Quando é um tipo concreto, aponta
    // o procedure da própria classe.
    if (callee is ast.Member) return _methodCall(c, callee);
    if (callee is! ast.Ident) _ice('call-nonident', c); // valor-função: §7.4-b
    final res = check.resolution[callee];
    // `opOffset` (o `(` da invocação) é o span do call — o stack trace aponta
    // p/ o seletor, não p/ o início do receptor (doutrina de span da AST).
    if (res is GroundRes) {
      if (res.name != 'print') _ice('ground-${res.name}', c);
      return k.StaticInvocation.byReference(printRef, _groundArgs(c))
        ..fileOffset = c.opOffset;
    }
    if (res is TopLevelRes) {
      final decl = res.decl;
      // **Nome de TIPO em posição de chamada é CONSTRUÇÃO** — `P(x: 1)` não é
      // uma função que devolve `P`, é o `init` memberwise (§7.4-c). A F5 já o
      // trata assim (`_constructorType`), e aqui vira `ConstructorInvocation`.
      if (decl is ast.StructDecl) {
        final ctor = _constructors[decl];
        if (ctor == null) _ice('call-unemitted-struct', c);
        return k.ConstructorInvocation(ctor, _initArgs(c, decl))
          ..fileOffset = c.opOffset;
      }
      // `class` — mesma forma, mas os "params" são os do `init` EXPLÍCITO, não
      // os campos: `class` nunca tem memberwise (ADR-0012 §A-1).
      if (decl is ast.ClassDecl) {
        final ctor = _constructors[decl];
        if (ctor == null) _ice('call-unemitted-class', c);
        return k.ConstructorInvocation(ctor, _classInitArgs(c, decl))
          ..fileOffset = c.opOffset;
      }
      if (decl is! ast.FnDecl) _ice('call-toplevel-${decl.runtimeType}', c);
      final target = _procedures[decl];
      // Assinatura não emitida = bug NOSSO no passo 1, não input ruim.
      if (target == null) _ice('call-unemitted-fn', c);
      return k.StaticInvocation(target, _userArgs(c, decl))
        ..fileOffset = c.opOffset;
    }
    _ice('call-${res.runtimeType}', c); // Local (valor-função) / Self (método)
  }

  /// `print` é 1 posicional `String` (§12-4) — o chão não tem labels.
  k.Arguments _groundArgs(ast.Call c) {
    final positional = <k.Expression>[];
    for (final a in c.args) {
      if (a.label != null) _ice('named-arg', a.value);
      positional.add(_expr(a.value));
    }
    return k.Arguments(positional);
  }

  /// Args de `fn` do usuário → **named**, montados pela **side-table nº5**.
  ///
  /// `slot[i]` é o índice do PARÂMETRO que o argumento `i` preenche — e isso não
  /// é recuperável aqui: `Arg.label` é nullable, e a regra "ordem obrigatória,
  /// defaults saltáveis" permite `f(a:1, c:3)` saltar o param do MEIO. Sem o slot,
  /// a F7 teria de re-rodar o `_matchArgs` da F5.
  ///
  /// O nome de cada `NamedExpression` é o do `VariableDeclaration` do param
  /// (= o label) — casar por nome é como o Kernel resolve named
  /// (`verifier.dart:1337-1354`), então derivá-lo do MESMO objeto que a
  /// assinatura usou é o que garante que os dois lados não divirjam.
  k.Arguments _userArgs(ast.Call c, ast.FnDecl decl) {
    final call = check.resolvedCalls[c];
    if (call == null) _ice('call-unresolved', c); // nº5 ausente em programa verde
    final slot = call.slot;
    if (slot.length != c.args.length) _ice('call-slot-arity', c);

    final named = <k.NamedExpression>[];
    for (var i = 0; i < c.args.length; i++) {
      final paramIndex = slot[i];
      if (paramIndex < 0 || paramIndex >= decl.params.length) {
        _ice('call-slot-range', c);
      }
      final paramDecl = _kernelDecls[decl.params[paramIndex]];
      if (paramDecl == null) _ice('call-param-unemitted', c);
      named.add(k.NamedExpression(paramDecl.name!, _expr(c.args[i].value))
        ..fileOffset = c.args[i].value.offset);
    }
    // Params SALTADOS (default) não entram — a VM materializa o default a partir
    // do `initializer`. Hoje `param-default` é ICE, então a lista é sempre total.
    return k.Arguments([], named: named);
  }

  /// Args do `init` memberwise → **named**, pelos NOMES DOS CAMPOS.
  ///
  /// Difere do [_userArgs] num ponto que importa: o `init` sintetizado não tem
  /// `Param` de AST — seus "params" são os campos (`TypeInfo.fields`, nº2), e é
  /// a ordem DELES que o `slot` da nº5 indexa. Por isso a resolução do nome vai
  /// à lista de campos, não a `decl.params`.
  k.Arguments _initArgs(ast.Call c, ast.StructDecl decl) {
    final call = check.resolvedCalls[c];
    if (call == null) _ice('init-unresolved', c);
    final fieldInfos = check.types.of(decl)?.fields;
    if (fieldInfos == null) _ice('init-nofields', c);
    final slot = call.slot;
    if (slot.length != c.args.length) _ice('init-slot-arity', c);

    final named = <k.NamedExpression>[];
    for (var i = 0; i < c.args.length; i++) {
      final fieldIndex = slot[i];
      if (fieldIndex < 0 || fieldIndex >= fieldInfos.length) {
        _ice('init-slot-range', c);
      }
      named.add(
        k.NamedExpression(fieldInfos[fieldIndex].name, _expr(c.args[i].value))
          ..fileOffset = c.args[i].value.offset,
      );
    }
    return k.Arguments([], named: named);
  }

  /// **`e?` — o `Try`, e o único gabarito com FLUXO NÃO-LOCAL** (§7.4-e, **CA8**).
  ///
  /// É o núcleo do *zero try/catch* (P7): o `?` marca no CARACTERE EXATO onde a
  /// propagação acontece. A ausência de marca significa que nada propaga — o
  /// oposto do try/catch, onde a ausência significa "isto pode lançar".
  ///
  /// A semântica é `match e { .ok($v) => $v, .err($e) => return .err($e) }`, e o
  /// `return` está DENTRO de uma expressão (`let x = f()?`). No Kernel isso pede
  /// **`BlockExpression`** — `Block` de statements + a `value` que ele rende:
  ///
  ///     BlockExpression(
  ///       Block([
  ///         var #try = <operando>;
  ///         if (#try is ItaResult$err) return ItaResult$err(#try.value);
  ///       ]),
  ///       (#try as ItaResult$ok).value as T,
  ///     )
  ///
  /// ⚠️ O `ReturnStatement` sai da FUNÇÃO envolvente, não do bloco — que é
  /// exatamente o early-return que o `?` promete. A F5 já garantiu o contrato
  /// (`try-outside-result-fn` exige `Result` no retorno da fn; `error-type-mismatch`
  /// exige `E` IDÊNTICO, sem `From`), então aqui não há o que re-checar.
  ///
  /// ⚠️ O `.err` é RECONSTRUÍDO, não repassado: `ItaResult$err(#try.value)`. O
  /// objeto de origem tem tipo `Result<T₁,E>` e o de destino `Result<T₂,E>` —
  /// mesmo `E`, `T` diferente. Como o payload é `Object` e só o `E` importa no
  /// caminho de erro, reconstruir é o que mantém o tipo do retorno honesto.
  k.Expression _try(ast.Try t) {
    final rt = _resultRuntime();
    final value = check.exprTypes[t];
    if (value == null) _ice('try-untyped', t);

    final tmp = k.VariableDeclaration(
      '#try',
      initializer: _expr(t.operand),
      type: k.InterfaceType(rt.base, k.Nullability.nonNullable),
      isFinal: true,
    )..fileOffset = t.offset;

    final errCls = rt.errCtor.enclosingClass;
    final okCls = rt.okCtor.enclosingClass;
    k.Expression payload(k.Class cls, k.Field field) => k.InstanceGet(
          k.InstanceAccessKind.Instance,
          k.AsExpression(
            k.VariableGet(tmp),
            k.InterfaceType(cls, k.Nullability.nonNullable),
          )..fileOffset = t.offset,
          field.name,
          interfaceTarget: field,
          resultType: field.type,
        )..fileOffset = t.offset;

    return k.BlockExpression(
      k.Block([
        tmp,
        k.IfStatement(
          k.IsExpression(
            k.VariableGet(tmp),
            k.InterfaceType(errCls, k.Nullability.nonNullable),
          )..fileOffset = t.offset,
          k.ReturnStatement(
            k.ConstructorInvocation(
              rt.errCtor,
              k.Arguments([payload(errCls, rt.errValue)]),
            )..fileOffset = t.offset,
          )..fileOffset = t.offset,
          null,
        )..fileOffset = t.offset,
      ])..fileOffset = t.offset,
      // O caminho feliz: o payload do `.ok`, estreitado para o `T` que a F5 provou.
      k.AsExpression(payload(okCls, rt.okValue), _emitType(value, t))
        ..fileOffset = t.offset,
    )..fileOffset = t.offset;
  }

  /// `panic(msg)` → `Throw` de um `ItaPanic` (§7.4-f, **CA9**).
  ///
  /// **Zero try/catch na linguagem (P7) ⟹ NADA o captura.** O isolate morre, o
  /// stderr recebe a mensagem, e o exit code é ≠ 0 — na VM/AOT vale **255**
  /// (`runtime/bin/error_exit.h::kErrorExitCode`), no JS/Node vale **1**. A
  /// paridade do ADR-0005 cobre só a PROPRIEDADE ("exit ≠ 0"); o VALOR diverge, e
  /// o CA9 o marca DIVERGE-DOCUMENTADO. Por isso o fixture assere `EXPECT-EXIT`
  /// no valor da VM e o runner só roda a VM — declarar isso é o que impede o
  /// número 255 de virar promessa dos três alvos.
  ///
  /// A classe é criada **sob demanda**: programa sem `panic` não carrega
  /// `ItaPanic` no `.dill`. Isso mantém o gate de custo zero honesto — o
  /// invariante `checkNoSyntheticClasses` conhece este nome e só o tolera aqui.
  k.Expression _panic(ast.Panic p) =>
      k.Throw(k.ConstructorInvocation(_panicCtor(), k.Arguments([_expr(p.operand)])))
        ..fileOffset = p.offset;

  /// O runtime de **`Result<T,E>`** (§7.4-c: *"`Result` → classe, payload nos
  /// dois lados"*), materializado sob demanda como `ItaResult` selado +
  /// `ItaResult$ok` / `ItaResult$err`.
  ///
  /// ⚠️ **Por que classe, e `Option` não.** `Option<T>` ≡ `T?` tem equivalente
  /// NATIVO no Kernel (nulidade), então custa zero. `Result` carrega payload nos
  /// DOIS lados — não há tipo nativo que represente "ou T ou E" sem perder um
  /// deles. Aqui a classe é o preço mínimo, não uma escolha de conveniência.
  ///
  /// Os campos são `dynamic`? **Não.** São `Object`: o `Result` do Itá é
  /// genérico e a emissão ainda não baixa type-params (`fn-generic` é ICE), mas
  /// `dynamic` violaria o ADR-0013 e o invariante o pegaria. `Object` é honesto
  /// — perde precisão, não soundness — e o `as` no destructuring devolve o tipo
  /// certo, que a F5 já provou.
  ({k.Class base, k.Constructor okCtor, k.Field okValue, k.Constructor errCtor, k.Field errValue})
      _resultRuntime() {
    final existing = _resultParts;
    if (existing != null) return existing;

    final objectType = k.InterfaceType(objectClass, k.Nullability.nonNullable);
    final base = k.Class(
      name: 'ItaResult',
      isAbstract: true,
      fileUri: fileUri,
      supertype: objectClass.asThisSupertype,
    );
    final baseCtor = k.Constructor(
      k.FunctionNode(k.EmptyStatement(), returnType: const k.VoidType()),
      name: k.Name(''),
      fileUri: fileUri,
    );
    base.addConstructor(baseCtor);

    ({k.Class cls, k.Constructor ctor, k.Field field}) side(String name) {
      final cls = k.Class(
        name: 'ItaResult\$$name',
        fileUri: fileUri,
        supertype: k.Supertype(base, const []),
      );
      final field = k.Field.immutable(
        k.Name('value'),
        type: objectType,
        fileUri: fileUri,
      );
      cls.addField(field);
      final param = k.VariableDeclaration('value', type: objectType);
      final ctor = k.Constructor(
        k.FunctionNode(
          k.EmptyStatement(),
          positionalParameters: [param],
          returnType: const k.VoidType(),
        ),
        name: k.Name(''),
        initializers: [
          k.FieldInitializer(field, k.VariableGet(param)),
          k.SuperInitializer(baseCtor, k.Arguments.empty()),
        ],
        fileUri: fileUri,
      );
      cls.addConstructor(ctor);
      return (cls: cls, ctor: ctor, field: field);
    }

    final ok = side('ok');
    final err = side('err');
    _resultClasses = [base, ok.cls, err.cls];
    return _resultParts = (
      base: base,
      okCtor: ok.ctor,
      okValue: ok.field,
      errCtor: err.ctor,
      errValue: err.field,
    );
  }

  /// Materializa (uma vez) a `class ItaPanic { final String message; … }` com um
  /// `toString()` que devolve `panic: <msg>` — é o `toString` que a VM chama ao
  /// imprimir a exceção não-capturada, e sem ele o stderr traria
  /// `Instance of 'ItaPanic'` em vez da mensagem que o dev escreveu.
  ///
  /// ⚠️ O `toString` é `StringConcatenation` de partes **já-String**, não um
  /// `DynamicInvocation('toString')` como o oracle faz (`codegen.dart:1168`):
  /// aquele nó é exatamente o que o ADR-0013 proíbe, e o invariante do runner o
  /// pegaria. Portar a LIÇÃO, não o estilo.
  k.Constructor _panicCtor() {
    final existing = _panicConstructor;
    if (existing != null) return existing;

    final stringType = _emitType(const StringType(), check.program);
    final cls = k.Class(
      name: 'ItaPanic',
      fileUri: fileUri,
      supertype: objectClass.asThisSupertype,
    );
    final field = k.Field.immutable(
      k.Name('message'),
      type: stringType,
      fileUri: fileUri,
    );
    cls.addField(field);

    final param = k.VariableDeclaration('message', type: stringType);
    final ctor = k.Constructor(
      k.FunctionNode(
        k.EmptyStatement(),
        positionalParameters: [param],
        returnType: const k.VoidType(),
      ),
      name: k.Name(''),
      initializers: [k.FieldInitializer(field, k.VariableGet(param))],
      fileUri: fileUri,
    );
    cls.addConstructor(ctor);

    cls.addProcedure(
      k.Procedure(
        k.Name('toString'),
        k.ProcedureKind.Method,
        k.FunctionNode(
          k.ReturnStatement(
            k.StringConcatenation([
              k.StringLiteral('panic: '),
              k.InstanceGet(
                k.InstanceAccessKind.Instance,
                k.ThisExpression(),
                k.Name('message'),
                interfaceTarget: field,
                resultType: stringType,
              ),
            ]),
          ),
          returnType: stringType,
        ),
        isStatic: false,
        fileUri: fileUri,
      ),
    );

    _panicClass = cls;
    return _panicConstructor = ctor;
  }

  /// Unário: `-x` e `!b`.
  ///
  /// ⚠️ **O `-` unário NÃO é o `-` binário.** No Kernel o nome do operador é
  /// `unary-` (`names.dart:55`), justamente para não colidir com a subtração —
  /// e é o ÚNICO aritmético que `int` sobrescreve em vez de herdar de `num`
  /// (`int.dart:311`). Resolvê-lo pela tabela dos binários daria o alvo errado.
  ///
  /// `!b` → `Not`, o mesmo nó que o `!=` usa por baixo.
  k.Expression _unary(ast.Unary u) {
    final operand = _expr(u.operand);
    switch (u.op) {
      case ast.UnaryOp.not:
        return k.Not(operand)..fileOffset = u.offset;
      case ast.UnaryOp.neg:
        final type = check.exprTypes[u.operand];
        if (type is! IntType && type is! FloatType) {
          _ice('neg-on-${type.runtimeType}', u);
        }
        final op = negOp;
        return k.InstanceInvocation(
          k.InstanceAccessKind.Instance,
          operand,
          op.name,
          k.Arguments([]),
          interfaceTarget: op,
          functionType:
              op.function.computeFunctionType(k.Nullability.nonNullable),
        )..fileOffset = u.offset;
    }
  }

  /// `match` sobre **`Option`/`T?`** → nós PRIMITIVOS (§7.4-e).
  ///
  /// ⚠️ **TRAVA DURA:** os pattern-nodes do Dart 3 (`IfCaseStatement`,
  /// `PatternSwitchStatement`, `PatternVariableDeclaration`) são **CFE-internos e
  /// PROIBIDOS** no `.dill` cru — a VM os trata na mesma cláusula do
  /// `ForInStatement` no `kernel_binary_flowgraph.cc` (*"removed by the constant
  /// evaluator"* → `UNREACHABLE()`). Logo o `match` baixa para
  /// `EqualsNull`/`Not`/`ConditionalExpression`/`Let`, e nada mais.
  ///
  /// **RD-1 decide a forma:** `MatchExpr` é EXPRESSÃO (todo braço é `=> expr`, e
  /// só a seta rende) ⟹ **right-fold de `ConditionalExpression`**. A forma-bloco
  /// (cadeia de `IfStatement` com o subject em block-var, não `Let` — regra
  /// dart2js do ADR-0005) é do `match`-statement, que não existe na AST.
  ///
  /// **O subject é avaliado UMA vez.** Ele entra num `Let` antes do fold: sem
  /// isso, `match f() { … }` chamaria `f()` uma vez por teste de braço — efeito
  /// colateral duplicado, e nenhum golden de valor puro perceberia.
  ///
  /// **O ÚLTIMO braço não ganha teste** — vira o `otherwise` do fold. É sound
  /// porque a **F6 já provou exaustividade** (Maranget, spec 014 §4); a §7.4-e é
  /// explícita: *"exaustividade e unreachable são F6 — a F7 confia"*. Sem essa
  /// garantia haveria de sobrar um `throw` de fim-de-cadeia.
  ///
  /// **Família `Option`/`T?`** (a desta fatia): `.none` → `EqualsNull(subject)`;
  /// `.some(x)` → `Not(EqualsNull(subject))` com `x` ligado ao subject. Custo
  /// zero — nenhuma classe `Option` participa (CA10).
  ///
  /// O bind precisa do **`as`**: `x: T` é non-nullable (ADR-0013) e o subject é
  /// `T?`. O Kernel cru **não tem flow-promotion** — o que o Dart faria por
  /// análise, aqui é um nó explícito.
  k.Expression _matchExpr(ast.MatchExpr n) {
    final subjectType = check.exprTypes[n.scrutinee];
    // Famílias com gabarito HOJE: `Option`/`T?` e ESCALAR (Int/Float/String/Bool,
    // incluindo `range` sobre Int). Enum-com-payload, produto (`struct`/record) e
    // `List` (gated pela 012) têm gabarito PRÓPRIO na §7.4-e — cada uma é fatia.
    final isOption = subjectType is OptionalType;
    final isEnum = subjectType is NamedType;
    final isResult =
        subjectType is BuiltinType && subjectType.kind == BuiltinKind.result;
    final isScalar = subjectType is IntType ||
        subjectType is FloatType ||
        subjectType is StringType ||
        subjectType is BoolType;
    if (!isOption && !isScalar && !isEnum && !isResult) {
      _ice('match-on-${subjectType.runtimeType}', n);
    }
    final staticType = check.exprTypes[n];
    if (staticType == null) _ice('match-untyped', n);
    if (n.arms.isEmpty) _ice('match-no-arms', n); // F6 não deixa passar

    // `subjectType` é non-null a partir daqui: os dois testes acima já o
    // exigiram, e o `_ice` é `Never` — mas a promoção não alcança por serem
    // booleanos intermediários, então o nome local a fixa.
    final scrutType = subjectType!;
    // Só a família `Option` desembrulha; escalar liga o subject inteiro.
    final innerType = isOption
        ? _emitType((scrutType as OptionalType).inner, n)
        : _emitType(scrutType, n);
    final subject = k.VariableDeclaration(
      '#subject',
      initializer: _expr(n.scrutinee),
      type: _emitType(scrutType, n),
      isFinal: true,
    )..fileOffset = n.scrutinee.offset;

    // Right-fold: o último braço é o `otherwise`, os demais viram testes.
    k.Expression result = _armBody(n.arms.last, subject, innerType, scrutType);
    for (var i = n.arms.length - 2; i >= 0; i--) {
      final arm = n.arms[i];
      result = k.ConditionalExpression(
        _armTest(arm, subject, scrutType),
        _armBody(arm, subject, innerType, scrutType),
        result,
        _emitType(staticType, n),
      )..fileOffset = arm.body.offset;
    }
    return k.Let(subject, result)..fileOffset = n.offset;
  }

  /// O TESTE de um braço, por FAMÍLIA de pattern (§7.4-e):
  ///
  ///   - `.none`/`.some(_)` (Option) ⟹ `subject == null` / `!= null`;
  ///   - **literal escalar** ⟹ `EqualsCall(subject, literal)` — o mesmo nó
  ///     ESPECIAL que o `==` binário usa, com `interfaceTarget` pelo tipo;
  ///   - **range** (Int) ⟹ `subject >= lo && subject <(=) hi`, dois
  ///     `InstanceInvocation` de `num` sob um `LogicalExpression`;
  ///   - `_`/binder puro ⟹ casa sempre.
  k.Expression _armTest(
    ast.MatchArm arm,
    k.VariableDeclaration subject,
    Type subjectType,
  ) {
    if (arm.guard != null) _ice('match-guard', arm.pattern); // fatia própria
    final pattern = arm.pattern;
    switch (pattern) {
      case ast.EnumPattern p:
        // `Result` → teste de CLASSE contra a subclasse de runtime.
        if (subjectType is BuiltinType &&
            subjectType.kind == BuiltinKind.result) {
          final rt = _resultRuntime();
          final cls = switch (p.variant) {
            'ok' => rt.okCtor.enclosingClass,
            'err' => rt.errCtor.enclosingClass,
            _ => _ice('result-pattern-${p.variant}', p),
          };
          return k.IsExpression(
            k.VariableGet(subject),
            k.InterfaceType(cls, k.Nullability.nonNullable),
          )..fileOffset = p.offset;
        }
        final isNull = k.EqualsNull(k.VariableGet(subject))
          ..fileOffset = p.offset;
        if (p.variant == 'none') return isNull;
        if (p.variant == 'some') {
          return k.Not(isNull)..fileOffset = p.offset;
        }
        // Variante de enum DO USUÁRIO **sem payload** → compara com a CONSTANTE
        // (identidade): cada variante é um objeto único, então `Object::==`
        // decide sem tag nem `IsExpression`. Com payload seria classe selada +
        // `IsExpression` — mas a F5 ainda não constrói uma (ver [_enum]).
        if (subjectType is NamedType) {
          // Enum SELADO → teste de CLASSE. `IsExpression` é o gabarito da
          // §7.4-e para sum type, e vale igual para variante com e sem payload
          // (o singleton existe por economia, não para o teste).
          final v = _variants[subjectType.decl]?[p.variant];
          if (v != null) {
            return k.IsExpression(
              k.VariableGet(subject),
              k.InterfaceType(v.cls, k.Nullability.nonNullable),
            )..fileOffset = p.offset;
          }
          if (p.subpatterns.isNotEmpty) _ice('match-payload-${p.variant}', p);
          final field = _fields[subjectType.decl]?[p.variant];
          if (field == null) _ice('match-unknown-variant-${p.variant}', p);
          final eq = equalsOps[const BoolType()]!; // `Object::==` — o de identidade
          return k.EqualsCall(
            k.VariableGet(subject),
            k.StaticGet(field),
            functionType:
                eq.function.computeFunctionType(k.Nullability.nonNullable),
            interfaceTarget: eq,
          )..fileOffset = p.offset;
        }
        _ice('match-variant-${p.variant}', p);

      case ast.LiteralPattern p:
        // O literal e o subject têm o MESMO tipo (a F5 cobra
        // `pattern-type-mismatch`), então o alvo do `==` sai do tipo do subject.
        final op = equalsOps[subjectType];
        if (op == null) _ice('match-eq-on-${subjectType.runtimeType}', p);
        return k.EqualsCall(
          k.VariableGet(subject),
          _expr(p.literal),
          functionType:
              op.function.computeFunctionType(k.Nullability.nonNullable),
          interfaceTarget: op,
        )..fileOffset = p.offset;

      case ast.RangePattern p:
        // A F5 já garantiu Int nos três (`_checkRangePattern`), e o parser já
        // garantiu que os endpoints são LITERAIS — não há expressão a avaliar
        // duas vezes aqui.
        if (subjectType is! IntType) _ice('match-range-on-${subjectType.runtimeType}', p);
        k.Expression cmp(ast.BinaryOp op, ast.Expr bound) {
          final proc = cmpOps[op]!;
          return k.InstanceInvocation(
            k.InstanceAccessKind.Instance,
            k.VariableGet(subject),
            proc.name,
            k.Arguments([_expr(bound)]),
            interfaceTarget: proc,
            functionType:
                proc.function.computeFunctionType(k.Nullability.nonNullable),
          )..fileOffset = p.offset;
        }

        // `1..10` é EXCLUSIVO no fim; `1..=10` inclui. O parser distingue pelo
        // token (`..` × `..=`), e trocar os dois aqui seria um off-by-one que
        // roda liso e erra na borda — exatamente o que o golden pega.
        return k.LogicalExpression(
          cmp(ast.BinaryOp.ge, p.start),
          k.LogicalExpressionOperator.AND,
          cmp(p.inclusive ? ast.BinaryOp.le : ast.BinaryOp.lt, p.end),
        )..fileOffset = p.offset;

      case ast.StructPattern p:
        // **PRODUTO** (§7.4-e): o subject JÁ é do tipo — não há variante a
        // testar, então o pattern não faz teste de CLASSE. Ele testa só os
        // campos que trazem um sub-pattern com teste (literal, range), e a
        // conjunção deles é o teste do braço. `Ponto { x: a, y: b }` (só binds)
        // casa SEMPRE ⟹ `true`, e a F6 é quem garante que isso não deixa braço
        // seguinte inalcançável.
        if (subjectType is! NamedType) {
          _ice('match-struct-on-${subjectType.runtimeType}', p);
        }
        final byName = _fields[subjectType.decl];
        if (byName == null) _ice('match-struct-unemitted', p);
        k.Expression? test;
        for (final f in p.fields) {
          final sub = f.pattern;
          if (sub == null) {
            // `Ponto { x }` — shorthand. A F4 o declara incapaz (débito D4), e
            // ele nem chega aqui em programa verde; o ICE é rede.
            _ice('match-struct-shorthand-${f.name}', p);
          }
          if (sub is ast.BindPattern || sub is ast.WildcardPattern) continue;
          final field = byName[f.name];
          if (field == null) _ice('match-struct-field-${f.name}', p);
          final one = _fieldTest(subject, field, sub);
          test = test == null
              ? one
              : (k.LogicalExpression(
                  test,
                  k.LogicalExpressionOperator.AND,
                  one,
                )..fileOffset = p.offset);
        }
        return test ?? k.BoolLiteral(true);

      // `_` e binder puro casam qualquer coisa — só chegam como último braço em
      // programa F6-verde (senão os seguintes seriam unreachable), mas o teste
      // honesto é `true`, não uma suposição.
      case ast.WildcardPattern _:
      case ast.BindPattern _:
        return k.BoolLiteral(true);

      default:
        _ice('match-pattern-${pattern.runtimeType}', pattern);
    }
  }

  /// Os campos emitidos do `struct` que um `StructPattern` nomeia.
  ///
  /// O pattern carrega o NOME do tipo (`Ponto { … }`), não a decl — e o
  /// `_armBody` não recebe o tipo do subject. Resolver por nome é seguro aqui
  /// porque a F5 já cobrou que o pattern casa com o tipo do escrutínio
  /// (`pattern-type-mismatch`): se chegou verde, o nome é o do subject.
  Map<String, k.Field>? _structFieldsFor(ast.StructPattern p) {
    for (final entry in _classes.entries) {
      final decl = entry.key;
      final name = switch (decl) {
        ast.StructDecl d => d.name,
        ast.EnumDecl d => d.name,
        _ => null,
      };
      if (name == p.typeName) return _fields[decl];
    }
    return null;
  }

  /// O teste de UM campo de `struct` em pattern: o valor do campo contra o
  /// sub-pattern. Reusa os mesmos gabaritos das famílias escalares — literal vira
  /// `EqualsCall`, range vira `>=` && `<(=)` — só que o receptor é
  /// `subject.campo` em vez do subject.
  k.Expression _fieldTest(
    k.VariableDeclaration subject,
    k.Field field,
    ast.Pattern sub,
  ) {
    // ⚠️ **Uma leitura NOVA por uso.** No Kernel cada nó tem UM pai; reusar a
    // mesma instância em dois lugares (o `>=` e o `<` de um range) monta uma
    // árvore com dois pais para o mesmo filho, e o `verifyComponent` reprova com
    // *"Incorrect parent pointer"*. Foi assim que este bug apareceu — o gate
    // CA12 o pegou antes de qualquer execução.
    k.Expression read() => k.InstanceGet(
          k.InstanceAccessKind.Instance,
          k.VariableGet(subject),
          field.name,
          interfaceTarget: field,
          resultType: field.type,
        )..fileOffset = sub.offset;

    switch (sub) {
      case ast.LiteralPattern p:
        // O alvo do `==` sai do tipo do CAMPO — não do subject, que é o struct.
        final op = _equalsForKernelType(field.type);
        if (op == null) _ice('match-field-eq-${field.name.text}', p);
        return k.EqualsCall(
          read(),
          _expr(p.literal),
          functionType:
              op.function.computeFunctionType(k.Nullability.nonNullable),
          interfaceTarget: op,
        )..fileOffset = p.offset;

      case ast.RangePattern p:
        k.Expression cmp(ast.BinaryOp op, ast.Expr bound) {
          final proc = cmpOps[op]!;
          return k.InstanceInvocation(
            k.InstanceAccessKind.Instance,
            read(),
            proc.name,
            k.Arguments([_expr(bound)]),
            interfaceTarget: proc,
            functionType:
                proc.function.computeFunctionType(k.Nullability.nonNullable),
          )..fileOffset = p.offset;
        }

        return k.LogicalExpression(
          cmp(ast.BinaryOp.ge, p.start),
          k.LogicalExpressionOperator.AND,
          cmp(p.inclusive ? ast.BinaryOp.le : ast.BinaryOp.lt, p.end),
        )..fileOffset = p.offset;

      default:
        // Pattern ANINHADO (`Ret { origem: Ponto { x: 0 } }`) é fatia própria:
        // exigiria compor testes sobre um receptor que já é um `InstanceGet`.
        _ice('match-field-${sub.runtimeType}', sub);
    }
  }

  /// O `operator ==` para um tipo já-Kernel (o do campo). Espelha a [equalsOps],
  /// que é keyed pelos `Type` da F5 — aqui só temos o `DartType`.
  k.Procedure? _equalsForKernelType(k.DartType type) {
    if (type is! k.InterfaceType) return null;
    return switch (type.classNode.name) {
      'int' || 'double' => equalsOps[const IntType()],
      'String' => equalsOps[const StringType()],
      'bool' => equalsOps[const BoolType()],
      _ => null,
    };
  }

  /// O CORPO de um braço, com o bind do payload quando houver.
  ///
  /// `.some(x)` liga `x` ao subject **desembrulhado** (`as T`); `.none` e `_`
  /// não ligam nada. Um `BindPattern` no topo (`match x { y => … }`) liga o
  /// subject inteiro, ainda opcional.
  k.Expression _armBody(
    ast.MatchArm arm,
    k.VariableDeclaration subject,
    k.DartType innerType,
    Type subjectType,
  ) {
    final pattern = arm.pattern;
    // **PRODUTO**: cada campo com bind vira `InstanceGet` direto do subject —
    // sem `as`, porque não houve estreitamento: o subject já É do tipo.
    if (pattern is ast.StructPattern) {
      final byName = _structFieldsFor(pattern);
      if (byName == null) _ice('match-struct-body-unemitted', pattern);
      // Declarar ANTES de emitir o corpo (a lição do enum-com-payload: emitir
      // primeiro deixa todo uso em `ident-unbound`).
      final binds = <k.VariableDeclaration>[];
      for (final f in pattern.fields) {
        final sub = f.pattern;
        if (sub is! ast.BindPattern) continue; // literal/range: só testam
        final field = byName[f.name];
        if (field == null) _ice('match-struct-bind-${f.name}', pattern);
        final bind = k.VariableDeclaration(
          sub.name,
          initializer: k.InstanceGet(
            k.InstanceAccessKind.Instance,
            k.VariableGet(subject),
            field.name,
            interfaceTarget: field,
            resultType: field.type,
          )..fileOffset = sub.offset,
          type: field.type,
          isFinal: true,
        )..fileOffset = sub.offset;
        _kernelDecls[sub] = bind;
        binds.add(bind);
      }
      k.Expression body = _expr(arm.body);
      for (var i = binds.length - 1; i >= 0; i--) {
        body = k.Let(binds[i], body)..fileOffset = binds[i].fileOffset;
      }
      return body;
    }
    // `Result`: `.ok(v)`/`.err(e)` ligam o payload lido da subclasse de runtime.
    if (pattern is ast.EnumPattern &&
        (pattern.variant == 'ok' || pattern.variant == 'err') &&
        _resultParts != null) {
      final rt = _resultParts!;
      final isOk = pattern.variant == 'ok';
      final field = isOk ? rt.okValue : rt.errValue;
      final cls = (isOk ? rt.okCtor : rt.errCtor).enclosingClass;
      if (pattern.subpatterns.length != 1) _ice('result-pattern-arity', pattern);
      final sub = pattern.subpatterns.single;
      if (sub is ast.WildcardPattern) return _expr(arm.body);
      if (sub is! ast.BindPattern) {
        _ice('result-payload-${sub.runtimeType}', sub);
      }
      // O tipo do binder vem da nº6 (a F5 o computou de `Result<T,E>`); o campo
      // é `Object`, então o `as` o estreita para o que a F5 provou.
      final bindType = check.binderTypes[sub];
      if (bindType == null) _ice('result-bind-untyped', sub);
      final bind = k.VariableDeclaration(
        sub.name,
        initializer: k.AsExpression(
          k.InstanceGet(
            k.InstanceAccessKind.Instance,
            k.AsExpression(
              k.VariableGet(subject),
              k.InterfaceType(cls, k.Nullability.nonNullable),
            )..fileOffset = sub.offset,
            field.name,
            interfaceTarget: field,
            resultType: field.type,
          )..fileOffset = sub.offset,
          _emitType(bindType, sub),
        )..fileOffset = sub.offset,
        type: _emitType(bindType, sub),
        isFinal: true,
      )..fileOffset = sub.offset;
      _kernelDecls[sub] = bind;
      return k.Let(bind, _expr(arm.body))..fileOffset = arm.body.offset;
    }
    // Enum SELADO com payload: `.circulo(r)` liga `r` ao campo, lido do subject
    // já ESTREITADO por `as`. O `as` é necessário porque o Kernel cru não tem
    // flow-promotion — o `is` do teste não estreita o tipo estático aqui.
    if (pattern is ast.EnumPattern && _sealedOf(pattern, subjectType) != null) {
      final v = _sealedOf(pattern, subjectType)!;
      final payload = v.fields.keys.toList();
      if (pattern.subpatterns.length > payload.length) {
        _ice('match-payload-arity-${pattern.variant}', pattern);
      }
      // ⚠️ **Os binds são DECLARADOS antes de o corpo ser emitido.** Emitir
      // primeiro (o que eu fiz na primeira versão) faz todo uso do binder cair
      // em `ice-codegen-ident-unbound`: o `_ident` consulta `_kernelDecls`, e o
      // registro ainda não existia. Mesma disciplina do `_let`, ao contrário —
      // lá o initializer vem antes DE PROPÓSITO (`let x = x` tem de falhar);
      // aqui o payload não pode se referenciar, então declarar primeiro é seguro.
      final binds = <k.VariableDeclaration>[];
      for (var i = 0; i < pattern.subpatterns.length; i++) {
        final sub = pattern.subpatterns[i];
        if (sub is ast.WildcardPattern) continue;
        if (sub is! ast.BindPattern) {
          _ice('match-payload-${sub.runtimeType}', sub); // aninhado: fatia própria
        }
        final field = v.fields[payload[i]]!;
        final bind = k.VariableDeclaration(
          sub.name,
          initializer: k.InstanceGet(
            k.InstanceAccessKind.Instance,
            // O `as` é necessário: o Kernel cru não tem flow-promotion, então o
            // `is` do teste não estreitou o tipo estático do subject.
            k.AsExpression(
              k.VariableGet(subject),
              k.InterfaceType(v.cls, k.Nullability.nonNullable),
            )..fileOffset = sub.offset,
            field.name,
            interfaceTarget: field,
            resultType: field.type,
          )..fileOffset = sub.offset,
          type: field.type,
          isFinal: true,
        )..fileOffset = sub.offset;
        _kernelDecls[sub] = bind;
        binds.add(bind);
      }
      k.Expression body = _expr(arm.body);
      // De trás para frente: cada bind embrulha o corpo num `Let`.
      for (var i = binds.length - 1; i >= 0; i--) {
        body = k.Let(binds[i], body)..fileOffset = binds[i].fileOffset;
      }
      return body;
    }
    if (pattern is ast.EnumPattern && pattern.variant == 'some') {
      if (pattern.subpatterns.length != 1) _ice('match-some-arity', pattern);
      final sub = pattern.subpatterns.single;
      if (sub is ast.WildcardPattern) return _expr(arm.body); // `.some(_)`
      if (sub is! ast.BindPattern) {
        _ice('match-some-${sub.runtimeType}', sub); // aninhado: fatia própria
      }
      final bind = k.VariableDeclaration(
        sub.name,
        // O `as` é o que o Kernel cru exige — não há flow-promotion aqui.
        initializer: k.AsExpression(k.VariableGet(subject), innerType)
          ..fileOffset = sub.offset,
        type: innerType,
        isFinal: true,
      )..fileOffset = sub.offset;
      _kernelDecls[sub] = bind;
      return k.Let(bind, _expr(arm.body))..fileOffset = arm.body.offset;
    }
    if (pattern is ast.BindPattern) {
      final bind = k.VariableDeclaration(
        pattern.name,
        initializer: k.VariableGet(subject),
        type: subject.type,
        isFinal: true,
      )..fileOffset = pattern.offset;
      _kernelDecls[pattern] = bind;
      return k.Let(bind, _expr(arm.body))..fileOffset = arm.body.offset;
    }
    return _expr(arm.body); // `.none`, `_`
  }

  /// `v.metodo(args)` → `InstanceInvocation` (§7.4-d, **CA4**).
  ///
  /// O `interfaceTarget` sai do TIPO ESTÁTICO do receptor, que é o que a nº3
  /// (`resolvedMembers.ownerType`) guarda:
  ///
  ///   - receptor `any Fala` ⟹ o procedure ABSTRATO do trait. A VM resolve por
  ///     **vtable** (Grupo B) — dois conformers distintos numa lista heterogênea
  ///     respondem cada um o seu, sem tabela nossa;
  ///   - receptor concreto (`Pato`) ⟹ o procedure da própria classe.
  ///
  /// A escolha entre os dois **não é nossa**: é o tipo estático que decide, e a
  /// F5 já o computou. Apontar sempre o concreto quebraria o existencial;
  /// apontar sempre o abstrato pagaria dispatch onde não precisa.
  k.Expression _methodCall(ast.Call c, ast.Member callee) {
    final resolved = check.resolvedMembers[callee];
    if (resolved == null) _ice('method-unresolved', c);
    final owner = resolved.ownerType;
    if (owner is! NamedType) _ice('method-on-${owner.runtimeType}', c);
    final proc =
        _methods[owner.decl]?[callee.name] ?? _traitMembers[owner.decl]?[callee.name];
    if (proc == null) _ice('method-unemitted-${callee.name}', c);

    final call = check.resolvedCalls[c];
    if (call == null) _ice('method-call-unresolved', c);
    final params = proc.function.namedParameters;
    final named = <k.NamedExpression>[];
    for (var i = 0; i < c.args.length; i++) {
      final pi = call.slot[i];
      if (pi < 0 || pi >= params.length) _ice('method-slot-range', c);
      named.add(k.NamedExpression(params[pi].name!, _expr(c.args[i].value))
        ..fileOffset = c.args[i].value.offset);
    }

    return k.InstanceInvocation(
      k.InstanceAccessKind.Instance,
      _expr(callee.receiver),
      proc.name,
      k.Arguments([], named: named),
      interfaceTarget: proc,
      functionType: proc.function.computeFunctionType(k.Nullability.nonNullable),
    )..fileOffset = callee.opOffset;
  }

  /// Args do `init` EXPLÍCITO de uma `class` → named, pelos params do `init`.
  ///
  /// Difere do [_initArgs] do `struct` num ponto que é o próprio ADR-0012 §A-1:
  /// lá os "params" são os CAMPOS (memberwise sintetizado); aqui são os params
  /// que o usuário escreveu no `init` — que podem não ter relação 1:1 com os
  /// campos. `Conta(inicial: 100)` inicializa `saldo` e `ativa`.
  k.Arguments _classInitArgs(ast.Call c, ast.ClassDecl decl) {
    final call = check.resolvedCalls[c];
    if (call == null) _ice('class-init-unresolved', c);
    final init = decl.members.whereType<ast.InitDecl>().firstOrNull;
    if (init == null) _ice('class-init-missing', c);
    final slot = call.slot;
    if (slot.length != c.args.length) _ice('class-init-slot-arity', c);

    final named = <k.NamedExpression>[];
    for (var i = 0; i < c.args.length; i++) {
      final pi = slot[i];
      if (pi < 0 || pi >= init.params.length) _ice('class-init-slot-range', c);
      final p = init.params[pi];
      named.add(k.NamedExpression(p.label ?? p.name, _expr(c.args[i].value))
        ..fileOffset = c.args[i].value.offset);
    }
    return k.Arguments([], named: named);
  }

  /// `p.x` → `InstanceGet` do getter do campo (§7.4-c).
  ///
  /// O `interfaceTarget` é o próprio `k.Field` — a nº3 (`resolvedMembers`) diz
  /// QUAL decl o membro é, e o `origin` diria quem o contribuiu (inline,
  /// `extension`, `impl`). Campo é sempre `ownDecl` por construção — `extension`
  /// não adiciona armazenamento —, então aqui basta a decl do receptor.
  ///
  /// Só campo de `struct`: método (`p.metodo()`), membro de built-in (`.length`,
  /// gated pela 012) e `class` são fatias próprias → ICE honesto.
  k.Expression _member(ast.Member m) {
    final resolved = check.resolvedMembers[m];
    if (resolved == null) _ice('member-unresolved', m);
    final owner = resolved.ownerType;
    if (owner is! NamedType) _ice('member-on-${owner.runtimeType}', m);
    final field = _fields[owner.decl]?[m.name];
    if (field == null) _ice('member-nonfield-${m.name}', m); // método/estático
    return k.InstanceGet(
      k.InstanceAccessKind.Instance,
      _expr(m.receiver),
      _memberName(m.name),
      interfaceTarget: field,
      resultType: _emitType(resolved.type, m),
    )..fileOffset = m.opOffset;
  }

  /// §7.4-a: `Str` COM interpolação → `StringConcatenation` (binary.md tag 36) —
  /// cada parte vira uma `Expression`: `StrLit` → `StringLiteral`; `StrInterp` →
  /// a `expr` emitida CRUA (o `Int` da interp entra como `IntLiteral`/
  /// `InstanceInvocation`).
  ///
  /// A conversão da parte não-`String` para `String` é **IMPLÍCITA na VM**, NÃO
  /// um `toString()` que emitimos: o próprio nó não a representa —
  /// `type_checker.dart:860-863` (`visitStringConcatenation`) só faz
  /// `forEach(visitExpression)` e devolve `String`, SEM `checkAssignable` dos
  /// elementos (contraste com `visitStaticSet`, `:853`); o `binary.md` §36 lista
  /// `List<Expression>` cru, sem tag de `toString` por elemento; e a VM baixa o
  /// nó para `StringBase._interpolate`/`_interpolateSingle`
  /// (`kernel_to_il.cc`, `FlowGraphBuilder::StringInterpolate`), que chama
  /// `toString()` em runtime. **Grupo B — não emitimos a conversão.**
  ///
  /// SEM interp o `Str` continua um `StringLiteral` puro (o `hello` não regride).
  k.Expression _str(ast.Str s) {
    final hasInterp = s.parts.any((p) => p is ast.StrInterp);
    if (!hasInterp) {
      final buf = StringBuffer();
      for (final part in s.parts) {
        if (part is ast.StrLit) buf.write(part.value);
      }
      return k.StringLiteral(buf.toString())..fileOffset = s.offset;
    }
    final parts = <k.Expression>[
      for (final part in s.parts)
        switch (part) {
          ast.StrLit l => k.StringLiteral(l.value)..fileOffset = s.offset,
          ast.StrInterp i => _expr(i.expr),
        },
    ];
    return k.StringConcatenation(parts)..fileOffset = s.offset;
  }
}
