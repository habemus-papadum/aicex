# xpra playbook: trying it out from a Mac

Step-by-step tests of a working xpra setup: connecting both ways, EDA
tools, OpenGL frame rate, and copy and paste. Setup and background are in
`XPRA_NOTES.md`.

The commands use the machines this was written on: the server is `legion`
(an `~/.ssh/config` alias for the Tailscale name `nehal-legion`), and the
login is `nehal`. Substitute your own.

## 0. One-time setup

On the Mac, after `tests/install_xpra_macos.sh`:

- `~/.xpra/xpra.conf` holds client defaults, one `option=value` per line
  (`ssh=ssh` would make `--ssh=ssh` unnecessary). Leave `encoding` at its
  default, auto: xpra 6.5.3's client rejects `encoding=png` at startup
  (`invalid encoding: png`), because it checks the option before loading
  its decoders. Auto already sends static text losslessly and uses video
  (NVENC on the server) for regions that change fast.
- Audio needs GStreamer on the Mac, which the source build doesn't
  install. Without it every connection logs "No Audio"; `speaker=off` and
  `audio=no` in `~/.xpra/xpra.conf` turn it off.
- The ssh host must resolve. `nehal-legion.local` (mDNS) didn't from the
  Mac, and xpra doesn't show ssh's error: it only prints `connection timed
  out` / `0 packets received`. Check with a plain `ssh legion true` first.

On the server, for readable xterms that share the Mac clipboard:

```sh
cat > ~/.Xresources <<'EOF'
XTerm*faceName: DejaVu Sans Mono
XTerm*faceSize: 16
XTerm*background: #1e1e1e
XTerm*foreground: #d4d4d4
! Use CLIPBOARD (what xpra shares with the Mac) instead of PRIMARY, so
! selecting copies to the Mac and middle-click/Shift-Insert paste from it.
XTerm*selectToClipboard: true
! Ctrl-Shift-C / Ctrl-Shift-V copy and paste (Cmd-Shift-C / Cmd-Shift-V from
! a Mac, since xpra sends Cmd as Ctrl).
XTerm*VT100.Translations: #override \n\
    Ctrl Shift <Key>C: copy-selection(CLIPBOARD) \n\
    Ctrl Shift <Key>V: insert-selection(CLIPBOARD)
EOF
ln -sfn .Xresources ~/.Xdefaults-$(hostname)
```

xpra sets its own X resources in each session, so xterm ignores
`~/.Xdefaults`, and xpra doesn't load `~/.Xresources` either. Xt apps also
read `~/.Xdefaults-<hostname>` on every display, which is what the symlink
is for.

## Shortcuts

### On the Mac

Shell functions that wrap everything below. They all work on one session
(`:100` by default) and never start a second one by accident: they start
the session on the server if it isn't running, and otherwise attach to it.

```sh
# xpra shortcuts. Paste into ~/.zshrc (they work in bash too).
XPRA_HOST=legion                    # ssh host (an ~/.ssh/config alias works)
XPRA_TLS=nehal@nehal-legion:14500   # user@host:port of the server's xpra proxy
XPRA_DISPLAY=100                    # the session everything below uses
XPRA_TLS_OPTS=(--ssl-server-verify-mode=none --ssl-check-hostname=no)

# Make sure session :$XPRA_DISPLAY exists on the server and has a window.
# Starts it with CMD (default xterm) if it isn't running. If it is, runs CMD
# in it, or an xterm when no CMD is given and the session has no windows.
# Runs on the server over ssh, so it's the same whichever way you attach.
_xpra_up() {
    ssh "$XPRA_HOST" "if xpra list 2>/dev/null | grep -q 'LIVE session at :$XPRA_DISPLAY\$'; then
            if [ -n '$*' ]; then
                xpra control :$XPRA_DISPLAY start -- $* >/dev/null
            elif ! xpra info :$XPRA_DISPLAY 2>/dev/null | grep -q '^windows\.[0-9]*\.title='; then
                xpra control :$XPRA_DISPLAY start xterm >/dev/null
            fi
        else
            xpra start :$XPRA_DISPLAY --start='${*:-xterm}' >/dev/null 2>&1
        fi"
}

xpssh()    { _xpra_up "$@" && xpra attach "ssh://$XPRA_HOST/$XPRA_DISPLAY" --ssh=ssh; }   # attach over ssh
xptls()    { _xpra_up "$@" && xpra attach "ssl://$XPRA_TLS/$XPRA_DISPLAY" "${XPRA_TLS_OPTS[@]}"; }  # attach on the port
xprun()    { _xpra_up "${@:-xterm}"; }                               # open another window: xprun emacs
# xpcd DIR CMD...: run CMD on the server from DIR, with its windows in the
# session. Goes through an interactive bash, so ~/.bashrc (PATH, and the xp
# helper) applies. Console output stays in this terminal; Ctrl-C ends it.
xpcd()     { local d=$1; shift; ssh -t "$XPRA_HOST" "cd $d && XPRA_DISPLAY=$XPRA_DISPLAY exec bash -ic 'xp ${*:-xterm}'"; }
xpls()     { ssh "$XPRA_HOST" xpra list; }                           # sessions on the server
xpdetach() { ssh "$XPRA_HOST" xpra detach ":$XPRA_DISPLAY"; }        # disconnect clients, keep the session
xpstop()   { ssh "$XPRA_HOST" xpra stop ":$XPRA_DISPLAY"; }          # end the session and its windows
xpdown()   {                                                         # end every session on the server
    ssh "$XPRA_HOST" 'for d in $(xpra list 2>/dev/null | sed -n "s/.*LIVE session at //p" | sort -u); do xpra stop $d; done'
}
```

| Command | Does |
|---|---|
| `xpssh [cmd]` | attach over ssh; starts the session if needed, and opens `cmd` (or an xterm if the session is empty) |
| `xptls [cmd]` | the same, directly on port 14500 (asks for your Linux password) |
| `xprun [cmd]` | open another window in the session, e.g. `xprun emacs`, `xprun 'xterm -fs 20'` |
| `xpcd dir [cmd]` | run `cmd` on the server from `dir`, e.g. `xpcd ~/src/aicex/tests ./smoke_test.sh gui magic` |
| `xpls` | list sessions on the server |
| `xpdetach` | disconnect every client; the session keeps running |
| `xpstop` | end the session and everything in it |
| `xpdown` | end every session on the server (the reset) |

`xpssh emacs` on a running session opens Emacs in it and attaches. Commands
are split on spaces on the server, so they can't contain quotes. Point the
functions at another session with `XPRA_DISPLAY=101 xpssh`.

`xprun` and `xpcd` differ in where the command runs. `xprun` asks the xpra
server to start it: it runs in your home directory with the server's
environment, and keeps running after you close the Mac terminal. `xpcd`
runs it in an ssh session: it gets `dir`, your `~/.bashrc` (PATH, conda
and so on), and its console output (magic's Tcl prompt, for example) stays
in your Mac terminal, but it ends when you press Ctrl-C or close that
terminal. `xpcd` needs the server-side helpers below.

### On the server

For a shell already on the server (ssh, or a VS Code remote terminal),
`~/.xpra-shell.sh`, sourced at the end of `~/.bashrc` with
`[ -f ~/.xpra-shell.sh ] && . ~/.xpra-shell.sh`:

```sh
# xpra helpers for shells on this machine (see aicex tests/XPRA_PLAYBOOK.md).
# Sourced from ~/.bashrc.
XPRA_DISPLAY=${XPRA_DISPLAY:-100}   # the session the Mac attaches to

# Start session :$XPRA_DISPLAY if it isn't running, and wait until its
# display accepts connections (xpra start returns before that). It starts
# with no windows; attach from the Mac with xpssh.
_xp_ensure() {
    local i
    DISPLAY=":$XPRA_DISPLAY" xdpyinfo >/dev/null 2>&1 && return
    xpra start ":$XPRA_DISPLAY" >/dev/null 2>&1
    for i in $(seq 30); do
        DISPLAY=":$XPRA_DISPLAY" xdpyinfo >/dev/null 2>&1 && return
        sleep 0.5
    done
    echo "xpra session :$XPRA_DISPLAY didn't start; see /run/user/$(id -u)/xpra/$XPRA_DISPLAY/server.log" >&2
    return 1
}

# xp CMD...: run CMD right here (this directory, this shell's PATH and
# environment), with its windows in the xpra session. Runs in the
# foreground like any command; add & to get the prompt back.
xp() { _xp_ensure && DISPLAY=":$XPRA_DISPLAY" "$@"; }

# xphere: point this shell at the session, so every GUI program started
# from it afterwards shows up there.
xphere() { _xp_ensure && export DISPLAY=":$XPRA_DISPLAY"; }
```

```sh
cd ~/src/aicex/tests
xp ./smoke_test.sh gui magic   # runs here; the window shows up on the Mac
xp emacs &                     # & to get the prompt back
xphere                         # or: every GUI program from this shell goes there
xschem &
```

Plain `DISPLAY=:100 some-app` does the same as `xp`; `xp` also starts the
session if it isn't running. Nothing shows up on the Mac until you attach
(`xpssh`); the program's windows are there when you do.

## 1. Connect

Over SSH:

```sh
xpra start ssh://legion/100 --ssh=ssh --start=xterm
```

Directly on port 14500 (TLS, asks for your Linux password). The certificate
is self-signed for "localhost", so skip verification. `V` is an array
because zsh doesn't split a plain `$V` string into words:

```sh
V=(--ssl-server-verify-mode=none --ssl-check-hostname=no)
xpra start ssl://nehal@nehal-legion:14500/ --start=xterm "${V[@]}"
```

The same session both ways: start over SSH, Ctrl-C the client on the Mac
(that detaches; the session keeps running), then reattach over TLS:

```sh
xpra attach ssl://nehal@nehal-legion:14500/100 "${V[@]}"
```

Browser, no client install: open `https://nehal-legion:14500/`, accept the
certificate warning, and log in.

Run everything below in the xterm that opens.

## 2. EDA tools

```sh
cd ~/src/aicex/tests
./smoke_test.sh gui magic      # sky130 layout; press v to fit, then pan and zoom
./smoke_test.sh gui xschem     # cmos_inv schematic
./smoke_test.sh gui gtkwave    # clock waveform
```

Magic's three drawing modes; the difference shows most when panning:

```sh
export PATH=/opt/eda/bin:$PATH
magic -d XR                    # Cairo, no OpenGL
magic -d OGL                   # OpenGL on the CPU (llvmpipe)
vglrun -d egl magic -d OGL     # OpenGL on the GPU
```

## 3. OpenGL frame rate

```sh
vblank_mode=0 glxgears                              # CPU; prints FPS every 5 s
vblank_mode=0 vglrun -d egl glxgears                # GPU
vglrun -d egl /opt/VirtualGL/bin/glxspheres64       # heavier; also prints fps
```

These are rendering rates on the server, not what reaches the Mac. For the
delivered rate, open Session Info from xpra's menu-bar icon, or run
`xpra info :100 | grep -iE 'fps|encoder='` on the server.

The default encoding (auto) switches a window to video, encoded by the
GPU (NVENC), once it keeps changing. To compare against always-video:

```sh
xpra attach ssh://legion/100 --ssh=ssh --encoding=stream  # forces video
```

`--encoding` on the Mac client only accepts auto, stream and rgb (see step
0).

## 4. Copy and paste with Emacs

```sh
emacs &
```

xpra sends Cmd as Ctrl (`swap-keys`), so Linux Ctrl shortcuts are typed
with Cmd:

| Where | Copy | Paste |
|---|---|---|
| Emacs | select, then `M-w` | Cmd-Y (`C-y`), or Edit > Paste |
| xterm | select with the mouse | Cmd-Shift-V, Shift-Insert or middle-click |
| gnome-terminal | Cmd-Shift-C | Cmd-Shift-V |
| Mac apps | Cmd-C | Cmd-V |

The xterm row needs the `~/.Xresources` settings from step 0, and only
applies to xterms started after they were added.
- Check the Linux side: `xclip -o -selection clipboard` prints what the
  server got; `echo hi | xclip -selection clipboard` sends text the other
  way.

Things that trip you up:

- xpra syncs the Mac clipboard with X's CLIPBOARD only. Out of the box,
  xterm copies and pastes with PRIMARY and has no key for CLIPBOARD, so
  Mac text never shows up in it; step 0's `~/.Xresources` fixes that.
  Emacs and gnome-terminal use CLIPBOARD.
- xpra swaps Cmd and Ctrl by default, so Cmd-Y is `C-y` in Emacs. Attach
  with `--swap-keys=no` to keep the Mac layout.
- If Option doesn't act as Meta, `Esc w` does the same as `M-w`.

## 5. Stop

```sh
xpra stop ssh://legion/100 --ssh=ssh   # ends the session and everything in it
ssh legion xpra list                   # what's running
```

Closing the last window doesn't end a session; it keeps running, empty,
until stopped.

## Setting up another machine

Everything above, as a checklist. Each file's contents are in this
playbook, in the section named.

### A new Linux server (instead of legion)

1. System install, once per machine: `XPRA_NOTES.md`, "Server setup"
   (xpra from xpra.org and its two 6.5.3 fixes for the port-14500 proxy,
   then VirtualGL and NVENC if the box has an NVIDIA GPU).
2. Packages the helpers and tests use: `sudo apt install x11-utils xclip`
   (`xdpyinfo` is how `xp` waits for the session; `xclip` is for the
   clipboard checks in step 4).
3. `~/.Xresources` and its `~/.Xdefaults-$(hostname)` symlink: step 0.
   The symlink is named after the host, so make it on the new box rather
   than copying it.
4. `~/.xpra-shell.sh`: "Shortcuts", "On the server".
5. Load it from `~/.bashrc`:
   ```sh
   printf '\n# xpra helpers: xp, xphere\n[ -f ~/.xpra-shell.sh ] && . ~/.xpra-shell.sh\n' >> ~/.bashrc
   ```
6. EDA tools and PDK, if the box needs them: `INSTALL.md`.

Check it from the server itself: `xp xdpyinfo | head -1` should print
`name of display: :100`.

### A new Mac client

1. `tests/install_xpra_macos.sh`, with `~/.local/bin` on `PATH`.
2. `~/.xpra/xpra.conf`:
   ```
   # xpra client defaults (see aicex tests/XPRA_PLAYBOOK.md).
   # encoding: leave at auto. xpra 6.5.3's client rejects encoding=png at
   # startup (it checks before loading its decoders), and auto already picks
   # lossless for static text and video (NVENC on the server) for motion.
   # Audio needs GStreamer on the Mac, which isn't installed; turning it off
   # avoids the "No Audio" warnings.
   speaker=off
   audio=no
   ```
3. The shortcuts block in `~/.zshrc`: "Shortcuts", "On the Mac".
4. An `~/.ssh/config` entry for the server whose `HostName` resolves from
   this Mac (step 0), and key login working: `ssh legion true`.

To point the Mac at a different server, change the three variables at the
top of the shortcuts block: `XPRA_HOST` (the ssh host), `XPRA_TLS`
(`user@host:14500`) and, if you want another session, `XPRA_DISPLAY`.
Check with `xpls`, then `xpssh`.

## Troubleshooting

**Connects, but no window appears.** The display already has a session,
probably one whose windows were all closed. `xpra start` on an existing
display just attaches to it and ignores `--start`. Launch a new window into
it, or stop it and start again:

```sh
xpra control ssh://legion/100 --ssh=ssh start xterm
```

**Sessions pile up.** `xpra start ssl://...:14500/` with no display number
makes the proxy create a new session on the next free display (`:0`, `:2`,
...) every time. Check with `ssh legion xpra list`. To reset everything:

```sh
ssh legion 'for d in $(xpra list | sed -n "s/.*LIVE session at //p" | sort -u); do xpra stop $d; done'
```
