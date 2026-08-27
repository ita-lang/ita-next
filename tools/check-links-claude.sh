#!/bin/sh
# ============================================================================
# check-links-claude.sh — todo path `.claude/` citado numa spec RESOLVE?
# ============================================================================
#
# Varre os `.md` das raízes de doutrina (`specs/`, `.specify/memory/`) atrás de
# link markdown que aponte para dentro de `.claude/`, resolve cada um relativo
# ao arquivo que o cita, e reprova nomeando arquivo, linha e alvo.
#
# ---------------------------------------------------------------------------
# Por que existe
# ---------------------------------------------------------------------------
#
# Auditoria de 2026-08-27. O commit `80e70f4` removeu as 6 skills `speckit-*`
# (quatro quebravam na primeira instrução, chamando um diretório que nunca
# existiu) — e deixou **19 links** para elas vivos em `specs/013/tasks.md` e
# `specs/014/tasks.md`. O `0dbbe81`, do dia anterior, reescreveu o
# `.claude/agents/README.md` e deixou a âncora `#mapa-de-disparo-na-pipeline-
# w0--w3` sem heading correspondente.
#
# Nenhum gate pegou: `check-citations.sh` valida âncora de spec/ADR, não path
# de `.claude/`. `make analyze` não lê markdown. O CI ficou verde nas duas
# vezes. É a mesma forma dos 30 runs verdes de 2026-07-29 — a referência aponta
# para o que não existe, e o silêncio se parece com saúde.
#
# ---------------------------------------------------------------------------
# As três decisões de leitura, e por quê
# ---------------------------------------------------------------------------
#
# 1. **Âncora conta.** Um arquivo que existe com heading que sumiu é link
#    meio-morto: leva o leitor ao topo do arquivo errado em silêncio. Foi
#    exatamente o caso do `README.md#mapa-de-disparo…`. Verificar só a
#    existência do arquivo deixaria esse passar.
#
# 2. **Falha FECHADA na vacuidade** (R12). Zero link encontrado REPROVA. Uma
#    régua que não acha o que medir é indistinguível de uma régua que aprovou
#    tudo — e este script é um regex sobre markdown, a coisa mais fácil de
#    quebrar em silêncio do repo. Se os links realmente acabarem, o número
#    mínimo se ajusta aqui, num diff que alguém revisa.
#
# 3. **Só link markdown** `](…)`. Path citado em prosa ou em bloco de código é
#    ilustração, não navegação — cobrá-lo faria a régua acusar o legítimo, e
#    régua que grita demais é desligada.
#
# Injeção de dependência por `ITA_LINK_BASE` / `ITA_LINK_ROOTS` / `ITA_LINK_MIN`
# (R10, alavanca nº1): `check-links-claude-test.sh` constrói a árvore defeituosa
# à mão, sem tocar nos arquivos reais do repo.
# ============================================================================

set -eu

REPO="$(cd "$(dirname "$0")/.." && pwd)"
BASE="${ITA_LINK_BASE:-$REPO}"
ROOTS="${ITA_LINK_ROOTS:-specs .specify/memory}"
# Anti-vacuidade: hoje o repo tem 5 links distintos vivos. Abaixo disso, o
# regex quebrou ou a doutrina sumiu — nos dois casos a régua deve reprovar.
MIN_LINKS="${ITA_LINK_MIN:-3}"

TAB="$(printf '\t')"

# --- 1. pelo menos uma raiz existe ------------------------------------------
FOUND_ROOT=0
for r in $ROOTS; do
  [ -d "$BASE/$r" ] && FOUND_ROOT=1
done

if [ "$FOUND_ROOT" -eq 0 ]; then
  echo "links-claude: nenhuma das raízes existe em '$BASE'." >&2
  echo "              procurei: $ROOTS" >&2
  echo "              Sem doutrina não há link a validar — e uma régua que não" >&2
  echo "              acha o corpus tem de reprovar, não passar." >&2
  exit 1
fi

# --- 2. colher os links ------------------------------------------------------
# `FILENAME`/`FNR` do awk dão arquivo e linha de graça. O laço interno pega
# mais de um link por linha (as tabelas W0–W3 têm três).
LINKS=$(cd "$BASE" && find $ROOTS -name '*.md' -type f 2>/dev/null | sort | while read -r f; do
  awk -v f="$f" '
    {
      line = $0
      while (match(line, /\]\([^)]*\.claude\/[^)]*\)/)) {
        print f "\t" FNR "\t" substr(line, RSTART + 2, RLENGTH - 3)
        line = substr(line, RSTART + RLENGTH)
      }
    }
  ' "$f"
done)

TOTAL=$(printf '%s' "$LINKS" | grep -c . || true)

if [ "$TOTAL" -lt "$MIN_LINKS" ]; then
  echo "links-claude: achei $TOTAL link(s) para \`.claude/\` — o mínimo é $MIN_LINKS." >&2
  echo "              Ou o regex parou de casar, ou a doutrina que aponta para" >&2
  echo "              o harness sumiu. Régua sem corpus aprova por vacuidade;" >&2
  echo "              se a queda for legítima, ajuste ITA_LINK_MIN no script." >&2
  exit 1
fi

# --- 3. cada link resolve ----------------------------------------------------
BROKEN=$(mktemp)
ANCHORED=0
trap 'rm -f "$BROKEN"' EXIT

printf '%s\n' "$LINKS" | while IFS="$TAB" read -r file lineno link; do
  [ -n "$link" ] || continue

  case "$link" in
    *\#*) path="${link%%\#*}"; anchor="${link#*\#}" ;;
    *)    path="$link";        anchor="" ;;
  esac

  full="$(dirname "$BASE/$file")/$path"

  if [ ! -e "$full" ]; then
    printf '%s:%s — alvo inexistente: %s\n' "$file" "$lineno" "$path" >>"$BROKEN"
    continue
  fi

  # Âncora só faz sentido contra um `.md`; num diretório, é ruído.
  [ -n "$anchor" ] || continue
  [ -f "$full" ] || continue
  case "$path" in *.md) ;; *) continue ;; esac

  # Slug no formato do GitHub: minúsculas, pontuação fora, espaço vira hífen.
  # Acentos ficam — `[:alnum:]` os cobre no locale do repo.
  if ! grep -q '^#\{1,6\} ' "$full"; then
    printf '%s:%s — âncora #%s, mas %s não tem heading nenhum\n' \
      "$file" "$lineno" "$anchor" "$path" >>"$BROKEN"
    continue
  fi

  if ! sed -n 's/^#\{1,6\}[[:space:]]\{1,\}//p' "$full" \
       | tr '[:upper:]' '[:lower:]' \
       | sed 's/[^[:alnum:] _-]//g; s/[[:space:]]\{1,\}/-/g' \
       | grep -qx "$anchor"; then
    printf '%s:%s — âncora morta: #%s (o arquivo %s existe, o heading não)\n' \
      "$file" "$lineno" "$anchor" "$path" >>"$BROKEN"
  fi
done

# --- 4. veredito -------------------------------------------------------------
if [ -s "$BROKEN" ]; then
  echo "links-claude: link para \`.claude/\` que não resolve —" >&2
  sed 's/^/  ✗ /' "$BROKEN" >&2
  echo >&2
  echo "              Um path morto numa spec é doutrina que aponta para o" >&2
  echo "              nada: quem seguir o link não descobre que ele quebrou." >&2
  echo "              Conserte o alvo, ou tire o link e deixe o nome em prosa." >&2
  exit 1
fi

ANCHORED=$(printf '%s\n' "$LINKS" | grep -c '#' || true)
echo "  ✅ links-claude: $TOTAL link(s) para \`.claude/\` resolvem ($ANCHORED com âncora)"
