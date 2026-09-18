# Installing aicex from scratch

The end-to-end install: Python tooling, the IP repositories, the EDA tools,
and the sky130 PDK. It ends with `tests/smoke_test.sh` green and the repo's
own `make test` passing DRC and LVS on a real cell.

This is the general flow, with the macOS-specific parts called out in
[macOS specifics](#macos-specifics). For the platform-specific problems you
may hit while building, see `MACOS_NOTES.md` and `UBUNTU_NOTES.md`; for what
the checks actually do, `SMOKE_TESTS.md`.

Verified end to end on macOS 26.4 (Apple Silicon, Homebrew in
`/opt/homebrew`, XQuartz in `/opt/X11`) on 2026-09-18.

## 0. Decide on a prefix

Two directories matter, and everything else follows from them:

| Variable     | What goes there                          |
|--------------|------------------------------------------|
| `EDA_PREFIX` | magic, xschem, netgen, ngspice, iverilog, yosys, tcl/tk |
| `PDK_ROOT`   | the sky130A / sky130B PDK                |

**Install into a prefix you own.** Every `*_install` target and
`install_open_pdk.sh` decide whether to use `sudo` by testing whether the
prefix (or its nearest existing parent) is writable. Point them at a
directory under `$HOME` and no step in this guide needs root at all:

```sh
export EDA_PREFIX=$HOME/opt/eda
export PDK_ROOT=$HOME/opt/pdk/share/pdk
```

`PDK_ROOT` must end in `/share/pdk` — `install_open_pdk.sh` derives the
open_pdks prefix by stripping that suffix, and refuses to guess otherwise.

Put this in your shell config (`~/.zshrc` on macOS, `~/.bashrc` on Ubuntu)
so it applies to every new terminal, with `$EDA_PREFIX/bin` **first** on
`PATH`:

```sh
# >>> aicex / open-source EDA >>>
export EDA_PREFIX=$HOME/opt/eda
export PDK_ROOT=$HOME/opt/pdk/share/pdk
path=("$EDA_PREFIX/bin" $path)   # zsh; on bash: export PATH="$EDA_PREFIX/bin:$PATH"
export path
# <<< aicex / open-source EDA <<<
```

Putting it first matters if you have ever installed any of these tools
another way. A previous `sudo make install` of magic leaves
`/usr/local/bin/magic` and a stale `/usr/local/lib/magic` tech tree behind;
with `$EDA_PREFIX/bin` ahead of `/usr/local/bin` the new build wins. To
remove the old one outright (the only command in this guide that needs
root):

```sh
sudo rm -rf /usr/local/bin/magic /usr/local/bin/ext2sim \
            /usr/local/bin/ext2spice /usr/local/lib/magic
```

Open a new terminal, or `source ~/.zshrc`, before continuing.

## 1. Clone, with submodules

The `--recursive` is not optional. `ip/tech_sky130B` and
`ip/rply_ex0_sky130nm` are submodules, and the smoke tests and `make test`
both read them.

```sh
git clone --recursive https://github.com/wulffern/aicex.git
cd aicex
```

Already cloned without it:

```sh
git submodule update --init --recursive
```

Five submodules should report a commit with no leading `-`:

```sh
git submodule status
```

## 2. Python tooling with uv

[uv](https://docs.astral.sh/uv/) manages the Python side. It reads
`pyproject.toml` / `uv.lock`, builds `.venv` with pinned versions of
cicconf, cicsim, cicspi and cicpy, and fetches the interpreter named in
`.python-version` — no system Python is involved, which matters on Ubuntu
24.04+ where `pip install --user` is refused outright (PEP 668).

```sh
uv sync
```

Add `--extra wave` for `cicwave`, the Qt waveform viewer. It's opt-in
because PySide6 alone is ~650 MB.

`uv run <tool>` works without activating anything;
`source .venv/bin/activate` also works if you prefer.

## 3. Get the IPs

The submodules are only the infrastructure. The actual designs are separate
repositories listed in `ip/config.yaml`, cloned by cicconf:

```sh
cd ip
uv run cicconf clone --https
cd ..
```

Use `--https` unless you have SSH keys on GitHub. This clones several dozen
repositories (`jnw_*`, `lelo_*`, `rey_*`, `sun_*`, `cnr_*`, ...).

## 4. System packages

```sh
cd tests
make requirements
```

On macOS this is Homebrew; on Ubuntu it's `apt` and the only step that uses
`sudo`. The Ubuntu branch picks its package list from `/etc/os-release`, so
24.04 and 26.04 each get the right one.

## 5. Compile Tcl/Tk

```sh
make tt
```

This builds tcl/tk 8.6.13 from source into `$EDA_PREFIX` — Tcl first, then
Tk against it. Magic, netgen and xschem are all Tcl/Tk applications and are
linked against this build.

Required on macOS and on Ubuntu 24.04. On Ubuntu 26.04 the tools build
against the system tcl/tk and you can skip it.

Verify the prefix was baked in correctly before moving on:

```sh
echo 'puts [::tcl::pkgconfig get scriptdir,runtime]' | $EDA_PREFIX/bin/tclsh8.6
# -> $EDA_PREFIX/lib/tcl8.6
```

If that prints a *different* prefix, you built tcl at one prefix and then
changed `EDA_PREFIX`. Magic will fail at startup with "Can't find a usable
init.tcl". Rerun `make tt` — the targets now `make distclean` first, which
fixes it (MACOS_NOTES issue 5).

## 6. Build and install the EDA tools

```sh
make eda_compile
make eda_install
```

`eda_compile` builds magic, xschem, netgen, iverilog, yosys and ngspice; it
takes roughly 10 minutes on an M-series Mac. `eda_install` puts them in
`$EDA_PREFIX/bin` and, on macOS, runs the `install_name_tool` fixups that
repoint the binaries at `$EDA_PREFIX/lib`.

Expect these in the log and **ignore them** — they are `git pull` on a
detached HEAD at a pinned tag, and the recipes prefix them with `-`:

```
make[1]: [magic_compile] Error 1 (ignored)
make[1]: [xschem_compile] Error 1 (ignored)
```

Check what you got:

```sh
magic --version && xschem --version && yosys -V && ngspice -v | head -2
```

The versions are pinned at the top of `tests/Makefile`. This run produced
magic 8.3.541, netgen 1.5.323, xschem 3.4.7, yosys 0.69+75, ngspice 47.

## 7. Install the sky130 PDK

`install_open_pdk.sh` *runs magic*, so step 6 has to be done and magic has
to be on `PATH` first.

```sh
./install_open_pdk.sh
```

It clones open_pdks next to the script, then builds sky130A and sky130B
into `$PDK_ROOT` (~480 MB, and the slowest step — mostly cloning the
sources). It builds only the primitives, the `hd` standard cells and the
xschem/klayout setup; gf180mcu and the other sky130 libraries are skipped.

**Build sky130B, not just sky130A.** `ip/tech_sky130B` and every
`*_sky130nm` IP read `$PDK_ROOT/sky130B`, and the repo's `make test` is one
of them. `SKY130_VARIANTS=A` is only right if you exclusively want the
newer sky130a designs (`jnw_*`, `lelo_*`, `rey_*`).

## 8. Optional: Xyce and GTKWave

Neither is part of `eda_install`, and `smoke_test.sh` reports them as SKIP
when missing. Install them if you want no skips:

```sh
make gtkwave_compile gtkwave_install     # a few minutes
make xyce_compile    xyce_install        # slow: builds Trilinos first
```

GTKWave 3.3.117 is the waveform viewer (`gtkwave`, plus the `vcd2fst` /
`fst2vcd` converters). Xyce 7.10.0 is an alternative SPICE simulator; its
build compiles Trilinos 14.4 from source, which dominates the time.

Xyce needs a Fortran compiler, BLAS/LAPACK, SuiteSparse and FFTW, which
`make requirements` now installs on both platforms. If you ran
`requirements` before that was added, top up first — on Ubuntu:

```sh
sudo apt -y install cmake gfortran libblas-dev liblapack-dev \
                    libsuitesparse-dev libfftw3-dev
```

and on macOS `brew install suitesparse cmake`.

## 9. Verify

```sh
./smoke_test.sh
```

All checks should pass:

```
PASS  magic: runs a Tcl script headless
PASS  netgen: starts in batch mode
PASS  xschem: reports its version
PASS  iverilog: compiles and simulates
PASS  yosys: synthesizes a 2-input AND
PASS  ngspice: 1k/2k divider on 1.8 V = 1.2 V
PASS  Xyce: divider gives 1.2 V
PASS  gtkwave tools: VCD -> FST -> VCD keeps clk
```

Then the real end-to-end check, from the repo root — it simulates,
extracts and compares `RPLY_EX0`, exercising magic, ngspice, xschem,
netgen and cicsim together against the actual PDK:

```sh
cd .. && make test
```

```
RPLY_EX0    [ DRC OK  ]
RPLY_EX0    [ LVS OK  ]
```

Finally the GUIs, which need a working display (see below):

```sh
cd tests
./smoke_test.sh gui magic      # the RPLY_EX0 layout on sky130B
./smoke_test.sh gui xschem
./smoke_test.sh gui gtkwave
```

`SMOKE_TESTS.md` lists what each one should look like.

---

# macOS specifics

Everything above applies. These are the parts that differ on macOS, in the
order you hit them.

## Homebrew and Xcode command line tools

`make requirements` assumes Homebrew. The Makefile picks `BREW_DIR` by
testing for `/opt/homebrew` (Apple Silicon) and falling back to
`/usr/local` (Intel), so both work without configuration.

## The compiler is Homebrew gcc, not Apple clang

On macOS the Makefile compiles magic and ngspice with `gcc-${GCC_VER}` /
`g++-${GCC_VER}`, currently **`GCC_VER=16`** at the top of `tests/Makefile`.
ngspice needs a real gcc for working OpenMP; Apple clang won't do.

Homebrew only links the *current* major version into `/opt/homebrew/bin`,
so when Homebrew's `gcc` moves to 17, `gcc-16` silently disappears from
`PATH` and configure fails with "C compiler cannot create executables".
Either bump `GCC_VER`, or `brew install gcc@16` — a versioned formula
survives `brew upgrade`. Check with:

```sh
ls /opt/homebrew/bin/gcc-*
```

iverilog and Xyce are deliberately built with clang instead; that's already
encoded in the Makefile.

## Homebrew's bison and flex are keg-only

macOS ships bison 2.3, which is too old for iverilog (`bison: invalid
option -- W`) and yosys (needs >= 3.6). Homebrew's bison and flex are
keg-only, so they are not on `PATH` by default. The Makefile handles this
by prepending them for every recipe:

```make
export PATH := ${BREW_DIR}/opt/bison/bin:${BREW_DIR}/opt/flex/bin:${PATH}
```

Nothing to do — but if you build a tool by hand outside the Makefile,
you'll need the same.

## X11 comes from XQuartz

magic, xschem, netgen, Tk and ngspice's plot window all draw through X11,
which on macOS means XQuartz (`brew install --cask xquartz`, included in
`make requirements`). The Makefile points the builds at `/usr/X11`.
GTKWave is a native GTK3/Quartz app and does **not** need XQuartz.

**Do not put `export DISPLAY=:0` in your shell config.** XQuartz's launch
agent sets `DISPLAY` to a launchd socket, and the first X client to connect
starts XQuartz automatically. A hardcoded `:0` overrides that, only works
while XQuartz already happens to be running, and also clobbers the
`DISPLAY` that `ssh -X` sets. The symptom of a stale `:0` is:

```
X server connection failed, although DISPLAY shell variable is set.
```

If `echo $DISPLAY` is empty in a fresh terminal, the launch agent isn't
loaded. That happens even when System Settings shows XQuartz as allowed.
Load it by hand, then **quit and reopen your terminal app** — processes
only receive `DISPLAY` at startup:

```sh
launchctl bootstrap gui/$(id -u) /Library/LaunchAgents/org.xquartz.startx.plist
```

Confirm it took, and that X11 actually answers:

```sh
launchctl getenv DISPLAY          # -> /var/run/com.apple.launchd.XXXX/org.xquartz:0
/opt/X11/bin/xdpyinfo | head -3
```

For a remote machine, `XPRA_NOTES.md` covers the xpra alternative.

## sudo is avoidable, and worth avoiding

On Linux the conventional prefix is `/opt/eda`, which needs root once. On
macOS just use `$HOME/opt/eda` as in step 0 and skip root entirely.

If you have already run an install as root and the prefix ended up
root-owned, later non-sudo installs fail with permission errors. Repair it:

```sh
sudo chown -R "$(whoami)":staff ~/opt
```

## Tk's install_name fixups

Several `*_install` targets run `install_name_tool -change` on macOS to
repoint `magicexec`, `netgenexec`, `xschem` and `wish` at
`$EDA_PREFIX/lib/libtk8.6.dylib`. Some are guarded with `-test -f ... &&`
and print `Error 1 (ignored)` when the file doesn't exist. That's expected
and harmless — it's the Linux/macOS naming difference between
`wish8.6.13` and `wish8.6`.

## Known gaps fixed in this repo

Two packages `make requirements` didn't install, added in this pass:

- **cmake** — yosys switched from its Makefile to CMake in v0.67, and
  `YOSYS_VER=main` follows upstream. Without it `yosys_compile` dies with
  `/bin/sh: cmake: command not found` (exit 127). Needs >= 3.28.
- **suitesparse** — Trilinos links its AMD library, per
  `TRILINOS_CMAKE_FLAGS`. Only needed for the optional Xyce build.

## Time and disk

Rough figures from the verified run on an M-series Mac:

| Step                      | Time    | Disk   |
|---------------------------|---------|--------|
| `make requirements`       | ~10 min | —      |
| `make tt`                 | ~1 min  | small  |
| `make eda_compile`        | ~10 min | ~3 GB in `tests/` |
| `install_open_pdk.sh`     | ~15 min | 480 MB in `$PDK_ROOT` |
| `make gtkwave_compile`    | ~3 min  | small  |
| `make xyce_compile`       | ~1 hr   | several GB |

The build trees stay in `tests/` (`magic/`, `yosys/`, `ngspice/`,
`trilinos-build/`, ...). They're gitignored, and safe to delete once
installed — at the cost of a full rebuild next time.
