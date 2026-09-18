# Building the EDA tools on Ubuntu 24.04: issues and workarounds

Notes from building with `tests/Makefile` on Ubuntu 24.04.4 LTS (Noble,
x86_64, gcc 13.3), installing into `/opt/eda` with the prefix owned by the
user so no step needs `sudo`. The macOS equivalent is `MACOS_NOTES.md`.

## Setup

Make the prefixes writable once, as root, then never use `sudo` again:

```sh
sudo mkdir -p /opt/eda /opt/pdk
sudo chown "$(id -un):$(id -gn)" /opt/eda /opt/pdk
```

`SUDO` in the Makefile resolves to empty when `$EDA_PREFIX` (or its nearest
existing parent) is writable, so every `*_install` target then runs as you.
This is the Linux counterpart of issue 3 in `MACOS_NOTES.md`: it keeps
root-owned files out of the prefix.

Shell config (`~/.bashrc`, same as `tests/bashrc`):

```sh
export PDK_ROOT=/opt/pdk/share/pdk
export PATH=/opt/eda/bin:/opt/eda/python3/bin:$HOME/.local/bin:$PATH
```

`tests/bashrc` also exports `LD_LIBRARY_PATH=/opt/eda/lib`. That is no longer
necessary — `make eda_install` bakes an `$ORIGIN`-relative RPATH into the
binaries (issue 3 below) — but it does no harm.

Then, from `tests/`:

```sh
make requirements    # apt packages
make tt              # tcl/tk 8.6.13 into $EDA_PREFIX
make eda_compile
make eda_install      # also runs set_rpath.sh on Linux
make gtkwave_compile gtkwave_install
./install_open_pdk.sh
```

## Verified (2026-09-18)

`make requirements`, `make tt`, `make eda_compile` and `make eda_install`
run clean with `EDA_PREFIX=/opt/eda` and never use sudo, after the fixes
below. `tests/smoke_test.sh` reruns these checks.

`./smoke_test.sh` reports **8 passed, 0 failed, 0 skipped** once Xyce is
built as well (`make xyce_compile xyce_install`; it is not part of
`eda_compile`). Without it, 7 passed and Xyce skipped.

| Tool     | Version                      | Check                                           |
|----------|------------------------------|-------------------------------------------------|
| magic    | 8.3.541                      | `magic -dnull -noconsole` runs a Tcl script     |
| netgen   | 1.5.323                      | `netgen -batch` starts                          |
| xschem   | 3.4.7                        | `xschem --version`                              |
| iverilog | 14.0 (devel)                 | compiles and simulates a `$display` testbench   |
| yosys    | 0.69+75 (CMake, g++ 13.3.0)  | synthesizes a 2-input AND to one `$_AND_` cell  |
| ngspice  | 47 (XSPICE, CIDER, OpenMP)   | `.op` of a 1k/2k divider on 1.8 V gives 1.2 V   |
| GTKWave  | 3.3.117 (GTK2)               | `--version`; VCD→FST→VCD round-trip             |
| Xyce     | 7.10.0 (Trilinos 14.4, serial) | `.DC` of the divider gives 1.2 V              |
| sky130   | open_pdks A+B (495 MB)       | `magic -rcfile .../sky130{A,B}.magicrc` loads each |

`xschem` links `/opt/eda/lib/libtcl8.6.so` and `libtk8.6.so`, not the system
8.6.14 — which is what `make tt` is for on this release.

The whole flow was also checked end to end with the repo's own
`make test` (`ip/rply_ex0_sky130nm`), which exercises ngspice, xschem, magic
and netgen against sky130B:

```
RPLY_EX0   [ DRC OK ]
RPLY_EX0   [ LVS OK ]
ibns_20u_9n = 21.76 uA,  vgs_m1 = 0.6203 V
```

It needs `/opt/eda/bin` and the uv `.venv/bin` on `PATH`, plus
`PDK_ROOT=/opt/pdk/share/pdk`. One cosmetic message appears partway through:

```
Error: incomplete or empty netlist
       or no ".plot", ".print", or ".fourier" lines in batch mode;
```

That is cicsim's second ngspice pass, the one that loads `*.raw` and runs the
measurements from a `.control` block, so it legitimately has no `.print`
lines. The transient itself ran (2003 rows) and the measurements were written
to both YAML and CSV.

`make requirements` on the 24.04 branch was sufficient as written for
`eda_compile` — every header and tool those builds needed was already in
the list. It was *not* sufficient for Xyce; see issues 8 and 9. `libtool` there
provides `libtoolize`, which is what `ngspice_compile` calls; the `libtool`
wrapper script itself lives in `libtool-bin` and is not needed.

## Issues

### 1. yosys: "C and C++ compilers must be provided by the same vendor"

**Symptom:** `make eda_compile` fails in yosys' cmake configure:

```
-- The C compiler identification is GNU 13.3.0
-- The CXX compiler identification is Clang 18.1.3
CMake Error at CMakeLists.txt:151 (message):
  C and C++ compilers must be provided by the same vendor
```

**Cause:** `yosys_compile` was the only compile target that did not pin the
compiler. cmake defaults to `cc` and `c++`, which are `update-alternatives`
symlinks that can point at different vendors:

```
$ update-alternatives --query c++ | grep -E 'Status|Value'
Status: manual
Value: /usr/bin/clang++
```

Every other target already passes `CC=${CC_GCC} CXX=${CC_GPP}`.

**Fix:** `yosys_compile` now passes `-DCMAKE_C_COMPILER`/`-DCMAKE_CXX_COMPILER`
on Linux. macOS keeps cmake's default, because `CC_GCC` there is Homebrew's
`gcc-${GCC_VER}` rather than the clang that builds the rest of the tools.

After a failed configure, remove the stale cache before retrying:
`rm -rf yosys/build`.

### 2. GTKWave: "The databases in [...] could not be updated"

**Symptom:** `make gtkwave_install` exits 2, but only after the binaries are
already in place — so it is easy to miss:

```
/usr/bin/update-desktop-database
The databases in [/usr/share/ubuntu/applications, ...] could not be updated.
make[5]: *** [Makefile:517: install-data-hook] Error 1
```

**Cause:** configure detects `update-desktop-database`, enables `FDO_MIME`,
and the generated `install-data-hook` runs it with no arguments — which
rewrites the *system-wide* XDG databases, not the ones under `--prefix`.
Installing into a prefix you own (no sudo) has no permission to do that.
macOS never hits this: there is no `update-desktop-database`, so the hook is
never generated.

**Fix:** the Linux branch of `gtkwave_compile` now passes
`--disable-mime-update`.

### 3. Nothing was built with an RPATH, so `${EDA_PREFIX}/lib` was invisible

**Symptom:** one loud failure and two silent ones. `smoke_test.sh` fails:

```
FAIL  iverilog: compiles and simulates
      vvp: error while loading shared libraries: libvvp.so.1: ...
```

**Cause:** the loader never searches `${EDA_PREFIX}/lib`. Of the 68 ELF files
under `/opt/eda`, exactly three link something from there without an RPATH:

| File | Needs | Resolved to |
|------|-------|-------------|
| `bin/vvp` | `libvvp.so.1` | **not found** |
| `bin/xschem` | `libtcl8.6.so`, `libtk8.6.so` | **system** 8.6.14 |
| `lib/netgen/tcl/netgenexec` | `libtcl8.6.so` | **system** 8.6.14 |

The last two are the dangerous ones: they do not fail, they quietly load the
distro's tcl/tk instead of the 8.6.13 that `make tt` built, which makes
`make tt` a no-op for them. tcl/tk and magic already emit
`RUNPATH=${EDA_PREFIX}/lib` from their own configure, which is why
`wish8.6`, `tclsh8.6`, `magicexec` and `magicdnull` were always fine.

macOS never hits any of this: the `install_name_tool` steps in the Makefile
bake the paths into the binaries.

**Fix:** `tests/set_rpath.sh`, run automatically by `make eda_install` on
Linux (also available as `make eda_rpath`). It is the Linux counterpart of
the macOS `install_name_tool` steps: for every installed ELF file that NEEDs
a library shipped in `${EDA_PREFIX}/lib`, it sets an RPATH expressed relative
to that file's own directory:

```
  bin/vvp                     RPATH=$ORIGIN/../lib
  bin/xschem                  RPATH=$ORIGIN/../lib
  lib/magic/tcl/magicexec     RPATH=$ORIGIN/../..
  lib/netgen/tcl/netgenexec   RPATH=$ORIGIN/../..
```

Files that link nothing from the prefix (ngspice, yosys, gtkwave) are left
untouched. `patchelf` was added to the apt lists.

**No `LD_LIBRARY_PATH` is needed afterwards.** `smoke_test.sh` now explicitly
`unset`s it, so the checks genuinely exercise the RPATH — with it set, a
missing or stale RPATH would go unnoticed. `tests/bashrc` still exports it;
that is now redundant but harmless.

**Scope of "relocatable":** because the RPATH uses `$ORIGIN`, *library
resolution* survives moving the prefix — `cp -a /opt/eda /tmp/eda-moved` and
`/tmp/eda-moved/bin/xschem` resolves entirely within the copy, with zero
references back to `/opt/eda`. The tools' *data* paths do not move: magic
still has `-DCAD_DIR="/opt/eda/lib"` compiled in, so a relocated magic reads
its scripts and tech files from the original prefix. Relocating the install
properly still means rebuilding with the new `EDA_PREFIX`.

### 4. Python: "error: externally-managed-environment" (PEP 668)

**Symptom:** every `install_*.sh` script fails:

```
$ python3 -m pip install --user -e .
error: externally-managed-environment
× This environment is externally managed
```

**Cause:** Ubuntu 24.04 ships `/usr/lib/python3.12/EXTERNALLY-MANAGED`, so
pip refuses to install into the system or user site. `install.sh`,
`install_cicpy.sh`, `install_cicsim.sh`, `install_cicconf.sh` and
`install_local.sh` all use `python3 -m pip install --user`, which was written
for 20.04/22.04 and cannot work on 24.04 as-is.

**Fix:** the repo root is now a [uv](https://docs.astral.sh/uv/) project —
`pyproject.toml` plus a committed `uv.lock` and `.python-version`:

```sh
uv sync                  # .venv with cicconf, cicsim, cicspi, cicpy
uv sync --extra wave     # ...plus cicwave (Qt viewer, ~650 MB of PySide6)
uv run cicconf clone --https
```

uv fetches its own interpreter, so PEP 668 never applies and no system python
is involved. `uv.lock` pins all 48 transitive packages, so macOS and Linux
resolve identically. `.python-version` had to be un-ignored in `.gitignore`
(the stock Python template ignores it for pyenv) or the pin would not be
shared.

All five tools are on PyPI, so nothing needs a git dependency or an editable
install of the `ip/cicsim` / `ip/cicconf` submodules.

Not changed: `install.sh`, `install_cicpy.sh`, `install_cicsim.sh`,
`install_cicconf.sh` and `install_local.sh` still use `pip install --user`.
They remain correct for the older Ubuntu releases the Docker images target,
and `docker/Dockerfile_24.04` still builds its own venv at
`/opt/eda/python3` inside the container. On a 24.04 workstation, use uv.

**None of this is needed to build the EDA tools.** open_pdks, yosys and magic
all run `/usr/bin/python3`; nothing under `/opt/eda/bin` references a venv,
and `smoke_test.sh` touches python not at all.

### 5. `requirements` picks the wrong apt branch without `lsb_release`

**Symptom:** in a container, `make requirements` fails with

```
E: Package 'libgl1-mesa-glx' has no installation candidate
```

**Cause:** `VER=$(shell lsb_release -sr)` selected the package list, but the
`ubuntu:24.04` base image has no `lsb-release` package (verified: `docker run
--rm ubuntu:24.04 command -v lsb_release` finds nothing). `VER` is then empty,
both `ifeq` tests fail, and the pre-22.04 branch runs — which asks for
`libgl1-mesa-glx`, dropped from Ubuntu after 22.04. This affects
`make ci24` / `docker/Dockerfile_24.04`, not a desktop install, where
`lsb_release` is present.

**Fix:** `VER` now reads `VERSION_ID` from `/etc/os-release`, which is always
present, and falls back to `lsb_release -sr`.

### 6. `install_open_pdk.sh` built sky130A only, but the IPs need sky130B

**Symptom:** nothing fails at install time. It only shows up when running a
design: `ip/rply_ex0_sky130nm/work` resolves `PDKPATH=${PDK_ROOT}/sky130B` and
LVS reads `${PDKPATH}/libs.tech/netgen/sky130B_setup.tcl`, which is absent.

**Cause:** the script passed `--with-sky130-variants=A` (as does
`docker/Dockerfile_26.04`), so open_pdks installed only `sky130A`. But
`ip/tech_sky130B` references `sky130B` 6240 times, and every `*_sky130nm` IP
(`sun_*`, `rply_*`, `cnr_*`) uses it — including `ip/rply_ex0_sky130nm`, which
is what the *root* `make test` runs. Only the newer `sky130a` designs
(`jnw_*`, `lelo_*`, `rey_*`) work with variant A alone.

**Fix:** the variant list is now `SKY130_VARIANTS`, defaulting to `all`, which
open_pdks expands to `A B` (`sky130/Makefile.in`: `ENABLED_VARIANTS = all | A
| B`). Set `SKY130_VARIANTS=A` for a smaller sky130A-only install.

Both variants together cost far less than twice one: 495 MB for A+B versus
459 MB for A alone, because open_pdks shares most of the content.

### 7. `magic_compile`: "Error 1 (ignored)"

`magic_compile` checks out a tag (`MAGIC_VER=8.3.541`), so the following
`git pull` runs on a detached HEAD and fails. The step is prefixed with `-`,
so make ignores it and prints `Error 1 (ignored)`. Harmless, and the same on
macOS.

### 8. Xyce: Trilinos aborts with `TPL_AMD_NOT_FOUND=TRUE`

**Symptom:** `make xyce_compile` fails in the Trilinos configure step:

```
-- Searching for headers in AMD_INCLUDE_DIRS=''
-- ERROR: Could not find a header file in the set "amd.h"
-- ERROR: Failed finding all of the parts of TPL 'AMD' (see above), Aborting!
CMake Error at cmake/tribits/core/package_arch/TribitsProcessEnabledTpls.cmake:278 (message):
  ERROR: TPL_AMD_NOT_FOUND=TRUE, aborting!
```

**Cause:** Debian and Ubuntu put SuiteSparse's headers in
`/usr/include/suitesparse`, not `/usr/include`. Trilinos' TPL search finds
`libamd.so` on the default library path without help, but never finds
`amd.h`. `TRILINOS_CMAKE_FLAGS` set `AMD_INCLUDE_DIRS` on macOS only, so
the Linux configure ran with it empty.

**Fix:** the `else` branch now sets
`TRILINOS_CMAKE_FLAGS = -D AMD_INCLUDE_DIRS=/usr/include/suitesparse`.
The library directory still needs no help.

### 9. Xyce: the apt lists were missing its build dependencies

**Cause:** Xyce isn't part of `eda_compile`, so `requirements` never
installed what it needs: `gfortran` (Trilinos' Fortran code — Xyce's
INSTALL.md reports AztecOO failures without it), BLAS/LAPACK,
SuiteSparse, FFTW, and `cmake`.

**Fix:** the 24.04 and 26.04 apt lists now include `cmake gfortran
libblas-dev liblapack-dev libsuitesparse-dev libfftw3-dev`. On a box
that already ran the old `requirements`:

```sh
sudo apt -y install cmake gfortran libblas-dev liblapack-dev \
                    libsuitesparse-dev libfftw3-dev
```

### Notes

- `make requirements` selects its package list with `VER=$(lsb_release -sr)`.
  `lsb_release` is present on a desktop 24.04 install but not in a minimal
  container; without it `VER` is empty and the build falls through to the
  legacy branch, which still asks for `libgl1-mesa-glx` (dropped after 22.04).
- On 24.04 `make tt` is required: `magic_compile` points `--with-tcl` and
  `--with-tk` at `${TK_PREFIX}/lib`, so the system tcl/tk is not used even
  though 8.6.14 is installed. Only the 26.04 branch builds against system
  tcl/tk.
- `yosys_compile` hardcodes `cmake --build build -j 8`. On a larger machine,
  raise it or use `-j $(nproc)`.
- GTKWave prints `Gtk-Message: Failed to load module "canberra-gtk-module"`
  on startup. Cosmetic; `sudo apt install libcanberra-gtk-module` silences it.
- Magic is built with both the OpenGL and Cairo backends. Over `ssh -X`/`-Y`
  the OpenGL backend needs indirect GLX, which XQuartz disables by default.
  Either run `magic -d XR` (Cairo) or, on the Mac,
  `defaults write org.xquartz.X11 enable_iglx -bool true` and restart XQuartz.

## X11 forwarding from a Mac

The server side needs nothing beyond a stock Ubuntu install: `X11Forwarding
yes` is already the default in `/etc/ssh/sshd_config`, and `xauth` is
installed. Verify from the box itself with:

```sh
ssh -X localhost 'echo $DISPLAY; xdpyinfo >/dev/null && echo ok'
```

which should print `localhost:10.0` and `ok`.

On the Mac, install XQuartz (`brew install --cask xquartz`) and log out once
so its launchd socket is registered. Then use `-Y` (trusted) rather than
`-X`: untrusted forwarding expires after `ForwardX11Timeout` (20 minutes by
default), after which windows die with `BadAccess`, and it blocks extensions
that magic and xschem use. In `~/.ssh/config`:

```sshconfig
Host legion
    HostName <host>
    User <user>
    ForwardX11 yes
    ForwardX11Trusted yes
    ForwardX11Timeout 596h
    Compression yes          # helps on a WAN link, hurts on a fast LAN
```

`xeyes` (from `x11-apps`, which `make requirements` does *not* install — it
is already present on a desktop install) is the quickest end-to-end check.
