#!/bin/sh
# ============================================================================
# check-readme-derivado-test.sh — o RED de `check-readme-derivado.sh`
# ============================================================================
#
# Régua quebrada tem de reprovar a SI MESMA antes de reprovar o repo — mesmo
# arranjo de `citations`, `gate-hook-selftest`, `ci-cobre-gate` e
# `links-claude`.
#
# O caso que carrega o peso é o **bidirecional**: uma régua que só confere "a
# linha do índice aponta para spec que existe" fica cega para a spec nova que
# ninguém indexou — e é essa metade que apodrece, porque criar spec é o ato
# frequente. Os dois sentidos têm caso próprio.
#
# As árvores entram por `ITA_README` / `ITA_REPO_BASE`: o teste nunca lê nem
# altera o `specs/README.md` real.
# ============================================================================

set -u

REPO="$(cd "$(dirname "$0")/.." && pwd)"
REGUA="$REPO/tools/check-readme-derivado.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT INT TERM

N=0
FALHAS=0
FRASES="$TMP/frases"
: > "$FRASES"

# Árvore mínima e COERENTE: 2 specs, 3 fixtures de codegen, 2 .dart, 1 CA.
# Cada caso parte dela e estraga exatamente uma coisa.
ARV=0
arvore() {
  ARV=$((ARV + 1))
  D="$TMP/c$ARV"
  mkdir -p "$D/specs/003-lexer-scaffold" "$D/specs/004-parser-ast" \
           "$D/conformance/codegen" "$D/codegen/lib" "$D/codegen/test"
  for i in 1 2 3; do : > "$D/conformance/codegen/f$i.tu"; done
  : > "$D/codegen/lib/emit.dart"; : > "$D/codegen/lib/finalize.dart"
  printf '  CriterioAceite(\n' > "$D/codegen/test/ca_ledger.dart"
  cat > "$D/specs/README.md" <<'EOF'
# Índice

<!-- DERIVADO:INICIO -->

| sinal | valor |
|:--|--:|
| specs no repo | 2 |
| CAs no ledger da spec 013 | 1 |
| fixtures `conformance/codegen` | 3 |
| arquivos `.dart` em `codegen/lib` | 2 |

<!-- DERIVADO:FIM -->

| Fase | Spec |
|:-:|:-:|
| F1 | [003](003-lexer-scaffold/) |
| F2 | [004](004-parser-ast/) |
EOF
  printf '%s' "$D"
}

# roda <descrição> <exit esperado> <raiz> [substring] [id-da-guarda]
roda() {
  desc="$1"; esperado="$2"; dir="$3"; frase="${4-}"; guarda="${5-}"
  N=$((N + 1))

  saida=$(ITA_REPO_BASE="$dir" sh "$REGUA" 2>&1)
  obtido=$?

  if [ "$obtido" -ne "$esperado" ]; then
    echo "  ❌ $desc"
    echo "     exit esperado: $esperado · obtido: $obtido"
    [ -n "$saida" ] && echo "     saída: $saida"
    FALHAS=$((FALHAS + 1))
    return
  fi

  if [ -n "$frase" ] && ! printf '%s' "$saida" | grep -qF "$frase"; then
    echo "  ❌ $desc"
    echo "     esperava a frase: $frase"
    echo "     saída: $saida"
    FALHAS=$((FALHAS + 1))
    return
  fi

  # Números e paths de tmp normalizados: a R13 compara a FORMA da frase, não
  # os valores que ela interpola (defeito que o RED do `ci-cobre-gate` pegou).
  if [ -n "$guarda" ]; then
    printf '%s\t%s\n' "$guarda" \
      "$(printf '%s\n' "$saida" | head -1 | sed "s|$TMP[^ ']*|<TMP>|g; s/[0-9][0-9]*/N/g")" \
      >> "$FRASES"
  fi

  echo "  ✅ $desc"
}

echo ""
echo "  check-readme-derivado: a régua prova que sabe ficar VERMELHA"
echo ""

# --- o que deve PASSAR ------------------------------------------------------

roda "índice coerente com o repo — passa" 0 "$(arvore)"

# --- o que deve REPROVAR ----------------------------------------------------

# O caso nasceu esperando exit 0 ("diretório vazio não precisa de linha") e o
# RED mostrou que a expectativa é que estava errada: se um diretório de
# conformance existe, ele TEM de ter sinal. A alternativa — medir só uma lista
# fixa de nomes — é a R5 dentro da régua: `conformance/nova-fase/` nunca seria
# conferido. A régua passou a DESCOBRIR os diretórios por causa deste caso.
D=$(arvore)
mkdir -p "$D/conformance/flow"
roda "diretório de conformance NOVO, sem linha no índice — reprova (R5)" 1 "$D" \
  "sinal ausente no bloco" contradiz

D=$(arvore)
: > "$D/conformance/codegen/f4.tu"
roda "fixture NOVO e contagem velha — reprova com declarado × medido" 1 "$D" \
  "fixtures \`conformance/codegen\` — declarado 3, medido 4" contradiz

D=$(arvore)
: > "$D/codegen/lib/sanitize.dart"
roda "arquivo .dart novo em codegen/lib — reprova" 1 "$D" \
  "declarado 2, medido 3" contradiz

D=$(arvore)
printf '  CriterioAceite(\n  CriterioAceite(\n' > "$D/codegen/test/ca_ledger.dart"
roda "CA novo no ledger e índice velho — reprova" 1 "$D" \
  "CAs no ledger da spec 013 — declarado 1, medido 2" contradiz

D=$(arvore)
mkdir -p "$D/specs/005-decl-surface"
roda "SPEC NOVA no disco, fora do índice — reprova (o sentido que apodrece)" 1 "$D" \
  "spec no disco e FORA do índice: 005-decl-surface" contradiz

D=$(arvore)
printf '| F9 | [009](009-nao-existe/) |\n' >> "$D/specs/README.md"
roda "índice aponta para spec INEXISTENTE — reprova" 1 "$D" \
  "índice aponta para spec inexistente: 009-nao-existe" contradiz

D=$(arvore)
sed -i.bak '/fixtures `conformance\/codegen`/d' "$D/specs/README.md"
roda "sinal medível AUSENTE do bloco — reprova (R5, falha fechada)" 1 "$D" \
  "sinal ausente no bloco" contradiz

D=$(arvore)
sed -i.bak '/DERIVADO:INICIO/d' "$D/specs/README.md"
roda "bloco DERIVADO ausente — reprova com guarda própria" 1 "$D" \
  "não achei o marcador" sem-bloco

D=$(arvore)
sed -i.bak '/DERIVADO:FIM/d' "$D/specs/README.md"
roda "bloco DERIVADO abre e NÃO FECHA — guarda própria (R13)" 1 "$D" \
  "abre e não fecha" bloco-aberto

D=$(arvore)
rm -f "$D/specs/README.md"
roda "índice inexistente — reprova (contrato)" 1 "$D" \
  "índice não encontrado" sem-readme

D=$(arvore)
rm -rf "$D/conformance" "$D/codegen"
cat > "$D/specs/README.md" <<'EOF'
# Índice
<!-- DERIVADO:INICIO -->
| sinal | valor |
|:--|--:|
| specs no repo | 2 |
<!-- DERIVADO:FIM -->
| F1 | [003](003-lexer-scaffold/) |
| F2 | [004](004-parser-ast/) |
EOF
roda "só 1 sinal conferível — reprova por vacuidade (R12)" 1 "$D" \
  "o mínimo é 3" vacuidade

# --- R13: guardas distintas, cada uma sempre com a mesma frase --------------
N=$((N + 1))
GUARDAS=$(cut -f1 "$FRASES" | sort -u | wc -l | tr -d ' ')
FRASES_U=$(cut -f2 "$FRASES" | sort -u | wc -l | tr -d ' ')
INSTAVEIS=$(sort -u "$FRASES" | cut -f1 | sort | uniq -d | wc -l | tr -d ' ')

if [ "$GUARDAS" != "$FRASES_U" ] || [ "$INSTAVEIS" != "0" ]; then
  echo "  ❌ as $GUARDAS guardas de recusa deviam dizer $GUARDAS frases distintas"
  echo "     frases distintas: $FRASES_U · guardas com frase instável: $INSTAVEIS"
  sort -u "$FRASES" | sed 's/^/     /'
  FALHAS=$((FALHAS + 1))
else
  echo "  ✅ as $GUARDAS guardas de recusa dizem $GUARDAS frases distintas, uma cada (R13)"
fi

echo ""
if [ "$FALHAS" -ne 0 ]; then
  echo "  ❌ check-readme-derivado: $FALHAS de $N casos reprovaram"
  echo ""
  exit 1
fi

echo "  ✅ check-readme-derivado: $N casos — acusa o índice que mente, não acusa o coerente"
echo ""
