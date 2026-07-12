// D3 — operator custom: precedence + associatividade `left`/`right` preservadas.
operator + (a: Vec, b: Vec) -> Vec precedence 6 left {
  a
}
