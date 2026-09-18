#!/usr/bin/env bash
#- Smoke tests for the tools installed by tests/Makefile. See SMOKE_TESTS.md.
#-
#-   ./smoke_test.sh              run the command-line checks (no windows)
#-   ./smoke_test.sh gui <tool>   open one GUI with a small example:
#-                                tk, magic, xschem, netgen, ngspice, gtkwave
#-   ./smoke_test.sh gui magic --no-pdk
#-                                start magic on its built-in tech instead of
#-                                opening a sky130 cell
set -uo pipefail

EDA_PREFIX=${EDA_PREFIX:-/opt/eda}
PDK_ROOT=${PDK_ROOT:-/opt/pdk/share/pdk}
export PATH=${EDA_PREFIX}/bin:${PATH}
#- Resolved before the cd below, so the magic check can find the example IP.
REPO=$(cd -- "$(dirname -- "$0")/.." && pwd)
#- Deliberately *not* setting LD_LIBRARY_PATH: "make eda_install" runs
#- set_rpath.sh, which bakes an $ORIGIN-relative RPATH into everything that
#- links ${EDA_PREFIX}/lib. Leaving it unset is what makes these checks catch a
#- missing or stale RPATH (without it, vvp fails outright, and xschem/netgen
#- silently fall back to the system tcl).
unset LD_LIBRARY_PATH

tmp=${TMPDIR:-/tmp}
WORK=$(mktemp -d "${tmp%/}/smoke.XXXXXX")
cd "$WORK"

#- Example inputs ------------------------------------------------------------

write_clock_tb() {
    cat > t.v <<'EOF'
`timescale 1ns/1ps
module t;
  reg clk = 0;
  always #5 clk = ~clk;
  initial begin
    $dumpfile("t.vcd");
    $dumpvars;
    #100 $finish;
  end
endmodule
EOF
    #- GTKWave save file that adds t.clk to the Waves pane on startup.
    cat > t.gtkw <<'EOF'
@28
t.clk
EOF
    #- GTKWave only zooms to fit on its own when the dump spans <= 400 time
    #- units; 100 ns at 1 ps resolution is 100000, so ask for it explicitly.
    echo 'do_initial_zoom_fit 1' > t.gtkwaverc
}

write_inputs() {
    write_clock_tb
    echo 'module hello; initial begin $display("IVERILOG_OK %0d", 6*7); $finish; end endmodule' > hello.v
    echo 'module and2(input a, b, output y); assign y = a & b; endmodule' > and2.v
    echo 'puts "MAGIC_OK [magic::version]"; quit -noprompt' > magic.tcl
    cat > div.cir <<'EOF'
voltage divider (ngspice)
V1 in 0 DC 1.8
R1 in out 1k
R2 out 0 2k
.control
op
print v(out)
quit
.endc
.end
EOF
    cat > xdiv.cir <<'EOF'
voltage divider (Xyce)
V1 in 0 DC 1.8
R1 in out 1k
R2 out 0 2k
.DC V1 1.8 1.8 1
.PRINT DC V(out)
.end
EOF
    cat > rc.cir <<'EOF'
RC step response
V1 in 0 PULSE(0 1 1u 1n 1n 1m 2m)
R1 in out 1k
C1 out 0 1n
.control
tran 10n 10u
plot v(in) v(out)
.endc
.end
EOF
}

#- GUI launchers -------------------------------------------------------------

need_x11() {
    if [ -z "${DISPLAY:-}" ]; then
        echo "DISPLAY is not set, so $1 has no X server to draw on (XQuartz on" >&2
        echo "macOS, or ssh -Y from one). See SMOKE_TESTS.md." >&2
        exit 1
    fi
}

#- The example layout the magic check opens, and the variant it was drawn in
#- ("tech sky130B" on line 2 of the .mag). It comes from ip/rply_ex0_sky130nm,
#- so it is only there once the submodules are checked out.
MAGIC_CELL_DIR=${REPO}/ip/rply_ex0_sky130nm/design/RPLY_EX0_SKY130NM
MAGIC_CELL=RPLY_EX0
MAGIC_VARIANT=sky130B

#- Start magic on a real PDK cell when one is available. Bare magic only shows
#- that a window opens, on the built-in "minimum" tech - it says nothing about
#- the PDK. Loading a sky130 cell also exercises tech-file parsing, the layer
#- colours and the cairo/X11 draw path, which is what tends to break over
#- "ssh -Y". Falls back to an empty layout, and finally to bare magic.
magic_gui() {
    local rcfile=${PDK_ROOT}/${MAGIC_VARIANT}/libs.tech/magic/${MAGIC_VARIANT}.magicrc

    if [ "${1:-0}" = 1 ]; then
        echo "--no-pdk: starting magic on its built-in tech (no PDK loaded)."
        magic
    elif [ ! -f "$rcfile" ]; then
        echo "No ${MAGIC_VARIANT} rcfile under ${PDK_ROOT}; starting magic on its" >&2
        echo "built-in tech. Run tests/install_open_pdk.sh for the PDK." >&2
        magic
    elif [ ! -f "${MAGIC_CELL_DIR}/${MAGIC_CELL}.mag" ]; then
        echo "${MAGIC_CELL}.mag not found (run: git submodule update --init" >&2
        echo "ip/rply_ex0_sky130nm); opening an empty ${MAGIC_VARIANT} layout." >&2
        magic -rcfile "$rcfile"
    else
        echo "Opening ${MAGIC_CELL} on ${MAGIC_VARIANT}. Press 'v' to fit the view."
        cd "$MAGIC_CELL_DIR" && magic -rcfile "$rcfile" "$MAGIC_CELL"
    fi
}

gui() {
    local no_pdk=0 tool=${1:-}
    shift 2>/dev/null || true
    for opt in "$@"; do
        case "$opt" in
            --no-pdk) no_pdk=1 ;;
            *) echo "unknown option: $opt" >&2; exit 2 ;;
        esac
    done
    write_inputs
    case "$tool" in
        tk)      need_x11 wish
                 echo 'button .b -text "Tk works - click to close" -command exit; pack .b' | wish8.6 ;;
        magic)   need_x11 magic;   magic_gui "$no_pdk" ;;
        xschem)  need_x11 xschem;  xschem "${EDA_PREFIX}/share/doc/xschem/examples/cmos_inv.sch" ;;
        netgen)  need_x11 netgen;  netgen ;;
        ngspice) need_x11 ngspice
                 echo "Type 'quit' at the ngspice prompt to exit."
                 ngspice rc.cir ;;
        gtkwave) iverilog -o t.vvp t.v && vvp -n t.vvp >/dev/null && gtkwave -r t.gtkwaverc t.vcd t.gtkw ;;
        *)       echo "usage: $0 gui tk|magic|xschem|netgen|ngspice|gtkwave [--no-pdk]" >&2
                 exit 2 ;;
    esac
}

#- Command-line checks -------------------------------------------------------

pass=0 fail=0 skip=0

#- check NAME REGEX COMMAND...: pass if the command's output matches REGEX.
check() {
    local name=$1 want=$2 out
    shift 2
    out=$("$@" 2>&1)
    if grep -Eq -- "$want" <<<"$out"; then
        printf 'PASS  %s\n' "$name"; pass=$((pass + 1))
    else
        printf 'FAIL  %s\n' "$name"; tail -5 <<<"$out" | sed 's/^/      /'
        fail=$((fail + 1))
    fi
}

#- need LABEL TOOL...: skip (return 1) unless every tool is installed.
need() {
    local label=$1 t
    shift
    for t in "$@"; do
        if ! command -v "$t" >/dev/null; then
            printf 'SKIP  %s (%s not installed)\n' "$label" "$t"; skip=$((skip + 1)); return 1
        fi
    done
}

cli() {
    write_inputs
    echo "Tools from ${EDA_PREFIX}/bin, scratch files in ${WORK}"

    need magic magic &&
        check "magic: runs a Tcl script headless" 'MAGIC_OK' \
            bash -c 'magic -dnull -noconsole magic.tcl </dev/null'
    need netgen netgen &&
        check "netgen: starts in batch mode" '^Netgen [0-9]' \
            bash -c 'netgen -batch source /dev/null </dev/null'
    need xschem xschem &&
        check "xschem: reports its version" 'XSCHEM V[0-9]' xschem --version
    need iverilog iverilog vvp &&
        check "iverilog: compiles and simulates" 'IVERILOG_OK 42' \
            bash -c 'iverilog -o hello.vvp hello.v && vvp -n hello.vvp'
    need yosys yosys &&
        check "yosys: synthesizes a 2-input AND" '^ +1 +\$_AND_' \
            yosys -p 'read_verilog and2.v; synth -top and2; stat'
    need ngspice ngspice &&
        check "ngspice: 1k/2k divider on 1.8 V = 1.2 V" 'v\(out\) = 1\.200000e\+00' \
            ngspice -b div.cir
    need Xyce Xyce &&
        check "Xyce: 1k/2k divider on 1.8 V = 1.2 V" '1\.20000000e\+00' \
            bash -c 'Xyce xdiv.cir >/dev/null && cat xdiv.cir.prn'
    need "gtkwave tools" iverilog vvp vcd2fst fst2vcd &&
        check "gtkwave tools: VCD -> FST -> VCD keeps clk" '\$var reg 1 . clk' \
            bash -c 'iverilog -o t.vvp t.v && vvp -n t.vvp >/dev/null &&
                     vcd2fst t.vcd t.fst && fst2vcd t.fst'

    echo "${pass} passed, ${fail} failed, ${skip} skipped"
    #- Nothing passing usually means EDA_PREFIX is wrong, so count it as failure.
    [ "$fail" -eq 0 ] && [ "$pass" -gt 0 ] && rm -rf "$WORK"
    [ "$fail" -eq 0 ] && [ "$pass" -gt 0 ]
}

case "${1:-}" in
    gui) shift; gui "$@" ;;
    "")  cli ;;
    *)   echo "usage: $0 [gui <tool> [--no-pdk]]" >&2; exit 2 ;;
esac
