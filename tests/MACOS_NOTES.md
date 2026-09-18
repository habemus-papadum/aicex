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
`EDA_PREFIX=$HOME/opt/eda` and never use sudo. Smoke tests of the
installed tools:

| Tool     | Version                  | Check                                           |
|----------|--------------------------|-------------------------------------------------|
| magic    | 8.3.541                  | `magic -dnull -noconsole` runs a Tcl script     |
| netgen   | 1.5.323                  | `netgen -batch` starts                          |
| xschem   | 3.4.7                    | `xschem --version`                              |
| iverilog | master                   | compiles and simulates a `$display` testbench   |
| yosys    | 0.69+75 (CMake build)    | synthesizes a 2-input AND to one `$_AND_` cell  |
| ngspice  | 47 (XSPICE, CIDER, OpenMP) | `.op` of a 1k/2k divider on 1.8 V gives 1.2 V |

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

Note: every step of `ngspice_compile` is prefixed with `-`, so make
ignores failures and the target always "succeeds". Check the log or
`ngspice/src/ngspice` to see whether it actually built.

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
