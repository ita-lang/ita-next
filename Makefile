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

# Tokeniza um arquivo .tu (dump legível). O driver `itac tokenize` entra na Fatia 2.
# Uso: make tokenize FILE=examples/hello.tu
tokenize:
	@cd $(COMPILER) && $(DART) run bin/itac.dart tokenize ../$(FILE)

# Conformância léxica: os goldens conformance/valid|invalid vs o dump do lexer.
# Vive no lexer_test.dart (grupos "conformance/…"); `make test` também cobre.
conformance:
	@cd $(COMPILER) && $(DART) test -n conformance

# Benchmark de compile-time (itac AOT, ADR-0006). Entra na fase de codegen.
bench:
	@echo "bench: placeholder — benchmark AOT entra na fase de codegen (build-itac.sh)."

# Materializa + valida o SDK Dart pinado (download ~200MB). NÃO é necessário
# para o léxico — só rode na fase de codegen. Ver dart-sdk.pin.
pin:
	@bash tools/pin-dart.sh

# ---- Backend F7 (codegen) — pacote ISOLADO ita-next/codegen -----------------
# Roda SEMPRE com o dart PINADO (kernel vendorado fmt 130). Ver specs/013 §0-A
# (o codegen NÃO mora em compiler/lib/codegen — isola o conflito kernel×test).
DART_PIN = .dart-sdk/3.12.2/dart-sdk/bin/dart

codegen-get:
	@cd codegen && ../$(DART_PIN) pub get

codegen-analyze:
	@cd codegen && ../$(DART_PIN) analyze

codegen-test:
	@cd codegen && ../$(DART_PIN) run test/sanitize_test.dart
	@cd codegen && ../$(DART_PIN) run test/finalize_test.dart
	@cd codegen && ../$(DART_PIN) run test/golden_test.dart

# Golden-runner do emitter: compila `conformance/codegen/*.tu`, RODA na VM pinada
# e compara stdout + exit code (spec 013 §7.7/§11). `codegen-golden-update`
# regrava os `.out` — só use depois de LER a saída nova.
codegen-golden:
	@cd codegen && ../$(DART_PIN) run test/golden_test.dart

codegen-golden-update:
	@cd codegen && ../$(DART_PIN) run test/golden_test.dart --update

help:
	@echo "compiler (F1-F6): get | test | analyze | tokenize FILE=... | conformance | bench | pin"
	@echo "codegen  (F7):    codegen-get | codegen-analyze | codegen-test"
	@echo "                  codegen-golden | codegen-golden-update"

.PHONY: get test analyze tokenize conformance bench pin help \
        codegen-get codegen-analyze codegen-test \
        codegen-golden codegen-golden-update
