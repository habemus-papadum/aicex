# Building the EDA tools on macOS: issues and workarounds

Notes from building with `tests/Makefile` on macOS 26.6 (Apple Silicon,
Homebrew in `/opt/homebrew`, XQuartz in `/opt/X11`), installing into
`$HOME/opt/eda` instead of `/opt/eda`.

## Setup

Shell config (`~/.zshrc`):

```sh
export EDA_PREFIX=$HOME/opt/eda
export PDK_ROOT=$HOME/opt/pdk/share/pdk
path=("$HOME/opt/eda/bin" $path)
export path
```

Then, from `tests/`:

```sh
make requirements   # Homebrew packages
make tt             # tcl/tk 8.6.13 (X11) into $EDA_PREFIX
make eda_compile
make eda_install
```

## Verified (2026-09-18)

`make tt`, `make eda_compile` and `make eda_install` all run clean with
`EDA_PREFIX=$HOME/opt/eda` and never use sudo. `tests/smoke_test.sh`
reruns these checks (see `SMOKE_TESTS.md`, which also covers the GUIs):

| Tool     | Version                  | Check                                           |
|----------|--------------------------|-------------------------------------------------|
| magic    | 8.3.541                  | `magic -dnull -noconsole` runs a Tcl script     |
| netgen   | 1.5.323                  | `netgen -batch` starts                          |
| xschem   | 3.4.7                    | `xschem --version`                              |
| iverilog | master                   | compiles and simulates a `$display` testbench   |
| yosys    | 0.69+75 (CMake build)    | synthesizes a 2-input AND to one `$_AND_` cell  |
| ngspice  | 47 (XSPICE, CIDER, OpenMP) | `.op` of a 1k/2k divider on 1.8 V gives 1.2 V |
| Xyce     | 7.10.0 (Trilinos 14.4, FFTW) | divider gives 1.2 V; RC step matches 1−e^(−t/RC) |
| GTKWave  | 3.3.117 (GTK3, Quartz)   | `--version`; VCD→FST→VCD round-trip of an iverilog dump |

Xyce and GTKWave are built separately with `make xyce_compile xyce_install`
and `make gtkwave_compile gtkwave_install`.

## Issues

### 1. `gcc-15` not found: "C compiler cannot create executables"

**Symptom:** `make magic_compile` fails in configure. In
`magic/scripts/config.log`:

```
gcc-15    conftest.c
./configure: line 3112: gcc-15: command not found
```

**Cause:** On macOS the Makefile uses `gcc-${GCC_VER}`. Homebrew's
`gcc` formula moved to 16, and Homebrew only links the current version
into `/opt/homebrew/bin`. The old 15.2.0 files stay in the Cellar, but
`gcc-15` isn't on `PATH` anymore.

**Fix:** Set `GCC_VER=16`. Or `brew install gcc@15` if you need to stay
on 15. A versioned formula survives `brew upgrade`.

### 2. magic: "too many arguments to function ...; expected 0"

**Symptom:**

```
CMWmain.c:227:9: error: too many arguments to function 'WindMove'; expected 0, have 2
```

**Cause:** GCC 15 and later default to `-std=gnu23`. In C23, `int f();`
means `int f(void);`. Magic has many old K&R-style prototypes
(`int f();`) that are called with arguments.

**Fix:** Add `-std=gnu11` to magic's CFLAGS. The Ubuntu 26.04 branch
already does this.

### 3. `sudo make install` into a home-directory prefix

**Symptom:** `make tt` left `~/opt` and `~/opt/eda` owned by `root`.
Installs without sudo then fail with permission errors.

**Cause:** Every `*_install` target hardcoded `sudo`.

**Fix:** Install steps now use `${SUDO}`. That is empty when
`$EDA_PREFIX` (or its nearest existing parent) is writable by the
current user, and `sudo` otherwise. To repair an install that was
already done as root:

```sh
sudo chown -R "$(whoami)":staff ~/opt
```

### 4. Hardcoded install prefix

**Cause:** `EDA_PREFIX`/`TK_PREFIX` were fixed at `/opt/eda`, and
`iverilog_install` hardcoded `/opt/eda` in `install_name_tool`.

**Fix:** `EDA_PREFIX ?= /opt/eda` and `TK_PREFIX ?= ${EDA_PREFIX}`,
overridable from the environment. `iverilog_install` now uses
`${EDA_PREFIX}`. Linux and Docker builds keep the `/opt/eda` default.

### 5. magic: "Can't find a usable init.tcl" after changing the prefix

**Symptom:** `magic` fails on startup. The first directory it searches
is the old prefix:

```
application-specific initialization failed: Can't find a usable init.tcl in the following directories:
    /opt/eda/lib/tcl8.6 /Users/.../opt/eda/lib/magic/lib/tcl8.6 ...
```

**Cause:** `make tt` had first been run with `/opt/eda`, then again
with `$HOME/opt/eda`. The second configure regenerated tcl's Makefile,
but `make` only rebuilt objects that depend on `tclConfig.sh`.
`tclPkgConfig.o` kept `scriptdir,runtime=/opt/eda/lib/tcl8.6`, which
tcl's init script uses to find `init.tcl`. `tclsh` still worked because
it also searches relative to its own binary in `bin/`. Magic's
`magicexec` lives in `lib/magic/tcl/`, so that fallback misses.

**Fix:** `tcl_compile`/`tk_compile` now run `make distclean` before
configure. Rerun `make tt`. Magic doesn't need rebuilding, since it
loads libtcl dynamically. To check a tcl build for a stale prefix:

```sh
strings -a $EDA_PREFIX/lib/libtcl8.6.dylib | grep -A1 'scriptdir,runtime'
```

### 6. iverilog: `bison: invalid option -- W`

**Symptom:** `make iverilog_compile` fails generating `parse.h`:

```
/Library/Developer/CommandLineTools/usr/bin/bison: invalid option -- W
```

**Cause:** macOS ships bison 2.3. Homebrew's bison (3.8) and flex are
keg-only, so they aren't on `PATH`. The Makefile passed
`-L${BREW_DIR}/opt/bison/lib` but never used Homebrew's `bison` binary.

**Fix:** On macOS the Makefile now prepends
`${BREW_DIR}/opt/bison/bin:${BREW_DIR}/opt/flex/bin` to `PATH` for every
recipe. yosys needs bison >= 3.6 as well.

### 7. yosys: `No rule to make target 'config-gcc'`

**Cause:** yosys replaced its Makefile with CMake in v0.67 (v0.66 was
the last Makefile release). `YOSYS_VER=main` follows upstream, so this
breaks Linux/CI builds too.

**Fix:** `yosys_compile` now runs `cmake -B build . -DCMAKE_INSTALL_PREFIX=...`
then `cmake --build build`, and `yosys_install` runs `cmake --install build`.
It also runs `git submodule update --init --recursive` after `git pull`,
since yosys vendors abc, slang, fmt, etc. as submodules. yosys needs
CMake >= 3.28, bison >= 3.6, flex >= 2.6 and Python >= 3.11. Homebrew
has all of them. Ubuntu 22.04's apt CMake is too old.

### 8. ngspice: clone fails with `RPC failed; curl 56 ... Connection reset by peer`

**Cause:** ngspice is only hosted on SourceForge. A full clone of its
history repeatedly got its connection reset partway through.

**Fix:** `git clone --depth 1 --branch ${NGSPICE_VER}`. It takes about
5 seconds. The existing `git checkout ... && git pull` in
`ngspice_compile` still works on a shallow clone.

### 9. ngspice: `required file './ltmain.sh' not found`

**Symptom:** `autogen.sh` fails, and a stray `tests/ltmain.sh` appears:

```
glibtoolize: putting auxiliary files in '..'.
configure.ac:53: error: required file './ltmain.sh' not found
Error: automake failed
```

**Cause:** ngspice's `configure.ac` has no `AC_CONFIG_AUX_DIR`, so
libtoolize guesses the aux directory. It takes the first of `.`, `..`,
`../..` that holds `install-sh` or `install.sh`. `autogen.sh` deletes
`ngspice/install-sh` first, so libtoolize found this repo's
`tests/install.sh` and put `ltmain.sh` in `tests/`. automake still
expected it in `ngspice/`. This happens whenever ngspice is cloned next
to a file called `install.sh`, so Linux is affected too. The old
`ngspice2_compile` target worked around it by symlinking
`../ltmain.sh`.

Two dead ends: copying automake's `install-sh` in first (`autogen.sh`
deletes it), and an empty `ngspice/install.sh` placeholder (ngspice
builds with `-Wall -Werror`, and automake rejects `install.sh` as "an
anachronism").

**Fix:** `ngspice_compile` inserts `AC_CONFIG_AUX_DIR([.])` before
`AM_INIT_AUTOMAKE` in `ngspice/configure.ac`. It runs
`git checkout -- configure.ac` before `git pull`, so the local edit
never blocks an update.

### 10. Xyce: the old `xyce_compile` target and `compile_xyce.sh`

The old target never worked as written:

- It cloned over SSH (`git@github.com:...`), which fails without a
  GitHub SSH key.
- It cloned into `Trilinos/` and `Xyce/` but built `../trilinos` and
  `../xyce`, which only works on case-insensitive filesystems.
- It did full-history clones. Trilinos alone is over 1 GB even shallow.
- It used `cmake/trilinos/trilinos-config.cmake`, which Xyce has since
  renamed to `trilinos-base.cmake`.
- It hardcoded `/opt/eda` and didn't use sudo.

**Fix:** Shallow HTTPS clones pinned to `XYCE_VER=Release-7.10.0` and
`TRILINOS_VER=trilinos-release-14-4-0`. Xyce's INSTALL.md says only
Trilinos 14.4 is rigorously tested. `compile_xyce.sh` builds and installs
Trilinos to `$EDA_PREFIX/trilinos`, then builds Xyce. `make xyce_install`
installs Xyce to `$EDA_PREFIX/xyce` and symlinks `$EDA_PREFIX/bin/Xyce`.
On macOS the Makefile passes:

- Apple clang for C/C++.
- `gfortran-${GCC_VER}` for Trilinos' Fortran. Xyce's docs report
  AztecOO failures with clang and no Fortran compiler.
- SuiteSparse's AMD from Homebrew (`include/suitesparse`).
- `FLEX_INCLUDE_DIR`. Homebrew's flex is keg-only, so `PATH` finds the
  binary but not `FlexLexer.h`. Without it Xyce's configure fails with
  `FLEX_INCLUDE_DIR-NOTFOUND`.

BLAS/LAPACK come from Apple's Accelerate.

### 11. Trilinos 14.4: `no member named 'sort_option' in 'SPADDHandle<...>'`

**Cause:** kokkos-kernels' `SPADDHandle::set_sort_option()` and
`get_sort_option()` use a member the class never declares. Nothing calls
them. Older compilers skipped uninstantiated template members, but Apple
clang 21 checks them. Trilinos 16 still has this bug. Upstream
kokkos-kernels has since deleted the methods.

**Fix:** `patches/trilinos-14.4-kokkos-kernels-sort_option.patch`
deletes them. `compile_xyce.sh` applies `patches/<repo>-*.patch` to
`./<repo>` and skips patches that are already applied.

### 12. Xyce 7.10: `call to 'abs' is ambiguous`

**Cause:** `N_LAS_BlockSystemHelpers.C` calls `std::abs<double>(val)`.
The floating-point `std::abs` is not a template, so the explicit template
argument only matched libc++'s templated integer overloads, and current
libc++ rejects the call as ambiguous.

**Fix:** `patches/xyce-7.10-std-abs.patch` changes it to
`std::abs(val)`, the same as upstream Xyce master.

Xyce doesn't understand ngspice `.control` blocks. Test it with a native
netlist (`.DC`/`.TRAN` plus `.PRINT`). Results go to `<netlist>.prn`.

### 13. GTKWave: no Homebrew package; GTK2 build loads two GTKs

**Homebrew:** the `gtkwave` cask is disabled ("discontinued upstream",
2025-10-29), and there is no formula. Build it with
`make gtkwave_compile gtkwave_install`. It isn't part of `eda_compile`.

**Download:** the old `http://gtkwave.sourceforge.net/...` URL now goes
through `https://downloads.sourceforge.net/project/gtkwave/<pkg>/<pkg>.tar.gz`.

**configure: `LZMA support for VZT is enabled, but xz could not be found`:**
Apple clang doesn't search `/opt/homebrew/include`, so `lzma.h` wasn't
found even though `liblzma` was. The Makefile now passes
`CPPFLAGS=-I${BREW_DIR}/include LDFLAGS=-L${BREW_DIR}/lib`. It also drops
the old Intel-only `PKG_CONFIG_PATH=/usr/local/lib/pkgconfig`.

**GTK2 and GTK3 in one process:** the GTK2 build ran, but it printed
`objc: Class GdkQuartzView is implemented in both .../libgdk-3.0.dylib and
.../libgdk-quartz-2.0.0.dylib ... mysterious crashes`. Homebrew's
`gtk-mac-integration` is GTK3-only, and configure linked it into the GTK2
binary. **Fix:** on macOS, build the GTK3 edition
(`gtkwave-gtk3-${GTKWAVE_VER}`, `--enable-gtk3`). Linux keeps GTK2.

**GTK3 without X11: `call to undeclared function 'gtk_plug_new'`:**
Homebrew's GTK3 has only the Quartz backend (`GDK_WINDOWING_QUARTZ`), and
`GtkPlug`/`GtkSocket` are X11-only. `patches/gtkwave-gtk3-3.3.117-no-x11.patch`
enables `--xid` only with X11 (upstream master guards it the same way). It
also builds `twinwave`, the side-by-side viewer built on `GtkSocket`, as a
stub that says it isn't supported. As a result, GTKWave on macOS is a
native Quartz app and doesn't need XQuartz.

**Known gap:** GTKWave's configure checks
`pkg-config --variable=target gdk-3.0`, but GTK 3.24 calls it `targets`.
So it doesn't detect Quartz and builds without macOS menu-bar/dock
integration, and menus sit inside the window. Everything else works.

### 14. PDK: `install_open_pdk.sh` assumed root and `/opt/pdk`

None of the Makefile targets install a PDK. The sky130A PDK comes from
`tests/install_open_pdk.sh`, which builds it with
[open_pdks](https://github.com/RTimothyEdwards/open_pdks) using the same
configure line as `docker/Dockerfile_26.04`. It builds only sky130A with
the primitives, the `hd` standard cells and xschem/klayout/precheck.
That is far smaller than the full sky130 set with every library and
variant. `tests/clone_open_pdk.sh` instead clones
[wulffern/pdk](https://github.com/wulffern/pdk), a 2022 snapshot of an
Ubuntu `/opt/pdk`, and wasn't changed.

Problems with the old script:

- It hardcoded `/opt/pdk`, `PDK_ROOT`, `/opt/eda/bin` and `/opt/eda/lib`.
- It ran `sudo mkdir /opt/pdk`, `sudo chmod 777 /opt/pdk` and
  `sudo make install` unconditionally.
- `test -f /opt/pdk` and `test -f open_pdks` should be `-d`. On a rerun,
  `git clone` failed on the existing directory, and the script carried on
  with the stale checkout.
- It cloned the source into the install prefix, `/opt/pdk/open_pdks`.
- It had no `set -e`, so a failed configure or make still exited 0.
- `--disable-klayout-gf180mcu` no longer exists (configure warns
  "unrecognized options"). The newer `gf180mcu_re_efuse` package wasn't
  disabled, so it would still be "installed automatically".

**Fix:** The prefix comes from `PDK_PREFIX`, else from `PDK_ROOT` minus
`/share/pdk`, else `/opt/pdk`. `sudo` is only used when that prefix isn't
writable, and `SUDO=` overrides it. The script clones or updates
`tests/open_pdks` (gitignored), puts `$EDA_PREFIX/bin` on `PATH` so
open_pdks finds magic, and uses `set -euo pipefail`. With the `~/.zshrc`
above, run `tests/install_open_pdk.sh` and it installs sky130A into
`~/opt/pdk/share/pdk`.

open_pdks' current top-level `configure` is a wrapper around
`scripts/configure`. `--help` shows the sky130 switch mangled as
`--enable-sky130-sky130`, but `--enable-sky130-pdk` still works. On macOS
it finds Homebrew's `gsed`, installed by `make requirements`.

Note: every step of `ngspice_compile` is prefixed with `-`, so make
ignores failures and the target always "succeeds". Check the log or
`ngspice/src/ngspice` to see whether it actually built.

### 15. xpra: the Homebrew cask no longer installs

**Symptom:** `brew install --cask xpra` refuses to install. Since
2026-09-01 the upstream `Xpra.app` no longer passes the Gatekeeper
check, so Homebrew won't install it.

The upstream macOS build (`docs/Build/MacOS.md` in the xpra repo) uses
jhbuild/gtk-osx and asks you to remove Homebrew or move it out of the
way first. That isn't practical here.

**Fix:** `tests/install_xpra_macos.sh` builds xpra from source with
Homebrew's GTK3 and PyGObject. It installs a command-line xpra, not an
`.app` bundle, so Gatekeeper never checks it. With no arguments it
builds the latest GitHub release. It clones into `tests/xpra`, which is
gitignored, and installs into a Python venv at `~/.local/share/xpra`.
It then writes `xpra` and `xpra_launcher` wrappers into `~/.local/bin`,
which must be on `PATH`. Override these with `XPRA_VER`, `XPRA_SRC`,
`XPRA_PREFIX` and `BIN_DIR`. It doesn't use sudo. `XPRA_NOTES.md`
covers using the client and setting up the Linux server.

```sh
tests/install_xpra_macos.sh
xpra --version
```

What the script works around:

- **The venv must use Homebrew's `python3`.** Homebrew's `pygobject3`
  (`gi`) is built for that interpreter only. The venv is created with
  `--system-site-packages` so it can see `gi` and `cairo`. The rest
  (pyobjc, pillow, pyopengl, cryptography, paramiko, ...) is installed
  with pip.
- **`FileNotFoundError: '/usr/local/bin/cython'`.** `setup.py` runs
  `cython --generate-shared` and looks for `cython` on `PATH`. The fix
  is to put the venv's `bin` on `PATH` for the build.
- **`fatal error: 'gtk-3.0/gdk/gdk.h' file not found`.** This happens in
  `xpra/platform/darwin/gdk3_bindings`. The include is relative to the
  Homebrew include directory, which Apple clang doesn't search by
  default. The fix is `CFLAGS=-I$(brew --prefix)/include` (plus the
  matching `LDFLAGS`).
- **`jhbuild: No such file or directory`.** These messages during
  `setup.py` are harmless. It is probing for the upstream gtk-osx build
  environment.
- **`No module named 'certifi'` / `failed to locate SSL ca file`.** Every
  command printed this traceback. The fix is to install `certifi` in the
  venv.
- **`cannot find CSS directory '.../Python.app/Contents/Resources/css'`.**
  xpra's macOS path code (`xpra/platform/darwin/paths.py`) assumes it is
  running from `Xpra.app`. It asks `gtkosx_application` for the bundle's
  resource path and finds Homebrew's `Python.app`. It expects `css/` at
  the top of the resources directory and `share/xpra/{icons,images}` and
  `etc/xpra` below it. The fix has two parts. First, the wrappers set
  `XPRA_RESOURCES_DIR` to the install prefix, which already has
  `share/` and `etc/` in that layout. Second, the script links
  `<prefix>/css` to `share/xpra/css`.

Limitations: the X11 server backends (`x11`, `gtk_x11`) and the webcam
are disabled on macOS, so this is a client plus a macOS shadow server.
There's no Dock or Finder app bundle. The venv is tied to Homebrew's
Python minor version. If `brew upgrade` moves `python3` to a new minor
version, the script stops and asks you to delete the prefix and rerun
it.

### 16. yosys: `/bin/sh: cmake: command not found`

**Symptom:** `make eda_compile` dies at yosys with exit 127:

```
cd yosys && cmake -B build . -DCMAKE_BUILD_TYPE=Release ...
/bin/sh: cmake: command not found
make[1]: *** [yosys_compile] Error 127
```

**Cause:** issue 7 moved `yosys_compile` to CMake, but `requirements`
never installed cmake. Nothing else in `eda_compile` needs it, so a
machine with no cmake gets all the way to yosys before failing. Because
yosys runs before ngspice in `eda_compile`, ngspice is skipped too.

**Fix:** `requirements` now runs `brew install cmake`. yosys wants
CMake >= 3.28. On Ubuntu, cmake is already in the apt lists.

### 17. Xyce: `AMD_INCLUDE_DIRS` points at a missing suitesparse

**Symptom:** `make xyce_compile` fails configuring Trilinos; the AMD
include directory named in `TRILINOS_CMAKE_FLAGS`
(`${BREW_DIR}/include/suitesparse`) doesn't exist.

**Cause:** `requirements` didn't install suitesparse. Xyce is not part
of `eda_compile`, so this only shows up when you build it explicitly.

**Fix:** `requirements` now runs `brew install suitesparse`.

### Notes

- `LD_LIBRARY_PATH` does nothing on macOS. The dynamic loader uses
  `DYLD_LIBRARY_PATH`, and System Integrity Protection strips it for
  system binaries anyway. The tools find their libraries through install
  names, which the `install_name_tool` steps in the Makefile fix up.
- `X11_LIB`/`X11_INC` point to `/usr/X11`, which XQuartz symlinks to
  `/opt/X11`. The built binaries link against `/opt/X11/lib/...`.
- `magic_compile` rewrites `magic/configure` in place with perl each
  time it runs, so the flag is appended again on every run. Reset it
  with `git -C magic checkout configure`.
