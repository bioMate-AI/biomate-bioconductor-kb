# REINVENT4 nf ECR rebuild — 2026-11-14 11:30

## Image

| | |
|---|---|
| Repo/tag | `biomate/reinvent4-nf:x86` |
| **New digest** | `sha256:0c798092f9c8591d3bf9abdd50b6875be3c503e9c733731de694d62117f036af` |
| Previous | `sha256:443e2e6e…` |

## Builder

- Instance: `i-08232195bc858e990` (winner)
- Context: `build-ctx-20261114T172138Z.tgz`

## Root causes fixed

1. **Pack verify `KeyError`** — macOS `tar` embeds `./` prefixes; fixed with `COPYFILE_DISABLE=1` + tar backend path.
2. **micromamba pip** — pip install path corrected for micromamba env.
3. **`env -i` false PATH FATAL** — clean env wiped PATH; fixed so PATH survives.
4. **Missing scipy** — undeclared REINVENT4 import; scipy added to image deps.

## Status

**Not committed.** Dockerfile + build script changes remain local/uncommitted.

## Next

Batch re-measure REINVENT4 `/opt/REINVENT4` + Zenodo bridge on live with the new digest.
