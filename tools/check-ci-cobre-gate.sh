#!/bin/sh
# ============================================================================
# check-ci-cobre-gate.sh — o CI roda o PORTÃO inteiro?
# ============================================================================
#
# Compara os pré-requisitos do alvo `gate:` (Makefile) com os `make <alvo>` que
# o CI de fato EXECUTA (`.github/workflows/ci.yml`). Pré-requisito que o CI não
# roda reprova, com nome.
#
# ---------------------------------------------------------------------------
# Por que existe
# ---------------------------------------------------------------------------
#
# Auditado em 2026-08-26: das SETE dependências do `gate`, o CI rodava seis. A
# que faltava era `gate-hook-selftest` — justamente a catraca que prova que a
# segunda camada do portão sabe ficar VERMELHA (R14).
#
# O furo era circular. Essa catraca só rodava pelo `pre-commit` nativo, que só
# dispara se `core.hooksPath` estiver configurado — e `core.hooksPath` é config
# LOCAL, que não vem no clone. Logo: clone onde `make setup-hooks` nunca rodou
# + um mutante em `gate-armed-hook.sh` = verde em todo lugar, zero diagnóstico.
# Medido: o mutante `exit 2` → `exit 0` reprova 10 dos 21 casos do selftest, e
# nenhum step do CI o executava.
#
# Acrescentar o step consertaria o CI de HOJE. Esta régua conserta a CLASSE: as
# duas listas são mantidas à mão, em arquivos diferentes, e já divergiram uma
# vez em silêncio. É o mesmo motivo pelo qual o `gate` existe — "a lista cresceu
# além do que alguém lembra".
#
# ---------------------------------------------------------------------------
# As duas decisões de leitura, e por quê
# ---------------------------------------------------------------------------
#
# 1. Só conta `make` que esteja num comando `run:` — linha única ou bloco
#    `run: |`. Um `make citations` citado em COMENTÁRIO não executa nada, e o
#    ci.yml tem vários (`make bench`, `make gate`, `tools/pin-dart.sh`). Contá-
#    los seria uma lista-branca cuja falha-padrão é "OK" (R5).
#
# 2. Falha FECHADA em contrato quebrado: sem `gate:` no Makefile, sem ci.yml,
#    sem nenhum `make` no CI, ou `gate:` quebrado em continuação de linha ⟹
#    exit 1 com mensagem PRÓPRIA (R13). Uma régua que não acha o que medir tem
#    de reprovar, não passar.
#
# Injeção de dependência por `ITA_MAKEFILE` / `ITA_CI_YML` (R10, alavanca nº1):
# `check-ci-cobre-gate-test.sh` constrói o par defeituoso à mão, sem tocar nos
# arquivos reais do repo.
# ============================================================================

set -eu

REPO="$(cd "$(dirname "$0")/.." && pwd)"
MAKEFILE="${ITA_MAKEFILE:-$REPO/Makefile}"
CI_YML="${ITA_CI_YML:-$REPO/.github/workflows/ci.yml}"

# --- 1. os dois artefatos existem ------------------------------------------
if [ ! -f "$MAKEFILE" ]; then
  echo "ci-cobre-gate: Makefile não encontrado em '$MAKEFILE'." >&2
  exit 1
fi

if [ ! -f "$CI_YML" ]; then
  echo "ci-cobre-gate: workflow não encontrado em '$CI_YML'." >&2
  echo "               Sem CI não há o que comparar — e o portão fica só no" >&2
  echo "               pre-commit local, que não vem no clone." >&2
  exit 1
fi

# --- 2. os pré-requisitos do `gate:` ---------------------------------------
# Presença e conteúdo são checados SEPARADAMENTE de propósito: `sed` sobre um
# `gate:` sem dependências devolve linha vazia, igual ao alvo ausente. Fundidos,
# "o portão sumiu" e "o portão está vazio" dariam a MESMA mensagem — a R13
# dentro da régua que a cobra (pego pelo RED, 2026-08-26).
if ! grep -q '^gate:' "$MAKEFILE"; then
  echo "ci-cobre-gate: não achei o alvo \`gate:\` em '$MAKEFILE'." >&2
  echo "               O portão mudou de nome? Esta régua mede a lista DELE;" >&2
  echo "               sem ela, ela não sabe o que cobrar." >&2
  exit 1
fi

GATE_LINE=$(sed -n 's/^gate:[[:space:]]*//p' "$MAKEFILE" || true)

# Continuação de linha mudaria o que `sed` vê, e o resto ficaria invisível —
# meia-lista medida com tique verde é pior que régua ausente.
case "$GATE_LINE" in
  *\\)
    echo "ci-cobre-gate: o \`gate:\` está quebrado em continuação de linha (\\)." >&2
    echo "               Esta régua lê só a primeira; deixe a lista numa linha" >&2
    echo "               só, ou ensine o script a juntar as partes." >&2
    exit 1
    ;;
esac

PRERREQS=$(printf '%s' "$GATE_LINE" | tr ' \t' '\n\n' | grep -v '^$' || true)

if [ -z "$PRERREQS" ]; then
  echo "ci-cobre-gate: o \`gate:\` não tem pré-requisito nenhum." >&2
  echo "               Portão vazio é portão aberto." >&2
  exit 1
fi

# --- 3. os `make <alvo>` que o CI EXECUTA ----------------------------------
# Só comandos de `run:` (linha única e bloco `run: |`); comentário não roda.
CI_CMDS=$(awk '
  /^[[:space:]]*#/ { next }
  {
    if (match($0, /^[[:space:]]*(-[[:space:]]+)?run:[[:space:]]*\|/)) {
      match($0, /^[[:space:]]*/); blockind = RLENGTH; inblock = 1; next
    }
    if (match($0, /^[[:space:]]*(-[[:space:]]+)?run:[[:space:]]*/)) {
      inblock = 0; print substr($0, RSTART + RLENGTH); next
    }
    if (inblock) {
      if ($0 ~ /^[[:space:]]*$/) { next }
      match($0, /^[[:space:]]*/)
      if (RLENGTH > blockind) { print; next }
      inblock = 0
    }
  }
' "$CI_YML")

CI_ALVOS=$(printf '%s\n' "$CI_CMDS" \
  | grep -oE '\bmake[[:space:]]+[a-zA-Z0-9_.-]+' \
  | sed 's/^make[[:space:]]*//' \
  | sort -u || true)

if [ -z "$CI_ALVOS" ]; then
  echo "ci-cobre-gate: nenhum \`make <alvo>\` nos comandos do CI." >&2
  echo "               Ou o workflow parou de usar o Makefile — e aí as duas" >&2
  echo "               listas não têm como ser comparadas —, ou a leitura de" >&2
  echo "               \`run:\` deste script quebrou. Nos dois casos, reprova." >&2
  exit 1
fi

# --- 4. o que o portão exige e o CI não roda -------------------------------
FALTAM=''
N=0
for alvo in $PRERREQS; do
  N=$((N + 1))
  printf '%s\n' "$CI_ALVOS" | grep -qx "$alvo" || FALTAM="$FALTAM $alvo"
done

if [ -n "$FALTAM" ]; then
  echo "  ❌ ci-cobre-gate: o CI não roda todo o portão." >&2
  echo "" >&2
  for alvo in $FALTAM; do
    echo "     falta no ci.yml:  make $alvo" >&2
  done
  echo "" >&2
  echo "     O \`gate\` local cobre esses alvos pelo pre-commit — que depende de" >&2
  echo "     \`core.hooksPath\`, config LOCAL que não vem no clone. Um clone sem" >&2
  echo "     \`make setup-hooks\` fica sem eles em lugar nenhum, e nada avisa." >&2
  echo "" >&2
  echo "     Acrescente um step \`run: make <alvo>\` em .github/workflows/ci.yml." >&2
  exit 1
fi

echo "  ✅ ci-cobre-gate: os $N alvos do portão rodam no CI"
