#!/usr/bin/env bash
#- Build and install the sky130 PDK with open_pdks: primitives, the hd
#- standard cells, and the xschem/klayout/precheck setup. Other sky130
#- libraries and all of gf180mcu are skipped.
#-
#- SKY130_VARIANTS selects the variants: "all" (default) builds sky130A and
#- sky130B, "A" or "B" builds just that one. sky130B is not optional for this
#- repo - ip/tech_sky130B and every *_sky130nm IP (sun_*, rply_*, cnr_*) read
#- ${PDK_ROOT}/sky130B/libs.ref and libs.tech, and the root "make test" target
#- runs ip/rply_ex0_sky130nm. Use SKY130_VARIANTS=A for a smaller install if
#- you only need the newer sky130a designs (jnw_*, lelo_*, rey_*).
#-
#- Installs into ${PDK_PREFIX}/share/pdk, i.e. PDK_ROOT=${PDK_PREFIX}/share/pdk.
#- PDK_PREFIX defaults to ${PDK_ROOT%/share/pdk} when PDK_ROOT is set, and
#- to /opt/pdk otherwise. sudo is only used when the prefix (or its nearest
#- existing parent) isn't writable; override with SUDO=... .
#-
#- open_pdks runs magic, so ${EDA_PREFIX:-/opt/eda}/bin must hold it. The
#- source is cloned next to this script, in tests/open_pdks.
set -euo pipefail

if [ -z "${PDK_PREFIX:-}" ]; then
    case "${PDK_ROOT:-}" in
        */share/pdk) PDK_PREFIX=${PDK_ROOT%/share/pdk} ;;
        "")          PDK_PREFIX=/opt/pdk ;;
        *)  echo "PDK_ROOT=$PDK_ROOT doesn't end in /share/pdk; set PDK_PREFIX" >&2
            exit 1 ;;
    esac
fi
export PDK_ROOT=${PDK_PREFIX}/share/pdk

EDA_PREFIX=${EDA_PREFIX:-/opt/eda}
export PATH=${EDA_PREFIX}/bin:${HOME}/.local/bin:${PATH}
export LD_LIBRARY_PATH=${LD_LIBRARY_PATH:+${LD_LIBRARY_PATH}:}${EDA_PREFIX}/lib

if [ -z "${SUDO+set}" ]; then
    d=$PDK_PREFIX
    while [ ! -e "$d" ]; do d=$(dirname "$d"); done
    if [ -w "$d" ]; then SUDO=""; else SUDO=sudo; fi
fi

command -v magic >/dev/null || { echo "magic not found in ${EDA_PREFIX}/bin" >&2; exit 1; }

echo "Installing sky130A into ${PDK_ROOT}${SUDO:+ (using $SUDO)}"
$SUDO mkdir -p "$PDK_PREFIX"

cd "$(dirname "$0")"
if [ -d open_pdks ]; then
    git -C open_pdks pull
else
    git clone https://github.com/RTimothyEdwards/open_pdks.git
fi

cd open_pdks
./configure --prefix="$PDK_PREFIX" --enable-sky130-pdk \
    --with-sky130-variants="${SKY130_VARIANTS:-all}" \
    --enable-primitive-sky130 --enable-sc-hd-sky130 \
    --disable-io-sky130 --disable-sc-hs-sky130 --disable-sc-ms-sky130 --disable-sc-ls-sky130 \
    --disable-sc-lp-sky130 --disable-sc-hdll-sky130 --disable-sc-hvl-sky130 --disable-alpha-sky130 \
    --enable-xschem-sky130 \
    --disable-gf180mcu-pdk --disable-primitive-gf180mcu \
    --disable-verification-gf180mcu --disable-io-gf180mcu \
    --disable-sc-7t5v0-gf180mcu --disable-sc-9t5v0-gf180mcu --disable-sram-gf180mcu \
    --disable-alpha-gf180mcu --disable-osu-sc-gf180mcu --disable-avalon-sc-gf180mcu \
    --disable-re-efuse-gf180mcu --disable-ocd-io-gf180mcu --disable-ocd-sram-gf180mcu
make
$SUDO make install

#- Patch missing metal resistor
#$SUDO cp ${PDK_ROOT}/sky130A/libs.tech/xschem/sky130_fd_pr/res_generic_li.sym ${PDK_ROOT}/sky130A/libs.tech/xschem/sky130_fd_pr/res_generic_l1.sym
