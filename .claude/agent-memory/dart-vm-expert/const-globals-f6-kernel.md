---
name: const-globals-f6-kernel
description: Globais 100% const-eval (modelo D-V1 da spec 014) — como materializar no Kernel v130 (pool de constantes, InstanceConstant, invariante isConst⟹inline), lazy×eager na VM, e o fork de semântica Int vm/js do avaliador const. Verificado no vendor 3.12.2 + GitHub tag 3.12.2 (2026-07-16).
metadata:
  type: reference
---

# Globais const (014 §5, modelo D-V1) → Kernel/VM — fatos confirmados

## Pool de constantes no formato binário 130 — EXISTE e é do Component
- `pkg/kernel/binary.md:150` `formatVersion = 130`; `:155-156` `List<Constant> constants` +
  `constantsMapping` (byte offsets); `:183-184` ComponentIndex tem `binaryOffsetForConstantTable(+Index)`.
- `ConstantExpression` tag 106 (`binary.md:1214-1219`) = `{fileOffset, DartType, ConstantReference}` — referencia o pool.
- Formas de valor: `IntConstant`(:1242) `DoubleConstant`(:1247) `BoolConstant`(:1237) `StringConstant`(:1252)
  `NullConstant`(:1233) `ListConstant`(:1270) **`InstanceConstant`(:1282-87)** = `{classRef, typeArguments,
  List<Pair<FieldReference, ConstantReference>>}` — serve struct-valor const E enum-com-payload (variant é classe
  após lowering, ver [[desugar-kernel-lowering]]) — **`RecordConstant`(:1327-32)**.
- `Field.fieldReference` é a key nos values de InstanceConstant (`members.dart:288-292`).

## Invariante de emissão: `isConst` ⟹ INLINE nos usos (nunca StaticGet)
- `verifier.dart:1237-1242` — `StaticGet` de Field const é PROBLEM quando `constantsAreAlwaysInlined && afterConst`.
  Idem local const: `:1197-1204`. `constantsAreAlwaysInlined = target.constantsBackend.alwaysInlineConstants`
  (`verifier.dart:220-222`), **default `true`** (`targets.dart:156`).
- `verifier.dart:737-743` — Field const TEM de ser static; `:744-768` — imutável (final/const) ⟹ SEM setterReference.
- ⟹ duas emissões válidas p/ global const do Itá: (A) estilo CFE: Field `isConst` + initializer `ConstantExpression`
  + TODO uso vira `ConstantExpression` inline; (B) Field `isFinal` static + `StaticGet` (legal, sem o invariante).

## Lazy×eager na VM (JIT) — inobservável com valor já-constante
- `runtime/vm/kernel_loader.cc` @3.12.2: `ReadInitialFieldValue()` — static com initializer ⟹ `Object::sentinel()`
  + getter lazy. **Fast path eager**: `SimpleExpressionConverter::IsSimple()` (literais Int/Double/String/Bool/Null)
  seta o valor no load. Initializer `ConstantExpression` (composto) NÃO entra no fast path — fica sentinel-lazy,
  lendo do constant table sob demanda. Com valor puro/canônico, lazy×eager é INOBSERVÁVEL (sem efeitos; identidade
  canônica preservada). Em AOT o objeto const vive no snapshot.

## Semântica Int do avaliador const — o fork vm/js é DE PRIMEIRA CLASSE no Kernel
- `pkg/kernel/lib/target/targets.dart:93-100` — `enum NumberSemantics { vm, js }`; `:151-152` default `vm`.
- CFE `pkg/front_end/lib/src/kernel/constant_int_folder.dart` @3.12.2: `VmConstantIntFolder` usa int 64 do host
  (**wrap two's complement, SEM erro**); `JsConstantIntFolder` representa como double. Nenhum modo erra em overflow.
- VM runtime: int nativo = 64-bit signed; `math.pow(2,63)` → `-9223372036854775808` (wrap) —
  `https://dart.dev/resources/language/number-representation`. Web: 53 bits de precisão.
- dart2js ERRA em literal não-representável exato em double (dart-lang/sdk#33286: "can't be represented exactly
  in JavaScript") — mas ⚠️ **wrap em compile-time pode MASCARAR**: `maxInt64+1` wrappa p/ `-2^63`, que É representável
  (potência de 2) ⟹ dart2js aceita em silêncio um valor que a aritmética JS de runtime nunca produziria.
- ⟹ recomendação dada à 014: V1 proibir overflow em const (erro; precedente Rust); resíduo Int>2^53 sem overflow
  cai na divergência Int já assentada em [[parity-js]] (ADR-0005).

## Assign como statement — custo zero
- `VariableSet` "Evaluates to the value of [value]" (`expressions.dart:268-270`; getStaticType `:286-287`);
  `InstanceSet` `:922-923` e `StaticSet` `:1490-91` idem. Embrulhar em `ExpressionStatement` (binary.md:1336)
  descarta o valor; NADA no Kernel/verifier exige consumo (`visitVariableSet` `:1207-16` só checa escopo).
  `Assign : Void` do Itá (014 §12-2) é portanto gratuito; se um desugar futuro precisar do valor, o nó Kernel já o dá.
