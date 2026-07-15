// Fatia D — P7: `Result<T,E>` + `?` + must-use (spec 009 §4.9 / §0.5-6).
// Os casos SEM erro estão de propósito no meio: o runner casa a lista EXATA,
// então um falso-positivo neles quebra o fixture.
// EXPECT-CHECK: try-outside-result-fn
// EXPECT-CHECK: error-type-mismatch
// EXPECT-CHECK: try-on-non-result
// EXPECT-CHECK: unused-result
// EXPECT-CHECK: arity-mismatch
// EXPECT-CHECK: type-mismatch

fn abre(caminho: String) -> Result<Int, String> => abre(caminho)

// `?` exige que a fn CORRENTE renda Result — esta rende Int.
fn semResult() -> Int { let fd = abre("/etc/hosts")? }

// `E` tem de ser IDENTICO — sem o `From` implícito do Rust, que é maquinaria
// invisível em TODO `?` (o único ponto onde o Rust fura o próprio "sem
// conversão implícita").
fn eDivergente() -> Result<Int, Float> { let fd = abre("/etc/hosts")? }

// `?` só existe sobre `Result` (P7): ausência é `guard let`/`??`/`?.`.
fn naoEResult() -> Result<Int, String> { let n = 5? }

// must-use é ERRO, não warning: sob RD-1 o bloco não rende, então isto é um
// `Result` descartado no chão — exceção não-checada com passos extras.
fn descarta() -> Result<Int, String> { abre("/etc/hosts") }

// O escape é explícito e greppável — e NÃO dispara must-use.
fn escapa() { let _ = abre("/etc/hosts") }

// Caminho feliz: o `?` desembrulha o `T` de `Result<T, E>` — `fd` é `Int`.
fn feliz() -> Result<Int, String> {
  let fd = abre("/etc/hosts")?
  let dobro: Int = fd
}

fn aridade() { let x = abre("a", "b") }

fn tipoErrado() { let x = abre(5) }
