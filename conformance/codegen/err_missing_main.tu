// CA NEGATIVO (§7.3 + ruling §12-5) — biblioteca sem entry-point.
//
// `itac check` ACEITA este arquivo (programa sem `main` é legítimo); só
// `build`/`run` o reprovam, e o erro é do **DRIVER**, não da emissão. O fixture
// existe para travar a fronteira: antes de 2026-07-28 isto saía como
// `ice: ice-codegen-missing-main`, exit 70 — a palavra "ICE" acusando bug
// INTERNO do compilador na cara de quem só escreveu uma biblioteca. A §7.8 é
// literal: "a F7 não tem erro de usuário".
//
// Diferente de um `EXPECT-ICE`, este CA é PERMANENTE: nenhuma fatia futura o
// promove a verde — o comportamento correto é falhar assim para sempre.
//
// EXPECT-BUILD-ERROR: missing-main

fn ajuda() -> Int => 1
