# Remote GUIs with xpra: Ubuntu 24.04 server, macOS client

xpra is "screen for X": GUI tools (magic, xschem, klayout, gtkwave) run in a
session on the Linux box, and you detach and reattach from anywhere, the way
you would with `screen`/`tmux`. OpenGL renders on the server, so it also avoids
the indirect-GLX problem with `ssh -X` described in `UBUNTU_NOTES.md`.

Tested with xpra 6.5.3, VirtualGL 3.1.5 and NVENC on Ubuntu 24.04 with an
NVIDIA GPU (driver 580, installed from NVIDIA's CUDA repo). None of the steps
below change the NVIDIA driver.

In the commands below, `HOST` is the Linux box and `USER` your login on it.

## Installing the client on a Mac

The client is a native macOS app, so XQuartz isn't needed. It requires
macOS 12 or later. Use a 6.x client to match the server.

**Homebrew cask: no longer works.** Since 2026-09-01 `Xpra.app` fails
the Gatekeeper check, so `brew install --cask xpra` won't install it.

**Build from source** (puts `xpra` on your `PATH`, needs no sudo):

```sh
tests/install_xpra_macos.sh
xpra --version
```

This builds the latest xpra release against Homebrew's GTK3 into a venv
at `~/.local/share/xpra`. It also adds `xpra` and `xpra_launcher`
wrappers to `~/.local/bin`, which must be on `PATH`. Rerun it to
upgrade. It builds a command-line client, not an app bundle, so there's
nothing to open from Finder. `xpra_launcher` opens the same connection
dialog that Xpra.app does. Why each step is needed is in
`MACOS_NOTES.md`, issue 15.

**PKG from xpra.org** (also registers `xpra+ssl://` links and `.xpra` session
files with macOS; the Homebrew cask uses the DMG, which doesn't):

- Apple Silicon (`uname -m` prints `arm64`): <https://xpra.org/stable/MacOS/arm64/Xpra.pkg>
- Intel (`uname -m` prints `x86_64`): <https://xpra.org/stable/MacOS/x86_64/Xpra.pkg>

It installs `/Applications/Xpra.app`. The command-line tool is inside the
bundle:

```sh
echo 'alias xpra=/Applications/Xpra.app/Contents/MacOS/Xpra' >> ~/.zshrc
```

If macOS won't open it the first time, allow it under System Settings >
Privacy & Security.

Mac-specific behaviour:

- Command and Control are swapped by default (`swap-keys`), so Cmd-C in a
  remote app sends Ctrl-C. Turn it off with `--swap-keys=no`.
- For `ssh://`, the client uses its bundled paramiko by default. Add
  `--ssh=ssh` to use the Mac's OpenSSH instead, so `~/.ssh/config`, the agent
  and `ProxyJump` apply.
- Launching Xpra.app without arguments opens a connection dialog (mode,
  host, port, username), an alternative to the command lines below.
- The command line prints diagnostics directly, so use it when something
  doesn't work.

## Connecting

### Over SSH

```sh
xpra start  ssh://USER@HOST/100 --start=xterm   # new session + attach
xpra attach ssh://USER@HOST/100                 # reattach later
```

### Directly (no SSH): port 14500

The system xpra proxy (see server setup below) listens on port 14500 on all
interfaces and logs you in with your normal Linux password. Only enable it on
a network you trust. Use `ssl://`: plain `tcp://` from another machine is
refused, because the client won't send a password unencrypted. The
certificate the package generates is self-signed for "localhost", so skip
verification:

```sh
V="--ssl-server-verify-mode=none --ssl-check-hostname=no"
xpra attach ssl://USER@HOST:14500/     $V   # attach to your only session
xpra attach ssl://USER@HOST:14500/100  $V   # pick one if you have several
xpra start  ssl://USER@HOST:14500/ --start=xterm $V   # proxy starts a new session
```

Browser, no client install: open `https://HOST:14500/`, accept the
certificate warning, then log in with your username and Linux password.

Service control: `sudo systemctl {status,restart,disable --now} xpra-server.socket xpra-server.service`.
Log: `journalctl -u xpra-server`.

### On the server itself

```sh
xpra list                         # running sessions
DISPLAY=:100 some-app &           # launch into an existing session
xpra stop :100
```

## GPU

- **OpenGL:** apps in an xpra session run on llvmpipe (CPU) by default. Prefix
  them with `vglrun -d egl` to render on the GPU. On the test machine,
  glxspheres64 ran at ~85 fps on llvmpipe vs ~1,270 fps with vglrun.
  `-d egl` means the first EGL device. On a laptop with integrated and
  NVIDIA graphics, check which one that is with
  `/opt/VirtualGL/bin/eglinfo -e` and pick another with `-d egl1`, etc.
- **NVENC:** automatic once set up (below). xpra uses it for video-like
  regions (h264/hevc/av1). Check with `xpra info :100 | grep 'encoder='` or
  `nvidia-smi --query-gpu=encoder.stats.sessionCount,encoder.stats.averageFps --format=csv -l 1`.

## Server setup (Ubuntu 24.04)

### xpra

Ubuntu's own `xpra` package (3.1.5) is too old for 24.04; use xpra.org's:

```sh
sudo wget -O /usr/share/keyrings/xpra.asc https://xpra.org/xpra.asc
sudo wget -O /etc/apt/sources.list.d/xpra.sources \
  https://raw.githubusercontent.com/Xpra-org/xpra/master/packaging/repos/noble/xpra.sources
sudo apt update && sudo apt install xpra
```

The package enables `xpra-server.socket` (the port-14500 proxy). In 6.5.3 it
needs two fixes before it works:

```sh
# 1. The proxy dies with "cannot import name TCP_SOCKTYPES" (sd_listen.pyx
#    imports it from the wrong module; fixed upstream after 6.5.3).
sudo sed -i 's/^from xpra.net.constants import ConnectionMessage$/from xpra.net.constants import ConnectionMessage, TCP_SOCKTYPES/' \
  /usr/lib/python3/dist-packages/xpra/net/common.py
# 2. The service file points at /etc/xpra/ssl-cert.pem, but the package
#    generates it in /etc/xpra/ssl/.
sudo ln -s /etc/xpra/ssl/ssl-cert.pem /etc/xpra/ssl-cert.pem
sudo systemctl restart xpra-server.socket
```

An xpra upgrade overwrites fix 1. If port 14500 stops working after
`apt upgrade`, check `systemctl status xpra-server` and re-apply it.
To turn the proxy off: `sudo systemctl disable --now xpra-server.socket`.

### VirtualGL

```sh
curl -sfL https://packagecloud.io/dcommander/virtualgl/gpgkey | gpg --dearmor \
  | sudo tee /etc/apt/trusted.gpg.d/VirtualGL.gpg >/dev/null
sudo wget -O /etc/apt/sources.list.d/VirtualGL.list \
  https://raw.githubusercontent.com/VirtualGL/repo/main/VirtualGL.list
sudo apt update && sudo apt install --no-install-recommends virtualgl
sudo usermod -aG video,render "$USER"   # GPU access when not logged in at the console
```

`vglserver_config` isn't needed for the EGL back end, and it's deliberately
not run here because it edits NVIDIA modprobe options.

### NVENC

xpra's NVENC encoder needs `pycuda`. Don't install Ubuntu's `python3-pycuda`
(or `xpra-codecs-nvidia` with its recommends) when the driver comes from
NVIDIA's repo: they pull in `libnvidia-compute-535`, which doesn't match the
driver. Preview with `apt-get install -s` first. Instead, build pycuda
against an installed CUDA toolkit (13.0 here, matching xpra's build):

```sh
sudo apt install --no-install-recommends xpra-codecs-nvidia \
  python3-numpy python3-pytools python3-mako
CUDA_ROOT=/usr/local/cuda-13.0 PATH=/usr/local/cuda-13.0/bin:$PATH \
  python3 -m pip wheel --no-deps --no-build-isolation -w wheels pycuda==2026.1
sudo python3 -m pip install --break-system-packages --no-deps wheels/pycuda-*.whl
xpra encoding | grep NVENC   # "NVENC v13 successfully initialized with codecs: h264, hevc, av1"
```

This installs pycuda into `/usr/local/lib/python3.12/dist-packages`; rebuild
it if xpra moves to a new Python. Remove it with
`sudo pip uninstall --break-system-packages pycuda`.

## Things to try later

- [ ] Magic, three ways, panning and zooming a big layout:
      `magic -d XR` (Cairo, no OpenGL) vs `magic -d OGL` (llvmpipe) vs
      `vglrun -d egl magic -d OGL` (GPU).
- [ ] KLayout's 2.5D view (OpenGL) with and without `vglrun -d egl`.
- [ ] Encodings from the client: default (auto) vs `--encoding=png`
      (pixel-exact, good for layouts/text) vs `--encoding=h264|hevc|av1`
      (forces video, so NVENC).
- [ ] On a slow link: `--quality=50` / `--min-quality=30`; on a fast LAN:
      `--quality=100`.
- [ ] Client-side `--opengl=yes` on the Mac for smoother window painting.
- [ ] Browser client at `https://HOST:14500/` (no client install).
- [ ] Real NVENC frame rate from the Mac. The headless test here only showed
      ~4 fps average, but its client was software-only on a virtual display,
      so that number doesn't reflect real use.
- [ ] Make a proper TLS cert for the server's hostname (SAN with hostname and
      LAN IP), so `--ssl-ca-certs=cert.pem` works instead of turning
      verification off.
- [ ] `vglrun -d egl` for anything else slow and GL-based (GTKWave doesn't
      use GL, so it won't help there).

## Known quirks (harmless)

- `xpra encoding` reports "dec_nvjpeg failed its self test". That's a
  client-side decoder, not used when the box is the server.
- The Linux xpra client crashes with `--mmap=no` unless you also pass
  `--webcam=no` (xpra bug).
- "Could not resolve keysym XF86..." warnings in server logs.
