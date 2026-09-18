---
layout: home
---

[![tests](https://github.com/wulffern/aicex/actions/workflows/tests.yaml/badge.svg)](https://github.com/wulffern/aicex/actions/workflows/tests.yaml)[![docs](https://github.com/wulffern/aicex/actions/workflows/jekyll-gh-pages.yml/badge.svg)](https://wulffern.github.io/aicex)
[![JNW](https://github.com/wulffern/aicex/actions/workflows/jnw.yaml/badge.svg)](https://github.com/wulffern/aicex/actions/workflows/jnw.yaml)
[![LELO](https://github.com/wulffern/aicex/actions/workflows/lelo.yaml/badge.svg)](https://github.com/wulffern/aicex/actions/workflows/lelo.yaml)

Head over to [wulffern.github.io/aicex](https://wulffern.github.io/aicex) for
the docs.

For the repo see [https://github.com/wulffern/aicex](https://github.com/wulffern/aicex)


# Files and folders

This is a repository that contains links to other github repositories with
analog designs. Most of the designs have been developed as part of the NTNU
course TFE4188 - Advanced Integrated Circuits.

``` sh
ci/       # Continous integration. Mostly check of the tutorials
docker/   # Dockerfiles to create a container with the tools
ip/       # all the IPs, config.yaml contains the links
tests/    # Makefile used for installation of the tools
```

# Installing, and usage 

For a detailed scription of installing the tools, see
<http://analogicus.com/aic2026/the_tools>

To build the tools and the PDK from source on your own machine, see
[tests/INSTALL.md](tests/INSTALL.md). It covers the whole flow — uv, the
IPs, the EDA tools, the PDK — and has a macOS section at the end.

For a description of the usage, see
<https://analogicus.com/aic2026/sky130nm_tutorial>


# For the impatient

The python tooling is managed with [uv](https://docs.astral.sh/uv/). `uv sync`
reads `pyproject.toml`/`uv.lock` and builds `.venv` with the pinned versions of
cicconf, cicsim, cicspi and cicpy. It also fetches the interpreter named in
`.python-version`, so no system python is involved — which matters on Ubuntu
24.04 and later, where `pip install --user` is refused outright (PEP 668).

``` sh
git clone --recursive https://github.com/wulffern/aicex.git
cd aicex
uv sync
cd ip
uv run cicconf clone --https
cd ..
```

`uv run <tool>` works without activating anything; `source .venv/bin/activate`
also works if you prefer. Add `--extra wave` to `uv sync` for `cicwave`, the Qt
waveform viewer — it is opt-in because PySide6 alone is ~650 MB.

I assume you have docker installed, or have windows subsystem for linux. 

> &#x26A0;  It's a very good idea to check what's inside scripts before you run them

``` sh
./run.sh
```

You should now see a cyan "aicex@~$" terminal.

Check that you can open a new X terminal 

``` sh
xterm &
```

You should now be able to run the tutorial at 
<https://analogicus.com/aic2026/sky130nm_tutorial>

# Known issues

## Xschem

* Netlisting seems to be done not by pin number, but by order of B's in .sym.
  Also, I've experienced different ordering for subckts, and for top cell

* Be careful of x1[5:0] notation. Xschem does not automatically discover if
  there is another same x<nr>. I would recommend always uniquely naming
  instances with bus notation 

## docker
* Using SSH: The aicex user has a uid of 1001, however, if you try and run it on a machine
  with a different uid for your user, then it does not seem to work. 

## Ngspice
