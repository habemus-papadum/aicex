#!/usr/bin/env bash
#- Bake ${EDA_PREFIX}/lib into every installed binary and library that links
#- something from it, as an $ORIGIN-relative RPATH.
#-
#- This is the Linux counterpart of the install_name_tool steps the Makefile
#- runs on macOS. Without it the loader never searches ${EDA_PREFIX}/lib, so:
#-
#-   bin/vvp                    libvvp.so.1: cannot open shared object file
#-   bin/xschem                 silently loads the *system* libtcl/libtk
#-   lib/netgen/tcl/netgenexec  silently loads the *system* libtcl
#-
#- tcl/tk and magic already emit RUNPATH=${EDA_PREFIX}/lib from their own
#- configure, so they are rewritten only to make them relocatable too.
#-
#- The RPATH is written relative to each file's own directory ($ORIGIN), so the
#- whole prefix can be moved or renamed without relinking - which neither an
#- absolute RPATH nor LD_LIBRARY_PATH gives you.
set -euo pipefail

EDA_PREFIX=${EDA_PREFIX:-/opt/eda}
LIBDIR=${EDA_PREFIX}/lib

command -v patchelf >/dev/null 2>&1 || {
    echo "set_rpath.sh: patchelf not found (sudo apt install patchelf)" >&2
    exit 1
}
[ -d "$LIBDIR" ] || { echo "set_rpath.sh: no such directory: $LIBDIR" >&2; exit 1; }

#- Basenames of the shared libraries we ship. Only files that NEED one of
#- these are touched; everything else is left exactly as the build made it.
own=$(find "$LIBDIR" -maxdepth 1 -name '*.so*' -printf '%f\n' 2>/dev/null | sort -u)
[ -n "$own" ] || { echo "set_rpath.sh: no shared libraries in $LIBDIR" >&2; exit 1; }

patched=0
while IFS= read -r f; do
    [ -f "$f" ] || continue
    [ "$(file -b "$f" 2>/dev/null | cut -c1-3)" = "ELF" ] || continue

    needed=$(patchelf --print-needed "$f" 2>/dev/null) || continue
    grep -qxF -f <(printf '%s\n' "$own") <<<"$needed" || continue

    rel=$(realpath -m --relative-to="$(dirname "$f")" "$LIBDIR")

    #- tcl/tk install their libraries read-only.
    restore=""
    [ -w "$f" ] || { restore=$(stat -c '%a' "$f"); chmod u+w "$f"; }
    patchelf --set-rpath "\$ORIGIN/${rel}" "$f"
    [ -z "$restore" ] || chmod "$restore" "$f"

    printf '  %-44s RPATH=$ORIGIN/%s\n' "${f#"${EDA_PREFIX}"/}" "$rel"
    patched=$((patched + 1))
done < <(find "${EDA_PREFIX}/bin" "$LIBDIR" -type f 2>/dev/null)

echo "set_rpath.sh: patched ${patched} file(s) under ${EDA_PREFIX}"
