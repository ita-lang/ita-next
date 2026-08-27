#!/bin/sh
# ============================================================================
# check-readme-derivado.sh — o índice das specs bate com o repo?
# ============================================================================
#
# Mede os sinais do bloco `DERIVADO` de `specs/README.md` contra o repositório
# e reprova nomeando o sinal, o valor declarado e o medido. Cobra também a
# cobertura BIDIRECIONAL do índice: spec no disco fora da tabela, e linha da
# tabela apontando para spec que não existe.
#
# ---------------------------------------------------------------------------
# Por que existe
# ---------------------------------------------------------------------------
#
# Medido em 2026-08-27: o `specs/README.md` ficou **109 commits** atrás do repo.
# Declarava *"emissão não escrita, `codegen/` só `.gitkeep`"* com 5.190 linhas
# em `codegen/lib/`, e `862 verde` com a suíte em `922`. O arquivo tinha um
# aviso escrito — *"quando as duas divergem, é dívida de bookkeeping"* — e o
# aviso não impediu nada: é a R9 (*"o placar deve ser DERIVADO, nunca uma
# tabela markdown editada pelo mesmo commit que ela avalia"*) um nível acima do
# ledger de CAs, que já resolveu isto para a spec 013.
#
# ---------------------------------------------------------------------------
# O RECORTE, declarado (R10)
# ---------------------------------------------------------------------------
#
# Esta régua mede o que é **estático**: contagem de arquivos, entradas de
# ledger, cobertura da tabela. Ela NÃO mede suíte verde nem CA fechado — esses
# são estado de EXECUÇÃO, e os alvos que os produzem (`make test`,
# `make codegen-test`) vivem em jobs de CI diferentes: nenhum job tem as duas
# métricas ao mesmo tempo, e um artefato intermediário versionado apodreceria
# igual ao número que ele substituiria.
#
# O que se fez em vez de fingir cobertura: esses números saíram do bloco
# derivado e foram para a seção "Estado corrente", **datados**. Fechar de
# verdade exige um job que rode as duas suítes e publique as métricas — fatia
# nomeada, não impossibilidade.
#
# Injeção por `ITA_README` / `ITA_REPO_BASE` (R10, alavanca nº1): o RED constrói
# o par defeituoso à mão, sem tocar no `specs/README.md` real.
# ============================================================================

set -eu

REPO="$(cd "$(dirname "$0")/.." && pwd)"
BASE="${ITA_REPO_BASE:-$REPO}"
README="${ITA_README:-$BASE/specs/README.md}"

FALHAS=$(mktemp)
trap 'rm -f "$FALHAS"' EXIT

# --- 1. o índice existe ------------------------------------------------------
if [ ! -f "$README" ]; then
  echo "readme-derivado: índice não encontrado em '$README'." >&2
  echo "                 É ele que esta régua mede; sem ele não há o que aferir." >&2
  exit 1
fi

# --- 2. o bloco DERIVADO existe e está fechado -------------------------------
# Presença e fechamento são checados SEPARADAMENTE: um bloco sem `FIM` faria o
# `sed` engolir o arquivo inteiro e medir linhas que não são sinais. Fundidos,
# "bloco ausente" e "bloco aberto" diriam a MESMA frase (R13).
if ! grep -q 'DERIVADO:INICIO' "$README"; then
  echo "readme-derivado: não achei o marcador \`DERIVADO:INICIO\` em '$README'." >&2
  echo "                 Sem o bloco, a régua não tem sinais a conferir — e um" >&2
  echo "                 índice sem catraca é o que apodreceu por 109 commits." >&2
  exit 1
fi

if ! grep -q 'DERIVADO:FIM' "$README"; then
  echo "readme-derivado: o bloco \`DERIVADO\` abre e não fecha." >&2
  echo "                 Sem o \`DERIVADO:FIM\` a leitura pegaria o arquivo" >&2
  echo "                 inteiro e mediria prosa como se fosse sinal." >&2
  exit 1
fi

BLOCO=$(sed -n '/DERIVADO:INICIO/,/DERIVADO:FIM/p' "$README")

# --- 3. medir cada sinal -----------------------------------------------------
# `medir <rótulo> <valor real>`: acha a linha da tabela pelo rótulo e compara.
# Sinal declarado que a régua não sabe medir é ERRO (R5, falha fechada): a
# tabela é o contrato, e um rótulo desconhecido ali dentro passaria despercebido
# para sempre.
CONFERIDOS=0

medir() {
  rotulo="$1"; real="$2"
  linha=$(printf '%s\n' "$BLOCO" | grep -F "| $rotulo |" || true)

  if [ -z "$linha" ]; then
    printf 'sinal ausente no bloco: "%s" (medido: %s)\n' "$rotulo" "$real" >>"$FALHAS"
    return
  fi

  decl=$(printf '%s' "$linha" | awk -F'|' '{gsub(/[^0-9]/, "", $3); print $3}')
  CONFERIDOS=$((CONFERIDOS + 1))

  if [ "$decl" != "$real" ]; then
    printf '%s — declarado %s, medido %s\n' "$rotulo" "${decl:-<vazio>}" "$real" >>"$FALHAS"
  fi
}

N_SPECS=$(find "$BASE/specs" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
medir "specs no repo" "$N_SPECS"

LEDGER="$BASE/codegen/test/ca_ledger.dart"
if [ -f "$LEDGER" ]; then
  medir "CAs no ledger da spec 013" \
        "$(grep -c '^  CriterioAceite(' "$LEDGER" | tr -d ' ')"
fi

# Os diretórios são DESCOBERTOS, nunca listados. Uma lista fixa aqui seria a
# R5 dentro da régua que a aplica: `conformance/nova-fase/` nasceria sem sinal,
# sem linha no índice e sem ninguém reprovando — a falha-padrão "OK" de novo.
# Pego pelo RED em 2026-08-27.
for dir in "$BASE"/conformance/*/; do
  [ -d "$dir" ] || continue
  medir "fixtures \`conformance/$(basename "$dir")\`" \
        "$(find "$dir" -maxdepth 1 -name '*.tu' | wc -l | tr -d ' ')"
done

if [ -d "$BASE/codegen/lib" ]; then
  medir "arquivos \`.dart\` em \`codegen/lib\`" \
        "$(find "$BASE/codegen/lib" -maxdepth 1 -name '*.dart' | wc -l | tr -d ' ')"
fi

# Anti-vacuidade (R12): uma régua que não conferiu sinal nenhum é
# indistinguível de uma que aprovou tudo — e este é um grep sobre markdown.
if [ "$CONFERIDOS" -lt 3 ]; then
  echo "readme-derivado: só $CONFERIDOS sinal(is) conferido(s) — o mínimo é 3." >&2
  echo "                 Ou os rótulos da tabela mudaram, ou o repo perdeu os" >&2
  echo "                 diretórios que ela mede. Régua sem sinal aprova por" >&2
  echo "                 vacuidade." >&2
  exit 1
fi

# --- 4. cobertura BIDIRECIONAL do índice -------------------------------------
# Só um sentido deixaria metade do defeito passar: conferir "toda linha aponta
# para spec que existe" não vê a spec nova que ninguém indexou, e vice-versa.
for dir in "$BASE"/specs/*/; do
  [ -d "$dir" ] || continue
  nome=$(basename "$dir")
  grep -q "($nome/)" "$README" \
    || printf 'spec no disco e FORA do índice: %s\n' "$nome" >>"$FALHAS"
done

for alvo in $(grep -o '](\([0-9][0-9][0-9]-[a-z0-9-]*\)/)' "$README" \
              | sed 's/^](//; s|/)$||' | sort -u); do
  [ -d "$BASE/specs/$alvo" ] \
    || printf 'índice aponta para spec inexistente: %s\n' "$alvo" >>"$FALHAS"
done

# --- 5. veredito -------------------------------------------------------------
if [ -s "$FALHAS" ]; then
  echo "readme-derivado: o índice contradiz o repo —" >&2
  sed 's/^/  ✗ /' "$FALHAS" >&2
  echo >&2
  echo "                 Atualize \`specs/README.md\`. Número de índice que" >&2
  echo "                 ninguém confere vira o \`862 verde\` de 2026-07-22:" >&2
  echo "                 lido como presente, errado por 109 commits." >&2
  exit 1
fi

echo "  ✅ readme-derivado: $CONFERIDOS sinais conferidos · $N_SPECS specs indexadas nos dois sentidos"
