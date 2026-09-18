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
