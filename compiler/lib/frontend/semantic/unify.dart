// ===========================================================================
// unify.dart — Fatia D: unificação de type-args (spec 009 §5.4-D).
// ===========================================================================
//
// Materialização À MÃO do **Algoritmo 6.19** (Dragon, Fig. 6.32) — union-find
// sobre o grafo de tipos:
//
//     boolean unify(Node m, Node n) {
//       s = find(m); t = find(n);
//       if (s = t) return true;
//       else if (s e t representam o mesmo tipo básico) return true;
//       else if (s é operador com filhos s1,s2 and t é operador com t1,t2) {
//         union(s,t); return unify(s1,t1) and unify(s2,t2);
//       }
//       else if (s ou t representa uma variável) { union(s,t); return true; }
//       else return false;
//     }
//
// ESCOPO — **só type-args em aplicação, SEM let-generalization** (§4.4). Não é
// HM: 6.5.4 é *"útil para uma linguagem como ML, que … **não exige que os nomes
// sejam declarados**"* — não é o Itá (a borda anota, §0.5-1). É o que
// Kotlin/Swift/Java fazem.
//
// ASSIMETRIA DO `union` (6.5.5, e é normativa): *"Se um dos representantes … for
// um nó que NÃO representa variável, union faz com que esse nó seja o
// representante"*. Sem isso *"duas expressões não equivalentes poderiam ser
// unificadas por meio dessa variável"*.
//
// INCOMPLETUDE DECLARADA (§4.6-cond.3, não é bug): o Alg. 6.19 é unificação
// **sintática sobre construtores livres**. Com `?` idempotente (ruling §12-7),
// **`?` não é construtor livre**: casar `List<T?>` contra `List<String?>` tem
// DUAS soluções — `T := String` (sintática) e `T := String?` (módulo a teoria).
// O algoritmo devolve a primeira e nunca considera a segunda; é determinístico e
// a solução preferida é a útil. Consequência concreta: `compact` com
// `T = String?` é inalcançável por inferência, e não há turbofish para forçar
// (GRAMMAR §6). Precedente: Swift viveu isto até o SE-0230.
// ===========================================================================

import 'package:ita_next_compiler/frontend/semantic/type.dart';

/// Union-find sobre variáveis de tipo (o `find`/`union` do 6.5.5).
class Unifier {
  final Map<TypeVar, Type> _subst = {};
  int _next = 0;

  /// Variável **NOVA** (6.5.4: *"em cada uso de um tipo polimórfico,
  /// substituímos as variáveis ligadas por **novas variáveis** e removemos os
  /// quantificadores universais"*). Distinta do [TypeParamType], que é a LIGADA.
  TypeVar fresh() => TypeVar(_next++);

  /// `find(n)` — o representante da classe de equivalência, com **path
  /// compression** (o campo `set` do livro, seguido até o representante).
  Type find(Type t) {
    if (t is! TypeVar) return t;
    final next = _subst[t];
    if (next == null) return t; // representante (o `set` nulo do livro)
    final root = find(next);
    if (root != next) _subst[t] = root; // compressão
    return root;
  }

  /// Aplica a substituição corrente em profundidade — o `S(t)` do 6.5.4.
  Type resolve(Type t) {
    final r = find(t);
    return switch (r) {
      OptionalType(:final inner) => optional(resolve(inner)), // smart ctor!
      NamedType n => NamedType(n.decl, n.kind, [for (final a in n.args) resolve(a)]),
      BuiltinType n => BuiltinType(n.kind, [for (final a in n.args) resolve(a)]),
      // Label e default são da DECLARAÇÃO — a substituição só toca o tipo.
      FunctionType n => FunctionType(
        [
          for (final p in n.params)
            ParamType(resolve(p.type), label: p.label, hasDefault: p.hasDefault),
        ],
        resolve(n.ret),
        isAsync: n.isAsync,
      ),
      TupleType n => TupleType([for (final e in n.elements) resolve(e)]),
      _ => r,
    };
  }

  /// O Algoritmo 6.19 (Fig. 6.32).
  bool unify(Type m, Type n) {
    final s = find(m);
    final t = find(n);

    if (s == t) return true; // `if (s = t) return true`

    // `ErrorType` é absorvente nos DOIS sentidos (§4.2b) — anti-cascata.
    if (s is ErrorType || t is ErrorType) return true;

    // `else if (s ou t representa uma variável) { union(s,t); return true; }`
    // A ASSIMETRIA: a variável nunca vira representante de uma classe que tem
    // construtor — por isso ligamos a VAR ao outro, nunca o inverso.
    if (s is TypeVar) return _bind(s, t);
    if (t is TypeVar) return _bind(t, s);

    // `else if (s e t são operadores com filhos) { union; unify(filhos) }`
    return switch ((s, t)) {
      (OptionalType a, OptionalType b) => unify(a.inner, b.inner),
      (NamedType a, NamedType b) =>
        identical(a.decl, b.decl) && _unifyAll(a.args, b.args),
      (BuiltinType a, BuiltinType b) =>
        a.kind == b.kind && _unifyAll(a.args, b.args),
      // Unificar dois tipos-função: só os TIPOS dos params. Label/default são
      // da declaração e não participam da equivalência estrutural — um
      // `(Int) -> Bool` anotado casa com a assinatura de `fn f(x: Int) -> Bool`.
      (FunctionType a, FunctionType b) =>
        a.isAsync == b.isAsync &&
            _unifyAll(
              [for (final p in a.params) p.type],
              [for (final p in b.params) p.type],
            ) &&
            unify(a.ret, b.ret),
      (TupleType a, TupleType b) => _unifyAll(a.elements, b.elements),
      // `else if (mesmo tipo básico) return true` — já coberto pelo `s == t`
      // acima (os básicos têm igualdade estrutural). Resto: falha.
      _ => false,
    };
  }

  bool _bind(TypeVar v, Type t) {
    if (v == t) return true;
    // **Occurs check** — o livro NÃO o faz (nota 7: *"é um erro unificar uma
    // variável com uma expressão contendo essa variável. O Algoritmo 6.19
    // permite tais substituições"*), porque lá a unificação serve também para
    // tipos circulares. Aqui é `Result<T,E>`/`List<T>` em aplicação: um tipo
    // infinito é bug, não feature — e o Kernel não teria imagem para ele.
    if (_occurs(v, t)) return false;
    _subst[v] = t;
    return true;
  }

  bool _occurs(TypeVar v, Type t) {
    final r = find(t);
    if (r == v) return true;
    return switch (r) {
      OptionalType n => _occurs(v, n.inner),
      NamedType n => n.args.any((a) => _occurs(v, a)),
      BuiltinType n => n.args.any((a) => _occurs(v, a)),
      FunctionType n => n.params.any((p) => _occurs(v, p.type)) || _occurs(v, n.ret),
      TupleType n => n.elements.any((e) => _occurs(v, e)),
      _ => false,
    };
  }

  bool _unifyAll(List<Type> a, List<Type> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!unify(a[i], b[i])) return false;
    }
    return true;
  }

  /// Instancia um tipo polimórfico — 6.5.4: *"em cada uso … substituímos as
  /// variáveis ligadas por novas variáveis e removemos os quantificadores"*.
  /// Cada [TypeParamType] (a LIGADA) vira um [TypeVar] fresco.
  Type instantiate(Type t, List<TypeParamType> params) {
    if (params.isEmpty) return t;
    return substitute(t, {for (final p in params) p: fresh()});
  }
}
