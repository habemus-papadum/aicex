#!/usr/bin/env bash
#- Build a serial Trilinos with the package set Xyce needs, install it to
#- ${EDA_PREFIX}/trilinos, then configure and build Xyce against it.
#- Run from tests/ via "make xyce_compile", which passes EDA_PREFIX, SUDO,
#- TRILINOS_CMAKE_FLAGS and XYCE_CMAKE_FLAGS. "make xyce_install" installs
#- Xyce itself.
set -euo pipefail

EDA_PREFIX=${EDA_PREFIX:-/opt/eda}
TRILINOS_PREFIX=${EDA_PREFIX}/trilinos
JOBS=${JOBS:-$(getconf _NPROCESSORS_ONLN)}

#- Local fixes for the pinned Trilinos and Xyce releases (see patches/;
#- patches/<repo>-*.patch applies to ./<repo>). Skip already-applied ones.
for repo in trilinos xyce; do
    for p in patches/${repo}-*.patch; do
        [ -e "$p" ] || continue
        if ! git -C "$repo" apply --reverse --check "../$p" 2>/dev/null; then
            echo "Applying $p"
            git -C "$repo" apply "../$p"
        fi
    done
done

cmake -S trilinos -B trilinos-build \
    -C xyce/cmake/trilinos/trilinos-base.cmake \
    -D CMAKE_INSTALL_PREFIX="${TRILINOS_PREFIX}" \
    -D CMAKE_BUILD_TYPE=Release \
    ${TRILINOS_CMAKE_FLAGS:-}
cmake --build trilinos-build -j "${JOBS}"
${SUDO:-} cmake --install trilinos-build

cmake -S xyce -B xyce-build \
    -D CMAKE_INSTALL_PREFIX="${EDA_PREFIX}/xyce" \
    -D Trilinos_ROOT="${TRILINOS_PREFIX}" \
    -D CMAKE_BUILD_TYPE=Release \
    ${XYCE_CMAKE_FLAGS:-}
cmake --build xyce-build -j "${JOBS}"
