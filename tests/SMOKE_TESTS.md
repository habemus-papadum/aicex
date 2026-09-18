# Smoke tests

`tests/smoke_test.sh` checks that the tools installed by `tests/Makefile`
into `$EDA_PREFIX` (default `/opt/eda`) actually work. See
`MACOS_NOTES.md` for how they were built on macOS.

```sh
cd tests
./smoke_test.sh               # command-line checks, no windows
./smoke_test.sh gui gtkwave   # open one GUI tool with a small example
```

Each run writes its example files to a fresh `$TMPDIR/smoke.XXXXXX`
directory. After a successful command-line run the directory is deleted.
After a failure it is kept so you can look at it.

## Command-line checks

`./smoke_test.sh` prints PASS, FAIL or SKIP for each check. It exits
non-zero if anything fails or nothing passes. A check is skipped when its
tool isn't installed, for example Xyce and GTKWave, which aren't part of
`make eda_install`.

| Check         | What it does                                                   | Passes when                    |
|---------------|----------------------------------------------------------------|--------------------------------|
| magic         | `magic -dnull -noconsole` runs a Tcl script with no display    | the script prints `MAGIC_OK`   |
| netgen        | `netgen -batch`                                                | it prints its `Netgen x.y` banner |
| xschem        | `xschem --version`                                             | it prints `XSCHEM Vx.y.z`      |
| iverilog      | compiles and runs a `$display` testbench with `vvp`            | it prints `IVERILOG_OK 42`     |
| yosys         | `synth` of a 2-input AND                                       | `stat` reports one `$_AND_`    |
| ngspice       | `ngspice -b` operating point of a 1k/2k divider on 1.8 V       | `v(out) = 1.2`                 |
| Xyce          | `.DC` of the same divider (Xyce doesn't read ngspice `.control`) | `V(OUT)` in `xdiv.cir.prn` is 1.2 |
| gtkwave tools | iverilog writes a clock VCD; `vcd2fst`, then `fst2vcd`         | the round-tripped VCD still declares `clk` |

## GUI checks

`./smoke_test.sh gui <tool>` writes the example files and opens the tool.

| Command                        | You should see                                                  |
|--------------------------------|-----------------------------------------------------------------|
| `./smoke_test.sh gui tk`       | a small window with a button; click it to close                  |
| `./smoke_test.sh gui magic`    | a layout window and a Tk console. Without a PDK it uses the built-in `scmos` tech. For sky130, run `magic -rcfile $PDK_ROOT/sky130A/libs.tech/magic/sky130A.magicrc` |
| `./smoke_test.sh gui xschem`   | xschem's bundled `cmos_inv.sch` example schematic               |
| `./smoke_test.sh gui netgen`   | the netgen Tk console                                           |
| `./smoke_test.sh gui ngspice`  | an X11 plot of an RC step (`v(in)`, `v(out)`). Type `quit` at the `ngspice` prompt to exit |
| `./smoke_test.sh gui gtkwave`  | `t.clk` toggling every 5 ns across 0–100 ns, already in the Waves pane |

**GTKWave** doesn't show any signals when it opens a dump file on its own.
You pick them in the SST/Signals panes at the left: select `clk`, then
click **Append** or double-click it. The GUI check sets up two files so
the clock appears right away:

- `t.gtkw`, a save file containing `@28` and `t.clk`, which adds the
  signal. `@28` is hex flags for binary, right-justified.
- `t.gtkwaverc`, containing `do_initial_zoom_fit 1`, passed with `-r`.
  GTKWave only zooms to fit on its own when the dump spans ≤ 400 time
  units (`main.c`). With `` `timescale 1ns/1ps ``, 100 ns is 100 000
  units, so without this setting it opens at full zoom-in. The Waves pane
  then shows 0–3 ps and `clk` looks like a flat line.

For your own dumps, put `do_initial_zoom_fit 1` in `~/.gtkwaverc`, or
use **Time → Zoom → Zoom Full** (Ctrl+0) after opening.

Terminal messages like `GTKWAVE | MESSAGE: gdk_atom_intern: assertion
'atom_name != NULL' failed` come from GTK3's Quartz drag-and-drop layer,
not from GTKWave. GTKWave's drag targets are ordinary names
(`text/plain`, `text/uri-list`, `STRING`). They are noise and don't stop
signals from being added. If dragging from the Signals list is
unreliable, use **Append**/**Insert** or a double-click instead.

### X11 and `DISPLAY` on macOS

magic, xschem, netgen, ngspice's plot window and Tk draw through
XQuartz. GTKWave is a native GTK3/Quartz app and doesn't need XQuartz.
The GUI checks for the X11 tools stop with a message if `DISPLAY` is
empty.

Normally you don't need to run `open -a XQuartz` or `export DISPLAY=:0`.
XQuartz's launch agent (`/Library/LaunchAgents/org.xquartz.startx.plist`)
sets `DISPLAY` to a launchd socket (`/private/tmp/com.apple.launchd.*/org.xquartz:0`)
for apps started after login. The first X11 client that connects then
starts XQuartz automatically.

If `echo $DISPLAY` is empty in a new terminal, the agent isn't loaded.
That happened here even though System Settings → Login Items allowed
XQuartz in the background, and `sfltool dumpbtm` showed the agent as
enabled and allowed. Load it by hand, then quit and reopen the terminal
app. Apps only receive `DISPLAY` when they start.

```sh
launchctl bootstrap gui/$(id -u) /Library/LaunchAgents/org.xquartz.startx.plist
```

Avoid an unconditional `export DISPLAY=:0` in `~/.zshrc`. It overrides
the launchd socket, which starts XQuartz on demand, and the `DISPLAY` set
by `ssh -X`. It also only works while XQuartz is already running.
