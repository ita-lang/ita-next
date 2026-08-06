#!/bin/sh
# ============================================================================
# build-itac.sh — o `itac` AOT do ADR-0006
# ============================================================================
#
# *"O `itac` de dev e de CI é o binário AOT, não JIT."* O ADR mediu o motivo no
# repo anterior: em JIT paga-se startup da VM + JIT do compilador inteiro a cada
# invocação — **~5–9 s para um hello**, e o corpus de conformance ia de 76,4 s
# (JIT) para 1,5 s (AOT). Compile-time é a métrica nº1 do Itá, e o norte escrito
# é *"perto do Go"*.
#
# O binário sai em `build/itac`, gitignorado e sob demanda: ~10 MB de artefato
# não entram no repo.
#
# ⚠️ **O AOT NÃO carrega o `vm_platform.dill` junto.** Sob AOT o
# `Platform.resolvedExecutable` é o próprio `itac`, e a derivação "o SDK que
# compila é o mesmo que executa" — verdadeira em JIT — deixa de valer. Por isso
# este script grava um WRAPPER (`bin/itac`) que exporta `ITA_DART_SDK` apontando
# para o SDK do pin. É o mesmo tropeço que o ADR-0006 já registra: *"Fix
# necessário: `ITA_COMPILER_LIB=compiler/lib` (sob AOT, `Platform.script` aponta
# pro binário, não achava `toml`)"*.
#
# P9 (zero Python) e P11 (zero codegen): sh + o `dart` do pin, nada mais.

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

# UMA fonte para a versão — o pin é normativo ("os TRÊS têm que vir da MESMA
# versão stable"), e hardcodar aqui faria o binário divergir dele em silêncio.
VERSAO=$(grep '^DART_VERSION=' dart-sdk.pin | cut -d= -f2)
DART="${DART_CG:-$ROOT/.dart-sdk/$VERSAO/dart-sdk/bin/dart}"

# ⚠️ O SDK é DERIVADO do dart que vamos usar, não do caminho `.dart-sdk/`.
# No CI o `.dart-sdk/` NÃO existe (é gitignorado, ~586 MB): o `setup-dart`
# instala a versão do pin no PATH e o Makefile passa `DART_CG=dart`. Montar
# `$ROOT/.dart-sdk/$VERSAO` cravaria um caminho que só existe na máquina do dev,
# e o wrapper sairia apontando para o vazio — falha no runner, não aqui.
DART_ABS=$(command -v "$DART" 2>/dev/null || true)
if [ -z "$DART_ABS" ] || [ ! -x "$DART_ABS" ]; then
  echo "build-itac: dart não encontrado: $DART" >&2
  echo "            rode \`make pin\` (baixa o SDK $VERSAO), ou passe DART_CG=dart" >&2
  exit 1
fi
SDK=$(cd "$(dirname "$DART_ABS")/.." && pwd)

if [ ! -f "$SDK/lib/_internal/vm_platform.dill" ]; then
  echo "build-itac: $SDK não tem lib/_internal/vm_platform.dill" >&2
  echo "            (derivado de $DART_ABS — é mesmo um SDK completo?)" >&2
  exit 1
fi

mkdir -p "$ROOT/build" "$ROOT/bin"

# O entry-point é o itac COMPLETO (F1–F7), que mora no pacote `codegen` porque
# `build` precisa do `compileToDill` de lá e a dependência de volta seria
# circular. `cd codegen` para o package_config ser o daquele pacote.
cd "$ROOT/codegen"
"$DART" compile exe bin/itac.dart -o "$ROOT/build/itac"
cd "$ROOT"

# O wrapper: fixa o SDK e delega. `exec` para o exit code ser o do itac, e
# `"$@"` com aspas para argumentos com espaço sobreviverem.
cat > "$ROOT/bin/itac" <<WRAPPER
#!/bin/sh
# GERADO por tools/build-itac.sh — não edite à mão.
#
# Existe porque o binário AOT não acha o \`vm_platform.dill\` sozinho: sob AOT o
# \`Platform.resolvedExecutable\` é este \`itac\`, não o \`dart\` do SDK.
# \`ITA_DART_SDK\` é o que \`dartSdkDir()\` consulta primeiro.
ITA_DART_SDK="\${ITA_DART_SDK:-$SDK}"
export ITA_DART_SDK
exec "\${ITA_ITAC_BIN:-$ROOT/build/itac}" "\$@"
WRAPPER
chmod +x "$ROOT/bin/itac"

TAM=$(wc -c < "$ROOT/build/itac" | tr -d ' ')
echo "  ✅ build/itac ($((TAM / 1024 / 1024)) MB, AOT, SDK $VERSAO)"
echo "     wrapper: bin/itac  (exporta ITA_DART_SDK=$SDK)"
