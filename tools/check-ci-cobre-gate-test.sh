#!/bin/sh
# ============================================================================
# check-ci-cobre-gate-test.sh — o RED de `check-ci-cobre-gate.sh`
# ============================================================================
#
# Régua quebrada tem de reprovar a SI MESMA antes de reprovar o repo — o mesmo
# arranjo de `citations: citations-test` e de `gate-hook-selftest`.
#
# Prova os DOIS lados: que a régua acusa o portão descoberto, e que ela NÃO
# acusa o que é legítimo. O caso que mais importa é o nº4: um `make <alvo>`
# escrito em COMENTÁRIO do ci.yml não pode contar como cobertura — é a forma
# exata pela qual esta régua viraria uma lista-branca que aprova o que não roda.
#
# Os pares Makefile × ci.yml são construídos à mão, em tmp, e entram por
# `ITA_MAKEFILE` / `ITA_CI_YML`: o teste nunca lê nem altera os arquivos reais.
# ============================================================================

set -u

REPO="$(cd "$(dirname "$0")/.." && pwd)"
REGUA="$REPO/tools/check-ci-cobre-gate.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT INT TERM

N=0
FALHAS=0
FRASES="$TMP/frases"
: > "$FRASES"

# caso <descrição> <exit esperado> <Makefile> <ci.yml> [substring] [id-da-guarda]
#
# `id-da-guarda` nomeia QUAL recusa o caso exercita. A régua R13 é sobre dois
# SÍTIOS dizerem a mesma frase — não sobre um sítio ser exercitado por vários
# casos. Sem o id, o teste confundia as duas coisas e acusava a reprovação
# principal de duplicada só porque quatro entradas legítimas chegam nela.
caso() {
  desc="$1"; esperado="$2"; mk="$3"; ci="$4"; frase="${5-}"; guarda="${6-}"
  N=$((N + 1))

  printf '%s\n' "$mk" > "$TMP/Makefile"
  if [ "$ci" = '<AUSENTE>' ]; then
    rm -f "$TMP/ci.yml"
  else
    printf '%s\n' "$ci" > "$TMP/ci.yml"
  fi

  saida=$(ITA_MAKEFILE="$TMP/Makefile" ITA_CI_YML="$TMP/ci.yml" sh "$REGUA" 2>&1)
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

  # R13: cada GUARDA diz uma frase própria — e a mesma guarda diz sempre a
  # mesma. Registrado como `guarda<TAB>primeira-linha`, cobrado nos dois
  # sentidos no fim.
  if [ -n "$guarda" ]; then
    printf '%s\t%s\n' "$guarda" "$(printf '%s\n' "$saida" | head -1)" >> "$FRASES"
  fi

  echo "  ✅ $desc"
}

echo ""
echo "  check-ci-cobre-gate: a régua prova que sabe ficar VERMELHA"
echo ""

MK_OK='gate: analyze test citations
	@echo portao'

CI_OK='jobs:
  a:
    steps:
      - name: analyze
        run: make analyze
      - name: test
        run: make test
      - name: citations
        run: make citations'

# --- o que deve PASSAR -----------------------------------------------------
caso "CI roda os três alvos do portão — passa" 0 "$MK_OK" "$CI_OK"

caso "alvo dentro de bloco \`run: |\` conta como coberto" 0 "$MK_OK" \
'jobs:
  a:
    steps:
      - name: analyze
        run: make analyze
      - name: resto
        run: |
          set -eu
          make test
          make citations'

caso "alvo com variável na linha (\`make X VAR=y\`) conta" 0 \
'gate: codegen-test
	@echo portao' \
'jobs:
  a:
    steps:
      - name: codegen
        run: make codegen-test DART_CG=dart'

caso "CI que roda MAIS que o portão — passa (não é dela cobrar a mais)" 0 "$MK_OK" \
"$CI_OK
      - name: bench
        run: make bench"

# --- o que deve REPROVAR ---------------------------------------------------
caso "portão exige um alvo que o CI não roda — reprova nomeando" 1 \
'gate: analyze test citations gate-hook-selftest
	@echo portao' "$CI_OK" \
'make gate-hook-selftest' 'descoberto'

caso "alvo só em COMENTÁRIO do ci.yml NÃO conta (R5)" 1 "$MK_OK" \
'jobs:
  a:
    steps:
      # o `make citations` roda junto do step abaixo
      - name: analyze
        run: make analyze
      - name: test
        run: make test' \
'make citations' 'descoberto'

caso "linha de comentário DENTRO do bloco \`run: |\` não conta" 1 "$MK_OK" \
'jobs:
  a:
    steps:
      - name: tudo
        run: |
          make analyze
          make test
          # make citations  (desligado enquanto o baseline não desce)' \
'make citations' 'descoberto'

caso "bloco \`run: |\` terminou — a linha desindentada não conta" 1 "$MK_OK" \
'jobs:
  a:
    steps:
      - name: parcial
        run: |
          make analyze
          make test
      - name: outro
        with:
          args: make citations' \
'make citations' 'descoberto'

caso "Makefile sem alvo \`gate:\` — reprova (contrato)" 1 \
'portao: analyze test
	@echo portao' "$CI_OK" \
'não achei o alvo' 'gate-ausente'

caso "\`gate:\` quebrado em continuação de linha — reprova (mede meia-lista)" 1 \
'gate: analyze test \
      citations
	@echo portao' "$CI_OK" \
'continuação de linha' 'gate-continuacao'

caso "\`gate:\` sem pré-requisito nenhum — reprova (portão vazio)" 1 \
'gate:
	@echo portao' "$CI_OK" \
'não tem pré-requisito' 'gate-vazio'

caso "ci.yml sem nenhum \`make\` — reprova (nada a comparar)" 1 "$MK_OK" \
'jobs:
  a:
    steps:
      - name: analyze
        run: dart analyze
      - name: test
        run: dart test' \
'nenhum `make <alvo>`' 'ci-sem-make'

caso "ci.yml inexistente — reprova" 1 "$MK_OK" '<AUSENTE>' \
'workflow não encontrado' 'ci-ausente'

# --- R13: cada GUARDA tem mensagem própria, nos dois sentidos ---------------
# Sentido 1: guardas distintas não podem dizer a mesma frase — senão são
#            indistinguíveis no relatório E na asserção.
# Sentido 2: a mesma guarda tem de dizer sempre a mesma frase — senão a
#            asserção do caso casa por acaso, e a régua vira loteria.
N=$((N + 1))
ERRO13=0

GUARDAS=$(cut -f1 "$FRASES" | sort -u)
NG=$(printf '%s\n' "$GUARDAS" | grep -c . || true)
NF=$(cut -f2 "$FRASES" | sort -u | grep -c . || true)

for g in $GUARDAS; do
  n=$(awk -F'\t' -v g="$g" '$1 == g { print $2 }' "$FRASES" | sort -u | grep -c . || true)
  if [ "$n" -ne 1 ]; then
    echo "  ❌ a guarda '$g' diz $n frases diferentes — asserção casa por acaso"
    ERRO13=1
  fi
done

if [ "$NF" -ne "$NG" ]; then
  echo "  ❌ $NG guardas para $NF frases — dois sítios dizem o mesmo (R13):"
  cut -f2 "$FRASES" | sort | uniq -d | sed 's/^/     /'
  ERRO13=1
fi

if [ "$ERRO13" -eq 0 ]; then
  echo "  ✅ as $NG guardas de recusa dizem $NF frases distintas, uma cada (R13)"
else
  FALHAS=$((FALHAS + 1))
fi

echo ""
if [ "$FALHAS" -ne 0 ]; then
  echo "  ❌ check-ci-cobre-gate: $FALHAS de $N casos reprovaram"
  echo ""
  exit 1
fi

echo "  ✅ check-ci-cobre-gate: $N casos — acusa o portão descoberto, não acusa o legítimo"
echo ""
