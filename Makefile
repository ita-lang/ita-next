# ===========================================================================
# Makefile do ita-next — paths relativos à raiz do repo (ita-next/)
# ===========================================================================
# Fase 1 (léxico) é Dart PURO: usa o `dart` do sistema (DART ?= dart).
# O SDK pinado (dart-sdk.pin) só é necessário na fase de codegen (.tu -> .dill);
# aí basta `make pin` (ou apontar DART para o binário pinado).
# ===========================================================================

DART    ?= dart
COMPILER = compiler

.DEFAULT_GOAL := help

# Resolve dependências do pacote (compiler/pubspec.yaml).
get:
	@cd $(COMPILER) && $(DART) pub get

# Testes unitários (compiler/test/**/*_test.dart). Preenchidos na Fatia 2.
test:
	@cd $(COMPILER) && $(DART) test

# Analisador estático (analysis_options.yaml). Deve ficar no verde desde o dia 1.
analyze:
	@cd $(COMPILER) && $(DART) analyze

# Procedência de ruling (Art. IV-6), mecanizada. CATRACA: o legado tem baseline
# em `tools/citations.baseline` e só pode DESCER; o que não passa é uma citação
# NOVA sem procedência. `--list` mostra todas, `--update` regrava (só p/ baixo).
citations: citations-test
	@tools/check-citations.sh

# O gate de procedência é load-bearing? Cada regra acusa o que promete, e não
# acusa o que é legítimo. Roda ANTES do `citations` — régua quebrada primeiro
# reprova a si mesma, não ao repo.
citations-test:
	@tools/check-citations-test.sh

# Duas guardas com a MESMA frase são indistinguíveis no relatório e na asserção
# — foi assim que uma anti-vacuidade ficou morta por dias (mutante M7).
assertions:
	@tools/check-assertions.sh

# Tokeniza um arquivo .tu (dump legível). O driver `itac tokenize` entra na Fatia 2.
# Uso: make tokenize FILE=examples/hello.tu
tokenize:
	@cd $(COMPILER) && $(DART) run bin/itac.dart tokenize ../$(FILE)

# Conformância léxica: os goldens conformance/valid|invalid vs o dump do lexer.
# Vive no lexer_test.dart (grupos "conformance/…"); `make test` também cobre.
conformance:
	@cd $(COMPILER) && $(DART) test -n conformance

# O guard de compile-time do ADR-0006: falha se a mediana passar de 0,5 s por
# arquivo — "barreira contra volta ao JIT ou codegen O(n²)". Mede o AOT; o JIT
# é ~20× mais lento e reprovaria todo dia por um custo que a entrega não paga.
bench: itac-aot
	@cd codegen && $(DART_CG) run tool/bench.dart

# O `itac` AOT (ADR-0006) + o wrapper que lhe aponta o SDK. `build/itac` e
# `bin/itac` são gitignorados: ~8 MB de artefato e um caminho ABSOLUTO de
# máquina não entram no repo.
itac-aot:
	@bash tools/build-itac.sh

# Materializa + valida o SDK Dart pinado (download ~200MB). NÃO é necessário
# para o léxico — só rode na fase de codegen. Ver dart-sdk.pin.
pin:
	@bash tools/pin-dart.sh

# ---- Backend F7 (codegen) — pacote ISOLADO ita-next/codegen -----------------
# Ver specs/013 §0-A (o codegen NÃO mora em compiler/lib/codegen — isola o
# conflito kernel×test).
#
# `dart` do backend. Default: o SDK PINADO (dart-sdk.pin). SOBRESCREVÍVEL, para
# o CI — onde o `setup-dart` instala a MESMA versão no PATH e `.dart-sdk/` não
# existe (é gitignorado, ~586 MB):
#
#     make codegen-test DART_CG=dart
#
# ABSOLUTO via $(CURDIR) DE PROPÓSITO: as receitas fazem `cd codegen`, e um
# default relativo (`../.dart-sdk/…`) só funcionaria por causa desse `cd` — um
# alvo futuro que rode da raiz quebraria com exit 127 e nenhum diagnóstico.
# Absoluto também deixa `DART_CG=/algum/path/dart` funcionar, o que `../$(VAR)`
# tornava impossível.
DART_CG ?= $(CURDIR)/.dart-sdk/3.12.2/dart-sdk/bin/dart

# `?=` NÃO dispara quando a variável está definida-porém-VAZIA (ex.: `DART_CG=`
# no env de uma matriz do Actions): a receita viraria `cd codegen && pub get`.
# Falha honesta em vez de comportamento torto.
ifeq ($(strip $(DART_CG)),)
  $(error DART_CG vazio — use `DART_CG=dart` ou remova a variável do ambiente)
endif

# Diagnóstico nunca mente: sem pin e sem override, diga O QUE fazer — em vez de
# um `No such file or directory` do shell.
codegen-guard:
	@command -v $(DART_CG) >/dev/null 2>&1 || { \
	  echo "ita-next: '$(DART_CG)' não existe."; \
	  echo "  -> 'make pin'  (baixa o SDK pinado), OU"; \
	  echo "  -> 'make <alvo> DART_CG=dart'  (se o dart do pin já está no PATH)."; \
	  exit 1; }

codegen-get: codegen-guard
	@cd codegen && $(DART_CG) pub get

codegen-analyze: codegen-guard
	@cd codegen && $(DART_CG) analyze

#
# ⚠️ ORDEM: o `golden_test` roda ANTES do `ca_ledger_test`, e não é estética.
# O ledger deriva os alvos de `codegen/build/alvos-rodados.txt`, que o runner
# grava ao fechar verde; invertido, ele leria o registro da execução ANTERIOR e
# afirmaria alvos sobre código que já mudou. O `alvos.dart` recusa registro
# obsoleto, então a inversão não mente — mas o placar encolheria a cada
# `make codegen-test`, sem razão visível.
codegen-test: codegen-guard
	@cd codegen && $(DART_CG) run test/sanitize_test.dart
	@cd codegen && $(DART_CG) run test/finalize_test.dart
	@cd codegen && $(DART_CG) run test/invariants_test.dart
	@cd codegen && $(DART_CG) run test/driver_build_test.dart
	@cd codegen && $(DART_CG) run test/golden_test.dart
	@cd codegen && $(DART_CG) run test/ca_ledger_test.dart

# Golden-runner do emitter: compila `conformance/codegen/*.tu` e roda o `.dill`
# nos **3 alvos** da §7.7 — VM/JIT, AOT (`dart compile exe` sobre o `.dill`
# COMPLETO) e JS (`dart compile js` sobre o mínimo + `node`) —, comparando stdout
# e exit code. O runner também assere o pin nas 3 pontas (dart ↔ vm_platform.dill
# ↔ pkg/kernel vendorado).
#
# Custo medido (2026-08-06, M2): ~10 s só VM, ~100 s nos três — o AOT compila um
# `.dill` de 8 MB por fixture. Por isso o `codegen-golden-vm`, para iteração; o
# recorte aparece no relatório e o ledger NÃO fecha os CAs dos alvos ausentes,
# então o atalho não vira placar inflado.
#
# `codegen-golden-update` regrava os `.out` — só use depois de LER a saída nova.
codegen-golden: codegen-guard
	@cd codegen && $(DART_CG) run test/golden_test.dart

codegen-golden-vm: codegen-guard
	@cd codegen && $(DART_CG) run test/golden_test.dart --targets=vm

codegen-golden-update: codegen-guard
	@cd codegen && $(DART_CG) run test/golden_test.dart --update

# A catraca da catraca prova que sabe ficar VERMELHA (R14). Roda ANTES de tudo,
# pelo mesmo motivo do `citations-test`: régua quebrada reprova a si mesma, não
# ao repo. Custa ~50ms.
#
# Existe porque a versão anterior do hook do harness lia `$$CLAUDE_TOOL_INPUT`
# — variável que o Claude Code NÃO exporta (a tool call vem por stdin, em JSON).
# A guarda nunca disparou, e o modo de falha dela era o silêncio: nada ficava
# vermelho. Auditado em 2026-08-06.
gate-hook-selftest:
	@tools/gate-armed-hook-test.sh

# O CI roda o PORTÃO INTEIRO? Compara os pré-requisitos do `gate:` (abaixo) com
# os `make <alvo>` que o ci.yml executa. Roda depois do seu próprio RED, pelo
# mesmo motivo do `citations-test`.
#
# Existe porque, auditado em 2026-08-26, das sete dependências do `gate` o CI
# rodava SEIS — e a que faltava era o `gate-hook-selftest`, a catraca que prova
# que o hook do harness sabe ficar vermelho. O furo era circular: aquela catraca
# só rodava pelo pre-commit, que só dispara com `core.hooksPath` configurado —
# config LOCAL, que não vem no clone.
#
# ⚠️ É por causa desta régua que o CI chama `make analyze` / `make test` em vez
# de `dart analyze` / `dart test`: com dois caminhos para a mesma verificação,
# "o CI cobre o portão" vira julgamento humano de equivalência, e a régua teria
# de manter uma lista de exceções — cuja falha-padrão é OK (R5).
ci-cobre-gate: ci-cobre-gate-test
	@tools/check-ci-cobre-gate.sh

ci-cobre-gate-test:
	@tools/check-ci-cobre-gate-test.sh

# ---- O PORTÃO ---------------------------------------------------------------
#
# Tudo que separa "escrevi" de "commitei", num alvo só. Existe porque a lista de
# gates cresceu além do que alguém lembra: `analyze` × 2, `test` × 2, citações,
# asserções — e esquecer UM é como os 8 bugs da auditoria de 2026-07-29
# sobreviveram a 30 runs de CI verdes.
#
# Quem o dispara é o `pre-commit` NATIVO (`tools/git-hooks/`, via
# `core.hooksPath`) — vale para o dono no terminal e para qualquer agente. O
# hook do `.claude/settings.json` NÃO roda este alvo: ele verifica que o
# pre-commit está armado (`.claude/hooks/gate-armed-hook.sh`), que é o único furo que
# o nativo não pode cobrir sozinho — `core.hooksPath` é config local e não vem
# no clone.
# ⚠️ Esta lista é normativa em DOIS lugares: aqui e no `.github/workflows/ci.yml`.
# O `ci-cobre-gate` é quem impede as duas de divergirem — alvo novo aqui sem step
# lá reprova, com nome. Antes dele a divergência era silenciosa, e durou.
gate: gate-hook-selftest ci-cobre-gate analyze test codegen-analyze codegen-test citations assertions
	@echo ""
	@echo "  ✅ PORTÃO: front-end + codegen + citações + asserções"

# Instala o portão como hook de git NATIVO. Roda uma vez por clone.
#
# `core.hooksPath` em vez de copiar para `.git/hooks/`: o diretório fica
# VERSIONADO, então o gate não se perde no próximo clone nem diverge entre
# máquinas. O hook do `.claude/settings.json` cobre o caso do agente; este cobre
# TODOS os casos — e foi preciso porque, testado, o do harness não pegou um
# commit real (hooks são lidos no início da sessão).
setup-hooks:
	@git config core.hooksPath tools/git-hooks
	@echo "  ✅ portão instalado — 'git commit' passa a rodar 'make gate'"
	@echo "     (escape deliberado: git commit --no-verify)"

help:
	@echo "compiler (F1-F6): get | test | analyze | tokenize FILE=... | conformance | bench | pin"
	@echo "codegen  (F7):    codegen-get | codegen-analyze | codegen-test"
	@echo "                  codegen-golden (3 alvos) | codegen-golden-vm (rápido)"
	@echo "                  codegen-golden-update"
	@echo "                  (dart do backend: DART_CG=... — default é o SDK pinado)"
	@echo "PORTÃO:           gate | setup-hooks  (instala o pre-commit nativo)"
	@echo "                  gate-hook-selftest | ci-cobre-gate  (as catracas do portão)"

.PHONY: get test analyze citations citations-test assertions gate gate-hook-selftest \
        ci-cobre-gate ci-cobre-gate-test setup-hooks tokenize conformance bench itac-aot pin help \
        codegen-guard codegen-get codegen-analyze codegen-test \
        codegen-golden codegen-golden-vm codegen-golden-update
