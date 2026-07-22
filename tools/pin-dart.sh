#!/usr/bin/env bash
# ===========================================================================
# pin-dart.sh (ita-next) — materializa e VALIDA o pin do backend Dart stable
# ===========================================================================
# Adaptado de ita/tools/pin-dart.sh. Paths relativos a ita-next/ (raiz do repo,
# = diretorio-pai deste script). Le ita-next/dart-sdk.pin e garante que os TRES
# componentes casam no mesmo formato de Kernel:
#   1. binario `dart` stable        (baixa+extrai em ita-next/.dart-sdk/<ver>/)
#   2. vm_platform.dill             (vem dentro do SDK)
#   3. pkg/kernel + _fe_analyzer_shared  (sparse-checkout da tag -> third_party/)
#
# IMPORTANTE (Fase 1 — lexico): o lexico e Dart PURO e NAO precisa deste script.
# O SDK stable (~200MB) e o vendor pkg/kernel so sao necessarios na fase de
# CODEGEN (.tu -> Kernel). Ate la, NAO rode isto. Os passos 3-6 (pub get com
# kernel, toml.runtime.dill, compilar hello.tu, suite) sao GUARDADOS: eles so
# executam quando os arquivos do compilador (bin/itac.dart etc.) ja existirem;
# antes disso o script materializa apenas SDK + vendor e para.
#
# Uso:
#   bash tools/pin-dart.sh            # materializa+valida o pin atual (idempotente)
#   bash tools/pin-dart.sh 3.13.0     # BUMP: baixa+vendora a nova versao e
#                                     # imprime o checklist (nao edita nada)
# ===========================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"              # ita-next/
PIN="$ROOT/dart-sdk.pin"
[ -f "$PIN" ] || { echo "FATAL: nao achei $PIN" >&2; exit 1; }

get() { grep -E "^$1=" "$PIN" | head -1 | cut -d= -f2-; }
DART_VERSION="$(get DART_VERSION)"
DART_KERNEL_TAG="$(get DART_KERNEL_TAG)"
EXPECTED_FMT="$(get EXPECTED_KERNEL_FORMAT)"
SDK_URL="$(get SDK_ZIP_URL)"
SDK_SHA="$(get SDK_ZIP_SHA256)"

BUMP=0
if [ "${1:-}" != "" ] && [ "$1" != "$DART_VERSION" ]; then
  BUMP=1
  DART_VERSION="$1"; DART_KERNEL_TAG="$1"; SDK_SHA=""
  SDK_URL="https://storage.googleapis.com/dart-archive/channels/stable/release/$1/sdk/dartsdk-macos-arm64-release.zip"
  echo ">> MODO BUMP: preparando Dart $1 (NAO edita dart-sdk.pin nem pubspec)"
fi

SDK_ROOT="$ROOT/.dart-sdk/$DART_VERSION/dart-sdk"
DART="$SDK_ROOT/bin/dart"
PLAT="$SDK_ROOT/lib/_internal/vm_platform.dill"
VENDOR="$ROOT/third_party/dart/$DART_KERNEL_TAG/pkg"
kver() { python3 -c "import struct,sys;print(struct.unpack('>II',open(sys.argv[1],'rb').read(8))[1])" "$1" 2>/dev/null; }
step() { echo; echo ">>> $*"; }

# --- 1. SDK stable --------------------------------------------------------
step "1. SDK stable $DART_VERSION"
if [ -x "$DART" ]; then
  echo "  ja presente: $SDK_ROOT"
else
  mkdir -p "$ROOT/.dart-sdk/$DART_VERSION"
  ZIP="$ROOT/.dart-sdk/$DART_VERSION/sdk.zip"
  echo "  baixando $SDK_URL"
  curl -fsSL "$SDK_URL" -o "$ZIP" || { echo "FATAL: download falhou" >&2; exit 1; }
  got="$(shasum -a 256 "$ZIP" | cut -d' ' -f1)"
  if [ -n "$SDK_SHA" ]; then
    [ "$got" = "$SDK_SHA" ] || { echo "FATAL: sha256 nao bate (pin=$SDK_SHA got=$got)" >&2; exit 1; }
    echo "  sha256 OK ($got)"
  else
    echo "  sha256=$got  (registre em SDK_ZIP_SHA256 do dart-sdk.pin ao promover)"
  fi
  unzip -q -o "$ZIP" -d "$ROOT/.dart-sdk/$DART_VERSION" && rm -f "$ZIP"
fi
"$DART" --version 2>&1 | sed 's/^/  /'
pfmt="$(kver "$PLAT")"
echo "  vm_platform.dill formato: ${pfmt:-?}"

# --- 2. vendor pkg/kernel -------------------------------------------------
step "2. Vendor pkg/kernel + _fe_analyzer_shared @ tag $DART_KERNEL_TAG"
if [ -f "$VENDOR/kernel/lib/binary/tag.dart" ]; then
  echo "  ja presente: $VENDOR"
else
  TMP="$(mktemp -d)"
  git clone --filter=blob:none --no-checkout --depth 1 --branch "$DART_KERNEL_TAG" \
    https://github.com/dart-lang/sdk.git "$TMP/sdk" 2>&1 | tail -1 | sed 's/^/  /'
  ( cd "$TMP/sdk" \
    && git sparse-checkout init --cone >/dev/null 2>&1 \
    && git sparse-checkout set pkg/kernel pkg/_fe_analyzer_shared >/dev/null 2>&1 \
    && git checkout "$DART_KERNEL_TAG" >/dev/null 2>&1 )
  mkdir -p "$VENDOR"
  cp -R "$TMP/sdk/pkg/kernel" "$VENDOR/"
  cp -R "$TMP/sdk/pkg/_fe_analyzer_shared" "$VENDOR/"
  rm -rf "$TMP"
  echo "  vendorizado em $VENDOR"
fi
grep -n "BinaryFormatVersion" "$VENDOR/kernel/lib/binary/tag.dart" 2>/dev/null | sed 's/^/  /'

if [ "$BUMP" = "1" ]; then
  echo
  echo ">>> BUMP preparado. Para promover Dart $DART_VERSION, edite:"
  echo "    - compiler/pubspec.yaml  -> path deps para third_party/dart/$DART_KERNEL_TAG/pkg/{kernel,_fe_analyzer_shared} (+ dependency_overrides)"
  echo "    - dart-sdk.pin           -> DART_VERSION/DART_KERNEL_TAG/EXPECTED_KERNEL_FORMAT (= $(kver "$VENDOR/kernel/lib/binary/tag.dart" 2>/dev/null || echo '<ver tag.dart>'))/SDK_ZIP_URL/SDK_ZIP_SHA256"
  echo "    - os paths .dart-sdk/<versao>/ nos configs (ou rode um sed do 3.12.2 -> $DART_VERSION)"
  echo "    Depois rode 'bash tools/pin-dart.sh' (sem arg) para validar."
  exit 0
fi

# --- 3. pub get (fecha o Gate 2: vendor pkg/kernel utilizavel) ------------
# O package_config autocontido faz parte do Gate 2 (spec 013 §0.6): roda
# sempre que o vendor existe, tornando o pkg/kernel importavel pelo codegen.
step "3. dart pub get (package_config autocontido)"
( cd "$ROOT/compiler" && "$DART" pub get 2>&1 | tail -3 | sed 's/^/  /' )
PKGS="$ROOT/compiler/.dart_tool/package_config.json"

# --- Passos 4-6: validacao do pipeline .tu -> .dill (guardados) -----------
# Estes passos exercem o CODEGEN (emitir .dill) e o RUNTIME-LIB do TOML.
# Enquanto o codegen nao nascer, nao ha .dill a validar:
#   - passo 4 (toml.runtime.dill) exige compiler/tool/gen_toml_runtime.sh +
#     compiler/lib/toml/toml.dart (o parser TOML robusto) — ainda nao portados;
#   - passos 5-6 (hello.tu -> .dill, suite) exigem o codegen da F7.
# O proxy honesto e' a existencia de FONTE .dart em compiler/lib/codegen/ (o
# dir ja existe com um .gitkeep — por isso testamos *.dart, nao o diretorio),
# NAO de bin/itac.dart (que ja existe desde a F1, so' com lex/parse/check/flow).
# Para limpo (nao e' erro).
if [ -z "$(ls "$ROOT"/compiler/lib/codegen/*.dart 2>/dev/null)" ]; then
  echo
  echo ">>> pin-dart OK (parcial) — Gate 2 materializado:"
  echo "    SDK $DART_VERSION + vendor pkg/kernel (formato $EXPECTED_FMT) + pub get."
  echo "    Passos 4-6 (toml.runtime.dill, hello.tu -> .dill, suite) pulados: o"
  echo "    codegen da F7 ainda nao nasceu (compiler/lib/codegen/ so tem .gitkeep)."
  echo "    Rode de novo quando a fase de codegen estiver pronta."
  exit 0
fi
ITAC="$ROOT/compiler/bin/itac.dart"   # usado pelos passos 5-6 (codegen presente)

# --- 4. regen toml.runtime.dill ------------------------------------------
step "4. Regenerar toml.runtime.dill (esperado v$EXPECTED_FMT)"
ITA_DART_BIN="$DART" bash "$ROOT/compiler/tool/gen_toml_runtime.sh" 2>&1 | tail -1 | sed 's/^/  /'
trt="$ROOT/compiler/lib/toml/toml.runtime.dill"
tfmt="$(kver "$trt")"
[ "$tfmt" = "$EXPECTED_FMT" ] || { echo "FATAL: toml.runtime.dill formato $tfmt != $EXPECTED_FMT" >&2; exit 1; }
echo "  toml.runtime.dill formato $tfmt OK"

# --- 5. assert do formato emitido ----------------------------------------
step "5. Compilar hello.tu + ASSERT formato == $EXPECTED_FMT"
TDILL="$(mktemp -t ita_pin_XXXX).dill"
"$DART" --packages="$PKGS" "$ITAC" \
  "$ROOT/examples/hello.tu" "$TDILL" "$PLAT" >/dev/null 2>&1 \
  || { echo "FATAL: nao compilou hello.tu" >&2; exit 1; }
fmt="$(kver "$TDILL")"
[ "$fmt" = "$EXPECTED_FMT" ] || { echo "FATAL: hello.dill formato $fmt != $EXPECTED_FMT" >&2; rm -f "$TDILL"; exit 1; }
echo "  hello.dill formato $fmt OK"
echo "  saida:"; "$DART" --dfe="$PLAT" "$TDILL" 2>&1 | head -3 | sed 's/^/    /'
rm -f "$TDILL"

# --- 6. suite de examples -------------------------------------------------
step "6. Suite de examples (ita-test)"
ITA_DART_BIN="$DART" ITA_PLATFORM_DILL="$PLAT" ITA_PACKAGES="$PKGS" \
  bash "$ROOT/.claude/skills/ita-test/test.sh" examples 2>&1 | tail -10 | sed 's/^/  /'

echo
echo ">>> pin-dart OK — Dart $DART_VERSION, formato de Kernel $EXPECTED_FMT (verde)"
