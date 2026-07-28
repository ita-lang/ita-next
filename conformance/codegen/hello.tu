// Passo B (spec 013 §7.4) — o menor programa que fecha o pipeline inteiro:
// `.tu` → F1..F6 → emissão → `.dill` → Dart VM. `print` de `Str` SEM interpolação
// baixa como `StringLiteral` puro (não `StringConcatenation`).

fn main() {
  print("olá")
}
