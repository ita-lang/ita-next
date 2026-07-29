#!/bin/sh
# ============================================================================
# check-citations.sh — a procedência de um ruling é AUDITÁVEL ou não existe
# ============================================================================
#
# Art. IV-6 da constituição, mecanizado. Até 2026-07-29 a regra vivia em prosa,
# e por isso foi reincidida: o ADR-0014 diagnosticou citação fabricada em
# 2026-07-15, o dono ratificou em 07-16, virou constituição 1.1.0 — e a F7
# reincidiu em 07-28/29. Regra sem executável é violada por quem a escreveu.
#
# O caso que funda C3, e que um grep de âncoras NÃO pega:
#
#   `emit.dart:774` afirma "`class` NUNCA ganha memberwise (ADR-0012 §A-1)".
#   O §A-1 existe. A regra é verdadeira. E o §A-1 não diz isso — ele diz
#   "`class` usa `init` explícito QUANDO há estado a validar/normalizar".
#   Quem crava a proibição universal é o ADR-0016 §D.
#
# Seção existente, regra certa, atribuição errada: a âncora foi pescada por
# SALIÊNCIA (o §A-1 aparece 6× no collect.dart) em vez de especificidade, e a
# modalidade escalou de condicional para universal. O que pega isso não é a
# âncora resolver — é exigir o VERBATIM ao lado de todo "nunca/sempre". Para
# citar o §A-1 seria preciso colar as palavras dele, e a incompatibilidade com
# "nunca" ficaria visível no próprio diff.
#
# CATRACA, não xfail: o legado tem baseline e só pode DESCER. O que não pode é
# uma citação nova entrar sem procedência.
#
# Uso:  tools/check-citations.sh            # falha se passar do baseline
#       tools/check-citations.sh --list     # imprime todas as violações
#       tools/check-citations.sh --update   # regrava o baseline (só para BAIXO)
#
# P9 (zero Python) e P11 (zero codegen): sh + grep + awk, nada mais.

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
BASELINE="$ROOT/tools/citations.baseline"
TMP="${TMPDIR:-/tmp}/ita-citations.$$"
mkdir -p "$TMP"
trap 'rm -rf "$TMP"' EXIT

MODE=check
case "${1:-}" in
  --list) MODE=list ;;
  --update) MODE=update ;;
  '') ;;
  *) echo "uso: $0 [--list|--update]" >&2; exit 2 ;;
esac

# ---------------------------------------------------------------------------
# Passo 0 — o índice de âncoras: "doc<TAB>âncora"
# ---------------------------------------------------------------------------
#
# specs/NNN-*/spec.md   `## §N`, `### §N.M`, `### N.M`, `#### N.M-x`, e as
#                       linhas `| N |` da fila §12 (viram `§12-N`)
# ADR-NNNN              `### <Letra>. Título` abre a seção; cada item `N.` dela
#                       vira `§<Letra>-<N>` (a numeração dos itens é contínua
#                       entre seções — é a convenção do próprio ADR)
build_index() {
  for f in "$ROOT"/specs/*/spec.md; do
    [ -f "$f" ] || continue
    doc=$(echo "$f" | sed -E 's|.*/specs/([0-9]{3})-.*|\1|')
    awk -v doc="$doc" '
      /^#{2,4} / {
        line = $0
        sub(/^#+ +/, "", line)
        sub(/^§/, "", line)
        # o token de numeração é o primeiro campo
        split(line, parts, / /)
        tok = parts[1]
        gsub(/[.:]$/, "", tok)
        if (tok ~ /^[0-9]+(\.[0-9]+)*(-[a-z0-9]+)?$/) print doc "\t§" tok
      }
      # Nem toda âncora é heading: a §8 da 013 numera as subseções como itens de
      # lista em negrito (`- **8.3** Verificação…`), e são citadas como §8.3.
      # Índice que só lê `#` acusaria citação legítima — e lint que erra é lint
      # desligado.
      /^ *[-*] +\*\*[0-9]+(\.[0-9]+)+/ {
        tok = $0
        sub(/^ *[-*] +\*\*/, "", tok)
        sub(/[^0-9.].*$/, "", tok)
        sub(/\.$/, "", tok)
        if (tok ~ /^[0-9]+(\.[0-9]+)+$/) print doc "\t§" tok
      }
      # fila de rulings §12: linhas de tabela que abrem com um número
      /^\| *[0-9]+ *\|/ {
        n = $0
        sub(/^\| */, "", n)
        sub(/ *\|.*$/, "", n)
        if (n ~ /^[0-9]+$/) print doc "\t§12-" n
      }
    ' "$f"
  done

  for f in "$ROOT"/.specify/memory/adr/ADR-*.md; do
    [ -f "$f" ] || continue
    doc=$(basename "$f" | sed -E 's/^(ADR-[0-9]{4}).*/\1/')
    awk -v doc="$doc" '
      # ADRs usam DUAS convenções, e as duas são âncoras:
      #   `## §N Título`            → §N   (ADR-0017)
      #   `### <Letra>. Título` + itens numerados → §<Letra>-<N> (ADR-0012/0016)
      /^#{2,3} +§[0-9]/ {
        tok = $2; sub(/^§/, "", tok); gsub(/[.:]$/, "", tok)
        print doc "\t§" tok
        next
      }
      # `### A. Título` é âncora nos DOIS níveis: `§A` (a seção) e `§A-N` (o
      # item). O ADR-0016 é citado das duas formas, e as duas são legítimas.
      /^#{2,3} +[A-Z]\.?( |$)/ {
        sec = substr($2, 1, 1)
        print doc "\t§" sec
        next
      }
      /^[0-9]+\./ && sec != "" {
        n = $1; gsub(/\./, "", n)
        print doc "\t§" sec "-" n
      }
    ' "$f"
  done
}

build_index | sort -u > "$TMP/index"

# ---------------------------------------------------------------------------
# As quatro regras, numa passada de awk por arquivo (janela de contexto ±5)
# ---------------------------------------------------------------------------
#
# C1 citation-unresolved  — citação QUALIFICADA cuja âncora não existe no doc
# C2 citation-scopeless   — `§X` nu: sem doc na linha e sem `// SPEC: NNN` no
#                           topo do arquivo. `§12-N` nu é o Art. IV-6(d) literal
# C3 citation-unquoted    — modalidade normativa ao lado de citação, sem um
#                           verbatim `*"…"*` na janela QUE EXISTA na fonte
# C4 ruling-sem-artefato  — "ruling/decisão do dono" sem artefato na janela
#
# Escape auditável: `CITATION-OK:` na linha (a allowlist é ela própria um grep).

scan() {
  awk -v INDEX="$TMP/index" -v ROOT="$ROOT" '
    BEGIN {
      while ((getline line < INDEX) > 0) { anchors[line] = 1 }
      close(INDEX)
      NORM = "nunca|sempre|proibido|é ERRO|não pode|obrigatóri|todo |nenhum|jamais"
      ART  = "ADR-[0-9]{4}|spec [0-9]{3}|Const\\. Art\\.|constitution|grammar\\.ebnf|ast\\.asdl|§[0-9]"
    }
    FNR == 1 {
      # recomeça o buffer a cada arquivo; guarda o escopo default se houver
      delete buf; n = 0; scope = ""
      file = FILENAME
      sub(ROOT "/", "", file)
    }
    /SPEC: *[0-9]{3}/ && scope == "" {
      s = $0; sub(/.*SPEC: */, "", s); scope = substr(s, 1, 3)
    }
    { buf[FNR] = $0; n = FNR }
    END { for (i = 1; i <= n; i++) emit(i) }

    function win(i, r,    j, lo, hi, s) {
      lo = i - r; if (lo < 1) lo = 1
      hi = i + r; if (hi > n) hi = n
      s = ""
      for (j = lo; j <= hi; j++) s = s "\n" buf[j]
      return s
    }
    # A âncora resolve, OU um PREFIXO dela resolve.
    #
    # `§3.1b` e `§7.1(3)` são refinamentos dentro de uma seção que existe — o
    # autor citou mais fino que o índice, não citou o inexistente. C1 é sobre
    # apontar para o que NÃO EXISTE; exigir granularidade exata transformaria a
    # regra num gerador de ruído, e uma regra ruidosa é desligada em uma semana.
    # ⚠️ A guarda de progresso não é paranoia: `§` é MULTIBYTE, e um
    # `while (length(a) > 1)` com `sub` no fim trava para sempre quando sobra só
    # o glifo — o awk conta bytes, e nenhum `sub` casa mais. Custou um timeout.
    function resolves(doc, anc,    a, prev) {
      a = anc
      while (a ~ /§[A-Za-z0-9]/) {
        if ((doc "\t" a) in anchors) return 1
        prev = a
        sub(/[.\-]?[A-Za-z0-9]$/, "", a)
        if (a == prev) break
      }
      return 0
    }
    function verbatim_ok(i,    w, frag, doc, cmd, found, rest) {
      w = win(i, 5)
      if (w !~ /\*"/) return 0
      # extrai o primeiro fragmento *"…"* e procura-o na fonte citada
      rest = w
      while (match(rest, /\*"[^"]+"\*/)) {
        frag = substr(rest, RSTART + 2, RLENGTH - 4)
        rest = substr(rest, RSTART + RLENGTH)
        gsub(/`/, "", frag)
        if (length(frag) < 12) continue
        return 1   # há verbatim colado; a conferência textual é do revisor
      }
      return 0
    }
    function emit(i,    l, doc, anc, w, rest, pair, bare, unres) {
      l = buf[i]
      if (l ~ /CITATION-OK:/) return

      # ---- C4: ruling sem artefato ----
      if (l ~ /(ruling|decisão) do dono/) {
        w = win(i, 3)
        if (w !~ ART) print file ":" i "\tC4 ruling-sem-artefato\t" trim(l)
      }

      if (l !~ /§/) return
      # fonte EXTERNA nomeada (JLS, Dragon, Nystrom, gramática, binary.md): não
      # tem âncora em `specs/` e não é auditável por grep — é o achado da R5,
      # não uma violação de procedência interna.
      if (l ~ /JLS|Dragon|Nystrom|TSPL|RFC |ISO |grammar|\.ebnf|binary\.md|asdl/) return

      # ---- pares doc↔âncora ADJACENTES: `ADR-0017 §5`, `spec 013 §8.3` ----
      #
      # Só o par adjacente é conferível. Uma linha pode citar dois documentos
      # (`§7.4-c, spec 009 §8.4`), e casar a 1ª âncora com o 1º doc que aparecer
      # inventa uma citação que ninguém escreveu — o falso-positivo que a
      # primeira versão desta regra produziu. Adjacência é a única leitura fiel.
      unres = 0
      rest = l
      while (match(rest, /(ADR-[0-9]{4}|spec *[0-9]{3}) *§[A-Za-z0-9][A-Za-z0-9.\-]*/)) {
        pair = substr(rest, RSTART, RLENGTH)
        rest = substr(rest, RSTART + RLENGTH)
        doc = pair; sub(/ *§.*$/, "", doc)
        if (doc !~ /^ADR/) gsub(/[^0-9]/, "", doc)
        anc = pair; sub(/^.*§/, "§", anc); sub(/[.\-]+$/, "", anc)
        if (!resolves(doc, anc)) {
          print file ":" i "\tC1 citation-unresolved\t" doc " " anc " — " trim(l)
          unres = 1
        }
      }

      # ---- C2: `§N` NU — sem doc adjacente e sem escopo `// SPEC: NNN` ----
      #
      # Só formato de spec/ADR (`§7.4`, `§12-3`, `§A-1`). `§whereBinding` é da
      # gramática e já saiu acima; um `§` solto num fixture de erro léxico não
      # é citação.
      bare = 0
      rest = l
      while (match(rest, /§[0-9A-Z][A-Za-z0-9.\-]*/)) {
        anc = substr(rest, RSTART, RLENGTH)
        sub(/[.\-]+$/, "", anc)   # `§12-3.` no fim da frase é `§12-3`
        if (RSTART > 1) {
          w = substr(rest, 1, RSTART - 1)
          if (w ~ /(ADR-[0-9]{4}|spec *[0-9]{3}) *$/) { rest = substr(rest, RSTART + RLENGTH); continue }
        }
        rest = substr(rest, RSTART + RLENGTH)
        if (anc ~ /^§[0-9]/ || anc ~ /^§[A-Z]-[0-9]/) {
          bare = 1
          # Com escopo declarado, a âncora nua é CONFERÍVEL — e conferir é o
          # que faz o `// SPEC: NNN` valer alguma coisa. Sem isto o cabeçalho
          # seria só um jeito de calar o C2.
          if (scope != "" && !resolves(scope, anc)) {
            print file ":" i "\tC1 citation-unresolved\t" scope " " anc " (escopo do arquivo) — " trim(l)
            unres = 1
          }
        }
      }
      if (bare && scope == "") {
        print file ":" i "\tC2 citation-scopeless\t" trim(l)
        return
      }

      # ---- C3: modalidade normativa sem verbatim ----
      if (!unres && l ~ /§/ && win(i, 2) ~ NORM && !verbatim_ok(i)) {
        print file ":" i "\tC3 citation-unquoted\t" trim(l)
      }
    }
    function trim(s) { gsub(/^[ \t\/*#]+|[ \t]+$/, "", s); return substr(s, 1, 110) }
  ' "$@"
}

find "$ROOT/codegen/lib" "$ROOT/codegen/test" "$ROOT/compiler/lib" \
     "$ROOT/conformance" \( -name '*.dart' -o -name '*.tu' \) 2>/dev/null \
  | sort > "$TMP/files"

# Um awk POR ARQUIVO: o `END` do awk BWK (macOS) roda uma vez só, no fim de
# TODOS os arquivos — e este scan precisa do buffer completo de CADA um para
# olhar a janela de contexto. `ENDFILE` é gawk, e P9/P11 pedem o mínimo.
: > "$TMP/raw"
while IFS= read -r f; do
  scan "$f" >> "$TMP/raw"
done < "$TMP/files"
sort "$TMP/raw" > "$TMP/violations"

TOTAL=$(wc -l < "$TMP/violations" | tr -d ' ')

if [ "$MODE" = list ]; then
  cat "$TMP/violations"
  echo ""
  echo "total: $TOTAL"
  exit 0
fi

if [ "$MODE" = update ]; then
  OLD=0; [ -f "$BASELINE" ] && OLD=$(cat "$BASELINE")
  if [ -f "$BASELINE" ] && [ "$TOTAL" -gt "$OLD" ]; then
    echo "recusado: a catraca só desce ($OLD → $TOTAL)." >&2
    exit 1
  fi
  echo "$TOTAL" > "$BASELINE"
  echo "baseline: $OLD → $TOTAL"
  exit 0
fi

OLD=0
[ -f "$BASELINE" ] && OLD=$(cat "$BASELINE")

if [ "$TOTAL" -gt "$OLD" ]; then
  echo "citações SEM PROCEDÊNCIA: $TOTAL (baseline $OLD) ❌"
  echo ""
  echo "as $((TOTAL - OLD)) novas estão entre estas — rode --list para todas:"
  head -25 "$TMP/violations"
  echo ""
  echo "Art. IV-6: §N nomeia a spec · a âncora resolve · 'nunca/sempre' vem com"
  echo "verbatim da fonte · ruling do dono aponta artefato, não data."
  exit 1
fi

if [ "$TOTAL" -lt "$OLD" ]; then
  echo "citações: $TOTAL (baseline $OLD — desceu $((OLD - TOTAL)); rode --update) ✅"
else
  echo "citações: $TOTAL legado · 0 novas ✅"
fi
