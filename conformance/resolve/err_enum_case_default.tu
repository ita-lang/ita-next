// O default do payload de um enum case é uma EXPRESSÃO e precisa resolver como
// qualquer outra — antes, o walk do resolver parava nos `members` do enum e
// nunca visitava os `cases`, então o nome errado aqui passava em silêncio.
// EXPECT-ERROR: unresolved-name
enum E {
  Some(v: Int = bogus)
  None
}
