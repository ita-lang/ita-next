// spec 005 CA6 — membro `async fn` em corpo de tipo (asyncMarker = async).
struct S { async fn tick() => 0 }
