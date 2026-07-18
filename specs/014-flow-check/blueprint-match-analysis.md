# Blueprint — F6 match analysis (Maranget 2007, spec 014 §4): o desenho que o implementador segue

> **Lote 2 da F6.** O lote 1 (flow-walk) está em `main` — ver
> `specs/014-flow-check/blueprint-flow-walk.md`. Este documento cobre a análise de `match`:
> **exaustividade** (`match-not-exhaustive`) e **redundância** (`unreachable-match-arm`), mais o
> warning opcional `wildcard-covers-known-variants`.
>
> **Fundamento-mestre:** o algoritmo é **Maranget, *"Warer's questions and lazy pattern matching"*
> — na prática o algoritmo de usefulness de *"Warnings for pattern matching"*, J. Funct.
> Programming 17(3), 2007** (`U`/`S`/`D` da §3.1, Figura 1). O Dragon Book **não cobre
> exaustividade de ADT** (a régua Art. III fecha em 6.x → codegen; exaustividade é lacuna
> declarada, roteada à literatura externa por norma). A TÉCNICA de integração ao walk continua SDD
> L-atribuída em UM walk (Dragon 5.2.4/5.5), como todo o resto da F6.
>
> **Escopo por FATIA (entrega incremental). ⚠️ Lacuna = ERRO honesto, nunca silêncio (spec 014
> §12-11, ruling do dono 2026-07-17) — ver I7 e §F1.4.**
> - **Fatia 1 — decidível sem modelar estrutura:** tipos FECHADOS (`Enum` via `TypeInfo.variants`,
>   `Option` `some`/`none`, `Result` `ok`/`err`, `Bool` `true`/`false`) **+ exaustividade de coluna
>   escalar infinita** (`Int`/`String`/`Float` `LiteralPattern` como átomos — Maranget §3.2); `ω` =
>   `Wildcard`/`Bind`; `match x {}` vazio. Os **dois erros** + `match-exhaustiveness-unsupported` +
>   testemunha + printer. **É o alvo deste design detalhado (§F1).**
> - **Fatia 2 — PRECISÃO de ordenados:** testemunha concreta e **redundância de Range** (interval-
>   splitting, `BigInt`); a exaustividade escalar já é Fatia 1. Blueprint em §3.2.
> - **Fatia 3 — estrutura:** `List` (partição por comprimento), `struct`/`record` (produto, campos na
>   ordem declarada), `String`-interpolada (débito F5). Enquanto não chegam, `List`/produto/`Range`
>   NÃO-fechados-por-`_` caem em `match-exhaustiveness-unsupported`. Blueprint em §3.3.

---

## 0. Invariantes (violar = bug, não opinião)

Herda I1–I4 do flow-walk (`blueprint-flow-walk.md` §0). Acrescenta:

- **I5 — a matriz nunca RE-TIPA.** A coluna é dirigida pelo **tipo**, e o tipo de cada coluna vem
  por **construção**: a coluna-raiz é o tipo do escrutínio (`_typeOf(n.scrutinee)`, nº1); as
  sub-colunas vêm dos **tipos de argumento do construtor** (`VariantInfo.payload` sob `substFor` /
  `OptionalType.inner` / `Result.args`). `analyzeMatch` **não consulta `exprTypes` para
  sub-patterns** — reconstrói o tipo pela mesma máquina que a F5 usou em `_bindEnumPattern`
  (`check.dart:687-691`). Consequência: `analyzeMatch` recebe `TypeTable` + o tipo do escrutínio, e
  **não** o `CheckResult` inteiro.
- **I6 — guard não conta, nunca.** Um braço com `guard != null` **não entra na matriz** `P` (o guard
  pode falhar — não cobre) **e nunca é consultado** como query de redundância (nunca é acusado de
  morto). Isto é um **delta deliberado vs JLS §14.11.1**, que ACUSA um braço guarded dominado.
  Registrado no DoD ("guard nunca acusado"). Precedente: Rust `match` (guarded arms não contam para
  exaustividade); Swift idem.
- **I7 — lacuna declarada, NUNCA silêncio (spec 014 §12-11, ruling do dono 2026-07-17).** Se a
  decisão de exaustividade **genuinamente depende** de especializar um tipo que a fatia corrente não
  modela — e **nenhum `_`/ω fecha aquela coluna** — a análise emite **`match-exhaustiveness-unsupported`
  (ERRO)**, a "não sei" honesta. **Jamais** cala (o silêncio mente: o dev pensa que o `match` é seguro)
  e **jamais** decide com informação incompleta (falsa-acusa `non-exhaustive` num `match` que talvez
  fosse exaustivo). Verbatim do dono: *"não pode mentir para o desenvolvedor… tem que ser uma PEDRA em
  suas regras"*. Corolário-chave: **um `_`/ω sempre entrega veredito** (verde ou `non-exhaustive`) **sem
  tocar a estrutura não-modelada** — o ramo default (`D`) só precisa saber "esta cabeça é ω?", que é
  respondível para QUALQUER pattern. Fatias 2/3 estreitam o gatilho do erro dando `Sig` real a
  List/produto/Range.

---

## 1. Fundamento — Maranget 2007 (§3.1, Figura 1)

O núcleo é **um** predicado, `U(P, q)` — *"o vetor de patterns `q` é **útil** com respeito à matriz
`P`?"*, i.e. existe um valor casado por `q` e por **nenhuma** linha de `P`. Tudo deriva dele:

- **Exaustividade** = `¬U(P_unguarded, (ω,…,ω))`. Se um vetor de wildcards ainda é útil, existe um
  valor não coberto → `match-not-exhaustive`. A **testemunha** é esse valor, construído na recursão.
- **Redundância** do braço `i` = `¬U(P_{<i}, row_i)` (com `P_{<i}` = braços unguarded ANTES de `i`;
  `row_i` = o pattern do braço `i`). Braço inútil = nunca casa nada que os anteriores não casem →
  `unreachable-match-arm`.

Os três operadores (Maranget §3.1):

- **`S(c, P)`** — *especialização* por construtor `c` de aridade `a`. Para cada linha:
  - cabeça `= c(r₁…rₐ)` → nova linha `(r₁…rₐ, resto)`;
  - cabeça `= c'≠c` → linha **descartada**;
  - cabeça `= ω` → nova linha `(ω,…,ω [a vezes], resto)`.
- **`D(P)`** — *default*. Mantém só linhas de cabeça `ω`, removendo a 1ª coluna (`c'≠ω` descartada).
- **`U`** recursivo (Figura 1), sobre a 1ª coluna de `q`:
  - `q₀ = c(r₁…rₐ)`: `U(S(c,P), (r₁…rₐ, q_resto))`.
  - `q₀ = ω`: seja **Σ** = construtores que aparecem na coluna 1 de `P`.
    - **Σ completa** (contém TODOS os construtores do tipo): `⋁_{c∈tipo} U(S(c,P), (ω^{ar(c)}, q_resto))`.
    - **Σ incompleta**: `U(D(P), q_resto)`, e a testemunha ganha na cabeça **um construtor FORA de Σ**
      (ou `ω`, se Σ = ∅).
  - **Caso base** (`P` tem 0 colunas): útil ⟺ `P` tem **0 linhas**.

A **testemunha** sobe da recursão: no caso base útil ela é o vetor vazio `()`; a cada retorno,
prepende-se a cabeça (`c(w₁…wₐ)` no ramo-ctor; o construtor-fora-de-Σ ou `ω` no ramo-default).

---

## 2. O design-centro: `Sig` sela a tabela §4

Os **três pontos de variação** de `U` (o que é "todos os construtores do tipo", como `S(c,·)`
expande, qual a aridade de `c`) são exatamente o que muda de tipo para tipo. Selamos isso num tipo
`Sig` — **a materialização da tabela de normalização superfície→construtor** que o parecer W1 pediu
(`ast.asdl` §4). `U`/`S`/`D` ficam **type-agnósticos**; só `Sig.of(colType)` sabe a família.

| Tipo da coluna              | `Sig`         | Σ (construtores)                         | fonte                                    |
|-----------------------------|---------------|------------------------------------------|------------------------------------------|
| `enum E { A, B(T), … }`     | `SealedSig`   | `{A/0, B/1, …}` de `TypeInfo.variants`   | `types.of(decl).variants` + `substFor`   |
| `Option<T>` (`T?`)          | `SealedSig`   | `{some/1 : T, none/0}`                    | `OptionalType.inner`                     |
| `Result<T,E>`               | `SealedSig`   | `{ok/1 : T, err/1 : E}`                   | `BuiltinType(result).args`               |
| `Bool`                      | `SealedSig`   | `{true/0, false/0}`                       | fixo                                     |
| `Never`                     | `EmptySig`    | `∅` (completa por vacuidade)             | fixo                                     |
| Int/Str/Float/List/produto  | `OpaqueSig`   | — (fatia 1 não sela; ver §F1.4)          | fatias 2/3                               |

**A normalização superfície→construtor mora em `headCtor`** (§F1.2): um `none` do `Option` pode vir
como `.none` (`EnumPattern`) **OU como `nil` (`LiteralPattern(NilLit)` — `parser.dart:1892`)**;
`true`/`false` vêm como `LiteralPattern(BoolLit)` (`parser.dart:1884-1890`), não como `EnumPattern`.
`Sig` é quem reconcilia as duas superfícies num único `Ctor`.

> **Por que `Sig` e não um `switch` gigante no tipo dentro de `U`:** `U`/`S`/`D` são o algoritmo
> universal (Maranget); a família do tipo é dado. Misturar as duas coisas replicaria o esqueleto de
> `U` por família. O `Sig` é o mesmo movimento do `sources()` único da F5 (o ponto onde os walks
> coincidem por construção) — **um** eixo de variação, isolado.

---

## 3. Fatias 2 e 3 (blueprint — implementação posterior)

### 3.1 Por que fatiar (sob o §12-11: lacuna = erro, não silêncio)

O corte é **por forma de pattern cuja ESTRUTURA a fatia precisa modelar para decidir**. Fatia 1
modela: `ω`, `EnumPattern`, `BoolLit`, `NilLit`, **e literais escalares (Int/String/Float
`LiteralPattern`) como átomos aridade-0 de Σ INFINITA** — a exaustividade de coluna escalar é decidível
sem enumerar (Maranget §3.2: tipo infinito ⟹ Σ nunca completa ⟹ ramo default ⟹ testemunha `_`). O que
Fatia 1 **não** modela: `Range`, `List`, `Struct`/`Record` (patterns cuja própria estrutura pode
particionar/cobrir o domínio — `Point{x,y}` cobre todo Point, `[]`+`[_,..]` cobre toda List). Contra
esses, o veredito só é seguro se um `_`/ω o fecha (o ramo `D` decide sem tocar a estrutura); senão →
`match-exhaustiveness-unsupported` (I7). **Nunca silêncio, nunca falsa-acusa.**

### 3.2 Fatia 2 — ordenados: precisão de Range/List (a exaustividade escalar JÁ está na Fatia 1)

- **Int / Range:** o **veredito de exaustividade de Int já é Fatia 1** (Int é infinito — só um `_`/ω
  top-level exaure; literais e ranges são gap-preserving, o `D` os dropa, testemunha `_`). O que a
  Fatia 2 acrescenta é **precisão**: (a) **testemunha concreta** (`10` em vez de `_` para `0..=9`),
  (b) **redundância entre ranges sobrepostos** (`5` dominado por `0..=9`) — exige **interval-splitting**
  (`S` parte a reta em intervalos-átomo, bordas nos endpoints Int-literais, `parser.dart:1858-1861`).
  ⚠️ **`BigInt`**: bordas de `i64` wrappam no `int` do Dart. Precedente: rustc `usefulness`. (Enquanto
  Fatia 2 não chega, um `Range` NÃO-fechado-por-`_` cai em `match-exhaustiveness-unsupported` — ver
  §F1.4, nota sobre Range.)
- **List:** família `{Len_0, …, Len_m, Len_{≥m+1}}`, partição TOTAL (`m` = maior aridade fixa/k-de-rest
  da coluna; prefixo+sufixo à rustc slice). `S(Len_n, ·)` expande `n` colunas-elemento; o representante
  `Len_{≥m+1}` cobre `[m+1,∞)`. Fecha com ω OU rest cobrindo `[k,∞)` + comprimentos `<k` cobertos.
  Pré-condição da F5 **já paga** (LT-F6a: `_bindListPattern`, `check.dart:575-596`).
- **Float:** átomo escalar como `Int`/`String` — `_HAtom`, chave `f:${value}` (`_classify` §F1.2,
  impl `match_analysis.dart`). Na **exaustividade**, Σ é infinita ⟹ nunca completa por enumeração; só
  `_`/ω fecha, testemunha `_` (Regime 2 — `match f: Float { 1.0 => a }` é NÃO-exaustivo). Na
  **redundância**, a chave exata pega literais idênticos (`1.0, 1.0`) — **sound** porque `NaN`/`-0.0`
  não parseiam como pattern-literal (LT-F6a) e `Infinity` compara igual.
  > ⚠️ **Reconciliação (W3, 2026-07-17):** o texto anterior — *"Float evapora, não conta para
  > exaustividade, não domina"* — **contradizia** o §F1 e a implementação, e seria **perigoso**: se
  > Float "não contasse", `match f { 1.0 => a }` passaria como seguro (mentira, contra o §12-11 — a
  > PEDRA não mente). A impl (Float = átomo, decidível na Fatia 1) é a correta e honesta; este texto
  > agora a reflete (derivação da orquestração + achado do W3, não do W1 original).

### 3.3 Fatia 3 — produto + string

- **Produto (`struct`/`record`):** `Sig` de **1 construtor** (a struct), aridade = nº de campos, `S`
  expande os campos **na ordem declarada** (`TypeInfo.fields`); campo omitido / `hasRest` → ω naquela
  coluna. Pré-condição F5: o shorthand `P { x, y }` ainda dá `pattern-binder-unsupported` (débito D4
  da F4 — `check.dart:726-729`); a forma explícita `P { x: a }` funciona.
- **String:** mesmo tratamento infinito do Int (resíduo-gloss na testemunha). ⚠️ **Débito F5 a fechar
  ANTES:** `interpolated-string-pattern` — uma `Str` interpolada em pattern (`"a${x}b"`) hoje passa a
  F5 como se fosse literal constante (`check.dart:609-618`); a Str-Sig do Maranget assume literal
  CONSTANTE. Banir (relaxável a guard) é ruling do dono — `tasks.md`.

---

## 4. `FlowError` ganha `detail` + `isWarning`

A testemunha precisa viajar no diagnóstico (`… — <termo> não coberto`), e
`wildcard-covers-known-variants` é **warning**, não erro. Hoje `FlowError` é `(code, offset, length)`
(`flow.dart:56-60`). Estender:

```dart
class FlowError {
  final String code;
  final int offset;
  final int length;
  final String? detail;      // NOVO — a testemunha / os nomes engolidos
  final bool isWarning;      // NOVO — severidade

  const FlowError(this.code, this.offset, this.length,
      {this.detail, this.isWarning = false});

  String format() {
    final prefix = isWarning ? 'flow-warning' : 'flow-error';
    final tail = detail == null ? '' : ' — $detail';
    return '$prefix: $code @$offset+$length$tail';
  }
}
```

E `FlowResult.hasErrors` **muda** de `errors.isNotEmpty` (`flow.dart:91`) para:

```dart
bool get hasErrors => errors.any((e) => !e.isWarning);
```

— **espelho exato** de `CheckResult.hasErrors` (`type_table.dart:507`) e `TypeTable.hasErrors`
(`type_table.dart:444`). Delta deliberado vs `CheckError.format`, que não distingue warning.

**Zero quebra do lote 1:** todos os `FlowError` do flow-walk nascem com `detail:null, isWarning:false`
→ `format()` idêntico ao atual; o runner de goldens casa `e.code`; os `.facts` não mudam. O `detail`
é testado em **UNIT**, não no `// EXPECT-FLOW:` (o comentário-âncora casa só o code).

O `_err` do walker ganha um irmão para severidade/detalhe:

```dart
void _err(String code, ast.AstNode node) =>
    errors.add(FlowError(code, node.offset, node.length));
void _errAt(String code, int offset, int length, {String? detail, bool warn = false}) =>
    errors.add(FlowError(code, offset, length, detail: detail, isWarning: warn));
```

---

## 5. Diagnósticos: nomes, spans, severidade, guard

| code                              | severidade | span                    | quando                                             |
|-----------------------------------|------------|-------------------------|----------------------------------------------------|
| `match-not-exhaustive`            | erro       | `MatchExpr` (o nó todo) | `U(P_unguarded, (ω)) útil`; `detail` = testemunha  |
| `unreachable-match-arm`           | erro       | `arm.pattern`           | braço unguarded `i` com `¬U(P_{<i}, row_i)`        |
| `match-exhaustiveness-unsupported`| **erro**   | `MatchExpr` (o nó todo) | veredito depende de tipo não-modelado que nenhum `_` fecha (I7 / §12-11) |
| `wildcard-covers-known-variants`  | **warning**| `arm.pattern`           | §6 (opcional na fatia 1)                            |

- **Span de `unreachable-match-arm` = `arm.pattern`** (não o `MatchArm`): `MatchArm` **não é
  `AstNode`** (`ast.dart:735`, como `Param`) — não tem `offset`/`length` próprios. `arm.pattern` é um
  `Pattern extends AstNode` (`ast.dart:630`) e aponta exatamente onde o braço morto começa.
- **`match-exhaustiveness-unsupported`** — nome na família `for-binder-unsupported` /
  `builtin-member-unsupported` / `pattern-binder-unsupported`; span = `MatchExpr` (é sobre a
  decidibilidade do `match` INTEIRO, não de um braço); **ERRO** (bloqueia F7 — a "não sei" honesta do
  §12-11 não pode virar Kernel; um `match` que talvez caia sem casar não emite). `detail` opcional
  nomeia o tipo/forma não-modelado (`"List<Int> exige partição por comprimento (fatia 3)"`).
- **Severidade dos dois erros = erro** (não warning): sem `#if`/conditional-compilation na língua,
  braço morto nunca é intencional, e coere com exaustividade-é-erro. (Java=erro; ruling do dono
  registrado no lote 1 §_severidade.) As severidades PODEM divergir no futuro — por isso o campo.
- **Guard (I6):** braço guarded fora de `P` e fora das queries. `5..5`/`9..3` (range vazio, parseiam)
  ⟹ braço morto por vacuidade — mas isso é **fatia 2** (range). Na fatia 1 não há range.

---

## 6. `wildcard-covers-known-variants` (warning — opcional na fatia 1)

Sai da **mesma** especialização de `U`, sem query nova. Dispara quando: braço **ω top-level**,
unguarded, VIVO, sobre coluna `SealedSig` de um **enum DECLARADO** (só ele — `Bool`/`T?`/`Result` não
ganham variantes novas; a razão do warning é "você adicionou uma variante e o `_` a engoliu em
silêncio"). Os nomes engolidos = `{v ∈ Σ | U(rows_{<i}, v(ω…)) útil}` (variantes que ESTE ω passou a
cobrir e nenhum braço anterior cobria). `Bind` conta como ω. `detail` = os nomes.

> **Fatia 1 pode entregar sem ele** (os dois erros são o must-have). Documentado aqui porque é a
> mesma maquinaria de `U`; landa junto ou logo após, sem redesenho.

---

# §F1 — Fatia 1: design de implementação concreto

> Escopo: `Sig` para Enum/Option/Result/Bool + **exaustividade escalar infinita** (Int/String/Float
> literais); `ω` = Wildcard/Bind; `match x {}` sobre esses; testemunha + printer; os **dois erros** +
> `match-exhaustiveness-unsupported`; guard não conta. Range/List/produto → §F1.4 (o erro honesto do
> §12-11, não silêncio).

## F1.1 Módulo, estruturas de dados, assinaturas

**Módulo novo:** `compiler/lib/frontend/analysis/match_analysis.dart`. Imports: `ast.dart`,
`type.dart` (`Type`, `substitute`, `NamedType`, `BuiltinType`, `OptionalType`, `BoolType`,
`NeverType`, `TypeParamType`), `type_table.dart` (`TypeTable`, `TypeInfo`, `VariantInfo`, `TypeKind`),
e `flow.dart` (`FlowError`).

### A matriz e as linhas

A matriz é uma **lista de colunas-tipo** (paralela, compartilhada por todas as linhas — I5) + **linhas
de patterns**. Trabalho **direto sobre `ast.Pattern`** (sem IR normalizado à parte: o conjunto da
fatia 1 é pequeno, e `headCtor`/`subPatterns` dispatcham na hora — evita uma cópia da árvore).

```dart
/// Matriz de patterns P (Maranget §3.1). `colTypes` tem o tipo de CADA coluna
/// (I5 — dirigida pelo tipo, nunca re-tipa); `rows[k].length == colTypes.length`.
class _Matrix {
  final List<Type> colTypes;
  final List<List<ast.Pattern>> rows;
  _Matrix(this.colTypes, this.rows);
  int get width => colTypes.length;
}
```

### O construtor selado (`Sig`) e o `Ctor`

```dart
/// Um construtor do tipo da coluna: nome canônico + tipos dos argumentos.
/// Aridade = argTypes.length. Ex.: Ctor('some', [T]); Ctor('none', []);
/// Ctor('ok', [T]); Ctor('true', []); Ctor(v.name, [subst(payload_i)]).
class _Ctor {
  final String name;
  final List<Type> argTypes;
  const _Ctor(this.name, this.argTypes);
  int get arity => argTypes.length;
}

/// A tabela §4 selada. `of()` é o ÚNICO ponto que sabe a família do tipo.
sealed class _Sig {
  const _Sig();
  /// Todos os construtores DO TIPO (fechados). Vazio p/ Empty/Opaque.
  List<_Ctor> get ctors;
  /// Σ_present ⊇ todos os construtores do tipo? (Maranget "signature complète")
  bool isComplete(Set<String> present);
}

class _SealedSig extends _Sig {
  @override final List<_Ctor> ctors;
  const _SealedSig(this.ctors);
  @override
  bool isComplete(Set<String> present) => ctors.every((c) => present.contains(c.name));
}

/// Never — Σ = ∅, completa por VACUIDADE (`match n: Never {}` exaure).
class _EmptySig extends _Sig {
  const _EmptySig();
  @override List<_Ctor> get ctors => const [];
  @override bool isComplete(Set<String> _) => true;
}

/// Int/String/Float/List/produto: NÃO selado. NUNCA "completa" por enumeração
/// (Σ infinita ou não-modelada). O veredito contra ela sai do ramo `D` — a
/// estrutura só é *tocada* se o `D` deixa gap E há pattern estrutural (§F1.4).
class _OpaqueSig extends _Sig {
  const _OpaqueSig();
  @override List<_Ctor> get ctors => const [];
  @override bool isComplete(Set<String> _) => false;
}
```

### A testemunha (`Wit`) e o relatório

```dart
/// Testemunha de não-cobertura — sobe da recursão de U (Maranget §3.1).
sealed class _Wit {}
/// `_` : um valor de [type] que nenhuma linha casa (coluna ω / opaca-vazia).
class _WWild extends _Wit { final Type type; _WWild(this.type); }
/// `.some(_)`, `.ok(.none)`, `true` : construtor + testemunhas dos argumentos.
class _WCtor extends _Wit { final _Ctor ctor; final List<_Wit> args; _WCtor(this.ctor, this.args); }

/// O que o walker consome (item 5).
class MatchReport {
  /// match-not-exhaustive / unreachable-match-arm / match-exhaustiveness-unsupported / warning.
  final List<FlowError> diagnostics;
  final Set<ast.MatchArm> deadArms;    // braços redundantes — o walker os pula no DA
  const MatchReport(this.diagnostics, this.deadArms);
}
```

### A classificação de cabeça (`_Head`) — o eixo do §12-11

A decisão do §12-11 (lacuna=erro, nunca silêncio nem falsa-acusa) mora numa **classificação de 4 vias**
da cabeça de cada pattern. `ω` fecha qualquer coluna; `_HCtor` é selado (decidível); `_HAtom` é literal
escalar (Σ infinita, decidível por Maranget §3.2 — testemunha `_`); `_HStruct` é forma cuja **estrutura
a fatia não modela** (Range/List/Struct/Record) — só o ramo `D` pode fechá-la; se não fechar, é o erro
honesto.

```dart
sealed class _Head {}
class _HWild   extends _Head {}                         // ω  (Wildcard/Bind)
class _HCtor   extends _Head { final String name; _HCtor(this.name); }  // selado: enum/some/none/ok/err/true/false
class _HAtom   extends _Head { final String key;  _HAtom(this.key);  }  // literal escalar Int/Str/Float (aridade 0, Σ∞)
class _HStruct extends _Head {}                          // Range/List/Struct/Record — estrutura NÃO-modelada
```

### Assinaturas de `U`/`S`/`D` e da entrada

```dart
/// Entrada única, chamada do walker (flow.dart:721). `scrutineeType` = _typeOf(n.scrutinee).
MatchReport analyzeMatch(ast.MatchExpr node, Type scrutineeType, TypeTable types);

// internas (dentro de uma classe _MatchAnalyzer que carrega `types`):
_Sig       _sigOf(Type colType);
_Head      _classify(ast.Pattern p, _Sig sig);          // a 4-vias acima
List<ast.Pattern> _subPatterns(ast.Pattern p, int arity);
_Matrix    _specialize(_Ctor c, _Matrix p);             // S(c, P) — só ctor selado
_Matrix    _specializeAtom(String key, _Matrix p);      // S(literal, P) — redundância escalar
_Matrix    _default(_Matrix p);                          // D(P) — só "é ω?", sempre computável
Set<String> _presentSealed(_Matrix p);                   // nomes de ctor selado presentes (col 0)
bool       _columnHasStruct(_Matrix p);                  // col 0 tem alguma cabeça _HStruct?
List<_Wit>? _useful(_Matrix p, List<ast.Pattern> q);     // U(P, q); null=inútil; pode throw _MatchUnsupported
```

`_useful` devolve **`List<_Wit>?`**: `null` = `q` inútil (exaustivo/não há testemunha); não-null = o
vetor-testemunha (comprimento = `p.width`; base útil = `<_Wit>[]`). **OU lança `_MatchUnsupported`** —
o único caminho para a "não sei" honesta do §12-11 (`class _MatchUnsupported implements Exception { const
_MatchUnsupported(); }`).

## F1.2 `_sigOf` + o split do `Sig` fechado

**`_sigOf`** — o único lugar que conhece a família (a tabela §4 em código):

```dart
_Sig _sigOf(Type t) {
  if (t is BoolType) {
    return const _SealedSig([_Ctor('true', []), _Ctor('false', [])]);
  }
  if (t is OptionalType) {                      // T?  ≡  Option<T> (§4.6)
    return _SealedSig([_Ctor('some', [t.inner]), const _Ctor('none', [])]);
  }
  if (t is BuiltinType && t.kind == BuiltinKind.result) {  // Result<T,E> = args[0],args[1]
    return _SealedSig([_Ctor('ok', [t.args[0]]), _Ctor('err', [t.args[1]])]);
  }
  if (t is NeverType) return const _EmptySig();
  if (t is NamedType) {
    final info = types.of(t.decl);
    if (info != null && info.kind == TypeKind.enum_ && info.variants != null) {
      final subst = info.substFor(t.args);      // MESMA máquina do _bindEnumPattern (check.dart:688)
      return _SealedSig([
        for (final v in info.variants!)
          _Ctor(v.name, [for (final p in v.payload) substitute(p, subst)]),
      ]);
    }
  }
  return const _OpaqueSig();                    // Int/Str/Float/List/struct/record → fatia 2/3
}
```

> `substitute`/`substFor` são exatamente `check.dart:688-690` — `Result<Int,String>.ok(v)` dá `v :
> Int` porque o payload do enum é substituído pelos type-args. Para `Option`/`Result`/`Bool` o
> payload já É o tipo concreto (`inner`/`args`), sem `TypeInfo`.

**`_classify`** — normalização superfície→cabeça (§2). É **onde o §12-11 se decide**: literal escalar
= átomo decidível; Range/List/Struct = estrutura não-modelada. **Não lança aqui** — a decisão de erro é
do `_useful` (só depois de saber que o `D` deixou gap):

```dart
_Head _classify(ast.Pattern p, _Sig sig) {
  switch (p) {
    case ast.WildcardPattern _:
    case ast.BindPattern _:
      return _HWild();                          // ω — fecha qualquer coluna
    case ast.EnumPattern n:
      return _HCtor(n.variant);                 // .some/.none/.ok/.err/.Variante (coluna selada)
    case ast.LiteralPattern n when n.literal is ast.BoolLit:
      return _HCtor((n.literal as ast.BoolLit).value ? 'true' : 'false');
    case ast.LiteralPattern n when n.literal is ast.NilLit:
      return _HCtor('none');                    // `nil` ≡ .none do Option (parser.dart:1892)
    case ast.LiteralPattern n:                  // IntLit / StringLit / FloatLit — átomo escalar
      return _HAtom(_atomKey(n.literal));       // Σ INFINITA: decidível sem enumerar (Maranget §3.2)
    // Estrutura que a fatia 1 NÃO modela — Range/List/Struct/Record (e Rest inline).
    case ast.RangePattern _:                    // (ver nota Range em §F1.4 — promovível a átomo)
    case ast.ListPattern _:
    case ast.RestPattern _:
    case ast.StructPattern _:
    case ast.RecordPattern _:
      return _HStruct();
    case ast.ErrorPattern _:                    // parser já reportou (I3 aborta antes); defensivo
      return _HStruct();
  }
}
```

`_atomKey` = a chave de igualdade do literal (`'42'`, `'"foo"'`, `'3.14'`) — usada só para `_HAtom` se
igualar a `_HAtom` na especialização escalar de redundância (`_specializeAtom`).

**`_subPatterns`** — os argumentos do construtor casado (para o `S`):

```dart
List<ast.Pattern> _subPatterns(ast.Pattern p, int arity) {
  if (p is ast.EnumPattern) return p.subpatterns;   // arity garantida pela F5 (pattern-arity-mismatch)
  // BoolLit/NilLit têm aridade 0; ω é tratado no _specialize (ω^arity).
  return const [];
}
```

**`_specialize` (`S(c,P)` — selado)**, **`_specializeAtom` (`S(literal,P)`)**, **`_default` (`D(P)`)**,
e os predicados de coluna. Note que `_default` só pergunta "é ω?" — **nunca** precisa modelar a
estrutura, e por isso o veredito sempre existe (I7):

```dart
_Matrix _specialize(_Ctor c, _Matrix p) {       // ctor SELADO — coluna 0 só tem _HWild/_HCtor
  final sig = _sigOf(p.colTypes[0]);
  final newRows = <List<ast.Pattern>>[];
  for (final row in p.rows) {
    final h = _classify(row[0], sig);
    if (h is _HWild) {                           // ω → ω^arity
      newRows.add([...List.filled(c.arity, _wild(row[0])), ...row.sublist(1)]);
    } else if (h is _HCtor && h.name == c.name) {// c(sub…) → sub… ++ resto
      newRows.add([..._subPatterns(row[0], c.arity), ...row.sublist(1)]);
    }                                            // c'≠c → descarta
  }
  return _Matrix([...c.argTypes, ...p.colTypes.sublist(1)], newRows);
}

_Matrix _specializeAtom(String key, _Matrix p) { // literal escalar (aridade 0) — redundância
  final sig = _sigOf(p.colTypes[0]);
  final newRows = <List<ast.Pattern>>[];
  for (final row in p.rows) {
    final h = _classify(row[0], sig);
    if (h is _HWild) {
      newRows.add(row.sublist(1));               // ω casa o literal
    } else if (h is _HAtom && h.key == key) {
      newRows.add(row.sublist(1));               // mesmo literal
    } else if (h is _HStruct) {
      throw const _MatchUnsupported();           // ex.: `5` vs `0..=9` — precisa de intervalo (fatia 2)
    }                                            // _HAtom(other)/_HCtor(≠) → descarta
  }
  return _Matrix(p.colTypes.sublist(1), newRows);
}

_Matrix _default(_Matrix p) {                     // SEMPRE computável — só "é ω?"
  final sig = _sigOf(p.colTypes[0]);
  final newRows = [
    for (final row in p.rows)
      if (_classify(row[0], sig) is _HWild) row.sublist(1),
  ];
  return _Matrix(p.colTypes.sublist(1), newRows);
}

Set<String> _presentSealed(_Matrix p) {           // só ctors selados (coluna selada)
  final sig = _sigOf(p.colTypes[0]);
  return {
    for (final row in p.rows)
      if (_classify(row[0], sig) case _HCtor(:final name)) name,
  };
}

bool _columnHasStruct(_Matrix p) {
  final sig = _sigOf(p.colTypes[0]);
  return p.rows.any((row) => _classify(row[0], sig) is _HStruct);
}
```

> `_wild(row[0])` = um `WildcardPattern` sintético para preencher a expansão ω^arity — pode reusar o
> span de `row[0]` (nunca é reportado; é maquinaria interna).

## F1.3 A recursão de `U` e a construção da testemunha

```dart
List<_Wit>? _useful(_Matrix p, List<ast.Pattern> q) {
  // Caso base (0 colunas): útil ⟺ nenhuma linha em P (Maranget §3.1).
  if (p.width == 0) return p.rows.isEmpty ? <_Wit>[] : null;

  final sig = _sigOf(p.colTypes[0]);
  final qh = _classify(q[0], sig);              // cabeça da QUERY

  // --- q₀ é construtor/átomo concreto: ocorre só em REDUNDÂNCIA (query = braço) ---
  if (qh is _HCtor) {
    final c = sig.ctors.firstWhere((x) => x.name == qh.name);
    final w = _useful(_specialize(c, p), [..._subPatterns(q[0], c.arity), ...q.sublist(1)]);
    return w == null ? null : _rebuild(c, w);
  }
  if (qh is _HAtom) {                            // literal escalar como query
    final w = _useful(_specializeAtom(qh.key, p), q.sublist(1));
    return w == null ? null : [_WWild(p.colTypes[0]), ...w];   // redundância ignora a testemunha
  }
  if (qh is _HStruct) throw const _MatchUnsupported();  // query estrutural → redundância indecidível

  // --- q₀ = ω (sempre o caso da EXAUSTIVIDADE; e braço-ω na redundância) ---
  if (sig is _SealedSig || sig is _EmptySig) {
    final present = _presentSealed(p);
    if (sig.isComplete(present)) {
      // Σ completa. Testemunha CONCRETA de qualquer ramo VENCE um ramo unsupported
      // (uma não-exaustividade definitiva é resposta melhor que "não sei" — §12-11).
      var anyUnsupported = false;
      for (final c in sig.ctors) {
        try {
          final w = _useful(_specialize(c, p),
              [...List.filled(c.arity, q[0] /* ω */), ...q.sublist(1)]);
          if (w != null) return _rebuild(c, w);
        } on _MatchUnsupported {
          anyUnsupported = true;                 // guarda; segue procurando testemunha concreta
        }
      }
      if (anyUnsupported) throw const _MatchUnsupported();
      return null;                               // todos os ramos exaustos → EXAUSTIVO
    } else {
      final w = _useful(_default(p), q.sublist(1));
      if (w == null) return null;
      return [_missing(sig, present), ...w];      // variante FORA de Σ, ω-preenchida
    }
  } else {
    // --- coluna OPAQUE contra ω. O ramo default SEMPRE decide o veredito. ---
    final w = _useful(_default(p), q.sublist(1));
    if (w == null) return null;                  // gap fechado (aqui ou adiante) → EXAUSTIVO
    //                                              — estrutura NUNCA foi tocada.
    // Há gap NESTA coluna opaca:
    if (_columnHasStruct(p)) throw const _MatchUnsupported();  // §12-11: Range/List/Struct fecharia? não sei
    // Só ω + átomos escalares ⟹ Σ infinita, testemunha `_` HONESTA (um valor ≠ literais presentes):
    return [_WWild(p.colTypes[0]), ...w];
  }
}

/// Empacota os `c.arity` primeiros wits em `c(...)`; o resto são as colunas-cauda.
List<_Wit> _rebuild(_Ctor c, List<_Wit> w) =>
    [_WCtor(c, w.sublist(0, c.arity)), ...w.sublist(c.arity)];

/// Um construtor do tipo que NÃO está em `present`, com args ω. (SealedSig
/// incompleta ⟹ existe ao menos um.)
_Wit _missing(_Sig sig, Set<String> present) {
  final c = sig.ctors.firstWhere((x) => !present.contains(x.name));
  return _WCtor(c, [for (final at in c.argTypes) _WWild(at)]);
}
```

**Como a testemunha-cabeça sai do resíduo do split:** no ramo-Σ-completa, `_rebuild` reconstrói o
construtor cujo sub-witness veio útil (a não-cobertura estava DENTRO de `c` — ex.: `.ok(false)`). No
ramo-incompleta selado, a cabeça é **fabricada** de fora de Σ (`_missing`). Na coluna opaca escalar, a
cabeça é `_WWild` (`_` — "um valor da coluna ≠ os literais listados", honesto por Maranget §3.2).
**Caso base:** `p.width == 0` com `rows` vazio devolve `<_Wit>[]` — o vetor-testemunha vazio de onde a
recursão começa a empilhar cabeças.

**Drivers** (dentro de `analyzeMatch`. Exaustividade e redundância têm `try` SEPARADOS — o
`_MatchUnsupported` da exaustividade é o ERRO honesto (§12-11); o da redundância só ABSTÉM aquele
braço, sem mentir sobre a segurança do `match`):

```dart
MatchReport analyzeMatch(ast.MatchExpr node, Type scrutineeType, TypeTable types) {
  final a = _MatchAnalyzer(types);
  final diags = <FlowError>[];
  final dead = <ast.MatchArm>{};

  // 1. Exaustividade: P = braços UNGUARDED (I6), query = (ω).
  final unguarded = [for (final arm in node.arms) if (arm.guard == null) [arm.pattern]];
  try {
    final w = a._useful(_Matrix([scrutineeType], unguarded), [_wildAt(node)]);
    if (w != null) {
      diags.add(FlowError('match-not-exhaustive', node.offset, node.length,
          detail: '${a._print(w.single)} não coberto'));
    }
  } on _MatchUnsupported {
    // §12-11: o veredito dependia de tipo não-modelado que nenhum `_` fechou.
    // A "não sei" HONESTA — nunca silêncio, nunca `non-exhaustive` chutado.
    diags.add(FlowError('match-exhaustiveness-unsupported', node.offset, node.length));
    return MatchReport(diags, dead);            // sem redundância sobre match indecidível
  }

  // 2. Redundância: para cada braço unguarded i, P_{<i} = unguarded anteriores.
  final prior = <List<ast.Pattern>>[];
  for (final arm in node.arms) {
    if (arm.guard != null) continue;            // I6: guarded nunca acusado
    try {
      final useful = a._useful(_Matrix([scrutineeType], [...prior]), [arm.pattern]);
      if (useful == null) {
        diags.add(FlowError('unreachable-match-arm', arm.pattern.offset, arm.pattern.length));
        dead.add(arm);                          // morto NÃO entra em P_{<j} dos seguintes
      } else {
        prior.add([arm.pattern]);
      }
    } on _MatchUnsupported {
      // Redundância deste braço indecidível (ex.: `5` vs range `0..=9`). ABSTÉM —
      // não acusa nem inocenta; o braço segue vivo em P_{<j}. NÃO é mentira de
      // exaustividade (a #1 já deu veredito): é incompletude conhecida do LINT de
      // redundância (o braço redundante ainda RODA correto). Ver nota-dono §F1.4.
      prior.add([arm.pattern]);
    }
  }
  return MatchReport(diags, dead);
}
```

> **`_wildAt(node)`** = um `WildcardPattern` sintético para a query de exaustividade (só precisa de um
> span qualquer; use o do `node`). **`_print`** = §F1 printer (abaixo).

## F1.4 CRÍTICO — o corte da fatia 1 sob o §12-11 (o que W0 vai auditar)

**Premissa (mudou 2026-07-17, ruling do dono, spec 014 §12-11):** tipo não-modelado que um `_` não
fecha → **`match-exhaustiveness-unsupported`, ERRO** — a "não sei" honesta. **Nunca silêncio** (mentiria
que o `match` é seguro) e **nunca** um veredito chutado (falsa-acusaria `non-exhaustive` num `match`
talvez exaustivo). O bail-silencioso do desenho anterior está MORTO.

**A chave que evita falsa-acusação — `match n { 0 => a, _ => b }` tem de passar VERDE:** o ramo default
`D` decide o veredito consultando **apenas "esta cabeça é ω?"** (`_HWild`), pergunta respondível para
QUALQUER pattern sem modelar nada. Logo **um `_`/ω sempre fecha a coluna e entrega veredito sem tocar a
estrutura**. O erro só nasce quando o `D` deixa gap E a coluna tem forma estrutural que poderia — ou
não — ter fechado esse gap, e a fatia não sabe. Três regimes:

**Regime 1 — coluna fechada por `_`/ω (o `D` decide, estrutura nunca inspecionada).**
No `_useful`, a coluna opaca com ω-query computa `w = _useful(_default(p), q_resto)` ANTES de qualquer
teste de estrutura. Se `w == null` (o `_`/ω sobreviveu ao `D` e fechou tudo) → **retorna null =
EXAUSTIVO**, e `_columnHasStruct` nunca é chamado. Passa verde mesmo com struct/list/range na coluna:
- `match n: Int { 0 => a, _ => b }` → `D` mantém a linha `_` → gap fechado → **VERDE**. (O literal `0`
  nem é classificado no caminho do veredito.)
- `match p: Point { Point{x, y} => a, _ => b }` → idem, o `_` fecha → **VERDE**. O `Point{x,y}` (struct,
  estrutural) NÃO é inspecionado.
- `match r: Result<Point,E> { .ok(_) => a, .err(e) => b }` → Σ(Result) completa → especializa `ok`
  (coluna Point só com `_`) → `D` fecha → exaustivo; `err` idem → **VERDE**.

**Regime 2 — coluna escalar infinita (Int/String/Float) SEM `_`/ω, só literais.** Decidível pelo
Maranget §3.2 SEM enumerar: Σ é infinita ⟹ nunca completa ⟹ ramo default ⟹ testemunha `_` (um valor ≠
os literais listados — HONESTO). Isto é **Fatia 1**, não defere:
- `match n: Int { 0 => a }` → `_columnHasStruct` = false (literal é `_HAtom`, não `_HStruct`) → testemunha
  `_WWild(Int)` → **`match-not-exhaustive`, `_ não coberto`**. (Responde a pergunta do coordenador: **o
  `U` genérico JÁ dá a testemunha "um Int ≠ 0" — Fatia 1 decide, não defere.**)
- `match n: Int { }` (vazio) → `D([])` = `[]` → `U([],())` útil, sem struct → **`match-not-exhaustive`,
  `_`**. Correto.

**Regime 3 — gap numa coluna cuja ESTRUTURA a fatia não modela (`_HStruct`: Range/List/Struct/Record).**
`w != null` (há gap) E `_columnHasStruct(p)` → **`throw _MatchUnsupported`** → `match-exhaustiveness-
unsupported` para o `match`. É o §12-11 literal: não sabemos se a estrutura fecharia o gap, então dizemos
"não sei" (não silêncio, não chute):
- `match p: Point { Point{x: 0} => a }` → `D` deixa gap E coluna tem struct → **`match-exhaustiveness-
  unsupported`**. (Talvez seja não-exaustivo com testemunha `Point{x: _}` x≠0 — mas produzir isso exige
  expansão de campos, Fatia 3. Honesto: "não modelo produto ainda".)
- `match xs: List { [] => a, [_, ..] => b }` → gap pelo `D` (ambos estruturais dropados) E struct →
  **unsupported**. (É EXAUSTIVO de fato, mas provar exige partição por comprimento — Fatia 3. Dizer
  `non-exhaustive` seria FALSA-ACUSAÇÃO; calar seria mentira. `unsupported` é a única resposta honesta.)

**Onde fica a linha Fatia-1/Fatia-2 (crave):**
- **Literais escalares soltos** (`match n { 0 => a }` sem `_`) → **Fatia 1 decide** (`non-exhaustive`,
  `_`). O `U` genérico já dá a testemunha; deferir seria dizer "não sei" quando sabemos.
- **`_`/ω top-level (ou via ctor selado)** → **sempre veredito** (verde ou concreto), qualquer estrutura.
- **Range / List / Struct / Record num gap não-fechado** → **`match-exhaustiveness-unsupported`** até a
  fatia que os modele (Range→Fatia 2; List/produto→Fatia 3).

> **Nota sobre Range (decisão togglável — sua, coordenador):** classifiquei `RangePattern` como
> `_HStruct` (defere via unsupported), seguindo seu "Range claramente defere". **Mas a rigor Range é
> promovível a `_HAtom` já na Fatia 1:** Int é infinito, então um range (span finito) é gap-preserving
> igual a um literal — `match n { 0..=9 => a }` (sem `_`) É não-exaustivo (10 descoberto) e a testemunha
> `_` é honesta. O único motivo real de Range deferir é **redundância** entre ranges sobrepostos
> (`5` ⊂ `0..=9`), que precisa de intervalo. Se topar, mover `RangePattern` para o braço `_HAtom` de
> `_classify` promove a exaustividade-com-range para Fatia 1 (mais informativo: `non-exhaustive` em vez
> de `unsupported`), deferindo só a redundância-de-range. Recomendo a promoção; deixei conservador por
> respeitar seu escopo. Trade-off explícito, sua escolha.

**Prova de que a Fatia 1 nunca falsa-acusa nem estoura (auditoria W0):**
1. `_default` e `_columnHasStruct` só perguntam "é `_HWild`?" / "é `_HStruct`?" — totais para todo
   `Pattern`, sem modelar estrutura ⟹ **nunca estoura** (nenhum `_classify` lança).
2. `_MatchUnsupported` só nasce (a) no Regime 3, DEPOIS de `w != null` confirmar gap real (um `_`/ω o
   teria fechado antes — Regime 1); (b) na redundância de query estrutural/átomo-vs-range (abstém, não
   acusa). ⟹ **nunca falsa-acusa** `non-exhaustive`.
3. `match-not-exhaustive` só sai quando `U` roda o Maranget EXATO sobre domínio decidível (selado,
   Never, ou escalar-infinito-só-átomos) ⟹ testemunha sempre honesta e produzível.
   **Não há caminho onde a Fatia 1 conclua veredito com informação que não tem** — ou decide, ou diz
   `unsupported`. É a PEDRA do §12-11.

## F1.5 Integração no walker (`flow.dart:721`) — consumo do `MatchReport`

`_matchExpr` do flow-walk hoje só faz o merge de DA sobre os braços (flow.dart:721-737). Passa a
chamar `analyzeMatch`, injetar os diagnósticos e **pular os braços mortos** no DA:

```dart
void _matchExpr(ast.MatchExpr n) {
  _expr(n.scrutinee);

  // Análise Maranget — SÓ aqui (não passe irmão): match em código MORTO nunca
  // chega a _matchExpr (o walker para no 1º unreachable — anticascata do lote 1,
  // flow.dart:_unreachableReported). Match aninhado é grátis pela visita recursiva.
  final report = analyzeMatch(n, _typeOf(n.scrutinee), _check.types);
  errors.addAll(report.diagnostics);

  final entry = _da;
  Set<Object>? merged;
  for (final arm in n.arms) {
    if (report.deadArms.contains(arm)) continue;   // braço morto NÃO roda:
    //  fora do ∩ é MAIS PRECISO (não é só anticascata) — um braço inalcançável
    //  não contribui atribuição nenhuma ao caminho vivo, e descer nele reportaria
    //  cascata dentro de código morto (a região já foi flagada em deadArms).
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
```

**Notas de integração:**
- **Anticascata de código morto = estrutural, grátis.** `_matchExpr` só é chamado de `_expr`, que só
  roda em stmt VIVO (o `_unreachableReported` do lote 1 para o walk do bloco antes). Um `match` em
  código morto nunca é analisado — exatamente o que o gate quer (morto ⟹ programa vermelho por
  `unreachable-code`; não empilhar `match-not-exhaustive` em cima).
- **Braço morto não é walkado** (`continue` antes de `_expr(arm.body)`): seu corpo é inalcançável;
  descer reportaria erros-cascata (use-before-assign, nº8 de closures mortas) dentro de código morto.
  O `unreachable-match-arm` já é o UM erro daquela região. Consistente com "nº8 total só em programa
  verde" (lote 1): um `match` com braço morto deixa o programa vermelho, e a F7 nunca lê a nº8.
- **`analyzeMatch` recebe `_check.types`** (a `TypeTable` do `CheckResult`, `type_table.dart:457`) e o
  tipo do escrutínio (`_typeOf(n.scrutinee)`, a nº1). Não recebe `exprTypes` (I5).
- **Empty-match verde:** `match x {}` passa a F5 muda (`check.dart:1756` — `acc ?? ErrorType`, sem
  erro), então o programa chega verde à F6 mesmo com `exprTypes[matchExpr] = ErrorType`. `_matchExpr`
  não lê o tipo do match (lê o do **escrutínio**, que é real em programa verde). A exaustividade pega
  o vazio corretamente (§F1.4 caso 1). **Não** viola I3: o escrutínio tem tipo real; só o RESULTADO do
  match vazio é `ErrorType`, e ninguém o consulta no caminho vivo.

## F1.6 Printer de superfície (`_print`)

Testemunha → sintaxe de pattern do Itá:

```dart
String _print(_Wit w) => switch (w) {
  _WWild _ => '_',
  _WCtor c => c.ctor.arity == 0
      ? _ctorSurface(c.ctor.name)                        // .none / true / .Red
      : '${_ctorSurface(c.ctor.name)}(${c.args.map(_print).join(', ')})',  // .some(_), .ok(.none)
};

String _ctorSurface(String name) => switch (name) {
  'true'  => 'true',
  'false' => 'false',
  _       => '.$name',                                    // enum/some/none/ok/err → prefixo `.`
};
```

Exemplos (o `detail` do `match-not-exhaustive`): `.some(_) não coberto`, `.none não coberto`,
`.err(_) não coberto`, `false não coberto`, `.Blue não coberto`, `.ok(false) não coberto`.

---

## Apêndice — casos-âncora da fatia 1 (para os testes do implementador)

| fonte                                                            | resultado esperado                                 |
|-----------------------------------------------------------------|----------------------------------------------------|
| `match b: Bool { true => a }`                                    | `match-not-exhaustive`, `false não coberto`        |
| `match b: Bool { true => a, false => b }`                        | verde                                              |
| `match o: Int? { .some(x) => a }`                               | `match-not-exhaustive`, `.none não coberto`        |
| `match o: Int? { .some(x) => a, nil => b }`                     | verde (`nil` normaliza p/ `none`)                  |
| `match o: Int? { .some(x) => a, .none => b, nil => c }`         | `unreachable-match-arm` @ `nil`                    |
| `match r: Result<Bool,E> { .ok(true) => a, .err(_) => b }`      | `match-not-exhaustive`, `.ok(false) não coberto`   |
| `match c: Color { .Red => a, .Green => b }` (enum 3 variantes)  | `match-not-exhaustive`, `.Blue não coberto`        |
| `match c: Color { _ => a }`                                     | verde (ω exaure); warning §6 se optar por ele      |
| `match c: Color { .Red => a, _ => b, .Green => c }`             | `unreachable-match-arm` @ `.Green`                 |
| `match n: Never { }`                                            | verde (Never exaure com 0 braços)                  |
| `match x: Int { }`                                              | `match-not-exhaustive`, `_ não coberto`            |
| `match x: Int { 0 => a }`                                       | `match-not-exhaustive`, `_ não coberto` (Regime 2 — Fatia 1 DECIDE) |
| `match x: Int { 0 => a, _ => b }`                              | **verde** (Regime 1 — o `_` fecha; literal nem inspecionado) |
| `match r: Result<Int,E> { .ok(0) => a, .err(e) => b }`         | `match-not-exhaustive`, `.ok(_) não coberto`       |
| `match r: Result<Int,E> { .ok(_) => a, .err(e) => b }`         | verde (Regime 1 — `_` fecha a coluna Int em `.ok`) |
| `match p: Point { Point{x: 0} => a }`                           | `match-exhaustiveness-unsupported` (Regime 3 — produto, Fatia 3) |
| `match p: Point { Point{x, y} => a, _ => b }`                  | **verde** (Regime 1 — `_` fecha; struct nem inspecionado) |
| `match xs: List<Int> { [] => a, [_, ..] => b }`               | `match-exhaustiveness-unsupported` (Regime 3 — List, Fatia 3) |
| `match xs: List<Int> { [] => a, _ => b }`                     | **verde** (Regime 1 — `_` fecha) |
| `match n: Int { 0..=9 => a }`                                  | conservador: `match-exhaustiveness-unsupported`; c/ promoção de Range (nota §F1.4): `non-exhaustive`, `_` |
| `match x: Bool { true if cond => a, false => b }`               | `match-not-exhaustive`, `true não coberto` (I6)    |
