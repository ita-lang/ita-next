// §7.4-a — RECURSÃO, a outra metade do que o two-pass compra.
//
// `fat` chama a si mesma: o corpo precisa do `Procedure` que ainda está sendo
// construído. Com as assinaturas emitidas ANTES dos corpos, o alvo já existe
// quando o corpo é andado — sem isso, o `StaticInvocation.targetReference`
// (non-nullable) não teria o que apontar e não há "preencher depois".
//
// `potencia` fecha o par com recursão + label externo: a chamada recursiva usa os
// labels (`base:`/`expoente:`), provando que o nome do named param do Kernel é
// estável entre a assinatura e TODOS os call-sites, inclusive o de dentro do
// próprio corpo.

fn fat(n: Int) -> Int => if n <= 1 => 1 else n * fat(n - 1)

fn potencia(base b: Int, expoente e: Int) -> Int =>
  if e <= 0 => 1 else b * potencia(base: b, expoente: e - 1)

fn main() {
  print("fat(5)=${fat(5)}")
  print("fat(0)=${fat(0)}")
  print("2^8=${potencia(base: 2, expoente: 8)}")
}
