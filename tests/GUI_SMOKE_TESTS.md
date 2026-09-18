# GUI smoke tests (macOS)

Quick commands to check that each GUI tool installed in `$EDA_PREFIX`
opens a window. Run them in a normal Terminal window, with
`$EDA_PREFIX/bin` on `PATH`. See `MACOS_NOTES.md` for how the tools were
built.

## 0. Start the X server

magic, xschem, netgen, ngspice's plot window and plain Tk all draw
through XQuartz. GTKWave is a native GTK3/Quartz app and doesn't need it.

```sh
open -a XQuartz
export DISPLAY=:0
```

If XQuartz was only just installed, you may have to log out and back in
once before `DISPLAY` is set automatically. Exporting it yourself as
above also works.

## 1. Tk

A window with a button means X11, tcl and tk all work.

```sh
echo 'button .b -text "Tk works - click to close" -command exit; pack .b' | wish8.6
```

## 2. Magic

Opens a layout window and a console. Without a PDK it uses the built-in
`scmos` technology. With sky130 installed, use
`magic -rcfile $PDK_ROOT/sky130A/libs.tech/magic/sky130A.magicrc`.

```sh
magic
```

## 3. xschem

Opens a bundled example schematic.

```sh
xschem ~/opt/eda/share/doc/xschem/examples/cmos_inv.sch
```

## 4. netgen

Opens the netgen console.

```sh
netgen
```

## 5. ngspice

Simulates an RC step and opens an X11 plot window. Type `quit` at the
ngspice prompt when done.

```sh
cat > /tmp/rc.cir <<'EOF'
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
ngspice /tmp/rc.cir
```

## 6. GTKWave

Simulates a clock with iverilog, writes a VCD, and opens it. In GTKWave,
select `t` in the SST pane, then drag `clk` into the Signals pane.

```sh
cd /tmp
printf 'module t; reg clk=0; always #5 clk=~clk; initial begin $dumpfile("t.vcd"); $dumpvars; #100 $finish; end endmodule\n' > t.v
iverilog -o t.vvp t.v && vvp t.vvp && gtkwave t.vcd
```

`twinwave`, which shows two viewers side by side, needs GTK's X11
backend. On macOS it prints "not supported" and exits.

## Non-GUI tools

These have no GUI. Their command-line checks are in the table in
`MACOS_NOTES.md`: iverilog, yosys, Xyce, and ngspice in batch mode (`-b`).
