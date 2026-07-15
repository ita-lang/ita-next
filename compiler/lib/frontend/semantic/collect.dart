// ===========================================================================
// collect.dart — Fatia A da Fase 5: Collect (spec 009 §5.4).
// ===========================================================================
//
// Materialização À MÃO da spec `009-semantic-types` §5.4-A (P11 / ADR-0010).
//
// O CORTE É DO LIVRO, não nosso: Dragon **6.3** popula a tabela a partir das
// DECLARAÇÕES (SDT das Figs 6.15/6.17/6.18 — `top.put(id.lexeme, T.type, …)`);
// **6.5** checa as EXPRESSÕES contra ela. Duas seções, dois passes.
//
// TWO-PASS É OBRIGATÓRIO, não estilo — 6.5.1: *"A síntese de tipo … exige que os
// nomes sejam declarados antes de serem usados"*. O módulo do Itá é **letrec**
// (ruling F4 §0.5-3), e os tipos são **mutuamente recursivos** (6.3.1, box
// *"Nomes de tipo e tipos recursivos"* + nota 3: o grafo tem ciclos). Daí:
//   A1 — planta as CABEÇAS (nome + kind + generics), corpo vazio;
//   A2 — preenche o CORPO (campos/variantes/supertipo/traits) resolvendo os
//        `TypeNode`, agora que toda cabeça existe;
//   A3 — boa-formação (`duplicate-field`, aridade de generic, ciclo de herança).
//
// ⚠️ Dragon **6.3.4/6.3.5 NÃO se aplicam** (largura, endereço relativo,
// alinhamento): é **Grupo B** — a Dart VM faz layout (ADR-0007). Metade do 6.3 é
// herdada; `offset += T.width` seria código sem consumidor.
// ===========================================================================

import 'package:ita_next_compiler/frontend/parser/ast.dart' as ast;
import 'package:ita_next_compiler/frontend/semantic/type.dart';
import 'package:ita_next_compiler/frontend/semantic/type_table.dart';

/// Roda a fatia A sobre a AST canônica (pós-desugar, pós-bind).
CollectResult collectTypes(ast.Program program) => runCollector(program).$2;

/// Como [collectTypes], mas devolve também o [Collector] — a fatia **B** precisa
/// dele para resolver as anotações que A2 não vê (as de `let`/`var`).
(Collector, CollectResult) runCollector(ast.Program program) {
  final c = Collector();
  c.run(program);
  // Ordem-FONTE, não ordem-de-descoberta: A2 percorre por decl e A3 roda depois,
  // então `duplicate-field` (A3) sairia atrás de um `redundant-optional` (A2) que
  // está mais abaixo no arquivo. Quem lê o erro lê o arquivo de cima p/ baixo.
  final errors = [...c.errors]..sort((a, b) => a.offset.compareTo(b.offset));
  return (c, CollectResult(program, c.types, errors, c.annotations));
}

class Collector {
  final TypeTable types = TypeTable();
  final List<CheckError> errors = [];
  final Map<ast.TypeNode, Type> annotations = Map.identity();

  /// Parâmetros genéricos em escopo: nome → a decl que os DECLAROU
  /// (`struct Box<T>` ⟹ `T` → o `StructDecl`). São da **fatia A**: sem eles, A2 não
  /// resolve as anotações da stdlib (`Option<T>` 33×, `List<T>` em tudo). O que a
  /// fatia **D** adiciona é a UNIFICAÇÃO de type-args em aplicação (Alg. 6.19).
  ///
  /// A decl-dona é necessária porque `GenericParam` **não é `AstNode`** (não tem
  /// span nem identidade própria — mesma limitação do `FieldPattern`, débito D4
  /// da F4): o par (dona, nome) é o que identifica um [TypeParamType].
  final List<Map<String, ast.AstNode>> _genericScopes = [];

  void run(ast.Program p) {
    final decls = p.body.whereType<ast.Decl>().toList();
    for (final d in decls) {
      _collectHead(d); // A1
    }
    for (final d in decls) {
      _collectBody(d); // A2
    }
    _checkWellFormed(); // A3
  }

  // --- A1: cabeças ---------------------------------------------------------

  void _collectHead(ast.Decl d) {
    final (name, kind, generics) = switch (d) {
      ast.StructDecl n => (n.name, TypeKind.struct_, _names(n.generics)),
      ast.ClassDecl n => (n.name, TypeKind.class_, _names(n.generics)),
      ast.EnumDecl n => (n.name, TypeKind.enum_, _names(n.generics)),
      ast.TraitDecl n => (n.name, TypeKind.trait_, _names(n.generics)),
      ast.ActorDecl n => (n.name, TypeKind.actor_, const <String>[]),
      _ => (null, TypeKind.struct_, const <String>[]),
    };
    if (name == null) return;
    // Redeclaração de tipo é `duplicate-declaration` da F4 (namespace unificado,
    // ruling F4 #1) — não repetimos o diagnóstico aqui.
    types.put(TypeInfo(d, name, kind, generics: generics));
  }

  List<String> _names(List<ast.GenericParam> gs) => [for (final g in gs) g.name];

  /// A **atribuição de papéis** — quem é superclasse e quem é trait.
  ///
  /// O parser separa por POSIÇÃO (`parser.dart:349`: o 1º type após `:` vai para
  /// `superclass`, **sempre**), que é o que ele pode fazer sem lookahead nem
  /// tabela de tipos. A spec 005 §42 já dizia que a validação é desta fase — *"a
  /// AST representa, não valida"* — mas a posição sozinha **mente**: em
  /// `class Pato : Voa` com `Voa` trait, o parser produz `superclass = Voa`, e o
  /// kind-check rejeitaria (`superclass-not-a-class`) um programa legítimo.
  /// Consequência: **`class` que conforma a trait sem ter superclasse era
  /// INEXPRIMÍVEL**.
  ///
  /// **Ruling do dono (2026-07-15): o papel vem do KIND, não da posição.** O 1º só
  /// é superclasse se for `class`; sendo trait, é trait, e a classe fica sem
  /// superclasse. É o que o Swift faz. A ordem-fonte é reconstruída sem perda
  /// (`[superclass, ...traits]`) porque o split do parser é puramente posicional —
  /// daí o ruling caber inteiro aqui, sem tocar a F2 nem os goldens dela.
  ///
  /// **Roda em A2, e o motivo é o SPAN:** o diagnóstico tem de cair no type
  /// ofensor, e [TypeInfo.traits] é lista MESCLADA (inline + o que `extension`/
  /// `impl` contribuem) ⟹ não é recasável 1:1 com a AST depois. Não há tensão com
  /// o ruling *"kind mora em A3"*: aquele era contra reportar no USO
  /// (`_isSubtype`, N vezes, longe da causa) — aqui é a DECL. E a A1 já fechou a
  /// tabela de kinds, então isto é ordem-independente (Ex. 5.10).
  ///
  /// **SEMPRE acumula — nunca substitui.** Conformance chega de duas fontes que
  /// coexistem por ruling (ADR-0012 #2: *"inline **e** `impl Trait for T` —
  /// declaração-de-intenção vs. retrofit externo"*).
  ///
  /// ⚠️ Aqui morava um bug meu: o `_collectBody` **atribuía** (`info.traits =
  /// […]`) e o `_contribute` **acumulava**. ⟹ `impl Voa for Ave` escrito ANTES de
  /// `struct Ave : Anda` tinha o trait **apagado** pelo assign — e a **ordem das
  /// declarações mudava o significado do programa**. É o que o **Ex. 5.10** proíbe
  /// (*"as entradas podem ser atualizadas em **qualquer ordem**"*).
  ///
  /// [inheritable] só é `true` para o corpo de uma `class`: superclasse vem da
  /// decl da própria classe e de **mais lugar nenhum** — sem isto,
  /// `extension Dog : Animal` **plantaria uma superclasse por retrofit**.
  void _conform(
    TypeInfo info,
    List<ast.TypeNode> conformances, {
    bool inheritable = false,
  }) {
    if (conformances.isEmpty) return;

    // **Trait é FOLHA** (ruling do dono, 2026-07-15): nenhuma aresta sai de um
    // trait. A gramática já não exprime `trait X : Y` (`traitDecl` não tem
    // cláusula `:`), mas `extension X : Y` e `impl Y for X` com X trait entravam
    // pela lateral — e a aresta FICAVA, sem ninguém a checar (o
    // `_checkTraitConformance` fazia `if (kind == trait_) return`, pulando). Ou o
    // recurso existe pela porta da frente, ou não existe: fechar a lateral é o que
    // deixa o grafo de traits com profundidade 1 ⟹ só `superclass` pode ciclar.
    if (info.kind == TypeKind.trait_) {
      for (final node in conformances) {
        _err('trait-supertype', node);
      }
      return;
    }

    // Estado LOCAL: `info.traits` pode já ter o que um `impl Voa for Ave` escrito
    // ANTES contribuiu, e ler dali faria a ordem das declarações mudar o
    // diagnóstico — o mesmo Ex. 5.10 que o assign já custou uma vez.
    Type? superclass;
    final traits = <Type>[];
    for (final node in conformances) {
      final t = _resolve(node);
      final ti = t is NamedType ? types.of(t.decl) : null;
      if (ti == null) continue; // `unknown-type` já reportado pelo `_resolve`
      if (ti.kind == TypeKind.trait_) {
        traits.add(t);
        continue;
      }
      // Não é trait ⟹ só resta ser a superclasse. E só `class` herda (P2:
      // subtipagem de valor é slicing ⟹ `struct` é final).
      if (!inheritable || ti.kind != TypeKind.class_) {
        _err(
          inheritable && superclass == null && traits.isEmpty
              ? 'superclass-not-a-class'
              : 'trait-expected',
          node,
        );
      } else if (superclass != null) {
        _err('multiple-superclasses', node);
      } else if (traits.isNotEmpty) {
        // **Superclasse primeiro ou em lugar nenhum** (ruling `ita-visionary`,
        // 2026-07-15 — corolário do ruling (b) do dono, não contradição dele:
        // (b) governa a DERIVAÇÃO, *o compilador não infere papel da posição*;
        // esta cerca governa a APRESENTAÇÃO, *a fonte não contradiz na posição o
        // papel que o kind deu*. As duas dizem o mesmo — kind e posição têm de
        // concordar — e esta só é enunciável PORQUE (b) é verdadeiro).
        //
        // **O teste é P4:** sem a cerca, `class Dog : Barker, Animal` convida a
        // leitura errada mais natural — toda linguagem da família `:` põe a
        // superclasse primeiro, e a nossa é emprestada do Swift, cuja regra é
        // literalmente esta (*"Superclass must appear first in the inheritance
        // clause"*). Forma que deixa a leitura natural errada e sem correção é
        // P4-negativa.
        //
        // ⚠️ O ganho **não** é "saber se `D` herda": para isso o leitor ainda
        // precisa do kind de `A`. O ganho honesto é que `B` e `C` **certamente
        // não** são a superclasse ⟹ **a busca cai de N arquivos para 1**. É a
        // forma do `override`: **aponta, não responde** — e é por ser ponteiro
        // local que é itaiano.
        _err('class-after-trait', node);
      } else {
        superclass = t;
      }
    }
    if (superclass != null) info.superclass = superclass;
    if (traits.isNotEmpty) info.traits = [...info.traits, ...traits];
  }

  // --- A2: corpos ----------------------------------------------------------

  void _collectBody(ast.Decl d) {
    // `extension`/`impl` **não têm TypeInfo próprio** — não são tipos, e a A1 não
    // lhes plantou cabeça. Eles **CONTRIBUEM** para a tabela do ALVO (§3.1).
    if (d is ast.ExtensionDecl) {
      _contribute(d, d.target, d.traits);
      return;
    }
    if (d is ast.ImplDecl) {
      // `impl Trait for T` ⟹ o trait; `impl T` ⟹ só métodos.
      _contribute(d, d.target, d.trait == null ? const [] : [d.trait!]);
      return;
    }

    final info = types.of(d);
    if (info == null) return;
    _genericScopes.add({for (final g in info.generics) g: d});

    switch (d) {
      case ast.StructDecl n:
        // `struct` não herda (P2) ⟹ tudo após `:` é trait.
        _conform(info, n.traits);
        info.fields = _fields(n.members);
        _methods(info, n.members, d);
        _initOf(info, n.members, d);
      case ast.ClassDecl n:
        // Ordem-fonte reconstruída: o split do parser é posicional, logo
        // reversível — é o `_conform` que atribui os papéis, pelo KIND.
        _conform(info, [
          if (n.superclass != null) n.superclass!,
          ...n.traits,
        ], inheritable: true);
        info.fields = _fields(n.members);
        _methods(info, n.members, d);
        _initOf(info, n.members, d);
      case ast.EnumDecl n:
        info.variants = [
          for (final c in n.cases)
            VariantInfo(c.name, [for (final p in c.payload) _param(p)]),
        ];
        _methods(info, n.members, d);
      case ast.TraitDecl n:
        info.fields = _fields(n.members);
        _methods(info, n.members, d);
      case ast.ActorDecl n:
        info.fields = _fields(n.members);
        _methods(info, n.members, d);
      default:
        break;
    }
    _genericScopes.removeLast();
  }

  /// `extension Alvo { … }` / `impl Trait for Alvo { … }` — spec 011 §3.1/§3.3.
  ///
  /// **A regra do alvo (§3.3): posição de ALVO = NOME NU.** É sítio de
  /// **binder**, não há o que aplicar — o `<T>` de `extension List<T>` seria
  /// *referência* a um tipo `T` inexistente, e **representar-como-outra-coisa
  /// fere P4 tanto quanto engolir**. Demais posições (o trait, os tipos no
  /// corpo) são normais, com o `T` do alvo em escopo ⟹
  /// `impl Comparable<T> for Stack` é **legal** (o trait é *use site*).
  ///
  /// **`extension` é o corpo do tipo, escrito noutro lugar — vê o que o corpo
  /// vê** (ruling de identidade). O binder é `struct Stack<T>`, e o leitor pode
  /// lê-lo: **não há binder escondido**, então passa em P4. Por isso a dona do
  /// [TypeParamType] é a decl do **ALVO** — o `T` aqui é o MESMO `T` de lá.
  void _contribute(ast.Decl d, ast.TypeNode target, List<ast.TypeNode> traits) {
    if (target is! ast.NamedType) {
      _err('extension-target-invalid', target);
      return;
    }
    if (target.args.isNotEmpty) {
      _err('target-has-type-args', target);
      return;
    }
    final targetDecl = types.declNamed(target.name);
    if (targetDecl == null) {
      // **Built-in não é "desconhecido" — é INALCANÇÁVEL** (ruling §12-2 + a
      // leitura do `ita-visionary`: *"`extension List` não é ilegal — é
      // inalcançável. O que falta não é mecanismo; é a **declaração** de
      // `List`"*). Isso é o Norte do Art. II chegando ⟹ **M5**.
      //
      // `unknown-type: Int` **MENTIRIA**: `Int` existe. É a mesma taxonomia do
      // `builtin-member-unsupported` — o código diz *"lacuna do COMPILADOR"*,
      // não *"erro do usuário"*. Ainda é erro (ADR-0013 satisfeito).
      //
      // Nota: `extension Int: Ord { }` é o **CA5 da spec 005** — mas aquela é
      // uma CA de **parser** (*"⟶ `ExtensionDecl.target = Int`, `traits =
      // [Ord]`"*), e ela continua passando. O que a F5 não faz é *aceitar*.
      _err(
        _isBuiltinName(target.name)
            ? 'extension-on-builtin-unsupported'
            : 'unknown-type',
        target,
      );
      return;
    }
    final info = types.of(targetDecl)!;

    // **Side-table nº4** (§7). O `_contribute` NÃO passa pelo `_resolve` — precisa
    // da decl antes de ter o tipo, então resolve o alvo **por string**
    // (`declNamed`) —, e por isso o `TypeNode` do alvo ficava fora de
    // `annotations`. A F7 teria de refazer esta resolução por NOME, que é
    // exatamente o que a tabela existe para não acontecer.
    annotations[target] = NamedType(targetDecl, info.kind);

    // Os generics do ALVO em escopo, com o ALVO como dono.
    _genericScopes.add({for (final g in info.generics) g: targetDecl});
    // Conformance: é AQUI que `impl Trait for T` passa a produzir `T ≤ Trait`.
    // Antes, `ImplDecl` não era lido por ninguém na F5, e o retrofit externo era
    // **no-op silencioso** — deixando INERTE a regra da própria 009 §4 e
    // meio-cumprido o ADR-0012 #2 (*"as duas formas coexistem"*).
    //
    // **`inheritable: false`**: retrofit conforma a trait, nunca planta
    // superclasse. E o kind passa a ser checado — antes, `extension Dog : Alguma`
    // com `Alguma` não-trait entrava na lista e o `_checkTraitConformance` a
    // **pulava em silêncio** (`if (ti.kind != trait_) continue`), declarando
    // `Dog ≤ Alguma` sem conferir nada.
    _conform(info, traits);
    final members =
        d is ast.ExtensionDecl ? d.members : (d as ast.ImplDecl).members;
    _methods(info, members, d);
    // **`init` em `extension` PRESERVA o memberwise** (diretriz Swift do dono).
    // Só entra se o tipo ainda não tem `init` — o do CORPO tem precedência,
    // porque é ele que diz "faço trabalho especial". Registrado como
    // `extensionInits` para o `duplicate-member` não o confundir com método.
    for (final m in members.whereType<ast.InitDecl>()) {
      final sig = FunctionType(
        [for (final p in m.params) _paramType(p)],
        _selfTypeOf(info, info.decl as ast.Decl),
        quantifiers: _ownerQuantifiers(info), // `init` ⟹ ∀ da CLASSE
      );
      info.extensionInits.add(sig);
    }
    _genericScopes.removeLast();
  }

  List<FieldInfo> _fields(List<ast.Decl> members) => [
    for (final m in members)
      if (m is ast.FieldDecl)
        FieldInfo(m.name, _resolve(m.type), m.isMutable, m),
  ];

  /// Os nomes que a linguagem conhece sem ninguém declarar — básicos + os
  /// builtins genéricos (`collect.dart` os reconhece em `_resolveInner`).
  /// **Fechada**, como manda a condição 1 do débito forma-M5.
  static const _builtinNames = {
    'Int', 'Float', 'Bool', 'String', 'Void', 'Never', // básicos
    'List', 'Map', 'Option', 'Result', // genéricos sem nó-decl
  };

  bool _isBuiltinName(String n) => _builtinNames.contains(n);

  /// Coleta as **assinaturas** dos métodos (não os corpos — 6.5.1: *"exige que
  /// os nomes sejam declarados antes de serem usados"*; os corpos são do
  /// checker, depois de A2/A3).
  ///
  /// [origin] é quem contribuiu — o tipo, ou o `extension`/`impl`.
  void _methods(TypeInfo info, List<ast.Decl> members, ast.AstNode origin) {
    final fromExtension = origin is ast.ExtensionDecl || origin is ast.ImplDecl;
    for (final m in members) {
      // ⚠️ Aqui havia um `if (m is! FnDecl) continue` — **catch-all disfarçado
      // de guarda**: campo e `init` dentro de `extension` sumiam em SILÊNCIO
      // (`extension S { let extra: Naoexiste }` não errava).
      if (m is! ast.FnDecl) {
        if (!fromExtension) continue; // no corpo do TIPO, campo é do `_fields`
        switch (m) {
          // **Ruling §12-B3 PENDENTE** (spec 011): a gramática aceita
          // `extension Foo { let length: Int }` e o parser dá `(field …)`. Mas
          // **campo é armazenamento**, e `extension` não adiciona armazenamento
          // (Swift proíbe *stored properties* em extension). É campo ou **getter
          // computado**? Enquanto o dono não decide, **recusar** — aceitar em
          // silêncio um glifo cujo significado não está decidido é P4.
          case ast.FieldDecl():
            _err('extension-field-unsupported', m);
          // ✅ **`init` em `extension` é LEGAL** — e é o escape canônico.
          //
          // Eu o havia banido (`extension-init-unsupported`). **Errado**, e quem
          // corrigiu foi a diretriz do dono (2026-07-15): *"se tiver divergência
          // ou indecisão, a maneira que o Swift trabalha é a diretriz"*.
          //
          // No Swift, `init` no CORPO mata o memberwise; `init` numa EXTENSION o
          // **preserva** — é o workaround canônico. Sem ele, quem precisa de um
          // 2º construtor **perde o memberwise inteiro** e não tem saída senão
          // escrevê-lo à mão. A extension é o glifo que diz *"estou ADICIONANDO,
          // não substituindo"*. (Ver `_initOf`.)
          case ast.InitDecl():
            break; // coletado abaixo, junto com os métodos
          default:
            break; // demais decls não são admitidas em `typeBody` (gramática)
        }
        continue;
      }
      // Os `<U>` do MÉTODO em escopo, por cima dos do alvo.
      //
      // O prefixo ∀ é **só o do método** — os generics do TIPO dono ficam de
      // fora de propósito: para quem chama `x.m()`, eles já foram fixados pelo
      // receptor (`_substOf(info, recv.args)`, no `_lookup`). O que sobrar livre
      // aqui é **rígido**, e instanciá-lo seria o buraco do `_freeParams`.
      final sig = _withMethodGenerics(m, () => FunctionType(
        [for (final p in m.params) _paramType(p)],
        m.returnType == null ? const VoidType() : _resolve(m.returnType!),
        isAsync: m.asyncMarker != ast.AsyncMarker.sync,
        quantifiers: [for (final g in m.generics) TypeParamType(m, g.name)],
      ));
      info.methods.add(MethodInfo(m.name, sig, m.isStatic, m, origin));
    }
  }

  T _withMethodGenerics<T>(ast.FnDecl m, T Function() f) {
    if (m.generics.isEmpty) return f();
    _genericScopes.add({for (final g in m.generics) g.name: m});
    final r = f();
    _genericScopes.removeLast();
    return r;
  }

  Type _param(ast.Param p) => p.type == null ? const ErrorType() : _resolve(p.type!);

  /// O `init` do tipo — **memberwise sintetizado** (`struct`) ou **explícito**.
  /// Ruling do dono, spec 005 §10; item 4 da 011.
  ///
  /// ## Onde o livro funda isto
  ///
  /// **6.3.5, não-terminais MARCADORES** (`M → ε {ação}`): um não-terminal que
  /// **não corresponde a texto do fonte** e existe só para executar ação
  /// semântica. É exatamente o memberwise — ninguém o escreve; a tabela o ganha.
  /// E 2.7.2: *"o papel de uma tabela de símbolos é passar informações de
  /// **declarações** para **usos**"* — a entrada é legítima mesmo sem texto.
  ///
  /// ⚠️ **Derivamos a ASSINATURA aqui; NÃO criamos um `InitDecl` fantasma.**
  /// Sintetizar nó de AST seria trabalho de F3 e **feriria P4**: o
  /// `itac parse --dump` mostraria uma decl que o usuário não escreveu.
  ///
  /// ## As regras (rulings do dono, 2026-07-15)
  ///
  /// - **`struct` sem `init`** ⟹ memberwise: **todos** os campos, **na ordem de
  ///   declaração**; campo com default ⟹ param **omissível**.
  /// - **`struct` COM `init`** ⟹ o explícito **SUBSTITUI** o memberwise. É o
  ///   Swift: *"o compilador só gera o memberwise se a declaração do tipo não
  ///   define um init próprio"*, porque *"é possível que você esteja fazendo
  ///   trabalho especial que o default desconhece"*. Duas portas para o mesmo
  ///   tipo, uma bypassando a validação da outra, é o furo que fez o dono
  ///   recusar copy-with em `class`.
  /// - **`init` em `extension`** ⟹ **preserva** o memberwise. Também Swift, e é
  ///   o escape canônico: a extension diz *"estou ADICIONANDO, não substituindo"*.
  ///   Sem ela, quem precisa de um 2º construtor perde o memberwise inteiro.
  /// - **`class` sem `init`** ⟹ **não ganha** memberwise, e o erro é no **USO**
  ///   (`no-init`), não na decl — classe base tem campos e nunca é construída.
  ///   Dar-lhe memberwise apagaria o contraste que o ADR-0012 #1 criou.
  /// - **`init` NÃO se herda.**
  void _initOf(TypeInfo info, List<ast.Decl> members, ast.Decl d) {
    final explicit = members.whereType<ast.InitDecl>().firstOrNull;
    if (explicit != null) {
      info.init = FunctionType(
        [for (final p in explicit.params) _paramType(p)],
        _selfTypeOf(info, d),
        quantifiers: _ownerQuantifiers(info),
      );
      info.initFromBody = true; // ⟹ matou o memberwise (diretriz Swift)
      return;
    }
    // `class` sem `init` explícito: fica **sem** construtor (ruling do dono).
    if (d is ast.ClassDecl) return;
    if (d is! ast.StructDecl) return;

    info.init = FunctionType(
      [
        for (final f in info.fields ?? const <FieldInfo>[])
          ParamType(
            f.type,
            label: f.name,
            // Campo com default ⟹ param omissível. O default está ESCRITO na
            // decl e o leitor o vê — o oposto de mágica (P4).
            hasDefault: f.decl.defaultValue != null,
          ),
      ],
      _selfTypeOf(info, d),
      quantifiers: _ownerQuantifiers(info),
    );
  }

  /// O tipo que o `init` **rende**: `Stack` ⟹ `Stack<T>` com os generics dele.
  Type _selfTypeOf(TypeInfo info, ast.Decl d) => NamedType(d, info.kind, [
    for (final g in info.generics) TypeParamType(d, g),
  ]);

  /// O prefixo ∀ de um `init` — **os generics da CLASSE**, não os de um método.
  ///
  /// É o 3º caso da regra do prefixo, e o Kernel confirma o corte: o
  /// `verifier.dart:1305-1307` cobra a aridade de `arguments.types` contra **duas
  /// listas distintas** — `enclosingClass.typeParameters` para Constructor,
  /// `function.typeParameters` para o resto. `init` é o Constructor ⟹ o ∀ dele é o
  /// da classe. `Box(v: 5)` é o sítio que instancia o `T` de `Box<T>`, exatamente
  /// como `Stack.nova()` (ver `_staticMember`).
  List<TypeParamType> _ownerQuantifiers(TypeInfo info) => [
    for (final g in info.generics) TypeParamType(info.decl, g),
  ];

  /// O param COMPLETO — tipo + label + tem-default (item 0).
  ///
  /// **O label é o `label ?? name`**: `fn f(a: Int)` é chamada `f(a: 1)`; a
  /// forma `fn f(ext int: Int)` (label externo ≠ nome interno) usa o `label`.
  /// Sem isto, os args ligavam por POSIÇÃO e os labels **mentiam**.
  ParamType _paramType(ast.Param p) => ParamType(
    _param(p),
    label: p.label ?? p.name,
    hasDefault: p.defaultValue != null,
  );

  // --- A2: TypeNode (sintaxe) → Type (semântica) ---------------------------

  /// A travessia anotação→tipo, **pública** porque a fatia **B** também precisa:
  /// A2 só percorre as ASSINATURAS (campos/params/variantes), mas um `let x:
  /// String = e` tem anotação que ninguém resolveria — e aí o `check` receberia
  /// `ErrorType` (absorvente) e o `nil-under-non-optional` **falharia em
  /// silêncio**, que é o mandato da fase inteira.
  Type resolveTypeNode(ast.TypeNode node) => _resolve(node);

  /// Abre o escopo dos generics de uma **função** (`fn mapa<T, U>(…)`).
  ///
  /// A A1 só planta cabeça para os tipos NOMEADOS (struct/class/enum/trait), que
  /// são os que entram na tabela — uma `fn` não é um tipo. Consequência não
  /// intencional: os generics dela nunca entravam em escopo, e **toda função
  /// genérica dava `unknown-type` no próprio `<T>`**. Isso tornava o
  /// `instantiate` da fatia D (Alg. 6.19) inalcançável a partir de fonte real —
  /// só os testes que montavam `TypeParamType` à mão o exercitavam.
  ///
  /// O par (dona, nome) identifica o [TypeParamType]: a dona aqui é o próprio
  /// nó da `fn`, o que mantém `T` de `f` distinto do `T` de `g`.
  void pushGenericScope(ast.AstNode owner, List<ast.GenericParam> generics) =>
      _genericScopes.add({for (final g in generics) g.name: owner});

  /// Idem, a partir dos **nomes** já coletados ([TypeInfo.generics]) — é o que o
  /// corpo de `extension`/`impl` precisa: os generics do **ALVO**, com o alvo
  /// como dono (spec 011 §3.3).
  void pushGenericScopeNamed(ast.AstNode owner, List<String> names) =>
      _genericScopes.add({for (final n in names) n: owner});

  void popGenericScope() => _genericScopes.removeLast();

  /// A travessia anotação→tipo. Preenche a side-table `<TypeNode, Type>` (§7-4).
  /// **MEMOIZADO** — é a separação `put`/`get` do livro (Fig. 2.38; 2.7.2: *"o
  /// papel de uma tabela de símbolos é passar informações de **declarações** para
  /// **usos**"*). Sem isto, quem resolve duas vezes **paga duas vezes**.
  ///
  /// ⚠️ **Bug que isto mata:** a assinatura de método era resolvida **duas
  /// vezes** — o `_methods` (A2) e o `_fnDecl` do checker, que **re-resolve** via
  /// `_annotated`. Consequências: `unknown-type` saía **DUPLICADO** no mesmo
  /// offset, e — pior, porque silencioso — o `annotations[node]` (a **side-table
  /// nº4** do §7) era **sobrescrito pelo segundo passe**. A tabela que a F7 vai
  /// ler estava sendo corrompida.
  ///
  /// **Memoizar por identidade é seguro aqui, e isso foi VERIFICADO:** o desugar
  /// **repassa a mesma instância** de `TypeNode` (`_param`: `Param(p.label,
  /// p.name, p.type, …)`) em vez de copiá-la, mas cada `TypeNode` aparece **uma
  /// única vez** na árvore — e a **posição** dela determina o escopo genérico.
  /// Nenhuma reescrita da F3 duplica subárvore com `TypeNode` (as que embrulham
  /// em closure sintetizam `Param` com `type: null`). ⟹ um `TypeNode`, um escopo,
  /// um tipo.
  Type _resolve(ast.TypeNode node) {
    final memo = annotations[node];
    if (memo != null) return memo; // `get`
    final t = _resolveInner(node);
    annotations[node] = t; // `put`
    return t;
  }

  Type _resolveInner(ast.TypeNode node) => switch (node) {
    ast.NamedType n => _named(n),
    ast.OptionalType n => _optionalAnnotation(n),
    // `mut` NÃO é tipo (§4.1): não tem imagem em `DartType` (o Kernel tem
    // `isFinal`/`Field.mutable`). Normaliza para o inner; a mutabilidade é flag
    // do binding/campo — `FieldDecl.isMutable` já a carrega.
    ast.MutType n => _resolve(n.inner),
    // Tipo-função ANOTADO (`(Int) -> Bool`): a superfície não tem label ali —
    // `functionType ::= "(" (type ("," type)*)? ")" "->" type`. Posicional puro.
    ast.FunctionType n => FunctionType.positional(
      [for (final p in n.params) _resolve(p)],
      _resolve(n.ret),
      isAsync: n.isAsync,
    ),
    ast.TupleType n => TupleType([for (final e in n.elements) _resolve(e)]),
    // A árvore é total (M2): `ErrorType` sintático já foi reportado pelo parser.
    ast.ErrorType _ => const ErrorType(),
  };

  /// `T?` — e é aqui que mora o `redundant-optional` (spec 009 §4.6-cond.2).
  ///
  /// **É de ANOTAÇÃO, não de `Type`**: dispara quando o usuário escreveu DOIS
  /// níveis de opcionalidade *nesta anotação*. Se morasse no smart constructor
  /// `optional()`, dispararia em `compact<String?>` — programa **LEGAL** —,
  /// porque lá os dois `?` vêm de SUBSTITUIÇÃO (fatia D), não de dois glifos.
  ///
  /// O critério é o INNER JÁ RESOLVIDO ser opcional — não `inner is
  /// ast.OptionalType`. Como `Option[T]` ≡ `T?` (§4.6), a forma `Option[Int]?`
  /// chega com inner `NamedType`, e `Option[Option[Int]]` nem passa por aqui
  /// (usando `[]` no lugar de angle brackets só para o doc-comment). As formas
  /// são o mesmo tipo, e todas têm de disparar (§11 CA28a).
  ///
  /// NOTA: `T??` **não é exprimível** — o lexer casa `??` como UM token
  /// (`questionQuestion`, o coalesce; maximal munch). O CA28a da spec cita
  /// `String??`, que na verdade morre antes, no parser (`expected-token`).
  Type _optionalAnnotation(ast.OptionalType n) {
    final inner = _resolve(n.inner);
    if (inner is OptionalType) _err('redundant-optional', n);
    return optional(inner);
  }

  Type _named(ast.NamedType n) {
    final args = [for (final a in n.args) _resolve(a)];

    // 1. Parâmetro de tipo DECLARADO (`T` dentro de `struct Box<T>`) — a
    //    variável LIGADA do 6.5.4, não a fresca da unificação (que é da fatia D).
    final owner = _genericOwner(n.name);
    if (args.isEmpty && owner != null) {
      return TypeParamType(owner, n.name);
    }

    // 2. Básicos (6.3.1).
    final basic = switch (n.name) {
      'Int' => const IntType(),
      'Float' => const FloatType(),
      'Bool' => const BoolType(),
      'String' => const StringType(),
      'Void' => const VoidType(),
      'Never' => const NeverType(),
      _ => null,
    };
    if (basic != null) {
      if (args.isNotEmpty) _err('generic-arity-mismatch', n);
      return basic;
    }

    // 3. Builtins genéricos SEM nó-decl — a stdlib os usa e nunca os declara
    //    (§4.1). Trazê-los para cá corrige o vazamento do oracle (§7-3): lá
    //    moram no `codegen.dart:683`, com type-args apagados p/ `DynamicType()`.
    final builtin = switch (n.name) {
      'Option' => BuiltinKind.option,
      'Result' => BuiltinKind.result,
      // O **CHÃO** (spec 010 §4.6.1) — irredutível, toca o Dart. Tabela
      // **FECHADA**: fora dela é `unknown-type`/`unknown-member`, nunca
      // `UnknownType` silencioso (as 3 condições do §3.3).
      'List' => BuiltinKind.list,
      'Map' => BuiltinKind.map,
      _ => null,
    };
    if (builtin != null) {
      if (args.length != builtinArity[builtin]) {
        _err('generic-arity-mismatch', n);
        return const ErrorType();
      }
      // `Option<X>` → `OptionalType(X)`: ALIAS canônico resolvido AQUI, em A2
      // (§4.6, ruling do dono 2026-07-12: `Option<T>` ≡ `T?`). Reescrita de uma
      // linha, NÃO instanciação genérica — por isso a nulidade não depende da
      // fatia D, e `BuiltinKind.option` não sobrevive à fatia A.
      if (builtin == BuiltinKind.option) {
        // Dois glifos de opcionalidade na mesma anotação (ver [_optionalAnnotation]).
        if (args.single is OptionalType) _err('redundant-optional', n);
        return optional(args.single);
      }
      // `Result<T,E>` SOBREVIVE: não tem equivalente nativo no Kernel (payload
      // nos dois lados ⟹ classe no heap, sempre — §8.4).
      return BuiltinType(builtin, args);
    }

    // 4. User-type declarado no módulo.
    final decl = types.declNamed(n.name);
    if (decl == null) {
      _err('unknown-type', n);
      return const ErrorType();
    }
    final info = types.of(decl)!;
    if (args.length != info.generics.length) {
      _err('generic-arity-mismatch', n);
      return const ErrorType();
    }
    return NamedType(decl, info.kind, args);
  }

  /// A decl que declarou o parâmetro genérico [name], ou `null` se não há um em
  /// escopo. Do mais interno para o mais externo (shadowing léxico).
  ast.AstNode? _genericOwner(String name) {
    for (final scope in _genericScopes.reversed) {
      final owner = scope[name];
      if (owner != null) return owner;
    }
    return null;
  }

  // --- A3: boa-formação ----------------------------------------------------

  /// **Duas passadas, e a ordem é o ponto.**
  ///
  /// O `_checkOverride` anda o grafo para cima (`_implementationAbove`), e andar o
  /// grafo enquanto houver UMA aresta de ciclo por cortar é entrar em laço. No
  /// loop único que morava aqui, o `_checkOverride(A)` rodava **antes** de o ciclo
  /// de `B` ser cortado — e era **por isso** que o `_implementationAbove` precisava
  /// de um `seen`. Não era virtude dele: era a ordem errada, paga com uma guarda
  /// em cada walker. Com a fase de ciclo fechada primeiro, o grafo que chega à
  /// passada 2 é acíclico e os walkers voltam a ser a Fig. 2.37 — sem guarda.
  ///
  /// O kind já foi checado na A2 (`_conform`), que é o que faz as arestas
  /// inválidas nunca existirem: `struct S : S` e `struct A : B`+`struct B : A`
  /// morrem lá (`struct` não herda) ⟹ nem chegam a formar ciclo. Sobra o que só a
  /// `class` pode fazer.
  void _checkWellFormed() {
    _checkInheritanceCycles();
    for (final info in types.all) {
      _checkDuplicateFields(info);
      _checkDuplicateMembers(info);
      _checkTraitConformance(info);
      _checkOverride(info);
    }
  }

  /// **`missing-override` / `override-nothing`** — item 2 da spec 011.
  ///
  /// **`override` é OBRIGATÓRIO**, e quem decide é **P4**, não P6
  /// (`ita-visionary`): eu media o eixo errado. P6 escolhe a **forma** (se marca,
  /// marca com keyword — já feito, `override` é reservada); **não** a
  /// obrigatoriedade. Java tem `@Override` opcional; Swift tem `override`
  /// obrigatório — P6 não escolhe entre eles.
  ///
  /// **P4 escolhe:** sem `override` obrigatório, ler `class D : A { fn f() }`
  /// **não diz** se `f` é novo ou substitui o de `A` — informação que **muda o
  /// comportamento**, escondida noutro arquivo. Mesma família do `mut`, do
  /// `struct` vs `class` (P2), do *"o nome novo É a honestidade"* (009 §4.6).
  ///
  /// **Não é cerimônia:** cerimônia é marca **sem informação** (o `@Override` do
  /// Java — o compilador já sabe). Aqui a keyword carrega informação **para o
  /// LEITOR**, que não tem a superclasse na tela. É a economia do `mut`: uma
  /// palavra que evita abrir outro arquivo. E o `override-nothing` pega **drift
  /// de refatoração** — renomeiam `f` na superclasse e o `override` do filho vira
  /// função nova, silenciosamente (ADR-0013 outra vez).
  ///
  /// ## As duas cercas
  ///
  /// **1. `override` marca SUBSTITUIR IMPLEMENTAÇÃO EXISTENTE** — superclasse
  /// concreta **ou default de trait** —, **não** satisfazer **requisito sem
  /// corpo**. Requisito não tem o que sobrepor. **Sem esta cerca,
  /// `missing-override` dispararia em TODA conformance de trait**, e aí seria
  /// cerimônia de verdade.
  ///
  /// **2. `override` sobre `extension` FAZ sentido** (correção do
  /// `compiler-craftsman`; eu havia dito o contrário). `extension Dog { override
  /// fn speak() }` com `class Dog : Animal` shadowa o **herdado** — não há
  /// colisão, logo não há `duplicate-member`. A regra é **uma só, sem exceção**:
  /// `override` exige que o walk **ACIMA** do nível do próprio tipo ache uma
  /// implementação; o `origin` é irrelevante. Que é justamente o que *"extension
  /// está no mesmo nível"* significa.
  void _checkOverride(TypeInfo info) {
    for (final m in info.methods) {
      final above = _implementationAbove(info, m.name);
      if (m.decl.isOverride && above == null) {
        // Pega drift de refatoração: renomearam o de cima e este virou novo.
        _err('override-nothing', m.decl);
        continue;
      }
      if (!m.decl.isOverride && above != null) {
        _err('missing-override', m.decl);
        continue;
      }
      // ⚠️ **`override-signature-mismatch` — sem isto, `D ≤ A` é MENTIRA.**
      //
      // Achado do W3 (contexto fresco). O check só verificava **presença**, e o
      // `_checkTraitConformance` **pula exatamente estes casos**
      // (`if (want.decl.body != null) continue` — tem default ⟹ não é
      // requisito). Os dois têm domínios **complementares** e a assinatura caía
      // no VÃO: requisito de trait era checado por `==`; superclasse concreta e
      // default de trait — os dois casos que o `override` cobre — **não eram
      // checados por ninguém**.
      //
      // O estrago: `class D : A { override fn f() -> String }` com
      // `A.f() -> Int` passava, e `_isSubtype` dizia `D ≤ A` ⟹
      // `fn g(a: A) -> Int => a.f()` + `g(d)` **tipava e devolvia String num
      // Int**. "Compila e roda errado" — a família que o ADR-0013 nasceu para
      // matar, e é *palavra por palavra* o argumento que o
      // `_checkTraitConformance` usa 60 linhas acima. A regra valia e parava no
      // `class`.
      //
      // Pior: a keyword **afirma** "estou substituindo `A.f`", e ninguém
      // conferia. **Marca que carrega promessa não-verificada é pior que marca
      // sem informação** — era `override` virando meia-cerimônia.
      //
      // Critério `==`, o mesmo do trait (009: variância **invariante**).
      if (above != null && m.sig != above.sig) {
        _err('override-signature-mismatch', m.decl);
      }
    }
  }

  /// Há **implementação** (não requisito) deste nome ACIMA do nível do tipo?
  /// Cerca 1: `body != null` — requisito sem corpo não tem o que sobrepor.
  ///
  /// **Sem guarda de ciclo**, e isso é uma consequência, não um descuido: o
  /// `_checkInheritanceCycles` já cortou as arestas antes desta passada, então o
  /// grafo que chega aqui é acíclico e este walker pode ser a Fig. 2.37. O `seen`
  /// que morava aqui era o preço da ordem errada.
  MethodInfo? _implementationAbove(TypeInfo info, String name) {
    for (final s in info.sources) {
      if (s is! NamedType) continue;
      final si = types.of(s.decl);
      if (si == null) continue;
      final hit = si.methods
          .where((x) => x.name == name && x.decl.body != null)
          .firstOrNull;
      if (hit != null) return hit;
      final up = _implementationAbove(si, name);
      if (up != null) return up;
    }
    return null;
  }

  /// **`missing-trait-member`** — item 1 da spec 011.
  ///
  /// O `_contribute` produz `T ≤ Trait` **sem verificar que os métodos existem**
  /// ⟹ dava para declarar conformidade e não implementar nada. E **subtipagem É
  /// obrigação**: `T ≤ Trait` significa *"todo `T` serve onde se espera
  /// `Trait`"*. Sem os métodos, a subtipagem é **mentira** — a chamada **tipa**
  /// (o walk acha o membro no nível 1, no próprio trait) e **explode em
  /// runtime**. É a família "compila mas roda errado" que o ADR-0013 nasceu para
  /// matar, e é P4 na veia.
  ///
  /// ⚠️ **Eu ia perguntar ao dono se isto era erro ou aviso, com base no
  /// ADR-0012 #2 ("declaração de intenção"). Era MÁ-LEITURA** (`ita-visionary`):
  /// o "intenção" ali **não** contrasta com "obrigação" — contrasta com
  /// **"retrofit externo"**. O eixo é **onde se escreve**, não **se vincula**. E
  /// o #2 põe as duas formas como equivalentes ("coexistem"), com a 009 §4 dando
  /// às duas o **mesmo** efeito. ⟹ **Erro, e é entailment — não gasta ruling.**
  ///
  /// **Default de trait existe** — `fnDecl ::= … fnBody?`, e o `ast.dart:47`
  /// crava *"assinatura sem corpo (`body == null`) = trait"*. Critério: **falta
  /// e não tem default**.
  void _checkTraitConformance(TypeInfo info) {
    // Nem `if (kind == trait_) return`, nem `if (ti.kind != trait_) continue`: os
    // dois eram **pulos que deixavam a aresta viva** — a incoerência de declarar
    // `T ≤ X` e não conferir nada. Agora o `_conform` garante o invariante na
    // fonte: trait é folha (a lista de um trait é vazia) e só trait entra na
    // lista (o resto virou `trait-expected`). O que sobrava aqui era a guarda
    // tapando o buraco do lado errado.
    for (final t in info.traits) {
      if (t is! NamedType) continue;
      final ti = types.of(t.decl);
      if (ti == null) continue;

      // Os type-args do trait substituem antes de comparar: `impl Comparable<T>
      // for Stack` ⟹ a assinatura pedida é a do trait COM o `T` do alvo.
      final subst = _substOfTrait(ti, t.args);
      for (final want in ti.methods) {
        if (want.decl.body != null) continue; // tem default ⟹ não é requisito
        final got = info.methods.where((m) => m.name == want.name).firstOrNull;
        if (got == null) {
          _err('missing-trait-member', info.decl as ast.Decl);
          continue;
        }
        // **Assinatura por `==`** — a 009 já cravou variância **invariante**
        // ("covariância em container mutável é insound — o array store do
        // Java"). Comparar por nome só deixaria `fn f() -> Int` satisfazer
        // `fn f() -> String`.
        if (got.sig != substitute(want.sig, subst)) {
          _err('trait-member-signature-mismatch', got.decl);
        }
      }
    }
  }

  Map<TypeParamType, Type> _substOfTrait(TypeInfo ti, List<Type> args) {
    if (ti.generics.isEmpty || args.length != ti.generics.length) return const {};
    return {
      for (var i = 0; i < ti.generics.length; i++)
        TypeParamType(ti.decl, ti.generics[i]): args[i],
    };
  }

  /// **`duplicate-member`** — rulings §12-3 e §12-4 do dono (spec 011).
  ///
  /// Mesma base do [_checkDuplicateFields]: 6.3.6, *"um nome pode aparecer no
  /// máximo uma vez"*. E o Ex. 5.10 autoriza explicitamente pôr isto em A3:
  /// *"Essa SDD não verifica se um identificador é declarado mais de uma vez,
  /// **mas ela pode ser modificada para fazer isso**"*.
  ///
  /// **`extension` está no MESMO NÍVEL dos membros próprios** (ruling §12-3):
  /// se ele contribui para a tabela do alvo (§3.1), não há degrau entre os dois.
  /// Colisão ⟹ **erro na DECLARAÇÃO** — na causa, não longe no uso — e nada de
  /// código morto silencioso. *(É o que o Swift faz de verdade:
  /// `Invalid redeclaration`. A alternativa "shadowing" que eu havia rotulado
  /// "(Swift)" era falsa; o dono corrigiu quando apontei.)*
  ///
  /// **Sem overload de método** (ruling §12-4) ⟹ o critério é o **NOME**, não a
  /// assinatura, e o 6.5.3 nunca é invocado aqui. *(Ele É invocado por
  /// **operador** — `_primitiveOps` no `check.dart` — e é o que mantém o
  /// built-in não-privilegiado, R5 da 009. O ruling é sobre método.)*
  ///
  /// **Campo × método também colidem:** 2.7 §1 — *"uma classe teria sua própria
  /// tabela, com uma entrada para cada campo **e** método"*. Uma tabela, um
  /// namespace.
  void _checkDuplicateMembers(TypeInfo info) {
    final seen = <String, MethodInfo>{};
    final fieldNames = {for (final f in info.fields ?? const <FieldInfo>[]) f.name};
    for (final m in info.methods) {
      if (fieldNames.contains(m.name) || seen.containsKey(m.name)) {
        // O span é o do MÉTODO que colide — se veio de `extension`, é lá que o
        // usuário conserta. É para isto que o `origin` existe.
        _err('duplicate-member', m.decl);
        continue;
      }
      seen[m.name] = m;
    }
  }

  /// Dragon 6.3.6, literal: *"Os nomes dos campos de um registro devem ser
  /// distintos; ou seja, um nome pode aparecer no máximo uma vez"*.
  void _checkDuplicateFields(TypeInfo info) {
    final seen = <String>{};
    for (final f in info.fields ?? const <FieldInfo>[]) {
      if (!seen.add(f.name)) _err('duplicate-field', f.decl);
    }
  }

  /// `class A : B` … `class B : A`. Sem isto, qualquer walk sobre a hierarquia
  /// (`≤` do §4.2b, o `_lookup`, F6, F7) entra em laço.
  ///
  /// **São DOIS grafos, com disciplinas opostas, e o livro dá as duas.** No grafo
  /// de **expressões de tipo** (campo, type-arg) o ciclo é LEGÍTIMO — 6.3.1 nota 3
  /// —, mas só *"se as arestas para os nomes de tipo são redirecionadas"*: o Itá
  /// usa equivalência de **NOME** (6.3.2), nunca redireciona, e por isso
  /// `struct A{b:B}` + `struct B{a:A}` é legal **e nenhum walker cicla**
  /// (`FieldInfo.type` é folha). Já `superclass`/`traits` **não é campo**: é o
  /// `prev` do `Env` (2.7 §1 + 1.6.4), e 2.7.1 diz que o encadeamento *"forma uma
  /// pilha"* / *"resulta numa árvore"*. **Árvore não tem ciclo** — aqui o ciclo é
  /// CORRUPÇÃO, não estrutura.
  ///
  /// **Por que o livro não precisa de guarda e o Itá precisa:** a Fig. 2.37 anda
  /// escopos com `for (e = this; e != null; e = e.prev)`, **sem** `visited`, e
  /// pode — `new Env(top)` só aponta para tabela que **já existe** ⟹ aciclicidade
  /// **por construção**. `class A : B` resolve o pai **por nome, depois** ⟹ o Itá
  /// perde a garantia estrutural e tem de **restaurá-la explicitamente**. É o que
  /// esta fase faz: depois dela, o grafo de decls é acíclico.
  ///
  /// **O corte é por DECL, e é ele que prova a terminação.** Um `visited` de
  /// TIPOS não bastaria: o `_lookup` recursa sobre o tipo **substituído**, e
  /// `class C<T> : C<List<T>>` gera infinitos TIPOS sobre finitas DECLS (recursão
  /// expansiva — Kennedy & Pierce 2007, lacuna do Dragon). Com o grafo de decls
  /// acíclico, todo walk sobre tipos desce um nível do DAG ⟹ termina. É a medida
  /// estrutural no lugar da contagem de classes da Fig. 6.32.
  ///
  /// **Ordem-independente (5.2.5):** a aresta `u → v` está em ciclo sse `v`
  /// alcança `u`. Detecta-se sobre o grafo ORIGINAL e só então se reporta e corta
  /// **todas** — cortar "a primeira que fecha o laço" faria o diagnóstico depender
  /// da ordem das declarações.
  ///
  /// Só `superclass` é cortada porque só ela pode ciclar: trait é folha
  /// (`_conform`), e `struct`/`enum`/`actor` só têm arestas para traits.
  void _checkInheritanceCycles() {
    final culprits = [
      for (final info in types.all)
        if (info.superclass case NamedType(:final decl))
          if (_reaches(decl, info.decl)) info,
    ];
    for (final info in culprits) {
      _err('inheritance-cycle', info.decl);
      info.superclass = null; // A3 CORTA: o grafo sai daqui acíclico.
    }
  }

  /// [from] alcança [target] subindo por [TypeInfo.sources]?
  ///
  /// O `visited` é a Fig. 6.32 — *"ao combinar em primeiro lugar … o algoritmo
  /// termina"* — e este é o **único** lugar que precisa dele: é o único walker que
  /// encara o grafo **antes** de a aciclicidade valer.
  bool _reaches(ast.AstNode from, ast.AstNode target) {
    final visited = <ast.AstNode>{};
    final stack = <ast.AstNode>[from];
    while (stack.isNotEmpty) {
      final cur = stack.removeLast();
      if (identical(cur, target)) return true;
      if (!visited.add(cur)) continue;
      for (final s in types.of(cur)?.sources ?? const <Type>[]) {
        if (s is NamedType) stack.add(s.decl);
      }
    }
    return false;
  }

  void _err(String code, ast.AstNode at) =>
      errors.add(CheckError(code, at.offset, at.length));
}
