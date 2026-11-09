#!/usr/bin/env bash
# Compila el emisor Cast Streaming de openscreen (cast_sender) con el parche «en vivo» de este repo
# y lo instala en ~/.local/lib/linuxricing/cast_sender. El código de openscreen NO se guarda en el repo.
# Uso: tools/build-openscreen.sh [directorio_de_trabajo]   (por defecto ~/.cache/linuxricing/openscreen)
# Requisitos del sistema: git, python3, clang, ninja, ffmpeg (dev), opus, libvpx, SDL2, pkgconf (paquetes de Arch).
set -euo pipefail

PIN=308a18e             # commit de openscreen sobre el que se probó el parche
WORK="${1:-$HOME/.cache/linuxricing/openscreen}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST="$HOME/.local/lib/linuxricing"

mkdir -p "$WORK" "$DEST"
cd "$WORK"
[ -d depot_tools ] || git clone --depth 1 https://chromium.googlesource.com/chromium/tools/depot_tools.git
export PATH="$WORK/depot_tools:$PATH" DEPOT_TOOLS_UPDATE=0

mkdir -p src_root && cd src_root
if [ ! -d openscreen ]; then
  cat > .gclient <<'G'
solutions = [
  {
    "name": "openscreen",
    "url": "https://chromium.googlesource.com/openscreen",
    "managed": False,
    "deps_file": "DEPS",
    "custom_deps": {},
  },
]
G
  gclient sync --nohooks --no-history -D
fi
cd openscreen
git fetch -q origin "$PIN" 2>/dev/null || true
git checkout -q -f "$PIN"
git apply --check "$HERE/openscreen-live.patch" 2>/dev/null && git apply "$HERE/openscreen-live.patch" \
  || { git apply -R --check "$HERE/openscreen-live.patch" 2>/dev/null && echo "parche ya aplicado"; }

mkdir -p out/Default
cat > out/Default/args.gn <<'A'
is_debug = false
is_clang = true
have_ffmpeg = true
have_libopus = true
have_libvpx = true
have_libsdl2 = true
use_sysroot = false
A
gn gen out/Default
/usr/bin/ninja -C out/Default cast_sender
install -m755 out/Default/cast_sender "$DEST/cast_sender"
echo "Instalado: $DEST/cast_sender"
