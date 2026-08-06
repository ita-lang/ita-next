#!/bin/sh
# ============================================================================
# gate-armed-hook-test.sh — o RED de `gate-armed-hook.sh`
# ============================================================================
#
# R14: "Antes de qualquer asserção, cada suíte roda `Harness.selfTest()`."
# A catraca da catraca precisa provar que sabe ficar VERMELHA — foi exatamente
# a ausência disto que deixou a versão de 2026-07-29 verde por 8 dias com uma
# guarda que nunca disparava.
#
# Mesmo padrão do `citations-test` (Makefile:35): roda ANTES do alvo que ele
# protege, para que uma régua quebrada reprove a si mesma, não ao repo.
#
# O hook é exercitado pelo MESMO caminho que o Claude Code usa — payload JSON
# por stdin, script real, sem cópia da lógica. Uma segunda cópia do regex aqui
# tornaria este teste capaz de passar com o hook quebrado.
#
# `core.hooksPath` entra por `ITA_GATE_HOOKSPATH` em vez de ser configurado de
# verdade: o teste constrói o clone defeituoso à mão (R10, alavanca nº2) sem
# desarmar o portão da máquina de quem o roda.
# ============================================================================

set -u

REPO="$(cd "$(dirname "$0")/.." && pwd)"
# O script vive em `.claude/hooks/` — o lugar que a doc de hooks documenta para
# scripts chamados por hook. O teste fica em `tools/`, com as outras réguas do
# `make` (`check-citations.sh`, `check-assertions.sh`).
HOOK="$REPO/.claude/hooks/gate-armed-hook.sh"
ARMADO='tools/git-hooks'
RAIZ_TESTE=''
PATH_TESTE=''

N=0
FALHAS=0

# caso <descrição> <exit esperado> <core.hooksPath> <payload> [substring no stderr]
caso() {
  desc="$1"; esperado="$2"; hookspath="$3"; payload="$4"; frase="${5-}"
  N=$((N + 1))

  saida=$(printf '%s' "$payload" \
    | env PATH="${PATH_TESTE:-$PATH}" CLAUDE_PROJECT_DIR="${RAIZ_TESTE:-$REPO}" \
          ITA_GATE_HOOKSPATH="$hookspath" "$HOOK" 2>&1)
  obtido=$?

  if [ "$obtido" -ne "$esperado" ]; then
    echo "  ❌ $desc"
    echo "     exit esperado: $esperado · obtido: $obtido"
    [ -n "$saida" ] && echo "     saída: $saida"
    FALHAS=$((FALHAS + 1))
    return
  fi

  # Duas guardas com a MESMA frase são indistinguíveis na asserção (R13): sem
  # esta metade, um único caminho de recusa atenderia a três casos distintos e
  # os outros dois nunca rodariam.
  if [ -n "$frase" ] && ! printf '%s' "$saida" | grep -qF "$frase"; then
    echo "  ❌ $desc"
    echo "     exit $obtido correto, mas a mensagem não identifica o caminho."
    echo "     esperava conter: $frase"
    echo "     obteve:          $saida"
    FALHAS=$((FALHAS + 1))
    return
  fi

  echo "  ✅ $desc"
}

COMMIT='{"tool_name":"Bash","tool_input":{"command":"git commit -m \"x\""}}'

echo ""
echo "  gate-armed-hook: o hook prova que sabe ficar VERMELHO"
echo ""

# --- deixa passar o que não é assunto dele ---------------------------------
# Com hooksPath VAZIO de propósito: se o roteamento não fosse real, o caminho
# do portão-desarmado dispararia e estes casos ficariam vermelhos. É o que
# torna o teste de roteamento não-vacuoso (R12).
caso 'git status não é git commit — passa' \
  0 '' '{"tool_name":"Bash","tool_input":{"command":"git status"}}'

caso 'git log --format=%H passa (não casa `commit` solto)' \
  0 '' '{"tool_name":"Bash","tool_input":{"command":"git log --format=%H"}}'

caso 'git status && echo commit passa (o `&&` corta o casamento)' \
  0 '' '{"tool_name":"Bash","tool_input":{"command":"git status && echo commit"}}'

caso 'tool que não é Bash (sem .tool_input.command) passa' \
  0 '' '{"tool_name":"Read","tool_input":{"file_path":"/tmp/x"}}'

# `git` fora de posição de comando é DADO, não commit. Estes quatro são o RED
# do falso positivo que a v1 produziu em 2026-08-06: ela barrou o próprio
# comando de teste que continha `git commit --no-verify` dentro de um `echo`.
# Num repo que cita `git commit` em prosa o tempo todo, isso é recorrente.
caso 'echo com `git commit` como texto passa' \
  0 '' '{"tool_name":"Bash","tool_input":{"command":"echo \"rode git commit -m x\""}}'

caso 'grep por `git commit` na doc passa' \
  0 '' '{"tool_name":"Bash","tool_input":{"command":"grep -rn \"git commit --no-verify\" CLAUDE.md"}}'

caso 'payload JSON contendo `git commit` como dado passa' \
  0 '' '{"tool_name":"Bash","tool_input":{"command":"printf %s (\"command\":\"git commit\")"}}'

caso 'git commit -m x && ls -n passa (o -n não é do commit)' \
  0 "$ARMADO" '{"tool_name":"Bash","tool_input":{"command":"git commit -m x && ls -n"}}'

# … e continua pegando o commit real quando ele não está na primeira posição.
caso 'cd sub && git commit com portão DESARMADO — bloqueia' \
  2 '' '{"tool_name":"Bash","tool_input":{"command":"cd codegen && git commit -m x"}}' \
  'portão NÃO instalado'

caso 'GIT_AUTHOR_NAME=x git commit com portão DESARMADO — bloqueia' \
  2 '' '{"tool_name":"Bash","tool_input":{"command":"GIT_AUTHOR_NAME=x git commit -m y"}}' \
  'portão NÃO instalado'

# --- bloqueia o que deve, com mensagem própria em cada caminho -------------
caso 'git commit com o portão DESARMADO — bloqueia' \
  2 '' "$COMMIT" 'portão NÃO instalado'

caso 'git commit com core.hooksPath APONTANDO PRO LUGAR ERRADO — bloqueia' \
  2 '.githooks' "$COMMIT" 'portão NÃO instalado'

caso 'git commit --no-verify com o portão armado — bloqueia' \
  2 "$ARMADO" \
  '{"tool_name":"Bash","tool_input":{"command":"git commit --no-verify -m \"x\""}}' \
  'no-verify'

caso 'git commit -n (forma curta de --no-verify) — bloqueia' \
  2 "$ARMADO" \
  '{"tool_name":"Bash","tool_input":{"command":"git commit -n -m \"x\""}}' \
  'no-verify'

caso 'stdin que não é o JSON do contrato — bloqueia' \
  2 "$ARMADO" 'isto não é json' 'contrato mudou'

# `core.hooksPath` aponta para o lugar certo, mas lá não há hook executável —
# um `chmod -x` acidental, ou um checkout que perdeu o bit. O caminho existia
# no script sem NENHUM caso que o alcançasse: um mutante que o trocava por
# `if false` sobrevivia à suíte inteira. R12, achado ao mutar em 2026-08-06.
CLONE_INERTE=$(mktemp -d)
mkdir -p "$CLONE_INERTE/tools/git-hooks"

RAIZ_TESTE="$CLONE_INERTE"
caso 'portão apontado mas o pre-commit NÃO EXISTE — bloqueia' \
  2 "$ARMADO" "$COMMIT" 'INERTE'

: > "$CLONE_INERTE/tools/git-hooks/pre-commit"
chmod -x "$CLONE_INERTE/tools/git-hooks/pre-commit"
caso 'portão apontado mas o pre-commit não é EXECUTÁVEL — bloqueia' \
  2 "$ARMADO" "$COMMIT" 'INERTE'

chmod +x "$CLONE_INERTE/tools/git-hooks/pre-commit"
caso 'clone com pre-commit executável — passa' \
  0 "$ARMADO" "$COMMIT"
RAIZ_TESTE=''
rm -rf "$CLONE_INERTE"

# Sem `jq` o hook não consegue LER a tool call — e um gate que não lê a entrada
# não pode aprovar nada (R5: falha-padrão "OK" é documentação executável do que
# alguém lembrou). Bloqueia até comando trivial, de propósito: o modo de falha
# precisa ser barulhento, não silencioso como o de 2026-07-29.
#
# Também sem caso até 2026-08-06 — o mutante que trocava este `exit 2` por
# `exit 0` sobrevivia à suíte.
SEM_JQ=$(mktemp -d)
mkdir -p "$SEM_JQ/bin"
for b in git grep tr cat mktemp; do
  caminho=$(command -v "$b") && ln -s "$caminho" "$SEM_JQ/bin/$b"
done

PATH_TESTE="$SEM_JQ/bin"
caso 'sem `jq` no PATH — bloqueia até um comando trivial' \
  2 "$ARMADO" '{"tool_name":"Bash","tool_input":{"command":"ls"}}' 'jq'
PATH_TESTE=''
rm -rf "$SEM_JQ"

# --- deixa passar quando o portão real está armado -------------------------
caso 'git commit com o portão ARMADO — passa (o pre-commit roda o gate)' \
  0 "$ARMADO" "$COMMIT"

caso 'git -C … commit com o portão ARMADO — passa (forma que `git\\s+commit` perdia)' \
  0 "$ARMADO" '{"tool_name":"Bash","tool_input":{"command":"git -C . commit -m \"x\""}}'

echo ""
if [ "$FALHAS" -ne 0 ]; then
  echo "  ❌ gate-armed-hook: $FALHAS de $N casos reprovaram"
  echo ""
  exit 1
fi

echo "  ✅ gate-armed-hook: $N casos — bloqueia o que deve, passa o que não é dele"
echo ""
