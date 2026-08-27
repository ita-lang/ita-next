#!/bin/sh
# ============================================================================
# check-links-claude-test.sh — o RED de `check-links-claude.sh`
# ============================================================================
#
# Régua quebrada tem de reprovar a SI MESMA antes de reprovar o repo — mesmo
# arranjo de `citations: citations-test`, `gate-hook-selftest` e
# `ci-cobre-gate: ci-cobre-gate-test`.
#
# Prova os dois lados: que a régua acusa o link morto, e que NÃO acusa o
# legítimo. Dois casos carregam o peso:
#
#   - **âncora morta** (o arquivo existe, o heading não). É o caminho que o
#     repo hoje NÃO exercita — zero âncoras vivas em `specs/**` desde que os
#     dois links para `README.md#mapa-de-disparo…` foram consertados. Sem este
#     RED a metade-âncora da régua seria um passe vacuoso (R12): verde para
#     sempre, sem nunca ter rodado. Aqui ela roda, sobre uma árvore construída
#     à mão (R10, alavanca nº2).
#
#   - **path em prosa não conta.** Se a régua acusasse `.claude/skills/foo`
#     citado num parágrafo ou num bloco de código, viraria uma régua que grita
#     no legítimo — e régua que grita demais é desligada.
#
# As árvores entram por `ITA_LINK_BASE` / `ITA_LINK_ROOTS` / `ITA_LINK_MIN`:
# o teste nunca lê nem altera `specs/` de verdade.
# ============================================================================

set -u

REPO="$(cd "$(dirname "$0")/.." && pwd)"
REGUA="$REPO/tools/check-links-claude.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT INT TERM

N=0
FALHAS=0
FRASES="$TMP/frases"
: > "$FRASES"

# Monta uma árvore nova e ecoa a raiz. Sempre nasce com os três agentes e a
# rule — o que existe de verdade no repo — para que cada caso mexa só no que
# está medindo.
# ⚠️ Chamada como `D=$(arvore)`, ou seja, em SUBSHELL: nada que ela atribua
# sobrevive. O contador de casos mora em `roda()`, que corre no shell do
# script — quando estava aqui, o resumo dizia "2 casos" com 14 rodados.
ARV=0
arvore() {
  ARV=$((ARV + 1))
  D="$TMP/c$ARV-$$-$(od -An -N2 -tu2 < /dev/urandom | tr -d ' ')"
  mkdir -p "$D/specs/f" "$D/.claude/agents" "$D/.claude/rules"
  printf '# Subagentes\n\n## Quando consultar cada um\n' > "$D/.claude/agents/README.md"
  for a in ita-visionary dart-vm-expert compiler-craftsman; do
    printf '# %s\n' "$a" > "$D/.claude/agents/$a.md"
  done
  printf '# Consulta\n' > "$D/.claude/rules/consulta-especialistas.md"
  printf '%s' "$D"
}

# roda <descrição> <exit esperado> <raiz> <min> [substring] [id-da-guarda]
#
# `id-da-guarda` nomeia QUAL recusa o caso exercita — a R13 é sobre dois
# SÍTIOS dizerem a mesma frase, não sobre um sítio exercitado por vários casos.
roda() {
  desc="$1"; esperado="$2"; dir="$3"; min="$4"; frase="${5-}"; guarda="${6-}"
  N=$((N + 1))

  saida=$(ITA_LINK_BASE="$dir" ITA_LINK_ROOTS="specs" ITA_LINK_MIN="$min" \
          sh "$REGUA" 2>&1)
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

  # Números e paths de tmp são NORMALIZADOS antes de virar assinatura: a
  # comparação da R13 é sobre a FORMA da frase, não sobre os valores que ela
  # interpola. Sem isto a guarda `vacuidade` parecia instável só porque
  # "achei 0 … mínimo é 3" e "achei 1 … mínimo é 5" são a mesma guarda com
  # outros números — o RED pegou isso, é o mesmo defeito que o de
  # `ci-cobre-gate` pegou em 2026-08-26.
  if [ -n "$guarda" ]; then
    printf '%s\t%s\n' "$guarda" \
      "$(printf '%s\n' "$saida" | head -1 | sed "s|$TMP[^ ']*|<TMP>|g; s/[0-9][0-9]*/N/g")" \
      >> "$FRASES"
  fi

  echo "  ✅ $desc"
}

echo ""
echo "  check-links-claude: a régua prova que sabe ficar VERMELHA"
echo ""

# --- o que deve PASSAR ------------------------------------------------------

D=$(arvore)
cat > "$D/specs/f/tasks.md" <<'EOF'
Ver [ita-visionary](../../.claude/agents/ita-visionary.md) e
[a rule](../../.claude/rules/consulta-especialistas.md).
EOF
roda "links para alvos existentes — passa" 0 "$D" 1

D=$(arvore)
cat > "$D/specs/f/tasks.md" <<'EOF'
O [mapa](../../.claude/agents/README.md#quando-consultar-cada-um) explica.
EOF
roda "âncora VIVA (heading existe) — passa" 0 "$D" 1

D=$(arvore)
cat > "$D/specs/f/tasks.md" <<'EOF'
| **W1** | [`a`](../../.claude/agents/ita-visionary.md) | [`b`](../../.claude/agents/dart-vm-expert.md) + [`c`](../../.claude/agents/compiler-craftsman.md) |
EOF
roda "três links na MESMA linha — todos conferidos, todos vivos" 0 "$D" 3

D=$(arvore)
cat > "$D/specs/f/tasks.md" <<'EOF'
Ver [ok](../../.claude/agents/ita-visionary.md).
As skills viviam em `.claude/skills/speckit-plan/` e saíram em 2026-08-26.
Path solto em prosa: ../../.claude/skills/speckit-tasks/
EOF
roda "path em PROSA / bloco de código não conta — não acusa o legítimo" 0 "$D" 1

D=$(arvore)
mkdir -p "$D/.claude/rules"
cat > "$D/specs/f/tasks.md" <<'EOF'
Ver [as rules](../../.claude/rules/).
EOF
roda "link para DIRETÓRIO que existe — passa" 0 "$D" 1

# --- o que deve REPROVAR ----------------------------------------------------

D=$(arvore)
cat > "$D/specs/f/tasks.md" <<'EOF'
Ver [speckit-plan](../../.claude/skills/speckit-plan/) para fatiar.
EOF
roda "skill DELETADA ainda linkada — reprova nomeando (o bug de 2026-08-27)" 1 "$D" 1 \
  "alvo inexistente: ../../.claude/skills/speckit-plan/" quebrado

D=$(arvore)
cat > "$D/specs/f/tasks.md" <<'EOF'
Ver [fantasma](../../.claude/agents/nao-existe.md).
EOF
roda "arquivo inexistente sob .claude/ — reprova" 1 "$D" 1 \
  "alvo inexistente" quebrado

D=$(arvore)
cat > "$D/specs/f/tasks.md" <<'EOF'
O [mapa](../../.claude/agents/README.md#mapa-de-disparo-na-pipeline-w0--w3) explica.
EOF
roda "ÂNCORA MORTA (arquivo existe, heading não) — reprova" 1 "$D" 1 \
  "âncora morta: #mapa-de-disparo-na-pipeline-w0--w3" quebrado

D=$(arvore)
printf 'sem heading nenhum, só prosa\n' > "$D/.claude/agents/README.md"
cat > "$D/specs/f/tasks.md" <<'EOF'
O [mapa](../../.claude/agents/README.md#qualquer-coisa) explica.
EOF
roda "alvo SEM heading nenhum + âncora — reprova com detalhe próprio" 1 "$D" 1 \
  "não tem heading nenhum" quebrado

D=$(arvore)
printf 'Nenhum link aqui.\n' > "$D/specs/f/tasks.md"
roda "ZERO links — reprova por vacuidade (R12)" 1 "$D" 3 \
  "o mínimo é 3" vacuidade

D=$(arvore)
cat > "$D/specs/f/tasks.md" <<'EOF'
Só [um](../../.claude/agents/ita-visionary.md).
EOF
roda "links ABAIXO do mínimo — reprova (regex pode ter quebrado)" 1 "$D" 5 \
  "achei 1 link(s)" vacuidade

D=$(arvore)
rm -rf "$D/specs"
roda "raiz \`specs/\` inexistente — reprova (contrato)" 1 "$D" 1 \
  "nenhuma das raízes existe" raiz

# --- R13: guardas distintas, e cada uma sempre com a mesma frase ------------
N=$((N + 1))
GUARDAS=$(cut -f1 "$FRASES" | sort -u | wc -l | tr -d ' ')
FRASES_U=$(cut -f2 "$FRASES" | sort -u | wc -l | tr -d ' ')
INCONSISTENTES=$(sort -u "$FRASES" | cut -f1 | sort | uniq -d | wc -l | tr -d ' ')

if [ "$GUARDAS" != "$FRASES_U" ] || [ "$INCONSISTENTES" != "0" ]; then
  echo "  ❌ as $GUARDAS guardas de recusa deviam dizer $GUARDAS frases distintas"
  echo "     frases distintas: $FRASES_U · guardas com frase instável: $INCONSISTENTES"
  sort -u "$FRASES" | sed 's/^/     /'
  FALHAS=$((FALHAS + 1))
else
  echo "  ✅ as $GUARDAS guardas de recusa dizem $GUARDAS frases distintas, uma cada (R13)"
fi

# --- os três DETALHES de link quebrado também se distinguem -----------------
# Uma guarda só (o relatório de quebrados), mas o item tem de dizer QUAL é o
# defeito: alvo ausente, âncora morta, ou arquivo sem heading. Detalhe único
# para os três seria a R13 um nível abaixo — o relatório não ensinaria nada.
N=$((N + 1))
D=$(arvore)
printf 'sem heading\n' > "$D/.claude/agents/dart-vm-expert.md"
cat > "$D/specs/f/tasks.md" <<'EOF'
[a](../../.claude/skills/sumida/) · [b](../../.claude/agents/README.md#nao-existe) · [c](../../.claude/agents/dart-vm-expert.md#x)
EOF
SAIDA=$(ITA_LINK_BASE="$D" ITA_LINK_ROOTS="specs" ITA_LINK_MIN=1 sh "$REGUA" 2>&1)
DETALHES=$(printf '%s\n' "$SAIDA" | grep -c '✗' || true)
DISTINTOS=$(printf '%s\n' "$SAIDA" | grep '✗' \
            | sed 's/.*—[[:space:]]*//; s/:.*//; s/#.*//' | sort -u | wc -l | tr -d ' ')

if [ "$DETALHES" != "3" ] || [ "$DISTINTOS" != "3" ]; then
  echo "  ❌ os 3 defeitos de link deviam dar 3 detalhes distintos"
  echo "     itens: $DETALHES · detalhes distintos: $DISTINTOS"
  printf '%s\n' "$SAIDA" | sed 's/^/     /'
  FALHAS=$((FALHAS + 1))
else
  echo "  ✅ os 3 defeitos (alvo ausente · âncora morta · sem heading) dizem detalhes distintos"
fi

echo ""
if [ "$FALHAS" -ne 0 ]; then
  echo "  ❌ check-links-claude: $FALHAS de $N casos reprovaram"
  echo ""
  exit 1
fi

echo "  ✅ check-links-claude: $N casos — acusa o link morto, não acusa o legítimo"
echo ""
