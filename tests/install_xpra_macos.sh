#!/usr/bin/env bash
#- Build and install xpra from source on macOS, against Homebrew's GTK3 and
#- PyGObject. The Homebrew cask (`brew install --cask xpra`) no longer passes
#- Gatekeeper, and the upstream macOS build (jhbuild/gtk-osx) wants Homebrew
#- moved out of the way, so this builds a plain command-line install instead
#- of an Xpra.app bundle. See MACOS_NOTES.md, "xpra".
#-
#- XPRA_VER     git tag to build (default: the latest GitHub release)
#- XPRA_SRC     where to clone the source (default: tests/xpra, next to this script)
#- XPRA_PREFIX  install prefix, a Python venv (default: $HOME/.local/share/xpra)
#- BIN_DIR      where the `xpra` and `xpra_launcher` wrappers go
#-              (default: $HOME/.local/bin; it must be on PATH)
#-
#- Nothing here needs sudo. Rerunning rebuilds and reinstalls into the same
#- prefix.
set -euo pipefail

if [ "$(uname -s)" != "Darwin" ]; then
    echo "This script is for macOS. On Linux, use the distribution's xpra packages." >&2
    exit 1
fi

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
XPRA_SRC=${XPRA_SRC:-$SCRIPT_DIR/xpra}
XPRA_PREFIX=${XPRA_PREFIX:-$HOME/.local/share/xpra}
BIN_DIR=${BIN_DIR:-$HOME/.local/bin}

if [ -z "${XPRA_VER:-}" ]; then
    XPRA_VER=$(curl -fsSL https://api.github.com/repos/Xpra-org/xpra/releases/latest \
        | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p')
fi
echo "xpra ${XPRA_VER}: source ${XPRA_SRC}, prefix ${XPRA_PREFIX}, wrappers in ${BIN_DIR}"

#- Build dependencies. gtk+3 is also pulled in by pygobject3; the codecs are
#- optional, and setup.py skips any it can't find.
brew install gtk+3 pygobject3 gobject-introspection py3cairo xxhash \
    libvpx x264 openh264 webp jpeg-turbo lz4 brotli adwaita-icon-theme pkgconf
BREW=$(brew --prefix)

#- Homebrew's pygobject3 is built for Homebrew's default python3, so the venv
#- has to use that interpreter and see its site-packages.
PYTHON=${BREW}/bin/python3
"$PYTHON" -c "import gi; gi.require_version('Gtk', '3.0'); from gi.repository import Gtk" \
    || { echo "Homebrew's python3 can't import GTK3 through gi" >&2; exit 1; }
PYVER=$("$PYTHON" -c 'import sys; print("%d.%d" % sys.version_info[:2])')

if [ -x "$XPRA_PREFIX/bin/python" ]; then
    VENVVER=$("$XPRA_PREFIX/bin/python" -c 'import sys; print("%d.%d" % sys.version_info[:2])' || true)
    if [ "$VENVVER" != "$PYVER" ]; then
        echo "$XPRA_PREFIX uses python $VENVVER, but Homebrew's python3 is now $PYVER." >&2
        echo "Remove $XPRA_PREFIX and rerun." >&2
        exit 1
    fi
else
    "$PYTHON" -m venv --system-site-packages "$XPRA_PREFIX"
fi
PIP="$XPRA_PREFIX/bin/pip"
"$PIP" install -q --upgrade pip setuptools wheel cython pkgconfig
#- Runtime modules: pyobjc for the macOS platform code, the rest for
#- encodings, OpenGL, ssh/ssl, mdns and config parsing. certifi is needed for
#- the SSL CA file lookup; without it every command logs a traceback.
"$PIP" install -q \
    pyobjc-core pyobjc-framework-Cocoa pyobjc-framework-Quartz \
    pyobjc-framework-AVFoundation pyobjc-framework-CoreMedia pyobjc-framework-AppleScriptKit \
    pillow pyopengl pyopengl-accelerate cryptography paramiko pyopenssl certifi \
    rencode lz4 brotli netifaces zeroconf pyyaml

if [ -d "$XPRA_SRC/.git" ]; then
    git -C "$XPRA_SRC" fetch --depth 1 origin tag "$XPRA_VER"
    git -C "$XPRA_SRC" checkout -q "$XPRA_VER"
else
    git clone --depth 1 --branch "$XPRA_VER" https://github.com/Xpra-org/xpra.git "$XPRA_SRC"
fi

#- - The venv's bin must be on PATH: setup.py runs `cython --generate-shared`
#-   and falls back to /usr/local/bin/cython.
#- - gdk3_bindings includes <gtk-3.0/gdk/gdk.h>, relative to the Homebrew
#-   include dir, which Apple clang doesn't search by default.
#- - The "jhbuild: No such file or directory" messages are harmless; setup.py
#-   probes for the upstream gtk-osx build environment.
(
    cd "$XPRA_SRC"
    export PATH="$XPRA_PREFIX/bin:$PATH"
    export PKG_CONFIG_PATH="${BREW}/lib/pkgconfig:${BREW}/share/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
    export CFLAGS="-I${BREW}/include${CFLAGS:+ $CFLAGS}"
    export LDFLAGS="-L${BREW}/lib${LDFLAGS:+ $LDFLAGS}"
    python setup.py install --prefix="$XPRA_PREFIX" --without-docs
)

#- xpra's macOS path code expects an Xpra.app bundle: resources live in
#- Contents/Resources, with css/ at the top and icons, images and etc/xpra
#- under share/ and etc/. Pointing XPRA_RESOURCES_DIR at the prefix matches
#- that layout once css/ is linked in; without it xpra looks inside
#- Homebrew's Python.app and logs "cannot find CSS directory".
ln -sfn share/xpra/css "$XPRA_PREFIX/css"

mkdir -p "$BIN_DIR"
for cmd in xpra xpra_launcher; do
    rm -f "$BIN_DIR/$cmd"
    cat > "$BIN_DIR/$cmd" <<EOF
#!/bin/sh
# wrapper for xpra ${XPRA_VER} built by install_xpra_macos.sh, installed in ${XPRA_PREFIX}
export XPRA_RESOURCES_DIR="\${XPRA_RESOURCES_DIR:-${XPRA_PREFIX}}"
exec "${XPRA_PREFIX}/bin/${cmd}" "\$@"
EOF
    chmod +x "$BIN_DIR/$cmd"
done

"$BIN_DIR/xpra" --version
case ":$PATH:" in
    *":$BIN_DIR:"*) ;;
    *) echo "Add $BIN_DIR to PATH, e.g. in ~/.zshrc: path=(\"$BIN_DIR\" \$path)" ;;
esac
