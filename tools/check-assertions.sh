#!/bin/sh
# ============================================================================
# check-assertions.sh — dois caminhos não podem dizer a MESMA frase
# ============================================================================
#
# O caso que funda esta régua (mutante M7, 2026-07-29):
#
#   `checkOrderIndependence` tinha DUAS guardas anti-vacuidade, e as duas
#   emitiam a mesma frase — "não testou nada". O RED assertava
#   `contains('não testou nada')`. O teste atingia sempre a PRIMEIRA, a segunda
#   ficou INALCANÇÁVEL por dias, e o relatório dizia verde o tempo todo.
#
# Duas guardas com a mesma mensagem são indistinguíveis para quem lê o relatório
# E para quem escreve a asserção. É o modo de falha que **mantém caminho morto
# vivo**, e nenhuma cobertura de linha o pega: a linha do teste executa, a
# asserção passa, e o caminho que ela deveria cobrir nunca roda.
#
# ⚠️ **Por que a régua olha `lib/` e não o teste.** A primeira versão comparava
# o literal de `contains('…')` contra `lib/` e deu dois falsos positivos em dez
# minutos: contava PROSA (`ADR-0013` aparece 19× em docstrings) e não enxergava
# mensagem com INTERPOLAÇÃO (`'… ${node.runtimeType} …'` nunca casa com
# `contains('IntLiteral')`). Uma régua que erra nos dois sentidos é desligada na
# primeira semana — pior que régua nenhuma. O defeito real do M7 não depende do
# teste: é a duplicata na FONTE, e ela é detectável sem ambiguidade.
#
# ⚠️ **A CONTAGEM varia com a implementação do `awk`** — 48 no macOS (BSD awk),
# 47 no CI (Ubuntu/mawk), com o mesmo commit e o mesmo `LC_ALL`. Uma mensagem é
# vista por um e não pelo outro, provavelmente no `{24,}` sobre bytes multibyte.
#
# O VEREDITO não muda (0 ambíguas nos dois), porque ele depende de duplicata, não
# de total. Mas a divergência significa que uma mensagem escapa de um dos lados —
# e se ELA vier a ter duplicata, um ambiente acusa e o outro não. Registrado como
# limite conhecido, não como detalhe: quando o parsing migrar para algo
# independente de implementação, isto some. Ver R10 — o complemento aqui é "não é
# possível SEM trocar o parser", e trocar o parser é fatia, não impedimento.
#
# P9/P11: sh + grep + awk.

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP="${TMPDIR:-/tmp}/ita-assert.$$"
mkdir -p "$TMP"
trap 'rm -rf "$TMP"' EXIT

# ---------------------------------------------------------------------------
# Colhe os fragmentos literais de toda mensagem de diagnóstico de `lib/`.
# ---------------------------------------------------------------------------
#
# Mensagem = string dentro de `violations.add(…)`, `_ice(…)`, `_err(…)`,
# `_errAt(…)`, `throw StateError(…)`. Só o texto FIXO conta: a interpolação
# `${…}` é o que varia entre sítios e não serve para distingui-los.
#
# Fragmentos < 24 chars saem: frases curtas coincidem legitimamente ("ordem: ",
# "CA13: "), e o que a régua persegue é a frase INTEIRA repetida.
# ⚠️ Colhe TODA string longa de código, não só as de `violations.add(`. A
# primeira versão filtrava por chamada (`violations.add|_ice|_err|StateError`) e
# NÃO pegou o próprio M7 quando ele foi reintroduzido para teste: a mensagem
# morava num `return (violations: [ … ])`, que não casa com nenhum desses. Régua
# que depende de reconhecer a FORMA da chamada perde toda forma nova — a mesma
# lição da lista-branca do `visitDynamicType` (R5).
colher() {
  grep -rn "'" \
    "$ROOT/codegen/lib" "$ROOT/compiler/lib" 2>/dev/null |
  awk -F: '
    {
      arquivo = $1; num = $2
      linha = $0
      sub(/^[^:]*:[0-9]+:/, "", linha)
      gsub(/^[ \t]+/, "", linha)
      if (linha ~ /^\/\//) next            # comentário não é sítio
      # cada string simples da linha
      while (match(linha, /'"'"'[^'"'"']{24,}'"'"'/)) {
        frag = substr(linha, RSTART + 1, RLENGTH - 2)
        linha = substr(linha, RSTART + RLENGTH)
        # a parte fixa termina onde começa a primeira interpolação
        i = index(frag, "$")
        if (i > 0) frag = substr(frag, 1, i - 1)
        gsub(/[ \t]+$/, "", frag)
        # ⚠️ Só FRASES, não identificadores. Um código de erro
        # (`missing-param-annotation`) repete-se de propósito: é o MESMO
        # diagnóstico com causas diferentes, e exigir um código por sítio
        # multiplicaria o vocabulário de erro sem ganho nenhum. O que o M7
        # produziu foi duas FRASES iguais — e frase tem espaço.
        if (length(frag) >= 24 && frag ~ / /) print frag "\t" arquivo ":" num
      }
    }'
}

colher | sort > "$TMP/frags"

# Fragmento que aparece em 2+ SÍTIOS DISTINTOS ⟹ ambíguo.
cut -f1 "$TMP/frags" | uniq -d > "$TMP/dup"

fails=0
if [ -s "$TMP/dup" ]; then
  while IFS= read -r frag; do
    sitios=$(awk -F'\t' -v f="$frag" '$1 == f { print "        " $2 }' "$TMP/frags")
    n=$(echo "$sitios" | wc -l | tr -d ' ')
    printf '  ✗ FAIL: mensagem AMBÍGUA em %s sítios\n' "$n"
    printf '      "%s…"\n' "$frag"
    echo "$sitios"
    fails=$((fails + 1))
  done < "$TMP/dup"
fi

total=$(cut -f1 "$TMP/frags" | sort -u | wc -l | tr -d ' ')

if [ "$fails" -gt 0 ]; then
  echo ""
  echo "mensagens ambíguas: $fails ❌"
  echo "  Dois caminhos com a mesma frase são indistinguíveis no relatório E na"
  echo "  asserção — foi assim que uma guarda anti-vacuidade ficou morta (M7)."
  echo "  Dê a cada um o seu texto; o sufixo -A/-B basta."
  exit 1
fi

echo "mensagens de diagnóstico: $total distintas · 0 ambíguas ✅"
