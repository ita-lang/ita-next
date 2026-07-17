// Fatia A — A2/A3: os erros de boa-formação.
// EXPECT-CHECK: unknown-type
// EXPECT-CHECK: generic-arity-mismatch
// EXPECT-CHECK: duplicate-field
// EXPECT-CHECK: redundant-optional
// EXPECT-CHECK: mut-field-on-struct
// EXPECT-CHECK: mut-field-on-struct
// EXPECT-CHECK: inheritance-cycle
// EXPECT-CHECK: inheritance-cycle
struct S { x: Naoexiste }
struct G { b: Option<Int, String> }
struct D { a: Int, a: String }
struct R { v: Option<Int>? }
struct M { var m: Int }
struct N { m: mut Int }
class A : B { z: Int }
class B : A { w: Int }
