// spec 005 §3.1b (correção 2026-07-14) — o `value` do guard-let vai até `pipe`,
// com só o `&&` de NÍVEL-TOPO reservado ao refino. Antes o value era `equality`,
// abaixo de `??`/`||`/`|>`/`>>`: os quatro viravam error-stmt aqui.
guard let v = a ?? b else { return }
guard let v = a |> f else { return }
guard let v = f >> g else { return }
guard let v = a || b else { return }
// o `&&` de nível-topo ainda separa value/refino, e os de cima ficam no value
guard let v = a ?? b && c else { return }
guard let v = a && b && c else { return }
// dentro de delimitador o `&&` é operador normal (a flag é resetada)
guard let v = (a && b) else { return }
guard let v = f(a && b) else { return }
