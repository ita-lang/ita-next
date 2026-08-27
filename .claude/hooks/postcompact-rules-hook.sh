#!/bin/sh
# ============================================================================
# postcompact-rules-hook.sh — as rules sobrevivem ao /compact
# ============================================================================
#
# `PostCompact` do `.claude/settings.json`. Reinjeta o conteúdo de
# `.claude/rules/*.md` no contexto logo depois da compactação.
#
# ---------------------------------------------------------------------------
# Por que existe
# ---------------------------------------------------------------------------
#
# O `CLAUDE.md` deste repo declara o furo desde 2026-07-29, e declarava sem
# catraca:
#
#   > ⚠️ Regra com `paths:` NÃO é re-injetada depois de `/compact` — ela só volta
#   > quando um arquivo que casa o padrão é lido de novo. Sessão compactada +
#   > mexer no emitter ⟹ reabrir o arquivo antes de decidir.
#
# "Reabrir antes de decidir" é instrução para um humano lembrar — a mesma forma
# que a auditoria mediu falhando: uma doutrina escrita às 19:40 foi violada às
# 21:47 do mesmo dia. O próprio parágrafo diz que é "o mesmo defeito que a última
# seção deste arquivo descreve: doutrina lembrada de memória em vez de relida".
#
# `PostCompact` é o mecanismo NATIVO para isso (code.claude.com/docs/en/hooks) e
# fecha o furo sem depender de ninguém lembrar.
#
# ---------------------------------------------------------------------------
# Por que injeta INTEIRO, e não uma lista
# ---------------------------------------------------------------------------
#
# Um aviso "releia as rules" seria outra declaração sem catraca: nada obriga a
# ler. As quatro rules somam ~200 linhas — o custo de injetá-las de uma vez é
# menor que o de um único ICE causado por decidir sem elas.
#
# Falha ABERTA aqui, ao contrário do `gate-armed-hook.sh`, e de propósito: este
# hook não é um portão. Se ele quebrar, o pior caso é o contexto ficar como já
# estava antes de existir; travar a sessão pós-compactação seria pior que o
# furo que ele fecha. Mas o silêncio é declarado — sem rules legíveis, ele diz
# no `systemMessage` que não injetou nada.
# ============================================================================

set -u

RAIZ="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
DIR="$RAIZ/.claude/rules"

# `jq -Rs` faz o escape de JSON (aspas, quebras, acentos) — montar a string à
# mão quebraria no primeiro `"` de um exemplo de código dentro de uma rule.
if ! command -v jq >/dev/null 2>&1; then
  printf '{"systemMessage":"rules pós-compact: `jq` ausente — nada reinjetado."}\n'
  exit 0
fi

CORPO=$(cat "$DIR"/*.md 2>/dev/null)

if [ -z "$CORPO" ]; then
  printf '{"systemMessage":"rules pós-compact: nenhuma rule legível em .claude/rules/."}\n'
  exit 0
fi

N=$(ls "$DIR"/*.md 2>/dev/null | wc -l | tr -d ' ')
L=$(printf '%s' "$CORPO" | wc -l | tr -d ' ')

CABECALHO="As regras técnicas de .claude/rules/ foram reinjetadas após a compactação (elas têm \`paths:\` e não voltam sozinhas). Valem como se o arquivo governado estivesse aberto:

"

printf '%s' "$CABECALHO$CORPO" | jq -Rs \
  --arg msg "rules pós-compact: $N rules ($L linhas) reinjetadas" \
  '{
     systemMessage: $msg,
     hookSpecificOutput: {
       hookEventName: "PostCompact",
       additionalContext: .
     }
   }'
