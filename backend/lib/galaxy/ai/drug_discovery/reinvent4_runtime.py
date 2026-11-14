"""
REINVENT4 CLI + prior resolution for live ECR and rebuilt invent4-nf images.

Live ``biomate/reinvent4-nf:x86`` (2026-11-10) ships a git checkout at
``/opt/REINVENT4`` without a PATH ``reinvent`` console script and without
staged ``.prior`` files (``priors/`` only has a Zenodo README). The repo
Dockerfile that ``pip install reinvent`` + curls priors was not what got
pushed. This module bridges both layouts:

  * PATH ``reinvent`` (rebuilt image), else ``python -c`` calling
    ``reinvent.Reinvent.main_script`` with ``/opt/REINVENT4`` on PYTHONPATH
    (live ECR git tree; older trees may lack ``reinvent/__main__.py``).
  * Staged priors under ``$REINVENT4_PRIORS`` / ``/opt/reinvent4/priors``,
    else fetch public Zenodo record 20701824 (DOI 10.5281/zenodo.15641296).

Used by ``generators.Reinvent4Generator``, ``reinvent4_trainer._Reinvent4Base``,
and ``reinvent4_finetune_rl/bin/run_reinvent4_training.py``. The Nextflow
``GENERATE_REINVENT4`` script mirrors the same logic inline so sampling works
before the next ECR rebuild copies this module into the image.
"""
from __future__ import annotations

import importlib.util
import os
import shutil
import sys
import tempfile
import urllib.error
import urllib.request
from typing import Iterable, List, Optional, Sequence

# Git-checkout layouts seen on live ECR + historical images.
SRC_ROOTS: Sequence[str] = (
    "/opt/REINVENT4",
    "/opt/reinvent4",
    "/opt/reinvent",
)

# Zenodo no longer ships classic reinvent.prior / mol2mol_similarity.prior;
# reinvent_pubchem.prior is the public Reinvent prior used for sampling.
ZENODO_PRIORS = {
    "reinvent.prior": (
        "https://zenodo.org/api/records/20701824/files/reinvent_pubchem.prior/content"
    ),
    "reinvent_pubchem.prior": (
        "https://zenodo.org/api/records/20701824/files/reinvent_pubchem.prior/content"
    ),
    "libinvent.prior": (
        "https://zenodo.org/api/records/20701824/files/libinvent.prior/content"
    ),
    "linkinvent.prior": (
        "https://zenodo.org/api/records/20701824/files/linkinvent.prior/content"
    ),
}

_MIN_PRIOR_BYTES = 1_000_000
_FETCH_TIMEOUT_S = 120


def allow_prior_fetch() -> bool:
    """Disable with REINVENT4_ALLOW_PRIOR_FETCH=0 (unit tests / air-gapped)."""
    return os.environ.get("REINVENT4_ALLOW_PRIOR_FETCH", "1").strip() not in (
        "0",
        "false",
        "False",
        "no",
    )


def ensure_reinvent_src_on_path() -> Optional[str]:
    """
    If a git checkout of REINVENT4 is present, put it on PYTHONPATH/sys.path.
    Returns the root used, or None.
    """
    for src_root in SRC_ROOTS:
        if os.path.isdir(os.path.join(src_root, "reinvent")):
            os.environ["PYTHONPATH"] = (
                src_root + os.pathsep + os.environ.get("PYTHONPATH", "")
            )
            if src_root not in sys.path:
                sys.path.insert(0, src_root)
            return src_root
    return None


def resolve_cli(cli_override: Optional[str] = None) -> Optional[List[str]]:
    """
    Return a truthy argv prefix if REINVENT4 is invokable, else None.

    Prefer :func:`run_reinvent` for actual execution — older git checkouts lack
    ``reinvent/__main__.py`` / console_scripts, so bare ``argv + [toml]`` can fail
    even when the package imports.
    """
    ensure_reinvent_src_on_path()
    override = cli_override or os.environ.get("REINVENT4_CLI")
    if override:
        exe = shutil.which(override) or (
            override if os.path.isfile(override) else None
        )
        return [exe] if exe else None
    exe = shutil.which("reinvent")
    if exe:
        return [exe]
    try:
        if importlib.util.find_spec("reinvent") is not None:
            return [sys.executable, "-m", "reinvent"]
    except Exception:
        pass
    return None


def run_reinvent(
    cfg_path: str,
    cli_override: Optional[str] = None,
    *,
    timeout: Optional[int] = None,
):
    """
    Invoke REINVENT4 on a TOML config.

    Uses PATH CLI when present; otherwise calls ``reinvent.Reinvent.main_script``
    via ``python -c`` (works for git checkouts without console_scripts /
    without ``__main__.py``).
    """
    import subprocess

    ensure_reinvent_src_on_path()
    override = cli_override or os.environ.get("REINVENT4_CLI")
    if override:
        exe = shutil.which(override) or (
            override if os.path.isfile(override) else None
        )
        if not exe:
            raise FileNotFoundError(f"REINVENT4_CLI not found: {override!r}")
        return subprocess.run(
            [exe, cfg_path],
            capture_output=True,
            text=True,
            timeout=timeout,
            env=os.environ.copy(),
        )
    exe = shutil.which("reinvent")
    if exe:
        return subprocess.run(
            [exe, cfg_path],
            capture_output=True,
            text=True,
            timeout=timeout,
            env=os.environ.copy(),
        )
    # Source-tree / pip package without a console script on PATH.
    runner = (
        "import sys\n"
        "from reinvent.Reinvent import main_script\n"
        'sys.argv = ["reinvent", sys.argv[1]]\n'
        "main_script()\n"
    )
    return subprocess.run(
        [sys.executable, "-c", runner, cfg_path],
        capture_output=True,
        text=True,
        timeout=timeout,
        env=os.environ.copy(),
    )


def prior_search_dirs(priors_dir: Optional[str] = None) -> List[str]:
    dirs: List[str] = []
    primary = priors_dir or os.environ.get("REINVENT4_PRIORS", "/opt/reinvent4/priors")
    for d in (
        primary,
        "/opt/reinvent4/priors",
        "/opt/REINVENT4/priors",
        "/opt/reinvent/priors",
    ):
        if d and d not in dirs:
            dirs.append(d)
    return dirs


def _prior_ok(path: str) -> bool:
    try:
        return os.path.isfile(path) and os.path.getsize(path) > _MIN_PRIOR_BYTES
    except OSError:
        return False


def _download(url: str, dest: str) -> None:
    """Fetch with a hard timeout (urlretrieve has none)."""
    req = urllib.request.Request(url, headers={"User-Agent": "biomate-reinvent4/1.0"})
    with urllib.request.urlopen(req, timeout=_FETCH_TIMEOUT_S) as resp:
        data = resp.read()
    if len(data) <= _MIN_PRIOR_BYTES:
        raise IOError(
            f"Zenodo prior download too small ({len(data)} bytes) from {url}"
        )
    tmp = dest + ".partial"
    with open(tmp, "wb") as fh:
        fh.write(data)
    os.replace(tmp, dest)


def find_or_fetch_prior(
    names: Iterable[str],
    priors_dir: Optional[str] = None,
    *,
    allow_fetch: Optional[bool] = None,
) -> Optional[str]:
    """
    Locate a prior by filename candidates, optionally fetching from Zenodo.

    ``mol2mol_similarity.prior`` is not on Zenodo — callers should pass
    ``['mol2mol_similarity.prior', 'reinvent.prior', 'reinvent_pubchem.prior']``
    so sampling can fall back to the public Reinvent prior.
    """
    name_list = list(names)
    for d in prior_search_dirs(priors_dir):
        for name in name_list:
            p = os.path.join(d, name)
            if _prior_ok(p):
                return p
            # Accept .model sibling (REINVENT4 ships both naming styles).
            alt = p.replace(".prior", ".model")
            if alt != p and _prior_ok(alt):
                return alt

    if allow_fetch is None:
        allow_fetch = allow_prior_fetch()
    if not allow_fetch:
        return None

    cache = os.path.join(tempfile.gettempdir(), "reinvent4_priors")
    os.makedirs(cache, exist_ok=True)
    for name in name_list:
        url = ZENODO_PRIORS.get(name)
        if not url:
            continue
        dest = os.path.join(cache, name)
        if not _prior_ok(dest):
            try:
                print(f"Fetching REINVENT4 prior {name} from Zenodo…", flush=True)
                _download(url, dest)
            except (urllib.error.URLError, OSError, TimeoutError) as exc:
                print(f"WARN: Zenodo fetch failed for {name}: {exc}", flush=True)
                continue
        if _prior_ok(dest):
            return dest
    return None


def default_sampling_prior_names(*, denovo: bool) -> List[str]:
    if denovo:
        return ["reinvent.prior", "reinvent_pubchem.prior"]
    return [
        "mol2mol_similarity.prior",
        "reinvent.prior",
        "reinvent_pubchem.prior",
    ]
