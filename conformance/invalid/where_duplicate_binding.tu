// Nomes dos bindings de um mesmo `where` são distintos entre si — repetir é erro,
// não shadowing. A Fase 3 aninha em matches (`match 1 { y => match 2 { y => V } }`),
// onde cada braço abre escopo: para a Fase 4 aquilo é shadowing legítimo e o
// `duplicate-declaration` nunca dispara, ao contrário do mesmo erro num bloco comum.
// A checagem conta os nomes LIGADOS pelo pattern, então destructure também conta.
let r = y where { let y = 1; let y = 2 }
// EXPECT: parse-error: where-duplicate-binding @445+9
