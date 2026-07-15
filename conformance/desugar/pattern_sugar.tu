let r = match x {
  "${a ?? b}" => 1
  .some([n, "${p |> f}"]) => 2
  { k: "${c?.d}" } => 3
  _ => 4
}
for "${e ?? g}" in xs { h() }
