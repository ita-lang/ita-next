#!/bin/sh
# ============================================================================
# gate-armed-hook.sh — a catraca da catraca
# ============================================================================
#
# `PreToolUse(Bash)` do `.claude/settings.json`. **NÃO** roda `make gate`:
# verifica que o portão REAL — `tools/git-hooks/pre-commit`, via
# `core.hooksPath` — está ARMADO neste clone. O gate roda uma vez só, lá.
#
# ---------------------------------------------------------------------------
# Por que esta forma, e não a de 2026-07-29
# ---------------------------------------------------------------------------
#
# A versão anterior decidia lendo `$CLAUDE_TOOL_INPUT` — variável que **não
# existe**. O Claude Code entrega a tool call por **stdin, em JSON**; as únicas
# variáveis que ele exporta para hooks são `CLAUDE_PROJECT_DIR`,
# `CLAUDE_PLUGIN_ROOT`, `CLAUDE_PLUGIN_DATA`, `CLAUDE_EFFORT`,
# `CLAUDE_CODE_REMOTE`, `CLAUDE_CODE_BRIDGE_SESSION_ID` e
# `CLAUDE_PLUGIN_OPTION_*`.
#
#   > "For command hooks, input arrives on stdin."
#   — code.claude.com/docs/en/hooks, lido em 2026-08-06
#
# Variável vazia ⟹ o `grep` falha ⟹ o `if` nunca entra ⟹ `exit 0`. A guarda era
# uma FRASE, não uma catraca: a R12 violada dentro do arquivo que implementa a
# R14, e invisível porque o modo de falha dela é o silêncio.
#
# `tools/git-hooks/pre-commit:8-12` atribui aquela falha a "os hooks são lidos
# no INÍCIO da sessão". Isso é verdade e é **outra** coisa. A frase seguinte —
# "a lógica dele estava correta (verificada isolada: exit 2, mensagem certa)" —
# não se sustenta: com a variável inexistente, carregado ou não, aquele caminho
# nunca bloquearia nada. A verificação isolada preencheu à mão o que o Claude
# Code nunca preenche.
#
# ---------------------------------------------------------------------------
# O que esta versão acrescenta
# ---------------------------------------------------------------------------
#
# O furo que NENHUMA das duas redes cobria: um clone onde `make setup-hooks`
# nunca rodou não tem portão nenhum — `core.hooksPath` é config LOCAL, não vem
# no clone — e nada avisa. Commit passa limpo, CI verde, zero diagnóstico.
#
# Falha FECHADA (R5): sem `jq`, com o contrato do stdin quebrado, ou com o
# portão desarmado ⟹ `exit 2`. Um gate cuja falha-padrão é "OK" é documentação
# executável do que alguém lembrou.
#
# Catraca: `make gate-hook-selftest`, pendurado no `make gate`. Prova os DOIS
# lados — bloqueia o que deve e deixa passar o que não é `git commit` —, e cada
# caminho de recusa tem mensagem própria (R13).
# ============================================================================

set -eu

ESPERADO='tools/git-hooks'

# --- 1. a tool call vem por STDIN, em JSON ---------------------------------
if ! command -v jq >/dev/null 2>&1; then
  echo 'portão: `jq` não encontrado — sem ele não dá para ler a tool call.' >&2
  echo '        `brew install jq`, ou remova o hook de .claude/settings.json.' >&2
  exit 2
fi

PAYLOAD=$(cat)

# Parse que FALHA é contrato quebrado (o Claude Code mudou o formato), não
# "nada a fazer". Ausência do campo é outra coisa: tool que não é Bash.
if ! CMD=$(printf '%s' "$PAYLOAD" | jq -r '.tool_input.command // empty' 2>/dev/null); then
  echo 'portão: o stdin do hook não é o JSON esperado — o contrato mudou?' >&2
  echo '        Ver code.claude.com/docs/en/hooks (campo .tool_input.command).' >&2
  exit 2
fi

# --- 2. não é `git commit`? não é assunto nosso ----------------------------
# `git` precisa estar em posição de COMANDO — início, ou depois de `;`/`&&`/
# `||`/`|`/newline —, não em qualquer lugar da string.
#
# A primeira versão casava a substring solta e reprovou, em 2026-08-06, o
# `echo` que continha `git commit --no-verify` como DADO. Num repo cujo
# CLAUDE.md, Makefile e hooks citam `git commit` em prosa, esse falso positivo
# é recorrente — e barrar `grep`/`echo`/`printf` não protege coisa alguma: a
# rede real é o pre-commit nativo, e este hook é redundância.
#
# O casamento continua frouxo o bastante para ser contornável (`sh -c "git
# commit"` escapa). É de propósito, e é a doutrina escrita do dono em
# `tools/git-hooks/pre-commit:24`: "o portão existe para impedir o
# esquecimento, não para impedir a decisão".
#
# `[^|;&]*` entre as âncoras pega `git -C x commit` e `git -c k=v commit`, que
# um `git\s+commit` perderia. O prefixo opcional cobre `FOO=1 git …` e
# `env FOO=1 git …`.
CMD_SEGMENTOS=$(printf '%s' "$CMD" | tr ';|&\n' '\n\n\n\n')
GIT_COMMIT='^[[:space:]]*(env[[:space:]]+|[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*git\b[^|;&]*\bcommit\b'

printf '%s' "$CMD_SEGMENTOS" | grep -qE "$GIT_COMMIT" || exit 0

# --- 3. `--no-verify` desarma o portão para este commit --------------------
# O escape é deliberado e é do DONO (tools/git-hooks/pre-commit:24). Um agente
# usá-lo por conta própria transforma "impedir o esquecimento" em "contornar a
# decisão".
#
# Casado no SEGMENTO do commit, não na linha inteira: `git commit -m x && ls -n`
# não é um commit sem verificação.
if printf '%s' "$CMD_SEGMENTOS" | grep -E "$GIT_COMMIT" \
   | grep -qE '(^|[[:space:]])(--no-verify|-n)([[:space:]]|$)'; then
  echo 'portão: `git commit --no-verify` pula o pre-commit — e o gate junto.' >&2
  echo '        O escape é decisão do dono (tools/git-hooks/pre-commit:24).' >&2
  echo '        Se é mesmo para pular, rode você: `! git commit --no-verify …`' >&2
  exit 2
fi

# --- 4. o portão está armado NESTE clone? ----------------------------------
RAIZ="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"

# Injeção de dependência (R10, alavanca nº1): o selftest constrói o clone
# defeituoso à mão, sem tocar no config real. `${VAR-}` sem `:` DE PROPÓSITO —
# `ITA_GATE_HOOKSPATH=""` precisa significar "não configurado", e não cair no
# default; com `${VAR:-}` o caso mais importante do teste seria inalcançável.
ATUAL="${ITA_GATE_HOOKSPATH-$(git -C "$RAIZ" config core.hooksPath 2>/dev/null || true)}"

if [ "$ATUAL" != "$ESPERADO" ]; then
  echo "portão NÃO instalado: core.hooksPath='${ATUAL:-<vazio>}', esperado '$ESPERADO'." >&2
  echo '        Rode `make setup-hooks`. Sem isso `git commit` não roda `make gate`,' >&2
  echo '        e nada mais neste clone o faria.' >&2
  exit 2
fi

# --- 5. armado, mas apontando para um hook inerte? -------------------------
HOOK="$RAIZ/$ESPERADO/pre-commit"
if [ ! -x "$HOOK" ]; then
  echo "portão apontado mas INERTE: '$HOOK' não existe ou não é executável." >&2
  echo '        `chmod +x` nele, ou `make setup-hooks` de novo.' >&2
  exit 2
fi

exit 0
