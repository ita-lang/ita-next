// CA NEGATIVO (§7.3 + ruling §12-5) — `main` com assinatura inválida.
//
// O entry-point é `fn main()`: aridade 0, sem genéricos, não-`async`, retorno
// `Void`. Qualquer outra coisa é erro do DRIVER em modo build (exit 65), não ICE.
//
// EXPECT-ERROR: invalid-main-signature

fn main(x: Int) {
  print("nunca chega aqui")
}
