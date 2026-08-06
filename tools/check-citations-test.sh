#!/bin/sh
# ============================================================================
# check-citations-test.sh — o gate de procedência é LOAD-BEARING?
# ============================================================================
#
# Mesma premissa do `invariants_test.dart`: uma régua que nunca acusa é
# indistinguível de uma régua quebrada. Até agora a prova de que o
# `check-citations.sh` funciona era MANUAL (inserir uma citação falsa e ver o CI
# vermelho) — o que quer dizer que ninguém a refaria depois de um refactor do
# awk, e um `return 0` acidental passaria despercebido para sempre.
#
# Cada caso abaixo é um arquivo com UMA violação conhecida, escrito num diretório
# temporário que o scanner enxerga. Rodar: `make citations-test`.

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP="${TMPDIR:-/tmp}/ita-citations-test.$$"
ALVO="$ROOT/conformance/_citations_selftest"
trap 'rm -rf "$TMP" "$ALVO"' EXIT
mkdir -p "$TMP" "$ALVO"

fails=0
ok()   { printf '  ✓ %s\n' "$1"; }
bad()  { printf '  ✗ FAIL: %s\n' "$1"; fails=$((fails + 1)); }

# Roda o scanner e conta as violações que casam com $2 no arquivo $1.
conta() {
  "$ROOT/tools/check-citations.sh" --list 2>/dev/null \
    | grep "_citations_selftest/$1" | grep -c "$2" || true
}

caso() { # <arquivo> <regra esperada> <descrição>
  n=$(conta "$1" "$2")
  if [ "$n" -ge 1 ]; then ok "$3"; else bad "$3 (esperava $2, achou 0)"; fi
}

echo 'check-citations — cada regra ACUSA o que promete:'

# C1 — a âncora não existe (o ADR-0012 vai até §E, não há §Z-9)
cat > "$ALVO/c1.tu" <<'EOF'
// Isto se apoia no ADR-0012 §Z-9, que não existe em documento nenhum.
fn main() { print("x") }
EOF
caso c1.tu 'C1' 'C1 — âncora que não resolve é acusada'

# C2 — `§N` nu, sem documento adjacente e sem cabeçalho `// SPEC:`
cat > "$ALVO/c2.tu" <<'EOF'
// A forma da emissão sai do §7.4-c, sem dizer de qual spec.
fn main() { print("x") }
EOF
caso c2.tu 'C2' 'C2 — `§N` nu (sem spec, sem escopo) é acusado'

# C3 — a regra que um grep de âncoras NÃO daria: modalidade universal sem
# verbatim colado. É o caso do `ADR-0012 §A-1` (âncora real, atribuição errada).
cat > "$ALVO/c3.tu" <<'EOF'
// SPEC: 013
// `class` NUNCA ganha memberwise (ADR-0012 §A-1) — dito sem colar a frase da
// fonte, que é justamente onde a modalidade escala de condicional para universal.
fn main() { print("x") }
EOF
caso c3.tu 'C3' 'C3 — "nunca" + citação SEM verbatim é acusado'

# C4 — ruling apoiado em data, sem artefato
cat > "$ALVO/c4.tu" <<'EOF'
// SPEC: 013
// Esta forma vem de um ruling do dono, 2026-07-15, e nada mais.
fn main() { print("x") }
EOF
caso c4.tu 'C4' 'C4 — "ruling do dono" + data sem artefato é acusado'

echo ''
echo 'check-citations — e NÃO acusa o que é legítimo:'

# O contraponto: sem ele, a suíte passaria com um scanner que acusa tudo.
cat > "$ALVO/ok.tu" <<'EOF'
// SPEC: 013
// A emissão segue o §7.4-c, e o ruling que a sustenta está no ADR-0016 §D:
// *"`class` sem `init` não ganha memberwise"* — verbatim, da fonte certa.
// Fonte externa nomeada não é auditável por grep e sai: JLS §16.2.10.
fn main() { print("x") }
EOF
n=$("$ROOT/tools/check-citations.sh" --list 2>/dev/null \
      | grep -c "_citations_selftest/ok.tu" || true)
if [ "$n" -eq 0 ]; then
  ok 'citação COMPLETA (spec + âncora real + verbatim) passa'
else
  bad "citação legítima foi acusada $n vez(es) — a régua vira ruído e é desligada"
  "$ROOT/tools/check-citations.sh" --list 2>/dev/null | grep "_citations_selftest/ok.tu"
fi

# O escape auditável tem de funcionar, senão o legado não tem saída documentada.
cat > "$ALVO/escape.tu" <<'EOF'
// Apoia-se no ADR-0012 §Z-9. CITATION-OK: caso de teste do próprio gate
fn main() { print("x") }
EOF
n=$(conta escape.tu 'C1')
if [ "$n" -eq 0 ]; then
  ok '`CITATION-OK:` isenta a linha (escape auditável)'
else
  bad '`CITATION-OK:` não isentou'
fi

echo ''
if [ "$fails" -gt 0 ]; then
  echo "check-citations self-test: $fails CHECK(S) VERMELHO(S) ❌"
  exit 1
fi
echo 'check-citations self-test: TODOS OS CHECKS VERDES ✅'
