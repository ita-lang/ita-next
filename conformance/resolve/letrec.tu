// CA3 — letrec de módulo: `a` chama `b` declarada DEPOIS (forward-ref /
// recursão mútua). `b` resolve top-level, ordem textual não importa.
fn a() -> Int => b()
fn b() -> Int => 1
