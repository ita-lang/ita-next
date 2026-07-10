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

help:
	@echo "Targets: get | test | analyze | tokenize FILE=... | conformance | bench | pin"

.PHONY: get test analyze tokenize conformance bench pin help
