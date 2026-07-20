// CA (spec 014 §11) — LT-F6c: blindagem de corpus contra `match` INSOUND.
//
// Achado 🟠3 da auditoria multi-agente de 2026-07-17: o corpus NÃO exercitava
// `match` não-exaustivo, então um `.dill` que "cai do fim" (nenhum braço casa
// em runtime) passaria VERDE — o "compila mas roda errado" que a reescrita
// existe para matar. Este CA é a rede que teria pego o buraco no dia 1: cada
// `fn` abaixo DEVE emitir o diagnóstico da LT-F6b (Maranget). É a co-verificação
// exigida pelo tasks.md — ANTES da LT-F6b a F6 não fazia exaustividade e TODAS
// passavam verde; a lista `EXPECT-FLOW` só casa PORQUE a análise existe.
//
// Um verde no MEIO (`green_wild`) é DELIBERADO: um falso-positivo nele quebraria
// a lista (a PEDRA não falsa-acusa — §12-11).
//
// EXPECT-FLOW: match-not-exhaustive
// EXPECT-FLOW: match-not-exhaustive
// EXPECT-FLOW: unreachable-match-arm
// EXPECT-FLOW: match-not-exhaustive
// EXPECT-FLOW: match-not-exhaustive
// EXPECT-FLOW: match-not-exhaustive
// EXPECT-FLOW: match-exhaustiveness-unsupported

enum Color { Red, Green, Blue }
struct Point { x: Int, y: Int }
class Ref { v: Int }

// 1. Bool não-exaustivo — falta `false` (Fatia 1, tipo fechado).
fn bool_gap(b: Bool) -> Int => match b { true => 0 }

// 2. Enum não-exaustivo — falta `.Blue` (Fatia 1, Σ conhecido).
fn enum_gap(c: Color) -> Int => match c { .Red => 0, .Green => 1 }

// 3. Arm redundante — o `_` já exaure; o `.Green` depois nunca casa (redundância).
fn redundant_arm(c: Color) -> Int => match c { .Red => 0, _ => 1, .Green => 2 }

// 4. Int só-literais — Σ infinita, testemunha concreta do gap (Fatia 2).
fn int_gap(n: Int) -> Int => match n { 0 => 1, 1 => 2 }

// 5. VERDE no meio — o `_` fecha a coluna (Regime 1); falso-positivo aqui
//    quebraria a lista de propósito.
fn green_wild(n: Int) -> Int => match n { 0 => 1, _ => 2 }

// 6. Produto — `Point{x: 0}` deixa x≠0 descoberto (Fatia 3a).
fn product_gap(p: Point) -> Int => match p { Point { x: 0, y: b } => 0 }

// 7. List — só `[]`; comprimentos maiores ficam descobertos (Fatia 3b).
fn list_gap(xs: List<Int>) -> Int => match xs { [] => 0 }

// 8. `class` — a última lacuna HONESTA (§12-11, ruling (e) do dono): produto de
//    REFERÊNCIA não é modelado ainda; a análise diz "não sei", não chuta. (O
//    2-rest `[..a, ..b]` NÃO está aqui: morre antes, na F5 — `duplicate-rest-
//    pattern`, ruling (a) — logo não é um erro de FLOW.)
fn class_gap(r: Ref) -> Int => match r { Ref { v: a } => 0 }
