"""
Nextflow Executor API

Provides POST /api/nextflow/execute — launches a Nextflow workflow
as a background subprocess and returns tracking IDs.

Does NOT require Galaxy workflow/invocation infrastructure.
"""
import logging
import os
import re
import subprocess
import threading
import time
import uuid
from pathlib import Path
from typing import Any, Dict, List, Optional

from fastapi import HTTPException, Response
from fastapi.responses import HTMLResponse
from pydantic import BaseModel

from galaxy.managers.context import ProvidesUserContext
from galaxy.webapps.galaxy.api import (
    DependsOnTrans,
    Router,
)

log = logging.getLogger(__name__)

# Load .env from the backend root so NEXTFLOW_USE_AWS, AWS_S3_BUCKET, etc.
# are available even when gunicorn is started without explicit env exports.
try:
    _backend_root = Path(__file__).resolve().parents[5]
    _dotenv_path = _backend_root / ".env"
    if _dotenv_path.exists():
        from dotenv import load_dotenv
        load_dotenv(_dotenv_path, override=False)  # override=False: real env vars win
        log.info(f"[Nextflow] Loaded environment from {_dotenv_path}")
except Exception as _e:
    log.warning(f"[Nextflow] Could not load .env: {_e}")

router = Router(tags=["nextflow"])

# In-process registry: run_id → {status, process, outdir, ...}
_runs: Dict[str, Dict[str, Any]] = {}
_runs_lock = threading.Lock()

# QC handler registry: invocation_id → NextflowQCGateHandler
# Populated by _start_qc_monitor so the export endpoint can retrieve live state.
_qc_handlers: Dict[str, Any] = {}
_qc_handlers_lock = threading.Lock()

# ---------------------------------------------------------------------------
# Public database accession detection
# ---------------------------------------------------------------------------
# Covers all major life-science databases so accession strings are never treated
# as local file paths.  Each entry maps a human-readable type label to a compiled
# regex (anchored) and a handler type used to choose the download strategy.
#
# handler types:
#   "sequencing"   → nf-core/fetchngs pre-step (produces samplesheet.csv)
#   "structure"    → RCSB / EMDB HTTP download  (produces .cif / .map.gz)
#   "protein_seq"  → UniProt / NCBI protein API  (produces .fasta)
#   "proteomics"   → PRIDE FTP or aspera         (produces raw MS files)
#   "chemical"     → ChEMBL / PubChem API        (produces .sdf / .json)
#   "genomic_ref"  → Ensembl REST / NCBI API     (produces .fasta / .vcf)
#   "annotation"   → no file download; informational only (rs IDs, ClinVar)
# ---------------------------------------------------------------------------

_ACCESSION_REGISTRY: list[dict] = [
    # ── Sequencing / raw reads ────────────────────────────────────────────
    {
        "label": "SRA run",
        "handler": "sequencing",
        "re": re.compile(r'^[SED]RR\d{6,9}$', re.IGNORECASE),
        "example": "SRR628582",
    },
    {
        "label": "ENA / SRA project",
        "handler": "sequencing",
        "re": re.compile(r'^[ES]RP\d{6,9}$', re.IGNORECASE),
        "example": "SRP123456",
    },
    {
        "label": "BioProject",
        "handler": "sequencing",
        "re": re.compile(r'^PRJ[NE][A-Z]\d{4,9}$', re.IGNORECASE),
        "example": "PRJNA12345",
    },
    {
        "label": "GEO series",
        "handler": "sequencing",
        "re": re.compile(r'^GSE\d{4,9}$', re.IGNORECASE),
        "example": "GSE12345",
    },
    {
        "label": "GEO sample",
        "handler": "sequencing",
        "re": re.compile(r'^GSM\d{5,9}$', re.IGNORECASE),
        "example": "GSM123456",
    },
    {
        "label": "ArrayExpress / BioStudies",
        "handler": "sequencing",
        "re": re.compile(r'^E-[A-Z]{4}-\d{4,9}$', re.IGNORECASE),
        "example": "E-MTAB-1234",
    },
    # ── Macromolecular structure ──────────────────────────────────────────
    {
        "label": "PDB entry",
        "handler": "structure",
        # PDB IDs: digit + 3 alphanumeric chars, at least one must be a letter
        # (pure-numeric 4-char strings like "1000" are not valid PDB IDs)
        "re": re.compile(r'^[0-9](?=[A-Z0-9]{0,2}[A-Z])[A-Z0-9]{3}$', re.IGNORECASE),
        "example": "4ZQK",
    },
    {
        "label": "EMDB entry",
        "handler": "structure",
        "re": re.compile(r'^EMD-\d{4,6}$', re.IGNORECASE),
        "example": "EMD-1234",
    },
    # ── Protein / gene sequences ─────────────────────────────────────────
    {
        "label": "UniProt accession",
        "handler": "protein_seq",
        # UniProtKB: [OPQ][0-9][A-Z0-9]{3}[0-9] or [A-NR-Z][0-9][A-Z][A-Z0-9]{2}[0-9]
        "re": re.compile(
            r'^[OPQ][0-9][A-Z0-9]{3}[0-9]$|^[A-NR-Z][0-9]([A-Z][A-Z0-9]{2}[0-9]){1,2}$',
            re.IGNORECASE,
        ),
        "example": "P12345",
    },
    {
        "label": "NCBI RefSeq protein",
        "handler": "protein_seq",
        "re": re.compile(r'^[NXW]P_\d{6,9}(\.\d+)?$', re.IGNORECASE),
        "example": "NP_012345.1",
    },
    {
        "label": "NCBI RefSeq nucleotide",
        "handler": "genomic_ref",
        "re": re.compile(r'^[NXW][CGMRTZ]_\d{6,9}(\.\d+)?$', re.IGNORECASE),
        "example": "NC_000001.11",
    },
    {
        "label": "Ensembl gene",
        "handler": "genomic_ref",
        "re": re.compile(r'^ENSG\d{11}(\.\d+)?$', re.IGNORECASE),
        "example": "ENSG00000141510",
    },
    {
        "label": "Ensembl transcript",
        "handler": "genomic_ref",
        "re": re.compile(r'^ENST\d{11}(\.\d+)?$', re.IGNORECASE),
        "example": "ENST00000269305",
    },
    {
        "label": "Ensembl protein",
        "handler": "protein_seq",
        "re": re.compile(r'^ENSP\d{11}(\.\d+)?$', re.IGNORECASE),
        "example": "ENSP00000269305",
    },
    # ── Proteomics / mass spectrometry ───────────────────────────────────
    {
        "label": "PRIDE dataset",
        "handler": "proteomics",
        "re": re.compile(r'^PXD\d{6,9}$', re.IGNORECASE),
        "example": "PXD001234",
    },
    {
        "label": "MassIVE dataset",
        "handler": "proteomics",
        "re": re.compile(r'^MSV\d{9}$', re.IGNORECASE),
        "example": "MSV000079033",
    },
    # ── Chemical / small molecules ───────────────────────────────────────
    {
        "label": "ChEMBL compound",
        "handler": "chemical",
        "re": re.compile(r'^CHEMBL\d{1,9}$', re.IGNORECASE),
        "example": "CHEMBL25",
    },
    {
        "label": "PubChem CID",
        "handler": "chemical",
        "re": re.compile(r'^CID\d{1,9}$', re.IGNORECASE),
        "example": "CID2244",
    },
    # ── Variant / clinical annotation (no download, flag only) ───────────
    {
        "label": "dbSNP variant",
        "handler": "annotation",
        "re": re.compile(r'^rs\d{6,12}$', re.IGNORECASE),
        "example": "rs1234567",
    },
    {
        "label": "ClinVar variant",
        "handler": "annotation",
        "re": re.compile(r'^[RV]CV\d{9}$', re.IGNORECASE),
        "example": "VCV000012345",
    },
]


def _classify_accession(value: str) -> Optional[Dict[str, str]]:
    """
    Return accession metadata if *value* is a recognised public-database accession,
    or None if it looks like a normal path/parameter value.

    Returns: {"label": str, "handler": str, "accession": str} or None.
    """
    if not isinstance(value, str):
        return None
    v = value.strip()
    if not v or len(v) < 4 or len(v) > 30:
        return None
    # Reject strings that look like file paths or URLs
    if v.startswith("/") or v.startswith("s3://") or v.startswith("http") or "." in v.split("/")[-1].split("_")[0]:
        return None
    for entry in _ACCESSION_REGISTRY:
        if entry["re"].match(v):
            return {"label": entry["label"], "handler": entry["handler"], "accession": v.upper()}
    return None


def _is_public_accession(value: str) -> bool:
    """Convenience wrapper: True if the value is a recognised public-database accession."""
    return _classify_accession(value) is not None


# ---------------------------------------------------------------------------
# Request / response models
# ---------------------------------------------------------------------------

def _default_nf_profile() -> str:
    """Return the deployment-level Nextflow profile from env, defaulting to 'docker'."""
    return os.environ.get("BIOMATE_NF_PROFILE", "docker")


class NextflowExecuteRequest(BaseModel):
    nextflow_path: str
    parameters: Optional[Dict[str, Any]] = None
    profile: Optional[str] = None  # None → resolved at execution time from BIOMATE_NF_PROFILE
    entry: Optional[str] = None
    history_id: Optional[str] = None
    compute_config: Optional[Dict[str, Any]] = None
    qc_overrides: Optional[Dict[str, Any]] = None
    qc_profile: Optional[str] = None
    workflow_domain: Optional[str] = None
    user_id: Optional[str] = None  # billing: propagated to Batch job env vars
    is_pilot: Optional[bool] = None  # pilot study: bypass billing; tag in KPI logs
    resume_from_run_id: Optional[str] = None  # if set, passes -resume -w <prev_work_dir>
    credentials: Optional[Dict[str, Any]] = None  # {tool_id: {username, token} | {license_key}}


class NextflowStatusRequest(BaseModel):
    run_id: str


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _get_nextflow_bin() -> str:
    nf = os.environ.get("NEXTFLOW_BIN", "nextflow")
    # Verify it's actually on PATH
    import shutil
    resolved = shutil.which(nf)
    if resolved:
        return resolved
    raise RuntimeError(
        f"Nextflow binary '{nf}' not found on PATH. "
        "Install with: curl -s https://get.nextflow.io | bash"
    )


def _candidate_bases() -> list[Path]:
    """
    Build ordered search roots for resolving logical Nextflow paths.

    We intentionally keep DB paths relative (portable across sites) and resolve
    them here against deployment-specific roots.
    """
    roots: list[Path] = []

    env_roots = os.environ.get("NEXTFLOW_SEARCH_ROOTS", "")
    if env_roots:
        for part in env_roots.split(":"):
            part = part.strip()
            if part:
                roots.append(Path(part))

    # Common in-repo defaults (relative to this file's location).
    this_file = Path(__file__).resolve()
    backend_root = this_file.parents[5]
    roots.extend([
        backend_root,  # allows resolving paths already rooted at backend/
        backend_root / "biomni_workflows" / "nextflow_nfcore",
        backend_root / "biomni_workflows" / "nextflow_nfcore" / "subworkflows",
        backend_root / "biomni_workflows" / "nextflow_nfcore" / "workflows",
        backend_root / "nf-core-workflows",
        backend_root / "nf-core-modules",
        backend_root / "nf-core-modules" / "subworkflows" / "nf-core",
    ])

    # Preserve order and uniqueness.
    seen: set[str] = set()
    unique_roots: list[Path] = []
    for root in roots:
        key = str(root)
        if key not in seen:
            seen.add(key)
            unique_roots.append(root)
    return unique_roots


def _resolve_nextflow_path(raw_path: str) -> Path:
    """
    Resolve DB/logical nextflow path to an executable local .nf script.

    Supported inputs:
    - absolute path to script
    - relative path to script
    - logical IDs like:
      - nfcore/<pipeline>/main.nf
      - nfcore/subworkflows/<name>
      - biomni_nf/<domain>/<name>.nf
    """
    provided = Path(raw_path)
    if provided.is_absolute() and provided.exists():
        return provided
    if provided.exists():
        return provided.resolve()

    # Normalize logical aliases used in indexed DB rows.
    logical_candidates: list[Path] = [Path(raw_path)]

    if raw_path.startswith("nfcore/subworkflows/"):
        name = raw_path.split("nfcore/subworkflows/", 1)[1].strip("/")
        logical_candidates.extend([
            Path("subworkflows") / name / "main.nf",
            Path(name) / "main.nf",
        ])
    elif raw_path.startswith("nfcore/"):
        rest = raw_path.split("nfcore/", 1)[1].strip("/")
        logical_candidates.extend([
            Path(rest),
            Path(rest) / "main.nf",
        ])
    elif raw_path.startswith("biomni_nf/"):
        rest = raw_path.split("biomni_nf/", 1)[1].strip("/")
        logical_candidates.extend([
            Path("subworkflows") / rest,
            Path("subworkflows") / rest / "main.nf",
        ])
    elif raw_path.startswith("nextflow_nfcore/"):
        # AI sometimes returns paths prefixed with nextflow_nfcore/ — strip it and
        # search both with and without an intermediate subworkflows/ component.
        rest = raw_path.split("nextflow_nfcore/", 1)[1].strip("/")
        logical_candidates.extend([
            Path(rest),
            Path(rest) / "main.nf",
            Path("subworkflows") / rest,
            Path("subworkflows") / rest / "main.nf",
        ])

    # If DB stored path without extension, try main.nf / .nf variants.
    expanded_candidates: list[Path] = []
    for candidate in logical_candidates:
        expanded_candidates.append(candidate)
        if candidate.suffix != ".nf":
            expanded_candidates.append(candidate.with_suffix(".nf"))
            expanded_candidates.append(candidate / "main.nf")

    # Search all candidates under configured roots.
    for root in _candidate_bases():
        for candidate in expanded_candidates:
            test_path = (root / candidate).resolve()
            if test_path.exists() and test_path.is_file() and test_path.suffix == ".nf":
                return test_path

    # Domain alias fallback: drug_discovery ↔ pharmacology subworkflows are
    # often identical. If the primary search failed, retry with the sibling domain.
    _DOMAIN_ALIASES: dict[str, str] = {
        "drug_discovery": "pharmacology",
        "pharmacology": "drug_discovery",
    }
    alias_candidates: list[Path] = []
    for candidate in expanded_candidates:
        parts = candidate.parts
        for i, part in enumerate(parts):
            if part in _DOMAIN_ALIASES:
                aliased = Path(*parts[:i]) / _DOMAIN_ALIASES[part] / Path(*parts[i + 1:])
                alias_candidates.append(aliased)
                break

    for root in _candidate_bases():
        for candidate in alias_candidates:
            test_path = (root / candidate).resolve()
            if test_path.exists() and test_path.is_file() and test_path.suffix == ".nf":
                return test_path

    raise FileNotFoundError(
        f"Could not resolve Nextflow script '{raw_path}'. "
        f"Set NEXTFLOW_SEARCH_ROOTS to include your workflow roots."
    )


def _detect_nextflow_entry(nf_path: Path) -> Optional[str]:
    """
    Detect entry workflow name for scripts that define only named workflows.

    If an anonymous `workflow { ... }` exists, Nextflow can use default entry and
    no explicit `-entry` is needed.
    """
    try:
        text = nf_path.read_text(errors="replace")
    except OSError:
        return None

    # Anonymous workflow block exists; default entry is available.
    if re.search(r"(?m)^\s*workflow\s*\{", text):
        return None

    named_entries = re.findall(r"(?m)^\s*workflow\s+([A-Za-z_][A-Za-z0-9_]*)\s*\{", text)
    if not named_entries:
        return None

    preferred = [name for name in named_entries if name.lower() in ("main", "run", "workflow")]
    return preferred[0] if preferred else named_entries[0]


def _extract_documented_images() -> list[str]:
    """
    Extract workflow container images from local BioMate docs.
    This keeps runtime image selection aligned with documented, previously built images.
    """
    docs = [
        Path(__file__).resolve().parents[5] / "20260119_1538_DOCKER_CONTAINER_ROUTING_APPROACH.md",
        Path(__file__).resolve().parents[5] / "20260116_BIOMNI_DOCKER_TEST_RESULTS.md",
        Path(__file__).resolve().parents[5] / "biomni_workflows" / "galaxy" / "docker" / "20251203_DOCKER_TOOL_EXECUTION_GUIDE.md",
        Path(__file__).resolve().parents[5] / "biomni_workflows" / "20251204_NEXTFLOW_DOCKER_CONFIGURATION.md",
    ]
    image_pattern = re.compile(r"(biomate/[a-zA-Z0-9._-]+(?::[a-zA-Z0-9._-]+)?)")
    images: list[str] = []
    for doc in docs:
        if not doc.exists():
            continue
        try:
            text = doc.read_text(errors="replace")
        except OSError:
            continue
        for match in image_pattern.findall(text):
            if match not in images:
                images.append(match)
    return images


def _is_local_docker_image(image: str) -> bool:
    """Return True if Docker image exists locally."""
    try:
        result = subprocess.run(
            ["docker", "image", "inspect", image],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            text=True,
            timeout=10,
        )
        return result.returncode == 0
    except Exception:
        return False


def _host_arch() -> str:
    """Return normalized host architecture: arm64 | amd64 | unknown."""
    machine = os.uname().machine.lower()
    if machine in ("aarch64", "arm64"):
        return "arm64"
    if machine in ("x86_64", "amd64"):
        return "amd64"
    return "unknown"


def _image_declared_arch(image: str) -> str:
    """
    Best-effort arch hint from image tag naming convention.
    Returns: arm64 | amd64 | unknown
    """
    image_l = image.lower()
    if ":arm64" in image_l or "-arm64" in image_l:
        return "arm64"
    if ":x86" in image_l or ":amd64" in image_l or "-x86" in image_l or "-amd64" in image_l:
        return "amd64"
    return "unknown"


def _image_runtime_arch(image: str) -> str:
    """Inspect local image architecture via Docker metadata."""
    try:
        result = subprocess.run(
            ["docker", "image", "inspect", "--format", "{{.Architecture}}", image],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            timeout=10,
        )
        if result.returncode != 0:
            return "unknown"
        arch = result.stdout.strip().lower()
        if arch in ("arm64", "aarch64"):
            return "arm64"
        if arch in ("amd64", "x86_64"):
            return "amd64"
        return "unknown"
    except Exception:
        return "unknown"


def _is_image_arch_compatible(image: str) -> tuple[bool, str, str]:
    """
    Returns (compatible, host_arch, image_arch).
    By default cross-arch is disabled; enable with NEXTFLOW_ALLOW_CROSS_ARCH_DOCKER=true.
    """
    host_arch = _host_arch()
    image_arch = _image_runtime_arch(image)
    if image_arch == "unknown":
        image_arch = _image_declared_arch(image)

    allow_cross = os.environ.get("NEXTFLOW_ALLOW_CROSS_ARCH_DOCKER", "false").lower() in ("1", "true", "yes")
    if allow_cross:
        return True, host_arch, image_arch
    if host_arch == "unknown" or image_arch == "unknown":
        return True, host_arch, image_arch
    return host_arch == image_arch, host_arch, image_arch


def _extract_python_imports(nf_path: Path) -> list[str]:
    """
    Best-effort extraction of Python imports embedded in Nextflow scripts.
    """
    try:
        text = nf_path.read_text(errors="replace")
    except OSError:
        return []

    imports: set[str] = set()
    # Only extract TOP-LEVEL (zero-indent) imports — these are always required.
    # Indented imports (inside try/except, if blocks, functions) are conditional/optional
    # and must NOT be treated as hard requirements (e.g. DeepPurpose inside a try block).
    for mod in re.findall(r"^import\s+([a-zA-Z_][a-zA-Z0-9_\.]*)", text, flags=re.MULTILINE):
        imports.add(mod.split(".")[0])
    for mod in re.findall(r"^from\s+([a-zA-Z_][a-zA-Z0-9_\.]*)\s+import", text, flags=re.MULTILINE):
        imports.add(mod.split(".")[0])

    stdlib = {
        "os", "sys", "re", "json", "math", "time", "datetime", "pathlib", "typing",
        "collections", "itertools", "functools", "subprocess", "logging", "argparse",
        "csv", "gzip", "shutil", "glob",
    }
    return sorted([m for m in imports if m not in stdlib])


def _docker_has_python_modules(image: str, modules: list[str]) -> bool:
    """Check whether image has all required Python modules."""
    if not modules:
        return True
    script = "; ".join([f"import {m}" for m in modules])
    cmd = ["docker", "run", "--rm", "--entrypoint", "python", image, "-c", script]
    try:
        result = subprocess.run(
            cmd,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            text=True,
            timeout=30,
        )
        return result.returncode == 0
    except Exception:
        return False


def _host_has_python_modules(modules: list[str]) -> tuple[bool, list[str]]:
    """Return (all_present, missing_modules) for host Python runtime."""
    missing: list[str] = []
    for mod in modules:
        try:
            __import__(mod)
        except Exception:
            missing.append(mod)
    return len(missing) == 0, missing


def _auto_install_host_modules(modules: list[str]) -> list[str]:
    """Attempt pip install for missing modules. Returns modules still missing."""
    if not modules:
        return []
    still_missing: list[str] = []
    for mod in modules:
        pkg = mod
        try:
            result = subprocess.run(
                ["python", "-m", "pip", "install", pkg],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                text=True,
                timeout=120,
            )
            if result.returncode != 0:
                still_missing.append(mod)
                continue
            try:
                __import__(mod)
            except Exception:
                still_missing.append(mod)
        except Exception:
            still_missing.append(mod)
    return still_missing


def _check_pipeline_constraints(
    nf_path: Path, params: dict, compute: dict
) -> Optional[Dict[str, Any]]:
    """
    Pre-flight check: detect pipelines that cannot run on this host and explain why.
    Returns None if OK to proceed, or a dict with blocking details.

    Currently detects:
      - CryoSPARC pipelines running with mock_mode=false on ARM64 without AWS Batch
    """
    executor = compute.get("executor", "local")
    if executor == "awsbatch":
        # Mock mode is never permitted on real cloud hardware — simulations waste
        # EC2 compute time and billing without producing real scientific data.
        if params.get("mock_mode", False):
            log.warning(
                "[Nextflow] mock_mode=true override: forcing mock_mode=false for "
                "awsbatch executor — real container images will run on Batch."
            )
            params["mock_mode"] = False
        return None  # skip local constraint checks for cloud executor

    if executor != "local":
        # Other non-local executors (slurm, etc.); skip local constraint checks.
        return None

    host_arch = _host_arch()
    if host_arch == "amd64":
        return None  # x86_64 host can run anything

    try:
        text = nf_path.read_text(errors="replace")
    except OSError:
        return None

    # Detect CryoSPARC pipelines
    is_cryosparc = (
        "use_cryosparc" in text
        or "cryosparc" in nf_path.as_posix().lower()
    )
    if not is_cryosparc:
        return None

    # Determine effective mock_mode
    # Priority: explicit param > pipeline default
    mock_from_params = params.get("mock_mode", None)
    if mock_from_params is not None:
        will_mock = bool(mock_from_params)
    else:
        # Check pipeline default: `params.mock_mode = true|false`
        m = re.search(r"params\.mock_mode\s*=\s*(true|false)", text, re.IGNORECASE)
        will_mock = (m is None) or (m.group(1).lower() == "true")

    if will_mock:
        return None  # mock_mode=true runs pure Python; ARM is fine

    return {
        "blocked": True,
        "reason": (
            f"CryoSPARC requires x86_64 hardware (this host is {host_arch}). "
            "CryoSPARC binaries and Docker images are not available for ARM."
        ),
        "suggestion": (
            "Option A: pass mock_mode=true to run the full pipeline with synthetic data.\n"
            "Option B: configure AWS Batch in Settings → Compute to run on x86_64 cloud."
        ),
        "mock_mode_available": True,
    }


_INPUT_SIZE_LIMIT_BYTES = 10 * 1024 ** 3  # 10 GB


def _is_path_param(key: str, value: Any) -> bool:
    """Heuristic: is this param likely a local file or directory path?"""
    if not isinstance(value, str):
        return False
    path_keywords = (
        "path", "input", "reads", "file", "dir", "movies", "sample",
        "samplesheet", "fasta", "fastq", "bam", "csv", "tsv", "mrc",
        "tif", "tiff", "mdoc", "ref", "genome",
    )
    # Known non-path params that happen to contain path-like substrings
    _NON_PATH_KEYS = frozenset({
        "publish_dir_mode", "save_merged_fastq", "publish_dir",
        "outdir_mode", "output_mode", "copy_mode", "dir_mode",
        "sample_id", "sample_name", "genome_build", "genome_name",
    })
    key_l = key.lower()
    if key_l in _NON_PATH_KEYS:
        return False
    val = value.strip()
    # Skip empty strings, booleans, numbers, mode strings, URLs already handled separately
    if not val or val.lower() in ("true", "false", "null", "none", "copy", "symlink", "move", "link"):
        return False
    if val.startswith("s3://") or val.startswith("http"):
        return False
    # Inline data (CSV, TSV, multi-line text) always contains newlines — never a path.
    if "\n" in val or "\r" in val:
        return False
    # Exclude chemistry/biology data strings that can't be filesystem paths.
    # SMILES, InChI, FASTA sequences, and compound IDs contain characters
    # that are illegal or highly unusual in file/directory names.
    _NON_PATH_CHARS = frozenset("()=#+@[]\\|~`'\"")
    if any(c in val for c in _NON_PATH_CHARS):
        return False
    # Long strings that don't look like paths (no slashes, no extension) are data.
    if len(val) > 100 and "/" not in val and "." not in val:
        return False
    # Short genome/reference identifiers (e.g. hg38, GRCh38, mm10, hg19) are NOT file paths.
    # They map to iGenomes S3 references; real paths would contain '/' or a file extension.
    _GENOME_ID_KEYS = frozenset({"genome", "reference_genome", "ref_genome", "genome_id", "assembly"})
    if key_l in _GENOME_ID_KEYS and "/" not in val and "." not in val:
        return False
    # Value must either start with '/' (absolute path) or contain a '/' (relative path),
    # OR have a recognized file extension — otherwise it's likely an identifier, not a path.
    _PATH_EXTENSIONS = frozenset({
        ".fasta", ".fa", ".fastq", ".fq", ".bam", ".sam", ".cram",
        ".vcf", ".bcf", ".bed", ".gtf", ".gff", ".gff3", ".csv",
        ".tsv", ".txt", ".mrc", ".tif", ".tiff", ".mdoc", ".json",
        ".gz", ".tar", ".zip",
    })
    looks_like_path = val.startswith("/") or "/" in val or any(val.lower().endswith(ext) for ext in _PATH_EXTENSIONS)
    # Key name must suggest a path AND value must look like a path
    return (any(kw in key_l for kw in path_keywords) and looks_like_path) or val.startswith("/")


def _local_path_size(p: Path) -> int:
    """Return total size in bytes of a file or directory tree."""
    if p.is_file():
        return p.stat().st_size
    total = 0
    for child in p.rglob("*"):
        if child.is_file():
            try:
                total += child.stat().st_size
            except OSError:
                pass
    return total


def _validate_input_paths(params: dict) -> None:
    """
    Validate all input path parameters before launching Nextflow.

    Checks:
    1. Every local path param exists (file or directory).
    2. Total local input size does not exceed 10 GB.
    3. Every S3 input path is accessible (bucket reachable + object exists).

    Raises HTTPException(422) on any violation.
    """
    missing: list[str] = []
    total_bytes = 0
    large_items: list[str] = []

    for key, value in params.items():
        if key == "outdir":
            continue  # output, not input — validated elsewhere
        if isinstance(value, str) and value.startswith("s3://"):
            # Pre-flight: validate S3 input is accessible before job starts.
            _validate_s3_url(value, check_object=True)
            continue
        # Skip public-database accessions — they will be resolved by a pre-step
        # download handler (_accession_chain_thread) before the main workflow runs.
        if _is_public_accession(str(value)):
            continue
        if not _is_path_param(key, value):
            continue

        p = Path(value)
        if not p.exists():
            missing.append(f"--{key} '{value}': path does not exist")
            continue

        size = _local_path_size(p)
        total_bytes += size
        if size > _INPUT_SIZE_LIMIT_BYTES:
            gb = size / 1024 ** 3
            large_items.append(f"--{key} '{value}' ({gb:.1f} GB)")

    if missing:
        raise HTTPException(
            status_code=422,
            detail={
                "error": "Input path(s) not found",
                "missing": missing,
                "suggestion": "Check that all --input / --reads / --movies_path values exist on disk.",
            },
        )

    if total_bytes > _INPUT_SIZE_LIMIT_BYTES:
        total_gb = total_bytes / 1024 ** 3
        raise HTTPException(
            status_code=422,
            detail={
                "error": "Input data exceeds the 10 GB per-run limit",
                "total_gb": round(total_gb, 2),
                "limit_gb": 10,
                "large_inputs": large_items or ["(combined total)"],
                "suggestion": (
                    "Split your data into batches of ≤ 10 GB, or stage large inputs "
                    "directly to S3 and pass an s3:// path instead."
                ),
            },
        )


def _validate_s3_url(s3_url: str, check_object: bool = False) -> None:
    """
    Validate an s3:// URL is accessible before launching Nextflow.

    Args:
        s3_url:       Must start with 's3://'.
        check_object: If True and the URL has a key component, verify the
                      object exists with head_object (used for input files).
                      Skipped for bucket-only or directory-prefix URLs.

    Raises HTTPException(422) with a human-readable reason if not.
    """
    try:
        import boto3
        from botocore.exceptions import ClientError, NoCredentialsError
    except ImportError:
        log.warning("[Nextflow] boto3 not installed — skipping S3 validation")
        return

    parts = s3_url[len("s3://"):].split("/", 1)
    bucket = parts[0]
    key = parts[1] if len(parts) > 1 else ""
    if not bucket:
        raise HTTPException(
            status_code=422,
            detail={"error": f"Invalid S3 URL '{s3_url}': no bucket name"},
        )

    s3 = boto3.client("s3", region_name=os.environ.get("AWS_DEFAULT_REGION", "us-west-2"))
    try:
        s3.head_bucket(Bucket=bucket)
    except NoCredentialsError:
        raise HTTPException(
            status_code=422,
            detail={
                "error": "AWS credentials not configured",
                "bucket": bucket,
                "suggestion": (
                    "Run 'aws configure' or set the AWS_ACCESS_KEY_ID / "
                    "AWS_SECRET_ACCESS_KEY environment variables."
                ),
            },
        )
    except ClientError as exc:
        code = exc.response.get("Error", {}).get("Code", "")
        if code in ("403", "AccessDenied"):
            raise HTTPException(
                status_code=422,
                detail={
                    "error": f"Access denied to S3 bucket '{bucket}'",
                    "bucket": bucket,
                    "suggestion": (
                        "Ensure the IAM role/user has s3:GetObject, "
                        "s3:PutObject, and s3:ListBucket on this bucket."
                    ),
                },
            )
        if code in ("404", "NoSuchBucket"):
            raise HTTPException(
                status_code=422,
                detail={
                    "error": f"S3 bucket '{bucket}' does not exist",
                    "bucket": bucket,
                    "suggestion": f"Create it with: aws s3 mb s3://{bucket} --region <region>",
                },
            )
        raise HTTPException(
            status_code=422,
            detail={
                "error": f"Cannot access S3 bucket '{bucket}': {exc}",
                "bucket": bucket,
            },
        )

    # Optional: verify the specific object exists (for input file paths).
    # Skip for directory-style prefixes (key ends with '/') or bucket-only URLs.
    if check_object and key and not key.endswith("/"):
        try:
            s3.head_object(Bucket=bucket, Key=key)
        except ClientError as exc:
            code = exc.response.get("Error", {}).get("Code", "")
            if code in ("404", "NoSuchKey"):
                raise HTTPException(
                    status_code=422,
                    detail={
                        "error": f"S3 input object not found: s3://{bucket}/{key}",
                        "bucket": bucket,
                        "key": key,
                        "suggestion": (
                            "Upload your input file first, or check the S3 path for typos. "
                            f"List available files with: aws s3 ls s3://{bucket}/{'/'.join(key.split('/')[:-1])}/"
                        ),
                    },
                )
            # Access denied on object but bucket was reachable — different IAM policy.
            if code in ("403", "AccessDenied"):
                raise HTTPException(
                    status_code=422,
                    detail={
                        "error": f"Access denied to S3 object s3://{bucket}/{key}",
                        "suggestion": "Ensure the IAM role has s3:GetObject on this key.",
                    },
                )


def _generate_executor_config(
    compute: dict, config_dir: Path, *, user_id: str = "unknown", run_id: str = "unknown",
    credentials: Optional[Dict[str, Any]] = None,
) -> Optional[Path]:
    """
    Generate a temporary nextflow.config for non-local executors.

    Nextflow reads executor from nextflow.config, NOT from environment variables.
    NXF_EXECUTOR is not a real Nextflow env var — this function replaces the
    previous (broken) NXF_EXECUTOR approach.

    Returns path to generated config file, or None for local execution.
    """
    executor = compute.get("executor", "local")
    if executor not in ("awsbatch", "slurm"):
        return None

    config_path = config_dir / "biomate_executor_override.config"

    if executor == "awsbatch":
        queue = (
            compute.get("aws_batch_queue")
            or os.environ.get("AWS_BATCH_QUEUE", "biomate-nextflow-queue")
        )
        region = (
            compute.get("aws_region")
            or os.environ.get("AWS_DEFAULT_REGION", "us-west-2")
        )
        s3_bucket = (
            compute.get("s3_bucket")
            or os.environ.get("NEXTFLOW_S3_BUCKET", "biomate-nextflow-work")
        )
        # Container for tasks. MUST have both Python 3 and the AWS CLI.
        # Nextflow injects an nxf_s3_upload() shell function into every task's
        # .command.run that calls `aws s3 cp` — if the container lacks the aws
        # binary, the task exits with code 127 immediately.
        # civitaspo/python-awscli:latest = Python 3 + AWS CLI v2 (verified working).
        container = compute.get("container") or os.environ.get(
            "NEXTFLOW_BATCH_CONTAINER", "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate-nextflow-base:latest"
        )

        lines = [
            # Override params.container so workflow configs that do
            # `process { container = params.container }` use the ECR image.
            # Override params.outdir so publishDir uses S3 — without this,
            # workflows default to ./results (container-local disk) and
            # s3_output_files stays empty after the run.
            "params {",
            f"    container = '{container}'",
            f"    outdir = 's3://{s3_bucket}/nextflow/outputs/{user_id}/{run_id}'",
            "}",
            "process {",
            "    executor = 'awsbatch'",
        ]
        if queue:
            lines.append(f"    queue = '{queue}'")
        # Build environment block — billing context + optional credentials
        creds = credentials or {}
        env_lines = [
            f"        BIOMATE_USER_ID: '{user_id}',",
            f"        BIOMATE_RUN_ID: '{run_id}',",
        ]
        # beforeScript parts — only credential injection; no CLI symlink needed
        # since AWS CLI is baked into all task containers via FROM biomate-nextflow-base.
        before_script_parts: list[str] = []

        # Docker Hub auth (AlphaFold3 or any docker_auth tool)
        af3_cred = creds.get("alphafold3") or {}
        if af3_cred.get("username") and af3_cred.get("token"):
            import base64 as _b64
            auth_b64 = _b64.b64encode(
                f"{af3_cred['username']}:{af3_cred['token']}".encode()
            ).decode()
            env_lines.append(f"        DOCKER_HUB_AUTH_B64: '{auth_b64}',")
            before_script_parts.append(
                r"mkdir -p $HOME/.docker && "
                r'printf \'{"auths":{"https://index.docker.io/v1/":{"auth":"%s"}}}\' '
                r'"$DOCKER_HUB_AUTH_B64" > $HOME/.docker/config.json'
            )
            log.info("[Nextflow] AlphaFold3 Docker auth will be injected into Batch tasks")

        # CryoSPARC license key
        cs_cred = creds.get("cryosparc") or {}
        if cs_cred.get("license_key"):
            env_lines.append(f"        CRYOSPARC_LICENSE_ID: '{cs_cred['license_key']}',")
            log.info("[Nextflow] CryoSPARC license key will be injected into Batch tasks")

        before_script_str = " && ".join(before_script_parts) if before_script_parts else ""

        lines += [
            f"    container = '{container}'",
            # Inject billing context + credentials into every Batch task container.
            "    environment = [",
        ] + env_lines + [
            "    ]",
        ]
        if before_script_str:
            lines.append(f"    beforeScript = '{before_script_str}'")
        lines.append("}")
        lines += [
            f"aws {{",
            f"    region = '{region}'",
            "    client {",
            "        maxConnections = 20",
            "        uploadChunkSize = 104857600",   # 100 MB chunks
            "    }",
            "    batch {",
            # AMI ami-08fe495be97a3dbf4 (biomate-nextflow-al2023-awscli-20260409):
            #   Base: ami-0b495ea217b3a1543 (ECS-optimized AL2023, kernel 6.1, 2026-04-03)
            #   Baked in: AWS CLI v2 at /usr/local/bin/aws + symlink /opt/aws-cli/bin/aws
            # cliPath = /opt/aws-cli/bin/aws:
            #   Nextflow mounts grandparent /opt/aws-cli (host→container) — safe, does NOT
            #   shadow /usr/local or /usr/bin. Works for BOTH ECR (BioMate) containers AND
            #   public third-party containers (gromacs, rocker, etc.) without aws of their own.
            # DO NOT change to /usr/local/bin/aws — that shadows /usr/local/lib/python3
            #   site-packages inside containers, causing exit 127 on all python tasks.
            "        cliPath = '/opt/aws-cli/bin/aws'",
            "    }",
            "}",
            "docker.enabled = true",
            f"workDir = 's3://{s3_bucket}/nextflow/work/{user_id}/{run_id}'",
        ]

        if not queue:
            log.warning(
                "[Nextflow] AWS Batch executor: no queue name. "
                "Set AWS_BATCH_QUEUE env var or compute_config.aws_batch_queue."
            )

    elif executor == "slurm":
        partition = compute.get("slurm_partition") or "compute"
        qos = compute.get("slurm_qos") or ""
        cluster_opts = f"--partition={partition}"
        if qos:
            cluster_opts += f" --qos={qos}"

        lines = [
            "process {",
            "    executor = 'slurm'",
            f"    clusterOptions = '{cluster_opts}'",
            "}",
        ]

    config_path.write_text("\n".join(lines) + "\n")
    log.info(f"[Nextflow] Generated executor config: {config_path}")
    return config_path


def _choose_container_strategy(nf_path: Path, raw_nextflow_path: str) -> Dict[str, Any]:
    """
    Choose execution strategy:
      1) Prefer documented local Docker images that satisfy module requirements.
      2) Fallback to host mode with automatic module installation.
    """
    required_modules = _extract_python_imports(nf_path)
    documented_images = _extract_documented_images()

    # Domain-aware preference order
    image_preferences: list[str] = []
    if raw_nextflow_path.startswith("biomni_nf/"):
        image_preferences.extend(["biomate/biomni-tools:latest", "biomate/biotools:arm64"])
    elif raw_nextflow_path.startswith("nfcore/"):
        image_preferences.extend(["biomate/rnaseq:x86", "biomate/biotools:arm64"])

    # Optional explicit priority list (comma-separated image refs).
    custom_priority = os.environ.get("NEXTFLOW_RUNTIME_IMAGE_PRIORITY", "").strip()
    if custom_priority:
        for image in [p.strip() for p in custom_priority.split(",") if p.strip()]:
            if image not in image_preferences:
                image_preferences.append(image)

    for image in documented_images:
        if image not in image_preferences:
            image_preferences.append(image)

    local_candidates: list[str] = []
    host_arch = _host_arch()
    for img in image_preferences:
        if not _is_local_docker_image(img):
            continue
        compatible, _, image_arch = _is_image_arch_compatible(img)
        if not compatible:
            log.info(
                f"[Nextflow runtime] Skipping cross-arch image {img} "
                f"(host={host_arch}, image={image_arch}). "
                "Set NEXTFLOW_ALLOW_CROSS_ARCH_DOCKER=true to allow emulation."
            )
            continue
        local_candidates.append(img)

    for image in local_candidates:
        if _docker_has_python_modules(image, required_modules):
            docker_opts: list[str] = ['-u $(id -u):$(id -g)', '--entrypoint ""']
            biomni_mount = Path(__file__).resolve().parents[6] / "Biomni"
            if biomni_mount.exists():
                docker_opts.append(f"-v {biomni_mount}:/app/Biomni:ro")
            return {
                "mode": "docker",
                "image": image,
                "docker_opts": " ".join(docker_opts),
                "required_modules": required_modules,
                "missing_modules": [],
                "host_arch": host_arch,
                "image_arch": _image_runtime_arch(image),
                "cross_arch_allowed": os.environ.get("NEXTFLOW_ALLOW_CROSS_ARCH_DOCKER", "false"),
            }

    # Fallback: host mode with auto install
    _, missing = _host_has_python_modules(required_modules)
    remaining = _auto_install_host_modules(missing)
    return {
        "mode": "host",
        "image": None,
        "docker_opts": "",
        "required_modules": required_modules,
        "missing_modules": remaining,
        "host_arch": host_arch,
        "image_arch": None,
        "cross_arch_allowed": os.environ.get("NEXTFLOW_ALLOW_CROSS_ARCH_DOCKER", "false"),
    }


_TRACE_SKIP_FILES = frozenset({
    ".command.sh", ".command.run", ".command.log", ".command.out",
    ".command.err", ".command.env", ".command.trace", ".exitcode",
    ".started", ".nf-params.json",
})


def _scan_task_work_dir(work_dir: str) -> List[str]:
    """List output files in a Nextflow task work directory, skipping internal files."""
    p = Path(work_dir)
    if not p.is_dir():
        return []
    files: List[str] = []
    try:
        for entry in p.iterdir():
            if not entry.is_file():
                continue
            if entry.name in _TRACE_SKIP_FILES:
                continue
            files.append(entry.name)
    except PermissionError:
        pass
    return sorted(files)


def _parse_trace_progress(trace_path: Path) -> dict:
    """Parse Nextflow trace file and return task-level progress counts.

    Also reads the optional ``workdir`` column (column 14) to surface per-task
    output files — enabling the UI to show intermediate results per step.
    """
    if not trace_path.exists():
        return {}
    try:
        lines = trace_path.read_text(errors="replace").splitlines()
    except OSError:
        return {}

    if not lines:
        return {}

    # Parse header to locate columns by name (trace format can vary)
    header = [h.strip() for h in lines[0].split("\t")]
    col_idx = {name: i for i, name in enumerate(header)}
    idx_task_id  = col_idx.get("task_id",  0)
    idx_name     = col_idx.get("name",     3)
    idx_status   = col_idx.get("status",   4)
    idx_workdir  = col_idx.get("workdir",  -1)  # not present in all Nextflow versions

    completed = failed = running = 0
    processes = []
    seen_tasks: Dict[str, str] = {}  # task_id → latest status

    for line in lines[1:]:  # skip header row
        if not line.strip():
            continue
        parts = line.split("\t")
        if len(parts) < 5:
            continue
        task_id      = parts[idx_task_id].strip() if idx_task_id < len(parts) else ""
        process_name = parts[idx_name].strip()    if idx_name    < len(parts) else ""
        status       = parts[idx_status].strip()  if idx_status  < len(parts) else ""
        work_dir     = (
            parts[idx_workdir].strip()
            if idx_workdir >= 0 and idx_workdir < len(parts)
            else ""
        )

        seen_tasks[task_id] = status

        # Collect files produced by this task (only for completed local tasks)
        task_files: List[str] = []
        if work_dir and status == "COMPLETED":
            task_files = _scan_task_work_dir(work_dir)

        processes.append({
            "id": task_id,
            "name": process_name,
            "status": status,
            "work_dir": work_dir,
            "task_files": task_files,
        })

    for s in seen_tasks.values():
        if s == "COMPLETED":
            completed += 1
        elif s == "FAILED":
            failed += 1
        elif s in ("RUNNING", "SUBMITTED"):
            running += 1

    total = len(seen_tasks)
    return {
        "completedTasks": completed,
        "failedTasks": failed,
        "runningTasks": running,
        "totalTasks": total,
        "progressPercent": int(completed * 100 / max(total, 1)) if total > 0 else 0,
        "processes": processes,
    }


def _start_qc_monitor(
    invocation_id: str,
    work_dir: Path,
    qc_overrides: Dict[str, Any],
    workflow_domain: str,
    qc_profile: Optional[str] = None,
    trace_path: Optional[Path] = None,
    is_batch: bool = False,
) -> None:
    """
    Spawn a background thread that polls the Nextflow trace file and fires
    QC gate / warning events via SSE inject for the direct-executor path.

    The thread exits gracefully once the process finishes (no more trace updates
    for 120 s local / 1800 s Batch with a COMPLETED/FAILED final status)
    or after a 12-hour hard cap.
    """
    try:
        from galaxy.jobs.qc_trace_monitor import NextflowQCGateHandler
    except ImportError:
        log.warning("[QC Monitor] QC gate handler not available — skipping QC monitoring")
        return

    import os as _os
    import json as _json
    import urllib.request as _urllib

    frontend_url = _os.environ.get("FRONTEND_URL", "http://localhost:5000")
    inject_url = f"{frontend_url}/internal/sse-inject"

    def _sse_callback(event_type: str, data: dict) -> None:
        payload = _json.dumps({
            "invocation_id": invocation_id,
            "event_type": event_type,
            "data": data,
        }).encode("utf-8")
        try:
            req = _urllib.Request(
                inject_url,
                data=payload,
                headers={"Content-Type": "application/json"},
            )
            with _urllib.urlopen(req, timeout=5):
                pass
        except Exception as exc:
            log.debug(f"[QC Monitor] SSE inject failed for {event_type}: {exc}")

    handler = NextflowQCGateHandler(
        invocation_id=invocation_id,
        work_dir=work_dir,
        sse_callback=_sse_callback,
        app=None,
        workflow_domain=workflow_domain,
        qc_overrides=qc_overrides,
        qc_profile=qc_profile,
    )

    # Register handler so export endpoint can access live QC state.
    with _qc_handlers_lock:
        _qc_handlers[invocation_id] = handler

    def _poll() -> None:
        import time as _time
        trace_file = trace_path if trace_path is not None else (work_dir / "workflow-trace.txt")
        seen_tasks: set = set()
        idle_seconds = 0
        max_idle = 1800 if is_batch else 120  # 30 min for Batch cold-start; 2 min local
        hard_cap = 12 * 3600  # 12-hour hard stop

        deadline = _time.monotonic() + hard_cap

        while _time.monotonic() < deadline:
            _time.sleep(5)
            if not trace_file.exists():
                idle_seconds += 5
                if idle_seconds >= max_idle:
                    break
                continue

            try:
                lines = trace_file.read_text(errors="replace").splitlines()
            except OSError:
                continue

            new_task_found = False
            for line in lines[1:]:  # skip header
                if not line.strip():
                    continue
                parts = line.split("\t")
                if len(parts) < 5:
                    continue
                task_id = parts[0].strip()
                process_hash = parts[1].strip()
                process_name = parts[3].strip()
                task_status = parts[4].strip()

                task_key = f"{task_id}:{task_status}"
                if task_key not in seen_tasks and task_status in ("COMPLETED", "FAILED"):
                    seen_tasks.add(task_key)
                    new_task_found = True
                    try:
                        handler.handle_process_completion(
                            task_id=task_id,
                            process_name=process_name,
                            process_hash=process_hash,
                            status=task_status,
                        )
                    except Exception as exc:
                        log.warning(f"[QC Monitor] Error handling {process_name}: {exc}")

            if new_task_found:
                idle_seconds = 0
            else:
                idle_seconds += 5
                if idle_seconds >= max_idle:
                    break

        log.debug(f"[QC Monitor] Monitoring thread for {invocation_id} exiting")
        # Keep handler in registry even after thread exits — it holds the
        # complete in-memory event log that the export endpoint reads.

    t = threading.Thread(target=_poll, daemon=True, name=f"qc-monitor-{invocation_id[:8]}")
    t.start()
    log.info(
        f"[QC Monitor] Started QC monitoring for {invocation_id} "
        f"(domain={workflow_domain}, profile={qc_profile!r}, overrides={list(qc_overrides.keys())})"
    )


def _list_s3_output_files(s3_uri: str) -> list:
    """
    List output files in an S3 prefix after a workflow completes.
    Returns list of dicts: {key, name, size, extension}.
    Skips Nextflow internal files (work/, .nextflow/, trace).
    """
    try:
        import boto3
    except ImportError:
        return []
    try:
        parts = s3_uri[len("s3://"):].split("/", 1)
        bucket = parts[0]
        prefix = (parts[1] if len(parts) > 1 else "").rstrip("/") + "/"
        s3 = boto3.client("s3", region_name=os.environ.get("AWS_DEFAULT_REGION", "us-west-2"))
        paginator = s3.get_paginator("list_objects_v2")
        skip_prefixes = ("/work/", "/.nextflow/", "/trace.", "/timeline.", "/dag.", "/report.")
        results = []
        for page in paginator.paginate(Bucket=bucket, Prefix=prefix):
            for obj in page.get("Contents", []):
                key = obj["Key"]
                # Skip Nextflow internals
                if any(p in key for p in skip_prefixes):
                    continue
                name = key.split("/")[-1]
                if not name:
                    continue
                ext = name.rsplit(".", 1)[-1].lower() if "." in name else ""
                results.append({
                    "s3_uri": f"s3://{bucket}/{key}",
                    "name": name,
                    "size": obj["Size"],
                    "extension": ext,
                })
        log.info(f"[Nextflow] Listed {len(results)} S3 output files from {s3_uri}")
        return results
    except Exception as exc:
        log.warning(f"[Nextflow] S3 output listing failed for {s3_uri}: {exc}")
        return []


def _tag_s3_outputs(run_meta: Dict[str, Any]) -> None:
    """
    Tag all S3 output objects for a completed run with user_id and run_id.

    This allows the biomate-s3-billing Lambda to attribute storage costs to the
    correct user even when Nextflow writes files without object tags. Called
    once after the run finishes — best-effort, never blocks the run itself.
    """
    user_id = run_meta.get("user_id") or ""
    run_id = run_meta.get("run_id") or ""
    outdir = run_meta.get("outdir") or ""

    if not (user_id and run_id and str(outdir).startswith("s3://")):
        return

    try:
        import boto3
        parts = outdir.replace("s3://", "").split("/", 1)
        bucket = parts[0]
        prefix = parts[1] if len(parts) > 1 else ""

        s3 = boto3.client("s3")
        paginator = s3.get_paginator("list_objects_v2")
        tag_set = [
            {"Key": "user_id", "Value": user_id},
            {"Key": "workflow_id", "Value": run_id},
            {"Key": "tagged_by", "Value": "biomate-postrun"},
        ]

        count = 0
        for page in paginator.paginate(Bucket=bucket, Prefix=prefix):
            for obj in page.get("Contents", []):
                key = obj["Key"]
                try:
                    s3.put_object_tagging(
                        Bucket=bucket,
                        Key=key,
                        Tagging={"TagSet": tag_set},
                    )
                    count += 1
                except Exception as tag_err:
                    log.warning("[S3 tag] Failed to tag s3://%s/%s: %s", bucket, key, tag_err)

        log.info("[S3 tag] Tagged %d output objects for run=%s user=%s", count, run_id, user_id)
    except Exception as exc:
        log.warning("[S3 tag] Post-run tagging failed for run=%s: %s", run_id, exc)


def _stream_logs(process: subprocess.Popen, run_id: str, log_path: Path):
    """Stream stdout+stderr to a log file and update run status when done."""
    try:
        with open(log_path, "w") as fh:
            for line in process.stdout:            # type: ignore[union-attr]
                fh.write(line)
                fh.flush()
        process.wait()
        returncode = process.returncode
        final_status = "succeeded" if returncode == 0 else "failed"
        run_meta: Dict[str, Any] = {}
        _completed_at_now = time.time()
        with _runs_lock:
            if run_id in _runs:
                _runs[run_id]["status"] = final_status
                _runs[run_id]["returncode"] = returncode
                _runs[run_id]["completed_at"] = _completed_at_now

        # Update timing.json on disk so other workers can read timing via disk fallback.
        try:
            import json as _json
            _timing_path = Path(os.environ.get("NEXTFLOW_WORK_DIR", "/tmp/nextflow_runs")) / run_id / "timing.json"
            _existing = {}
            if _timing_path.exists():
                _existing = _json.loads(_timing_path.read_text())
            _existing["completed_at"] = _completed_at_now
            _existing["status"] = final_status
            _timing_path.write_text(_json.dumps(_existing))
        except Exception as _te:
            log.debug("[timing] Could not update timing.json for %s: %s", run_id, _te)

        with _runs_lock:
            if run_id in _runs:
                # On success, enumerate S3 output files so the frontend can list/download them.
                if returncode == 0:
                    outdir = _runs[run_id].get("outdir", "")
                    if str(outdir).startswith("s3://"):
                        _runs[run_id]["s3_output_files"] = _list_s3_output_files(outdir)
                run_meta = dict(_runs[run_id])
        log.info(f"[Nextflow run {run_id}] finished with exit code {returncode}")

        # Tag all S3 output objects with user_id so the billing Lambda can attribute them.
        # This is done as a best-effort background step after run completion.
        _tag_s3_outputs(run_meta)

        # C2a — Write durable per-run JSON study log (required by pilot study plan)
        try:
            from galaxy.ai.study_run_logger import StudyRunLogger
            StudyRunLogger.record(run_meta)
        except Exception as _log_err:
            log.warning("[StudyRunLogger] log write failed for run %s: %s", run_id, _log_err)

        # C2b — Record workflow outcome in LTM (fire-and-forget; never blocks main flow)
        try:
            from galaxy.ai.memory.agentic_memory import get_memory_service
            duration_s = None
            started_at = run_meta.get("started_at")
            if started_at:
                duration_s = int(time.time() - started_at)
            nf_path = run_meta.get("nextflow_path", "")
            workflow_name = nf_path.rsplit("/", 1)[-1] if nf_path else run_id
            memory_svc = get_memory_service()
            memory_svc.record_workflow_outcome(
                user_id=run_meta.get("user_id") or "anonymous",
                session_id=run_id,
                query=workflow_name,
                workflow_id=nf_path or run_id,
                outcome=final_status,
                run_duration_s=duration_s,
                autofix_count=0,
                error_type=None if returncode == 0 else f"exit_code_{returncode}",
            )
            log.info("[ltm] Recorded workflow outcome: run=%s status=%s", run_id, final_status)
        except Exception as _ltm_err:
            log.warning("[ltm] record_outcome failed for run %s: %s", run_id, _ltm_err)

    except Exception as exc:
        log.error(f"[Nextflow run {run_id}] log streaming error: {exc}")
        with _runs_lock:
            if run_id in _runs:
                _runs[run_id]["status"] = "failed"


# ---------------------------------------------------------------------------
# Public-database accession download handlers
# ---------------------------------------------------------------------------

def _run_fetchngs_prefetch(
    accessions: list[str],
    work_base: Path,
    run_id: str,
    nf_bin: str,
    profile: str,
    env: dict,
    executor_config_path: Optional[Path],
) -> Optional[str]:
    """
    Run nf-core/fetchngs synchronously to download sequencing data for *accessions*.

    Returns the path to the generated samplesheet.csv, or None on failure.
    The samplesheet can be passed as --input to the main workflow.
    """
    try:
        fetchngs_path = _resolve_nextflow_path("nfcore/fetchngs/main.nf")
    except FileNotFoundError:
        log.warning("[fetchngs] nf-core/fetchngs not found in workflow search roots — skipping prefetch")
        return None

    fetch_run_dir = work_base / f"{run_id}_fetchngs"
    fetch_run_dir.mkdir(parents=True, exist_ok=True)

    # Write accession list file
    ids_file = fetch_run_dir / "ids.csv"
    ids_file.write_text("\n".join(accessions) + "\n")

    fetch_outdir = fetch_run_dir / "output"
    fetch_outdir.mkdir(exist_ok=True)
    fetch_work = fetch_run_dir / "work"
    fetch_work.mkdir(exist_ok=True)

    cmd = [
        nf_bin, "run", str(fetchngs_path),
        "-profile", profile,
        "-w", str(fetch_work),
        "--input", str(ids_file),
        "--outdir", str(fetch_outdir),
        "--nf_core_pipeline", "rnaseq",  # generates samplesheet compatible with nf-core pipelines
    ]
    if executor_config_path:
        cmd += ["-c", str(executor_config_path)]

    log_path = fetch_run_dir / "fetchngs.log"
    log.info(f"[fetchngs run_id={run_id}] Starting prefetch: {' '.join(accessions)}")
    log.info(f"[fetchngs run_id={run_id}] cmd: {' '.join(cmd)}")

    try:
        with open(log_path, "w") as lf:
            proc = subprocess.Popen(
                cmd,
                stdout=lf,
                stderr=subprocess.STDOUT,
                text=True,
                cwd=str(fetchngs_path.parent),
                env=env,
            )
            proc.wait(timeout=3600)  # 1 hour max for prefetch

        if proc.returncode != 0:
            log.error(f"[fetchngs run_id={run_id}] Failed (rc={proc.returncode}) — check {log_path}")
            return None

        # nf-core/fetchngs writes samplesheet to outdir/samplesheet/samplesheet.csv
        for candidate in [
            fetch_outdir / "samplesheet" / "samplesheet.csv",
            fetch_outdir / "fastq" / "samplesheet.csv",
            fetch_outdir / "samplesheet.csv",
        ]:
            if candidate.exists():
                log.info(f"[fetchngs run_id={run_id}] Samplesheet ready: {candidate}")
                return str(candidate)

        log.warning(f"[fetchngs run_id={run_id}] No samplesheet found in {fetch_outdir}")
        return None

    except subprocess.TimeoutExpired:
        proc.kill()
        log.error(f"[fetchngs run_id={run_id}] Prefetch timed out after 1 hour")
        return None
    except Exception as exc:
        log.error(f"[fetchngs run_id={run_id}] Prefetch error: {exc}")
        return None


def _download_pdb_structure(accession: str, out_dir: Path) -> Optional[str]:
    """
    Download a PDB/EMDB structure file via the RCSB / EMDB HTTP API.
    Returns local file path or None on failure.
    """
    import urllib.request
    import urllib.error

    out_dir.mkdir(parents=True, exist_ok=True)
    acc_upper = accession.upper()

    if acc_upper.startswith("EMD-"):
        emdb_id = acc_upper[4:]  # strip "EMD-"
        url = f"https://ftp.ebi.ac.uk/pub/databases/emdb/structures/EMD-{emdb_id}/map/emd_{emdb_id}.map.gz"
        dest = out_dir / f"emd_{emdb_id}.map.gz"
    else:
        # Use legacy PDB format (.pdb) for compatibility with Bio.PDB.PDBParser.
        # mmCIF format causes ValueError in PDBParser ("invalid literal for int").
        url = f"https://files.rcsb.org/download/{acc_upper}.pdb"
        dest = out_dir / f"{acc_upper}.pdb"

    if dest.exists():
        log.info(f"[accession] {acc_upper}: already downloaded at {dest}")
        return str(dest)

    try:
        log.info(f"[accession] Downloading {acc_upper} from {url}")
        urllib.request.urlretrieve(url, dest)
        log.info(f"[accession] {acc_upper}: saved to {dest} ({dest.stat().st_size // 1024} KB)")
        return str(dest)
    except urllib.error.HTTPError as exc:
        log.error(f"[accession] {acc_upper}: HTTP {exc.code} from {url}")
        return None
    except Exception as exc:
        log.error(f"[accession] {acc_upper}: download failed: {exc}")
        return None


def _download_uniprot_fasta(accession: str, out_dir: Path) -> Optional[str]:
    """
    Download a protein sequence (UniProt / Ensembl protein / NCBI RefSeq) as FASTA.
    Returns local file path or None on failure.
    """
    import urllib.request
    import urllib.error

    out_dir.mkdir(parents=True, exist_ok=True)
    acc_upper = accession.upper()
    dest = out_dir / f"{acc_upper}.fasta"

    if dest.exists():
        log.info(f"[accession] {acc_upper}: already downloaded at {dest}")
        return str(dest)

    # Choose URL based on accession prefix
    if acc_upper.startswith("ENSP"):
        url = f"https://rest.ensembl.org/sequence/id/{acc_upper}?content-type=text/x-fasta;type=protein"
    elif acc_upper.startswith(("NP_", "XP_", "WP_")):
        # NCBI efetch
        url = (
            f"https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi"
            f"?db=protein&id={acc_upper}&rettype=fasta&retmode=text"
        )
    else:
        # UniProtKB
        url = f"https://rest.uniprot.org/uniprotkb/{acc_upper}.fasta"

    try:
        log.info(f"[accession] Downloading protein FASTA for {acc_upper} from {url}")
        urllib.request.urlretrieve(url, dest)
        log.info(f"[accession] {acc_upper}: saved to {dest} ({dest.stat().st_size} bytes)")
        return str(dest)
    except urllib.error.HTTPError as exc:
        log.error(f"[accession] {acc_upper}: HTTP {exc.code} from {url}")
        return None
    except Exception as exc:
        log.error(f"[accession] {acc_upper}: download failed: {exc}")
        return None


def _download_genomic_ref(accession: str, out_dir: Path) -> Optional[str]:
    """
    Download a genomic reference sequence (Ensembl gene/transcript or NCBI RefSeq nucleotide).
    Returns local FASTA path or None on failure.
    """
    import urllib.request
    import urllib.error

    out_dir.mkdir(parents=True, exist_ok=True)
    acc_upper = accession.upper()
    dest = out_dir / f"{acc_upper}.fasta"

    if dest.exists():
        return str(dest)

    if acc_upper.startswith("ENSG") or acc_upper.startswith("ENST"):
        endpoint = "sequence/id"
        type_param = "genomic" if acc_upper.startswith("ENSG") else "cdna"
        url = f"https://rest.ensembl.org/{endpoint}/{acc_upper}?content-type=text/x-fasta;type={type_param}"
    else:
        # NCBI RefSeq nucleotide
        url = (
            f"https://eutils.ncbi.nlm.nih.gov/entrez/eutils/efetch.fcgi"
            f"?db=nuccore&id={acc_upper}&rettype=fasta&retmode=text"
        )

    try:
        log.info(f"[accession] Downloading genomic FASTA for {acc_upper}")
        urllib.request.urlretrieve(url, dest)
        return str(dest)
    except Exception as exc:
        log.error(f"[accession] {acc_upper}: download failed: {exc}")
        return None


def _download_chemical_structure(accession: str, out_dir: Path) -> Optional[str]:
    """
    Download a small-molecule structure (ChEMBL or PubChem) as SDF.
    Returns local file path or None on failure.
    """
    import urllib.request
    import urllib.error

    out_dir.mkdir(parents=True, exist_ok=True)
    acc_upper = accession.upper()
    dest = out_dir / f"{acc_upper}.sdf"

    if dest.exists():
        return str(dest)

    if acc_upper.startswith("CHEMBL"):
        url = f"https://www.ebi.ac.uk/chembl/api/data/molecule/{acc_upper}.sdf"
    elif acc_upper.startswith("CID"):
        cid_num = acc_upper[3:]  # strip "CID"
        url = f"https://pubchem.ncbi.nlm.nih.gov/rest/pug/compound/cid/{cid_num}/SDF"
    else:
        return None

    try:
        log.info(f"[accession] Downloading chemical structure for {acc_upper}")
        urllib.request.urlretrieve(url, dest)
        return str(dest)
    except Exception as exc:
        log.error(f"[accession] {acc_upper}: download failed: {exc}")
        return None


def _resolve_accession_file(
    accession_info: Dict[str, str],
    work_base: Path,
    run_id: str,
    nf_bin: str,
    profile: str,
    env: dict,
    executor_config_path: Optional[Path],
) -> Optional[str]:
    """
    Dispatch to the appropriate download handler for a single accession.
    Returns the local file path (or samplesheet path for sequencing data), or None.
    """
    handler = accession_info["handler"]
    accession = accession_info["accession"]
    dl_dir = work_base / f"{run_id}_accession_downloads"

    if handler == "sequencing":
        return _run_fetchngs_prefetch(
            [accession], work_base, run_id, nf_bin, profile, env, executor_config_path
        )
    elif handler == "structure":
        return _download_pdb_structure(accession, dl_dir)
    elif handler == "protein_seq":
        return _download_uniprot_fasta(accession, dl_dir)
    elif handler == "genomic_ref":
        return _download_genomic_ref(accession, dl_dir)
    elif handler == "chemical":
        return _download_chemical_structure(accession, dl_dir)
    elif handler == "proteomics":
        # PRIDE datasets are large; provide the FTP URL as metadata instead of downloading
        log.info(
            f"[accession] {accession}: PRIDE download not automated. "
            f"Retrieve from https://www.ebi.ac.uk/pride/archive/projects/{accession}"
        )
        return None
    elif handler == "annotation":
        # Variant / clinical IDs are looked up online; no file to download
        log.info(f"[accession] {accession}: annotation-only ID ({accession_info['label']}) — no file to download")
        return None
    else:
        log.warning(f"[accession] Unknown handler '{handler}' for {accession}")
        return None


def _accession_chain_thread(
    *,
    run_id: str,
    accession_params: Dict[str, Dict[str, str]],  # param_key → accession_info
    remaining_params: Dict[str, Any],
    main_cmd: list[str],
    nf_bin: str,
    nf_path: Path,
    profile: str,
    work_base: Path,
    log_path: Path,
    trace_path: Path,
    env: dict,
    executor_config_path: Optional[Path],
) -> None:
    """
    Background thread: resolve all public-database accessions, substitute resolved
    file paths into the main Nextflow command, then launch and stream the main workflow.

    Status transitions: fetching_accessions → running (or failed).
    """
    def _set_status(status: str, **extra: Any) -> None:
        with _runs_lock:
            if run_id in _runs:
                _runs[run_id]["status"] = status
                _runs[run_id].update(extra)

    log.info(f"[accession chain run_id={run_id}] Starting accession resolution for params: {list(accession_params)}")

    # Resolve each accession-valued parameter to a local file path
    resolved: Dict[str, str] = {}
    any_sequencing = any(v["handler"] == "sequencing" for v in accession_params.values())

    if any_sequencing:
        # Batch all sequencing accessions into a single fetchngs run
        sequencing_keys = [k for k, v in accession_params.items() if v["handler"] == "sequencing"]
        seq_accessions = [accession_params[k]["accession"] for k in sequencing_keys]
        _set_status("fetching_accessions", accession_status="running fetchngs")

        samplesheet = _run_fetchngs_prefetch(
            seq_accessions, work_base, run_id, nf_bin, profile, env, executor_config_path
        )
        if samplesheet:
            # Map the first sequencing param → samplesheet; others get the same path
            for k in sequencing_keys:
                resolved[k] = samplesheet
            log.info(f"[accession chain run_id={run_id}] fetchngs done → {samplesheet}")
        else:
            _set_status("failed", error="fetchngs prefetch failed — check fetchngs logs")
            return

    # Resolve non-sequencing accessions individually
    for key, info in accession_params.items():
        if info["handler"] == "sequencing":
            continue  # already resolved above
        local_file = _resolve_accession_file(
            info, work_base, run_id, nf_bin, profile, env, executor_config_path
        )
        if local_file:
            resolved[key] = local_file
        else:
            # Non-sequencing download failures are warnings, not fatal — the main
            # workflow may have its own retrieval logic (e.g. alphafold with PDB id)
            log.warning(f"[accession chain run_id={run_id}] Could not resolve {info['accession']} for --{key}; passing original accession string")
            resolved[key] = info["accession"]

    # Substitute resolved paths into the main command
    # Replace "--<key> <original_accession>" with "--<key> <resolved_path>"
    substituted_cmd = []
    skip_next = False
    original_accession_values = {k: v["accession"] for k, v in accession_params.items()}
    i = 0
    while i < len(main_cmd):
        token = main_cmd[i]
        if skip_next:
            skip_next = False
            i += 1
            continue
        # Check if this is a --param flag whose value should be substituted
        if token.startswith("--") and i + 1 < len(main_cmd):
            param_name = token[2:]
            next_val = main_cmd[i + 1]
            if param_name in resolved and next_val.upper() == original_accession_values.get(param_name, "").upper():
                substituted_cmd.append(token)
                substituted_cmd.append(resolved[param_name])
                skip_next = True
                i += 1
                log.info(f"[accession chain run_id={run_id}] Substituted --{param_name}: {next_val!r} → {resolved[param_name]!r}")
                i += 1
                continue
        substituted_cmd.append(token)
        i += 1

    _set_status("running", accession_status="launching main workflow")
    log.info(f"[accession chain run_id={run_id}] Launching main workflow: {' '.join(substituted_cmd)}")

    # Use the writable work_dir as cwd so Nextflow can write temp files and
    # bootstrap its .nextflow directory.  nf_path.parent is often read-only
    # inside the Galaxy container.
    chain_work_dir = work_base / run_id / "work"
    chain_work_dir.mkdir(parents=True, exist_ok=True)
    try:
        process = subprocess.Popen(
            substituted_cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            cwd=str(chain_work_dir),
            env=env,
        )
        with _runs_lock:
            if run_id in _runs:
                _runs[run_id]["process"] = process
    except Exception as exc:
        _set_status("failed", error=f"Failed to launch main workflow: {exc}")
        log.error(f"[accession chain run_id={run_id}] Launch error: {exc}")
        return

    _stream_logs(process, run_id, log_path)


# ---------------------------------------------------------------------------
# Routes
# ---------------------------------------------------------------------------

@router.post("/api/nextflow/execute", summary="Launch a Nextflow workflow")
def execute_nextflow(
    request: NextflowExecuteRequest,
) -> Dict[str, Any]:
    """
    Launch a Nextflow workflow by path.  Returns immediately with a run_id.
    The workflow runs as a background subprocess.
    """
    try:
        nf_path = _resolve_nextflow_path(request.nextflow_path)
    except FileNotFoundError as exc:
        raise HTTPException(
            status_code=404,
            detail=str(exc)
        )

    # Pre-flight: check if this pipeline can run on this host with these settings.
    params = dict(request.parameters or {})
    compute = dict(request.compute_config or {})

    # Default to AWS Batch when NEXTFLOW_USE_AWS=true and no explicit executor is set.
    # This is the platform default: all workflows run on Batch unless explicitly overridden.
    _use_aws_env = os.environ.get("NEXTFLOW_USE_AWS", "false").lower() in ("true", "1", "yes")
    # Normalise user_id early for path construction (before run_id is generated)
    _uid_for_path = (request.user_id or "unknown").replace("/", "_").replace("..", "_")
    # Route to AWS Batch when NEXTFLOW_USE_AWS=true OR when executor is already "awsbatch"
    # (the frontend sends executor="awsbatch" by default as the platform standard).
    _executor_requested = compute.get("executor", "")
    if _use_aws_env or _executor_requested == "awsbatch":
        s3_bucket_default = os.environ.get("AWS_S3_BUCKET", "biomate-nextflow-work")
        run_uuid_short = str(uuid.uuid4())[:8]
        _auto_outdir = f"s3://{s3_bucket_default}/nextflow/outputs/{_uid_for_path}/{run_uuid_short}"
        if not params.get("outdir"):
            params["outdir"] = _auto_outdir
            log.info(
                f"[Nextflow] AWS Batch executor — auto-setting "
                f"outdir={_auto_outdir}"
            )
        compute["executor"] = "awsbatch"
        if not compute.get("s3_bucket"):
            compute["s3_bucket"] = s3_bucket_default

    # Auto-detect S3 outdir → route to AWS Batch automatically.
    # If the caller passes outdir=s3://..., we treat that as an implicit request
    # for cloud execution — no separate compute_config.executor needed.
    effective_outdir = params.get("outdir", "")
    is_s3 = str(effective_outdir).startswith("s3://")

    if is_s3:
        # Validate the bucket is reachable before launching anything.
        _validate_s3_url(effective_outdir)

        # Auto-upgrade to AWS Batch unless an explicit executor was already given.
        if not compute.get("executor"):
            compute["executor"] = "awsbatch"
            log.info(
                f"[Nextflow] S3 outdir '{effective_outdir}' detected — "
                "auto-selecting AWS Batch executor"
            )

        # Propagate bucket name so _generate_executor_config can set workDir.
        if not compute.get("s3_bucket"):
            compute["s3_bucket"] = effective_outdir.split("/")[2]  # s3://BUCKET/...

    # Auto-detect S3 inputs → also route to AWS Batch.
    # Nextflow stages S3 inputs natively on awsbatch; local executor cannot
    # reliably access S3 paths without the nf-amazon plugin + S3 workDir.
    s3_inputs = [
        v for k, v in params.items()
        if k != "outdir" and isinstance(v, str) and v.startswith("s3://")
    ]
    if s3_inputs:
        if not compute.get("executor"):
            compute["executor"] = "awsbatch"
            log.info(
                f"[Nextflow] S3 input(s) detected ({len(s3_inputs)}) — "
                "auto-selecting AWS Batch executor"
            )
        # Ensure outdir is also S3 when inputs are S3: Batch containers cannot
        # write publishDir to a local path on the head node.
        if not is_s3:
            s3_bucket_from_input = s3_inputs[0].split("/")[2]
            effective_outdir = (
                f"s3://{s3_bucket_from_input}/nextflow/outputs/{_uid_for_path}/"
                + str(uuid.uuid4())[:8]
            )
            is_s3 = True
            params["outdir"] = effective_outdir
            if not compute.get("s3_bucket"):
                compute["s3_bucket"] = s3_bucket_from_input
            log.info(
                f"[Nextflow] Auto-setting S3 outdir for S3 inputs: {effective_outdir}"
            )

    # Validate all input paths exist and total size ≤ 10 GB.
    _validate_input_paths(params)

    constraint = _check_pipeline_constraints(nf_path, params, compute)
    if constraint and constraint.get("blocked"):
        raise HTTPException(
            status_code=422,
            detail={
                "error": "Pipeline cannot run locally on this host",
                "reason": constraint["reason"],
                "suggestion": constraint["suggestion"],
                "mock_mode_available": constraint.get("mock_mode_available", False),
            },
        )

    # Generate unique IDs
    run_id = str(uuid.uuid4())
    invocation_id = str(uuid.uuid4())

    # Work / output directory (local staging area for logs and config files).
    work_base = Path(os.environ.get("NEXTFLOW_WORK_DIR", "/tmp/nextflow_runs"))
    log_dir = work_base / run_id
    log_dir.mkdir(parents=True, exist_ok=True)

    if is_s3:
        # S3 mode: outputs go to S3; local work_dir only used by Nextflow head process.
        outdir = effective_outdir   # pass through as-is
        work_dir = log_dir / "work"
        work_dir.mkdir(parents=True, exist_ok=True)
    else:
        outdir_path = work_base / run_id / "output"
        work_dir = work_base / run_id / "work"
        outdir_path.mkdir(parents=True, exist_ok=True)
        work_dir.mkdir(parents=True, exist_ok=True)
        outdir = str(outdir_path)

    # Detect whether any param contains multi-line content (inline CSV/SMILES/FASTA).
    # If so, write ALL params to a JSON file and use --params-file instead of individual
    # --key value flags. This avoids shell/Nextflow arg-parsing issues with newlines
    # embedded in command-line arguments.
    _has_multiline = any(
        isinstance(v, str) and "\n" in v for v in params.values()
    )

    # Build nextflow command
    try:
        nf_bin = _get_nextflow_bin()
    except RuntimeError as e:
        raise HTTPException(status_code=503, detail=str(e))

    cmd = [nf_bin, "run", str(nf_path)]

    # Entry selection: honor explicit request first; otherwise auto-detect for
    # scripts with named-only workflows (e.g. runnable subworkflows).
    selected_entry = (request.entry or "").strip() or _detect_nextflow_entry(nf_path)
    if selected_entry:
        cmd += ["-entry", selected_entry]

    # Resolve runtime environment using documented local Docker images first.
    # For awsbatch, skip -with-docker — the ECR container is set in the executor config;
    # passing -with-docker here would override the per-process ECR container directives.
    _executor_for_container = (compute or {}).get("executor", "")
    strategy = _choose_container_strategy(nf_path, request.nextflow_path)
    if _executor_for_container != "awsbatch" and strategy["mode"] == "docker" and strategy["image"]:
        cmd += ["-with-docker", strategy["image"]]
    elif _executor_for_container != "awsbatch" and strategy["missing_modules"]:
        raise HTTPException(
            status_code=503,
            detail=(
                "Missing required runtime modules and auto-install failed: "
                + ", ".join(strategy["missing_modules"])
            ),
        )

    # Profile — explicit request value wins; fall back to BIOMATE_NF_PROFILE env var.
    profile = request.profile or _default_nf_profile()
    cmd += ["-profile", profile]

    # Real-mode guard: for any non-mock profile, ensure mock_mode is off.
    # Workflows default params.mock_mode = true; command-line params override defaults.
    # This keeps the logic centralised here rather than scattered across workflow configs.
    _mock_profiles = {"standard", "test", "test_full", "test_cache"}
    if not any(p.strip() in _mock_profiles for p in profile.split(",")) and "mock_mode" not in params:
        params["mock_mode"] = False
        log.info(f"[Nextflow run {run_id}] profile={profile!r} → injecting --mock_mode false")

    # Work directory — for awsbatch, the work dir must be S3 (set in executor config);
    # passing a local path via -w would override that and cause "S3 bucket required" errors.
    _executor = (compute or {}).get("executor", "")
    _s3_work_dir: str = ""  # set below for awsbatch; used in _runs registration
    if _executor == "awsbatch":
        s3_bucket_for_work = (
            (compute or {}).get("s3_bucket")
            or os.environ.get("NEXTFLOW_S3_BUCKET", "biomate-nextflow-work")
        )
        _s3_work_dir = f"s3://{s3_bucket_for_work}/nextflow/work/{_uid_for_path}/{run_id}"
        cmd += ["-w", _s3_work_dir]
    else:
        cmd += ["-w", str(work_dir)]

    # Nextflow -resume: reuse cached work from a prior run if requested.
    if request.resume_from_run_id:
        with _runs_lock:
            prev = _runs.get(request.resume_from_run_id, {})
        prev_work = prev.get("work_dir")
        if prev_work:
            cmd += ["-resume", "-w", str(prev_work)]
            log.info(f"[Nextflow run {run_id}] Resuming from {request.resume_from_run_id}, work_dir={prev_work}")

    if _has_multiline:
        # One or more params contain embedded newlines (inline CSV/SMILES/FASTA).
        # Write all params to a JSON file and pass via --params-file so Nextflow
        # receives the full multi-line strings without shell arg-parsing issues.
        import json as _ml_json
        _params_for_json = {}
        for key, value in params.items():
            if isinstance(value, bool):
                _params_for_json[key] = value
            elif isinstance(value, (int, float)):
                _params_for_json[key] = value
            else:
                _params_for_json[key] = str(value)
        if "outdir" not in _params_for_json:
            _params_for_json["outdir"] = str(outdir)
        _params_json_path = log_dir / "nf-params.json"
        _params_json_path.write_text(_ml_json.dumps(_params_for_json, indent=2))
        cmd += ["--params-file", str(_params_json_path)]
        log.info(f"[Nextflow run {run_id}] --params-file: {list(_params_for_json.keys())}")
    else:
        # Standard path: pass params as individual --key value flags.
        if "outdir" not in params:
            cmd += ["--outdir", str(outdir)]
        for key, value in params.items():
            if key == "outdir":
                cmd += ["--outdir", str(value)]
            elif isinstance(value, bool):
                cmd += [f"--{key}", "true" if value else "false"]
            else:
                cmd += [f"--{key}", str(value)]

    log.info(f"[Nextflow run {run_id}] cmd: {' '.join(cmd)}")
    log.info(f"[Nextflow run {run_id}] outdir: {outdir}")
    if selected_entry:
        log.info(f"[Nextflow run {run_id}] entry: {selected_entry}")

    log_path = log_dir / "nextflow.log"
    trace_path = log_dir / "workflow-trace.txt"
    cmd += ["-with-trace", str(trace_path)]

    # Environment
    env = os.environ.copy()
    env["NXF_HOME"] = str(log_dir / ".nextflow")
    if strategy["mode"] == "docker" and strategy["docker_opts"]:
        env["NXF_DOCKER_OPTS"] = strategy["docker_opts"]

    # Compute config overrides: generate a real nextflow.config for non-local executors.
    # NXF_EXECUTOR is not a valid Nextflow env var — executor must be set in a config file.
    billing_user_id = _uid_for_path  # same sanitised value used in S3 path construction
    executor_config_path = _generate_executor_config(
        compute, log_dir, user_id=billing_user_id, run_id=run_id,
        credentials=dict(request.credentials or {}),
    )
    if executor_config_path:
        cmd += ["-c", str(executor_config_path)]

    # Validate qc_overrides and qc_profile if provided
    qc_overrides = request.qc_overrides or {}
    qc_profile = request.qc_profile or None
    workflow_domain = request.workflow_domain or "unknown"
    try:
        from galaxy.jobs.qc_trace_monitor import NextflowQCGateHandler
        # Auto-infer qc_profile from workflow path when not explicitly provided
        if not qc_profile:
            qc_profile = NextflowQCGateHandler.infer_qc_profile(str(nf_path))
            if qc_profile:
                log.info(f"[QC] Auto-selected profile '{qc_profile}' for {nf_path}")
        if qc_overrides:
            valid, errors = NextflowQCGateHandler.validate_qc_overrides(qc_overrides)
            if not valid:
                raise HTTPException(
                    status_code=422,
                    detail={"error": "Invalid qc_overrides", "errors": errors}
                )
        if qc_profile:
            valid, errors = NextflowQCGateHandler.validate_qc_profile(qc_profile)
            if not valid:
                raise HTTPException(
                    status_code=422,
                    detail={"error": "Unknown qc_profile", "errors": errors}
                )
    except ImportError:
        log.warning("[QC] QC gate handler not available — skipping override/profile validation")

    _is_batch = compute.get("executor") == "awsbatch"

    # ── Detect public-database accessions in parameters ───────────────────────
    # If any parameter value is a recognised accession (SRA, PDB, UniProt, etc.)
    # we launch an accession-chain thread that first downloads / resolves the data,
    # then substitutes the local path into the Nextflow command and runs the workflow.
    # This avoids the 422 "path does not exist" error for accession-valued params.
    accession_params: Dict[str, Dict[str, str]] = {}
    for key, value in params.items():
        if key == "outdir":
            continue
        info = _classify_accession(str(value))
        if info:
            accession_params[key] = info
            log.info(
                f"[Nextflow run {run_id}] Detected {info['label']} accession in "
                f"--{key}: {info['accession']} (handler={info['handler']})"
            )

    initial_status = "fetching_accessions" if accession_params else "running"

    # Register run before starting any thread so status endpoint returns immediately.
    # Capture started_at once so _runs and timing.json use the identical timestamp.
    _started_at_now = time.time()
    with _runs_lock:
        _runs[run_id] = {
            "run_id": run_id,
            "invocation_id": invocation_id,
            "status": initial_status,
            "returncode": None,
            "outdir": str(outdir),
            "log_path": str(log_path),
            "trace_path": str(trace_path),
            "nextflow_path": str(nf_path),
            "profile": profile,
            "qc_overrides": qc_overrides,
            "qc_profile": qc_profile,
            "workflow_domain": workflow_domain,
            "work_dir": _s3_work_dir if _s3_work_dir else str(work_dir),
            "runtime_mode": strategy["mode"],
            "runtime_image": strategy["image"],
            "entry": selected_entry,
            "required_modules": strategy["required_modules"],
            "missing_modules": strategy["missing_modules"],
            "host_arch": strategy.get("host_arch"),
            "image_arch": strategy.get("image_arch"),
            "is_batch": _is_batch,
            "user_id": request.user_id or "anonymous",
            "is_pilot": bool(request.is_pilot),
            "started_at": _started_at_now,
            # Accession metadata (empty dict when not applicable)
            "accession_params": {k: v["label"] for k, v in accession_params.items()},
        }

    # Persist timing to disk so other gunicorn workers can read it via the disk fallback.
    try:
        import json as _json
        _timing_path = Path(os.environ.get("NEXTFLOW_WORK_DIR", "/tmp/nextflow_runs")) / run_id / "timing.json"
        _timing_path.parent.mkdir(parents=True, exist_ok=True)
        _timing_path.write_text(_json.dumps({"started_at": _started_at_now}))
    except Exception as _te:
        log.debug("[timing] Could not write timing.json for %s: %s", run_id, _te)

    if accession_params:
        # Accession path: run download pre-step then main workflow in one thread
        t = threading.Thread(
            target=_accession_chain_thread,
            kwargs={
                "run_id": run_id,
                "accession_params": accession_params,
                "remaining_params": {k: v for k, v in params.items() if k not in accession_params},
                "main_cmd": cmd,
                "nf_bin": nf_bin,
                "nf_path": nf_path,
                "profile": profile,
                "work_base": work_base,
                "log_path": log_path,
                "trace_path": trace_path,
                "env": env,
                "executor_config_path": executor_config_path,
            },
            daemon=True,
            name=f"nf-acc-{run_id[:8]}",
        )
        t.start()
        # QC monitor is started here; the chain thread will launch the Nextflow
        # process internally, but the monitor waits for the trace file to appear.
        _start_qc_monitor(
            invocation_id=invocation_id,
            work_dir=work_dir,
            qc_overrides=qc_overrides,
            workflow_domain=workflow_domain,
            qc_profile=qc_profile,
            trace_path=trace_path,
            is_batch=_is_batch,
        )
        return {
            "success": True,
            "run_id": run_id,
            "invocation_id": invocation_id,
            "status": "fetching_accessions",
            "accessions": {k: v["label"] for k, v in accession_params.items()},
            "outputs": {"outdir": str(outdir)},
            "runtime": {
                "mode": strategy["mode"],
                "image": strategy["image"],
                "entry": selected_entry,
            },
            "message": (
                f"Downloading {len(accession_params)} accession(s) before launching workflow "
                f"(run_id: {run_id})"
            ),
        }

    # ── Normal path: no accessions — launch Nextflow directly ────────────────
    # Use the writable work_dir as cwd — nf_path.parent is read-only in container.
    try:
        process = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            cwd=str(work_dir),
            env=env,
        )
    except Exception as exc:
        log.error(f"[Nextflow run {run_id}] failed to launch: {exc}")
        raise HTTPException(status_code=500, detail=f"Failed to launch Nextflow: {exc}")

    # Stream logs in background
    t = threading.Thread(
        target=_stream_logs,
        args=(process, run_id, log_path),
        daemon=True,
        name=f"nf-log-{run_id[:8]}",
    )
    t.start()

    # QC monitoring thread — reads trace file and fires QC gate events
    _start_qc_monitor(
        invocation_id=invocation_id,
        work_dir=work_dir,
        qc_overrides=qc_overrides,
        workflow_domain=workflow_domain,
        qc_profile=qc_profile,
        trace_path=trace_path,
        is_batch=_is_batch,
    )

    return {
        "success": True,
        "run_id": run_id,
        "invocation_id": invocation_id,
        "status": "running",
        "outputs": {
            "outdir": str(outdir),
        },
        "runtime": {
            "mode": strategy["mode"],
            "image": strategy["image"],
            "entry": selected_entry,
            "required_modules": strategy["required_modules"],
            "missing_modules": strategy["missing_modules"],
            "host_arch": strategy.get("host_arch"),
            "image_arch": strategy.get("image_arch"),
            "cross_arch_allowed": strategy.get("cross_arch_allowed"),
        },
        "message": f"Nextflow workflow started (run_id: {run_id})",
    }


class ResumeRunRequest(BaseModel):
    # Optional nextflow_path sent by routes.ts when _runs may be empty
    # (multi-worker: the original run was registered in a different gunicorn worker)
    nextflow_path: Optional[str] = None


@router.post("/api/nextflow/resume/{run_id}", summary="Resume a Nextflow run with -resume")
def resume_nextflow_run(run_id: str, body: ResumeRunRequest = ResumeRunRequest()) -> Dict[str, Any]:
    """
    Re-launch a previous Nextflow run with ``-resume``, reusing its work
    directory so all already-cached tasks are skipped.  Returns a new run_id.

    Multi-worker safe: if the run is not in this worker's _runs dict (it was
    registered in a different gunicorn worker), falls back to reconstructing
    the work directory from disk at NEXTFLOW_WORK_DIR/<run_id>/work.

    Called by the frontend "Run Step" / "Rerun Step" button in the per-step
    execution panel of nextflow-workflow-viewer.tsx.
    """
    with _runs_lock:
        prev = dict(_runs.get(run_id, {}))

    if not prev:
        # Multi-worker fallback: reconstruct from disk.
        work_base = Path(os.environ.get("NEXTFLOW_WORK_DIR", "/tmp/nextflow_runs"))
        candidate_work_dir = work_base / run_id / "work"
        nextflow_path = body.nextflow_path
        if not nextflow_path or not candidate_work_dir.exists():
            raise HTTPException(
                status_code=404,
                detail=(
                    f"Run {run_id!r} not found in this worker's run registry "
                    f"and work directory {candidate_work_dir} does not exist on disk. "
                    "The run may have been on a different host or the work directory was cleaned up."
                ),
            )
        prev = {
            "nextflow_path": nextflow_path,
            "work_dir": str(candidate_work_dir),
            "is_batch": False,
            "profile": None,
            "entry": None,
            "workflow_domain": None,
            "user_id": None,
        }
        log.info(
            f"[resume/{run_id}] _runs miss — reconstructed from disk: "
            f"work_dir={candidate_work_dir} nextflow_path={nextflow_path}"
        )

    resume_request = NextflowExecuteRequest(
        nextflow_path=prev["nextflow_path"],
        profile=prev.get("profile"),
        entry=prev.get("entry"),
        workflow_domain=prev.get("workflow_domain"),
        user_id=prev.get("user_id"),
        resume_from_run_id=run_id,
        compute_config=(
            {"executor": "awsbatch"} if prev.get("is_batch") else None
        ),
    )
    return execute_nextflow(resume_request)


@router.get("/api/nextflow/status/{run_id}", summary="Get Nextflow run status")
def get_nextflow_status(
    run_id: str,
) -> Dict[str, Any]:
    """Return current status of a Nextflow run."""
    with _runs_lock:
        info = _runs.get(run_id)

    if info is None:
        # Fallback: run may have been started in a different gunicorn worker.
        # gunicorn --workers 4 creates 4 separate Python processes each with their own
        # _runs dict. If the execute request hit Worker A and this status request hits
        # Worker B, _runs.get(run_id) returns None. Reconstruct status from disk.
        work_base = Path(os.environ.get("NEXTFLOW_WORK_DIR", "/tmp/nextflow_runs"))
        log_dir = work_base / run_id
        output_dir = log_dir / "output"
        log_path_fallback = log_dir / "nextflow.log"
        # Read persisted timing (written by execute_nextflow on start/end).
        _disk_timing: Dict[str, Any] = {}
        _timing_path_fb = log_dir / "timing.json"
        if _timing_path_fb.exists():
            try:
                import json as _json
                _disk_timing = _json.loads(_timing_path_fb.read_text())
            except Exception:
                pass
        _fb_started_at: float | None = _disk_timing.get("started_at")
        _fb_completed_at: float | None = _disk_timing.get("completed_at")
        _fb_duration_s: int | None = None
        if _fb_started_at:
            _end = _fb_completed_at if _fb_completed_at else time.time()
            _fb_duration_s = int(_end - _fb_started_at)
        log_tail_fallback: list = []
        log_full_text = ""
        if log_path_fallback.exists():
            try:
                with open(log_path_fallback) as fh:
                    log_full_text = fh.read()
                lines = log_full_text.splitlines()
                log_tail_fallback = [l.rstrip() for l in lines[-20:]]
            except Exception:
                pass
        if output_dir.exists():
            # Use the Nextflow log as the primary completion signal.
            # Nextflow writes pipeline_info/ as soon as execution starts, so we cannot
            # rely on directory presence alone — the run may still be in progress.
            nf_done = "Execution complete" in log_full_text
            nf_failed_log = (
                "Workflow execution failed" in log_full_text
                or "Pipeline failed" in log_full_text
                or "ERROR ~ " in log_full_text
            )
            if not nf_done and not nf_failed_log:
                # Log doesn't yet show completion → run is still in progress.
                return {
                    "run_id": run_id,
                    "invocation_id": run_id,
                    "status": "running",
                    "returncode": None,
                    "outdir": str(output_dir),
                    "work_dir": str(log_dir / "work"),
                    "log_tail": log_tail_fallback,
                    "is_batch": False,
                    "s3_output_files": [],
                    "completedSteps": 0,
                    "totalSteps": 0,
                    "progressPercent": 50,
                    "processes": [],
                    "started_at": _fb_started_at,
                    "completed_at": None,
                    "duration_s": _fb_duration_s,
                }

            # Nextflow finished. Check whether result directories were produced.
            nf_internal = {"pipeline_info"}
            real_subdirs = [
                d for d in output_dir.iterdir()
                if d.is_dir() and d.name not in nf_internal
            ] if output_dir.is_dir() else []
            has_results = len(real_subdirs) > 0

            fallback_status = "succeeded" if has_results else "failed"
            return {
                "run_id": run_id,
                "invocation_id": run_id,
                "status": fallback_status,
                "returncode": 0 if has_results else 1,
                "outdir": str(output_dir),
                "work_dir": str(log_dir / "work"),
                "log_tail": log_tail_fallback,
                "is_batch": False,
                "s3_output_files": [],
                "completedSteps": 0,
                "totalSteps": 0,
                "progressPercent": 100,
                "processes": [],
                "started_at": _fb_started_at,
                "completed_at": _fb_completed_at,
                "duration_s": _fb_duration_s,
            }
        elif log_dir.exists():
            # Log dir exists but no output yet → still running
            return {
                "run_id": run_id,
                "invocation_id": run_id,
                "status": "running",
                "returncode": None,
                "outdir": str(output_dir),
                "work_dir": str(log_dir / "work"),
                "log_tail": log_tail_fallback,
                "is_batch": False,
                "s3_output_files": [],
                "completedSteps": 0,
                "totalSteps": 0,
                "progressPercent": 50,
                "processes": [],
                "started_at": _fb_started_at,
                "completed_at": None,
                "duration_s": _fb_duration_s,
            }
        raise HTTPException(status_code=404, detail=f"Run not found: {run_id}")

    # Read last few lines of log for progress info
    log_tail: list = []
    log_path = Path(info.get("log_path", ""))
    if log_path.exists():
        try:
            with open(log_path) as fh:
                lines = fh.readlines()
            log_tail = [l.rstrip() for l in lines[-20:]]
        except Exception:
            pass

    # Parse trace file for task-level progress
    trace_path = Path(info.get("trace_path", ""))
    progress = _parse_trace_progress(trace_path)

    # Annotate each process with its matching S3 output files.
    # Convention: outdir/<PROCESS_NAME>/... — match by last segment of process name.
    s3_files = info.get("s3_output_files", [])
    processes = progress.get("processes", [])
    for proc in processes:
        proc_name = proc["name"].split(":")[-1]  # "NF_RNASEQ:STAR_ALIGN" → "STAR_ALIGN"
        proc["outputs"] = [
            f for f in s3_files
            if f"/{proc_name}/" in f.get("s3_uri", "") or
               f"/{proc_name.lower()}/" in f.get("s3_uri", "")
        ]

    outdir = info.get("outdir", "")
    work_dir = info.get("work_dir", "")

    started_at: float | None = info.get("started_at")
    completed_at: float | None = info.get("completed_at")
    now = time.time()
    duration_s: int | None = None
    if started_at:
        end = completed_at if completed_at else now
        duration_s = int(end - started_at)

    return {
        "run_id": run_id,
        "invocation_id": info["invocation_id"],
        "status": info["status"],
        "returncode": info["returncode"],
        "outdir": outdir,
        "work_dir": work_dir,
        "log_tail": log_tail,
        "is_batch": info.get("is_batch", False),
        "s3_output_files": s3_files,
        "started_at": started_at,
        "completed_at": completed_at,
        "duration_s": duration_s,
        **progress,
    }


@router.get("/api/nextflow/outputs/download", summary="Generate presigned download URL for S3 output")
def download_s3_output(
    s3_uri: str,
    run_id: str,
    presigned_only: int = 0,
) -> Any:
    """
    Generate a presigned S3 GET URL for a workflow output file.

    Security: the requested s3_uri must belong to the outdir of the given run_id.
    Returns a 302 redirect to the presigned URL (15-minute expiry).
    If presigned_only=1, returns JSON {"url": "..."} instead of redirecting.
    """
    from starlette.responses import RedirectResponse

    with _runs_lock:
        info = _runs.get(run_id)
    if info is None:
        # Same multi-worker fallback as get_nextflow_status: reconstruct from disk
        work_base = Path(os.environ.get("NEXTFLOW_WORK_DIR", "/tmp/nextflow_runs"))
        output_dir = work_base / run_id / "output"
        if output_dir.exists():
            info = {"outdir": str(output_dir), "invocation_id": run_id}
        else:
            raise HTTPException(status_code=404, detail=f"Run not found: {run_id}")

    outdir = str(info.get("outdir", ""))
    if not outdir.startswith("s3://"):
        raise HTTPException(status_code=400, detail="This run does not have S3 outputs.")

    # Auth guard: requested key must be within this run's outdir.
    if not s3_uri.startswith(outdir.rstrip("/") + "/"):
        raise HTTPException(
            status_code=403,
            detail="Requested S3 key is not within this run's output directory.",
        )

    try:
        import boto3
        parts = s3_uri[len("s3://"):].split("/", 1)
        bucket, key = parts[0], parts[1]
        s3 = boto3.client("s3", region_name=os.environ.get("AWS_DEFAULT_REGION", "us-west-2"))
        url = s3.generate_presigned_url(
            "get_object",
            Params={"Bucket": bucket, "Key": key},
            ExpiresIn=900,  # 15 minutes
        )
        if presigned_only:
            return {"url": url}
        return RedirectResponse(url, status_code=302)
    except ImportError:
        raise HTTPException(status_code=503, detail="boto3 not installed — S3 downloads unavailable.")
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"Failed to generate presigned URL: {exc}")


@router.get("/api/nextflow/runs/{run_id}/output_files", summary="List output files with presigned download URLs")
def list_run_output_files(run_id: str) -> Any:
    """
    List all output files for a completed run, with presigned S3 download URLs.
    Returns [{name, s3_uri, size, extension, download_url}].
    """
    with _runs_lock:
        info = _runs.get(run_id)
    if info is None:
        work_base = Path(os.environ.get("NEXTFLOW_WORK_DIR", "/tmp/nextflow_runs"))
        output_dir = work_base / run_id / "output"
        if output_dir.exists():
            # Local run — list files directly
            files = []
            for f in sorted(output_dir.rglob("*")):
                if f.is_file():
                    name = f.name
                    ext = name.rsplit(".", 1)[-1].lower() if "." in name else ""
                    files.append({
                        "name": name,
                        "s3_uri": None,
                        "size": f.stat().st_size,
                        "extension": ext,
                        "download_url": f"/api/nextflow/outputs/download?s3_uri={str(f)}&run_id={run_id}",
                    })
            return {"run_id": run_id, "files": files}
        raise HTTPException(status_code=404, detail=f"Run not found: {run_id}")

    outdir = str(info.get("outdir", ""))
    if not outdir.startswith("s3://"):
        return {"run_id": run_id, "files": [], "note": "Local run — no S3 outputs"}

    raw_files = _list_s3_output_files(outdir)
    if not raw_files:
        return {"run_id": run_id, "files": []}

    # Generate presigned URLs for each file
    try:
        import boto3
        s3 = boto3.client("s3", region_name=os.environ.get("AWS_DEFAULT_REGION", "us-west-2"))
    except ImportError:
        return {"run_id": run_id, "files": raw_files, "note": "boto3 not available — no download URLs"}

    enriched = []
    for f in raw_files:
        s3_uri = f["s3_uri"]
        try:
            parts = s3_uri[len("s3://"):].split("/", 1)
            bucket, key = parts[0], parts[1]
            url = s3.generate_presigned_url(
                "get_object",
                Params={"Bucket": bucket, "Key": key},
                ExpiresIn=3600,  # 1 hour
            )
        except Exception:
            url = None
        enriched.append({**f, "download_url": url})

    return {"run_id": run_id, "files": enriched}


@router.get("/api/qc/profiles", summary="List available named QC profiles")
async def list_qc_profiles() -> Dict[str, Any]:
    """
    Return all available named QC profiles (Layer 3 — curated threshold sets).

    Each profile includes:
      - id:          str  — profile identifier for use in qc_profile field
      - description: str  — human-readable summary
      - domain_hint: str  — primary workflow domain
      - overrides:   dict — threshold keys and values applied when profile is selected
      - references:  list — primary literature / guideline citations

    This is an async endpoint so it runs in the event loop (not the thread pool),
    ensuring it responds quickly even when worker threads are busy with AI calls.
    """
    try:
        from galaxy.jobs.qc_trace_monitor import NextflowQCGateHandler, QC_RED_LINES
        profiles = NextflowQCGateHandler.list_profiles()
        defaults = QC_RED_LINES
    except ImportError:
        profiles = []
        defaults = {}
    return {
        "profiles": profiles,
        "count": len(profiles),
        "defaults": defaults,
    }


@router.get("/api/invocations/{invocation_id}/qc-events",
            summary="Get QC event log for a workflow invocation")
def get_invocation_qc_events(
    invocation_id: str,
    trans: ProvidesUserContext = DependsOnTrans,
):
    """
    Return all QC gate and warning events recorded for a workflow invocation.

    Includes:
    - All blocking gate events (type='gate') with failures, metrics, suggestions
    - All near-threshold warning events (type='warning')
    - A methods_text paragraph suitable for inserting into paper methods sections
    - Summary counts (gates_triggered, warnings_emitted)
    """
    try:
        from galaxy.jobs.runners.nextflow_monitor import get_monitor_service
        monitor_service = get_monitor_service(trans.app)

        # Try integer lookup first (Galaxy invocation IDs), then string
        monitor = None
        for key in (invocation_id, int(invocation_id) if invocation_id.isdigit() else None):
            if key is None:
                continue
            monitor = monitor_service.monitors.get(key)
            if monitor:
                break

        if monitor is None or monitor.qc_handler is None:
            # Attempt to locate a persisted JSONL audit log even if monitor is gone
            import json as _json
            jobs_dir = getattr(getattr(trans.app, 'config', None), 'root', None)
            if jobs_dir:
                from pathlib import Path as _Path
                audit_path = (_Path(jobs_dir) / 'database' / 'jobs_directory'
                              / 'nextflow_workflows' / f"workflow_{invocation_id}"
                              / "qc_overrides_audit.jsonl")
                if audit_path.exists():
                    entries = []
                    for line in audit_path.read_text().splitlines():
                        try:
                            entries.append(_json.loads(line))
                        except Exception:
                            pass
                    return {
                        "invocation_id": invocation_id,
                        "source": "audit_jsonl",
                        "gates_triggered": sum(1 for e in entries if e.get("event_type") == "gate_triggered"),
                        "warnings_emitted": 0,
                        "events": entries,
                        "methods_text": "QC governance applied (see audit log for details).",
                    }
            return {
                "invocation_id": invocation_id,
                "source": "not_found",
                "gates_triggered": 0,
                "warnings_emitted": 0,
                "events": [],
                "methods_text": "No QC events recorded for this invocation.",
            }

        report = monitor.qc_handler.get_qc_report()
        report["source"] = "live_monitor"
        return report

    except Exception as e:
        log.error(f"[QC Events] Failed to retrieve events for {invocation_id}: {e}")
        raise HTTPException(status_code=500, detail=f"Failed to retrieve QC events: {e}")


@router.get("/api/invocations/{invocation_id}/qc-audit-download",
            summary="Download QC audit log as JSONL")
def download_invocation_qc_audit(
    invocation_id: str,
    trans: ProvidesUserContext = DependsOnTrans,
):
    """
    Download the full QC event log for a workflow invocation as a JSONL file.
    Each line is a JSON object representing one QC event.
    """
    import json as _json
    try:
        from galaxy.jobs.runners.nextflow_monitor import get_monitor_service
        monitor_service = get_monitor_service(trans.app)

        monitor = None
        for key in (invocation_id, int(invocation_id) if invocation_id.isdigit() else None):
            if key is None:
                continue
            monitor = monitor_service.monitors.get(key)
            if monitor:
                break

        events: list = []
        if monitor is not None and monitor.qc_handler is not None:
            report = monitor.qc_handler.get_qc_report()
            events = report.get("events", [])
        else:
            jobs_dir = getattr(getattr(trans.app, 'config', None), 'root', None)
            if jobs_dir:
                from pathlib import Path as _Path
                audit_path = (_Path(jobs_dir) / 'database' / 'jobs_directory'
                              / 'nextflow_workflows' / f"workflow_{invocation_id}"
                              / "qc_overrides_audit.jsonl")
                if audit_path.exists():
                    for line in audit_path.read_text().splitlines():
                        try:
                            events.append(_json.loads(line))
                        except Exception:
                            pass

        lines = "\n".join(_json.dumps(e) for e in events)
        return Response(
            content=lines,
            media_type="application/x-ndjson",
            headers={
                "Content-Disposition": f'attachment; filename="qc_audit_{invocation_id}.jsonl"',
            },
        )

    except Exception as e:
        log.error(f"[QC Audit Download] Failed for {invocation_id}: {e}")
        raise HTTPException(status_code=500, detail=f"Failed to download QC audit: {e}")


@router.get("/api/invocations/{invocation_id}/methods-report",
            summary="Download methods report as plain text")
def download_invocation_methods_report(
    invocation_id: str,
    trans: ProvidesUserContext = DependsOnTrans,
):
    """
    Download a plain-text methods report for a workflow invocation.
    Includes run ID, invocation ID, date, tool versions (if available),
    and the QC methods_text paragraph.
    """
    import json as _json
    from datetime import datetime as _datetime
    try:
        from galaxy.jobs.runners.nextflow_monitor import get_monitor_service
        monitor_service = get_monitor_service(trans.app)

        monitor = None
        for key in (invocation_id, int(invocation_id) if invocation_id.isdigit() else None):
            if key is None:
                continue
            monitor = monitor_service.monitors.get(key)
            if monitor:
                break

        methods_text = "No QC events recorded for this invocation."
        tool_versions: dict = {}
        run_id = "n/a"

        if monitor is not None and monitor.qc_handler is not None:
            report = monitor.qc_handler.get_qc_report()
            methods_text = report.get("methods_text", methods_text)
            for event in report.get("events", []):
                tv = event.get("tool_versions") or event.get("versions")
                if tv and isinstance(tv, dict):
                    tool_versions.update(tv)
        else:
            jobs_dir = getattr(getattr(trans.app, 'config', None), 'root', None)
            if jobs_dir:
                from pathlib import Path as _Path
                audit_path = (_Path(jobs_dir) / 'database' / 'jobs_directory'
                              / 'nextflow_workflows' / f"workflow_{invocation_id}"
                              / "qc_overrides_audit.jsonl")
                if audit_path.exists():
                    methods_text = "QC governance applied (see audit log for details)."
                    for line in audit_path.read_text().splitlines():
                        try:
                            event = _json.loads(line)
                            tv = event.get("tool_versions") or event.get("versions")
                            if tv and isinstance(tv, dict):
                                tool_versions.update(tv)
                            if event.get("run_id"):
                                run_id = event["run_id"]
                        except Exception:
                            pass

        # Look up run_id from in-process registry
        if run_id == "n/a":
            with _runs_lock:
                for rid, info in _runs.items():
                    if info.get("invocation_id") == invocation_id:
                        run_id = rid
                        break

        lines = [
            "BioMate AI — Methods Report",
            "=" * 40,
            f"Date:          {_datetime.utcnow().strftime('%Y-%m-%d %H:%M UTC')}",
            f"Invocation ID: {invocation_id}",
            f"Run ID:        {run_id}",
        ]
        if tool_versions:
            lines.append("")
            lines.append("Tool versions:")
            for tool, version in sorted(tool_versions.items()):
                lines.append(f"  {tool}: {version}")
        lines.append("")
        lines.append("Methods:")
        lines.append(methods_text)

        return Response(
            content="\n".join(lines),
            media_type="text/plain",
            headers={
                "Content-Disposition": f'attachment; filename="methods_report_{invocation_id}.txt"',
            },
        )

    except Exception as e:
        log.error(f"[Methods Report] Failed for {invocation_id}: {e}")
        raise HTTPException(status_code=500, detail=f"Failed to generate methods report: {e}")


# ---------------------------------------------------------------------------
# QC Report Export
# ---------------------------------------------------------------------------

class QCReportExportRequest(BaseModel):
    invocation_id: str
    format: str = "html"


def _lookup_work_dir_for_invocation(invocation_id: str) -> Optional[Path]:
    """
    Resolve the Nextflow work directory for a given invocation_id.

    Searches the in-process _runs registry (keyed by run_id) for a run whose
    invocation_id matches.  Returns None if no matching run is found.
    """
    with _runs_lock:
        for run_info in _runs.values():
            if run_info.get("invocation_id") == invocation_id:
                wd = run_info.get("work_dir")
                return Path(wd) if wd else None
    return None


def _build_qc_report_from_jsonl(invocation_id: str, audit_path: Path) -> Dict[str, Any]:
    """
    Reconstruct a minimal QC report from a persisted JSONL audit file.

    The audit file records override/profile initialisation and gate-trigger events.
    It does NOT contain full metric snapshots, so the reconstructed report has
    less detail than the live in-memory version.
    """
    import json as _json

    entries = []
    try:
        for line in audit_path.read_text(errors="replace").splitlines():
            line = line.strip()
            if not line:
                continue
            try:
                entries.append(_json.loads(line))
            except Exception:
                pass
    except OSError:
        pass

    gate_entries = [e for e in entries if e.get("event_type") == "gate_triggered"]
    active_profile = next(
        (e.get("active_profile") for e in entries if e.get("active_profile")), None
    )
    active_overrides = next(
        (e.get("configured_overrides", {}) for e in entries), {}
    )

    events = []
    for e in gate_entries:
        events.append({
            "type": "gate",
            "process_name": e.get("applied_overrides", {}).get("process_name", "unknown"),
            "timestamp": e.get("timestamp", ""),
            "metrics": {},
            "failures": [],
            "suggestions": [],
            "active_profile": e.get("active_profile"),
        })

    return {
        "invocation_id": invocation_id,
        "active_profile": active_profile,
        "active_overrides": active_overrides,
        "gates_triggered": len(gate_entries),
        "warnings_emitted": 0,
        "events": events,
        "methods_text": "QC governance applied (see audit log for details).",
        "source": "audit_jsonl",
    }


def _html_escape(value: Any) -> str:
    """Minimal HTML escaping for values embedded in table cells."""
    s = str(value)
    return (
        s.replace("&", "&amp;")
         .replace("<", "&lt;")
         .replace(">", "&gt;")
         .replace('"', "&quot;")
    )


def _render_qc_report_html(report: Dict[str, Any]) -> str:
    """
    Generate a self-contained HTML QC report from a structured report dict.

    The report dict is the same shape returned by NextflowQCGateHandler.get_qc_report().
    """
    from datetime import datetime as _dt, timezone as _tz

    invocation_id = report.get("invocation_id", "unknown")
    active_profile = report.get("active_profile") or "none"
    active_overrides = report.get("active_overrides", {})
    gates_triggered = report.get("gates_triggered", 0)
    warnings_emitted = report.get("warnings_emitted", 0)
    events = report.get("events", [])
    methods_text = _html_escape(report.get("methods_text", ""))
    source = report.get("source", "unknown")

    generated_at = _dt.now(_tz.utc).strftime("%Y-%m-%d %H:%M:%S UTC")

    # Summary counts
    gate_events = [e for e in events if e.get("type") == "gate"]
    warn_events = [e for e in events if e.get("type") == "warning"]
    total_steps = len(set(e.get("process_name", "") for e in events))
    failed_steps = len(set(e.get("process_name", "") for e in gate_events))
    warning_steps = len(set(e.get("process_name", "") for e in warn_events))
    passed_steps = total_steps - failed_steps

    # Build overrides table rows
    overrides_rows = ""
    if active_overrides:
        for metric, val in sorted(active_overrides.items()):
            overrides_rows += (
                f"<tr><td>{_html_escape(metric)}</td>"
                f"<td>{_html_escape(val)}</td></tr>\n"
            )
    else:
        overrides_rows = '<tr><td colspan="2" class="none">No custom overrides applied</td></tr>'

    # Build per-step event rows
    step_rows = ""
    for event in events:
        etype = event.get("type", "")
        process_name = _html_escape(event.get("process_name", "unknown"))
        timestamp = _html_escape(event.get("timestamp", ""))
        profile_used = _html_escape(event.get("active_profile") or "none")

        if etype == "gate":
            status_cell = '<td class="status-failed">FAILED</td>'
            row_class = "row-failed"
            failures = event.get("failures", [])
            detail_cells = _render_failures_cells(failures)
        elif etype == "warning":
            status_cell = '<td class="status-warning">WARNING</td>'
            row_class = "row-warning"
            warnings_list = event.get("warnings", [])
            detail_cells = _render_warnings_cells(warnings_list)
        else:
            status_cell = '<td class="status-passed">PASSED</td>'
            row_class = "row-passed"
            detail_cells = "<td>-</td><td>-</td><td>-</td><td>-</td>"

        step_rows += (
            f'<tr class="{row_class}">'
            f"<td>{process_name}</td>"
            f"{status_cell}"
            f"<td>{timestamp}</td>"
            f"<td>{profile_used}</td>"
            f"{detail_cells}"
            f"</tr>\n"
        )

    if not step_rows:
        step_rows = (
            '<tr><td colspan="8" class="none">'
            "No QC events recorded — all processes passed automatically."
            "</td></tr>"
        )

    # Build suggestions section (only if any gate events have suggestions)
    suggestions_section = ""
    all_suggestions = []
    for event in gate_events:
        for s in event.get("suggestions", []):
            all_suggestions.append((event.get("process_name", ""), s))

    if all_suggestions:
        sug_rows = ""
        for proc, s in all_suggestions:
            sug_rows += (
                f"<tr>"
                f"<td>{_html_escape(proc)}</td>"
                f"<td>{_html_escape(s.get('parameter', ''))}</td>"
                f"<td>{_html_escape(s.get('currentValue', ''))}</td>"
                f"<td>{_html_escape(s.get('suggestedValue', ''))}</td>"
                f"<td>{_html_escape(s.get('reason', ''))}</td>"
                f"<td>{_html_escape(s.get('confidence', ''))}</td>"
                f"</tr>\n"
            )
        suggestions_section = f"""
        <h2>Parameter Suggestions</h2>
        <table>
          <thead>
            <tr>
              <th>Process</th><th>Parameter</th><th>Current Value</th>
              <th>Suggested Value</th><th>Reason</th><th>Confidence</th>
            </tr>
          </thead>
          <tbody>{sug_rows}</tbody>
        </table>
        """

    html = f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>BioMate QC Report — {_html_escape(invocation_id)}</title>
  <style>
    body {{
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
      font-size: 14px;
      color: #1a1a1a;
      background: #f5f5f5;
      margin: 0;
      padding: 24px;
    }}
    .container {{
      max-width: 1200px;
      margin: 0 auto;
      background: #fff;
      border-radius: 8px;
      box-shadow: 0 1px 4px rgba(0,0,0,0.1);
      padding: 32px;
    }}
    h1 {{
      font-size: 22px;
      font-weight: 700;
      margin: 0 0 4px;
      color: #111;
    }}
    h2 {{
      font-size: 16px;
      font-weight: 600;
      margin: 28px 0 10px;
      border-bottom: 1px solid #e0e0e0;
      padding-bottom: 6px;
      color: #333;
    }}
    .meta {{
      font-size: 12px;
      color: #666;
      margin-bottom: 24px;
    }}
    .meta span {{ margin-right: 18px; }}
    .summary-grid {{
      display: grid;
      grid-template-columns: repeat(4, 1fr);
      gap: 12px;
      margin-bottom: 24px;
    }}
    .summary-card {{
      border-radius: 6px;
      padding: 14px 18px;
      text-align: center;
    }}
    .card-total   {{ background: #f0f4ff; border: 1px solid #c5d3f7; }}
    .card-passed  {{ background: #f0faf4; border: 1px solid #a8d5b8; }}
    .card-failed  {{ background: #fff4f4; border: 1px solid #f5c5c5; }}
    .card-warning {{ background: #fff9ec; border: 1px solid #f5dfa5; }}
    .summary-card .number {{
      font-size: 28px;
      font-weight: 700;
      line-height: 1.2;
    }}
    .summary-card .label {{
      font-size: 11px;
      text-transform: uppercase;
      letter-spacing: 0.05em;
      color: #555;
      margin-top: 2px;
    }}
    table {{
      width: 100%;
      border-collapse: collapse;
      font-size: 13px;
      margin-bottom: 16px;
    }}
    th {{
      background: #f5f5f5;
      text-align: left;
      padding: 8px 10px;
      border: 1px solid #ddd;
      font-weight: 600;
      white-space: nowrap;
    }}
    td {{
      padding: 7px 10px;
      border: 1px solid #e8e8e8;
      vertical-align: top;
    }}
    tr:hover td {{ background: #fafafa; }}
    .row-failed td {{ background: #fff8f8; }}
    .row-warning td {{ background: #fffbf0; }}
    .row-passed td {{ background: #f8fff9; }}
    .status-passed  {{ color: #1a7f3c; font-weight: 600; }}
    .status-failed  {{ color: #b91c1c; font-weight: 600; }}
    .status-warning {{ color: #b45309; font-weight: 600; }}
    .tier-gold   {{ color: #b45309; font-weight: 600; }}
    .tier-silver {{ color: #64748b; font-weight: 600; }}
    .tier-bronze {{ color: #92400e; font-weight: 600; }}
    .advisory    {{ color: #6d4c41; font-style: italic; }}
    .methods-box {{
      background: #f8faff;
      border: 1px solid #d0d9f0;
      border-radius: 6px;
      padding: 14px 18px;
      font-size: 13px;
      line-height: 1.6;
      margin-bottom: 24px;
    }}
    .overrides-small {{
      font-size: 12px;
      color: #555;
    }}
    .none {{
      color: #888;
      font-style: italic;
    }}
    .footer {{
      margin-top: 32px;
      padding-top: 14px;
      border-top: 1px solid #e8e8e8;
      font-size: 11px;
      color: #999;
      text-align: center;
    }}
    .badge {{
      display: inline-block;
      padding: 1px 7px;
      border-radius: 9px;
      font-size: 10px;
      font-weight: 600;
      text-transform: uppercase;
      letter-spacing: 0.04em;
    }}
    .badge-source {{
      background: #e8f0fe;
      color: #1a73e8;
    }}
  </style>
</head>
<body>
<div class="container">

  <h1>BioMate QC Governance Report</h1>
  <div class="meta">
    <span><strong>Invocation ID:</strong> {_html_escape(invocation_id)}</span>
    <span><strong>Generated:</strong> {generated_at}</span>
    <span><strong>QC Profile:</strong> {_html_escape(active_profile)}</span>
    <span><span class="badge badge-source">{_html_escape(source)}</span></span>
  </div>

  <h2>Summary</h2>
  <div class="summary-grid">
    <div class="summary-card card-total">
      <div class="number">{total_steps}</div>
      <div class="label">Total Steps with QC Events</div>
    </div>
    <div class="summary-card card-passed">
      <div class="number">{passed_steps}</div>
      <div class="label">Passed Steps</div>
    </div>
    <div class="summary-card card-failed">
      <div class="number">{failed_steps}</div>
      <div class="label">Failed Steps</div>
    </div>
    <div class="summary-card card-warning">
      <div class="number">{warning_steps + warnings_emitted}</div>
      <div class="label">Advisory Warnings</div>
    </div>
  </div>

  <h2>Methods Summary</h2>
  <div class="methods-box">{methods_text}</div>

  <h2>Per-Step QC Gate Results</h2>
  <table>
    <thead>
      <tr>
        <th>Process Name</th>
        <th>Status</th>
        <th>Timestamp</th>
        <th>Profile</th>
        <th>Metric</th>
        <th>Value</th>
        <th>Threshold</th>
        <th>Tier</th>
      </tr>
    </thead>
    <tbody>
      {step_rows}
    </tbody>
  </table>

  {suggestions_section}

  <h2>Active Threshold Overrides</h2>
  <table class="overrides-small">
    <thead>
      <tr><th>Metric</th><th>Override Value</th></tr>
    </thead>
    <tbody>
      {overrides_rows}
    </tbody>
  </table>

  <div class="footer">
    Generated by BioMate QC Governance Engine &mdash;
    <a href="https://biomate.ai" style="color:#999;">biomate.ai</a>
  </div>

</div>
</body>
</html>"""

    return html


def _render_failures_cells(failures: list) -> str:
    """Render the Metric / Value / Threshold / Tier table cells for gate failures."""
    if not failures:
        return "<td>-</td><td>-</td><td>-</td><td>-</td>"

    metric_parts, value_parts, threshold_parts, tier_parts = [], [], [], []
    for f in failures:
        metric = _html_escape(f.get("metric", ""))
        value = _html_escape(f.get("value", ""))
        threshold = _html_escape(f.get("threshold", ""))
        tier = _html_escape(f.get("tier", f.get("severity", "")))
        advisory = f.get("advisory", False)
        msg = _html_escape(f.get("message", ""))

        tier_class = ""
        if "GOLD" in tier.upper():
            tier_class = "tier-gold"
        elif "SILVER" in tier.upper():
            tier_class = "tier-silver"
        elif "BRONZE" in tier.upper():
            tier_class = "tier-bronze"

        adv_note = ' <span class="advisory">(advisory)</span>' if advisory else ""

        metric_parts.append(f"{metric}{adv_note}")
        value_parts.append(str(value))
        threshold_parts.append(f"{threshold} &mdash; {msg}" if msg else str(threshold))
        tier_parts.append(f'<span class="{tier_class}">{tier}</span>' if tier_class else tier)

    sep = "<br>"
    return (
        f"<td>{sep.join(metric_parts)}</td>"
        f"<td>{sep.join(value_parts)}</td>"
        f"<td>{sep.join(threshold_parts)}</td>"
        f"<td>{sep.join(tier_parts)}</td>"
    )


def _render_warnings_cells(warnings: list) -> str:
    """Render the Metric / Value / Threshold / Tier table cells for near-threshold warnings."""
    if not warnings:
        return "<td>-</td><td>-</td><td>-</td><td>-</td>"

    metric_parts, value_parts, threshold_parts, tier_parts = [], [], [], []
    for w in warnings:
        metric = _html_escape(w.get("metric", ""))
        value = _html_escape(w.get("value", ""))
        threshold = _html_escape(w.get("threshold", ""))
        severity = _html_escape(w.get("severity", "near_threshold"))
        msg = _html_escape(w.get("message", ""))

        metric_parts.append(metric)
        value_parts.append(str(value))
        threshold_parts.append(f"{threshold} &mdash; {msg}" if msg else str(threshold))
        tier_parts.append(severity)

    sep = "<br>"
    return (
        f"<td>{sep.join(metric_parts)}</td>"
        f"<td>{sep.join(value_parts)}</td>"
        f"<td>{sep.join(threshold_parts)}</td>"
        f"<td>{sep.join(tier_parts)}</td>"
    )


@router.post(
    "/api/export/qc_report",
    summary="Export QC governance report as HTML",
    response_class=HTMLResponse,
)
def export_qc_report(
    request: QCReportExportRequest,
) -> HTMLResponse:
    """
    Generate and return an HTML QC governance report for a workflow invocation.

    Lookup order:
      1. In-memory QC handler registry (_qc_handlers) — populated when the workflow
         is launched via POST /api/nextflow/execute.
      2. Persisted JSONL audit log at <work_dir>/qc_overrides_audit.jsonl — used when
         the handler has been evicted or the process was launched in a previous session.

    Accepted formats: "html" (only format supported in v1).

    Returns Content-Type: text/html.
    """
    invocation_id = request.invocation_id.strip()
    fmt = (request.format or "html").lower()

    if fmt != "html":
        raise HTTPException(
            status_code=422,
            detail=f"Unsupported format '{fmt}'. Only 'html' is supported.",
        )

    if not invocation_id:
        raise HTTPException(status_code=422, detail="invocation_id must not be empty.")

    report: Optional[Dict[str, Any]] = None

    # --- Path 1: live in-memory handler ---
    with _qc_handlers_lock:
        handler = _qc_handlers.get(invocation_id)

    if handler is not None:
        try:
            report = handler.get_qc_report()
            report["source"] = "live_handler"
        except Exception as exc:
            log.warning(f"[QC Export] Failed to get report from live handler: {exc}")

    # --- Path 2: persisted JSONL audit file ---
    if report is None:
        work_dir = _lookup_work_dir_for_invocation(invocation_id)
        if work_dir is not None:
            audit_path = work_dir / "qc_overrides_audit.jsonl"
            if audit_path.exists():
                report = _build_qc_report_from_jsonl(invocation_id, audit_path)

    # --- Path 3: empty report (no QC data recorded yet) ---
    if report is None:
        report = {
            "invocation_id": invocation_id,
            "active_profile": None,
            "active_overrides": {},
            "gates_triggered": 0,
            "warnings_emitted": 0,
            "events": [],
            "methods_text": (
                "No QC events have been recorded for this invocation. "
                "The workflow may still be running, or QC monitoring was not enabled."
            ),
            "source": "not_found",
        }

    try:
        html_content = _render_qc_report_html(report)
    except Exception as exc:
        log.error(f"[QC Export] HTML rendering failed for {invocation_id}: {exc}")
        raise HTTPException(status_code=500, detail=f"HTML rendering failed: {exc}")

    return HTMLResponse(content=html_content, status_code=200)


# ---------------------------------------------------------------------------
# Pipeline Manifest
# ---------------------------------------------------------------------------

@router.get(
    "/api/nextflow/invocations/{invocation_id}/manifest",
    summary="Get pipeline output manifest for a completed invocation",
)
def get_invocation_manifest(
    invocation_id: str,
    trans: ProvidesUserContext = DependsOnTrans,
) -> Dict[str, Any]:
    """
    Return the workflow_outputs.json manifest written by the PIPELINE_MANIFEST
    Nextflow process at pipeline completion.

    Returns 404 if the invocation is unknown or the manifest file has not yet
    been written (pipeline still running / manifest step not reached).
    """
    import json as _json

    # Locate outdir for this invocation from the in-process run registry
    outdir: Optional[Path] = None
    with _runs_lock:
        for run_info in _runs.values():
            if run_info.get("invocation_id") == invocation_id:
                raw = run_info.get("outdir")
                outdir = Path(raw) if raw else None
                break

    if outdir is None:
        raise HTTPException(
            status_code=404,
            detail=f"Invocation '{invocation_id}' not found.",
        )

    manifest_path = outdir / "workflow_outputs.json"
    if not manifest_path.exists():
        raise HTTPException(
            status_code=404,
            detail=(
                f"Manifest not yet available for invocation '{invocation_id}'. "
                "The pipeline may still be running or the PIPELINE_MANIFEST step has not completed."
            ),
        )

    try:
        manifest = _json.loads(manifest_path.read_text())
    except Exception as exc:
        log.error(f"[Manifest] Failed to read manifest for {invocation_id}: {exc}")
        raise HTTPException(status_code=500, detail=f"Failed to read manifest: {exc}")

    return manifest


# ---------------------------------------------------------------------------
# CryoSPARC direct execution routes
# ---------------------------------------------------------------------------

class CryoSPARCExecuteRequest(BaseModel):
    parameters: Optional[Dict[str, Any]] = None
    user_id: Optional[str] = None
    history_id: Optional[str] = None
    license_key: Optional[str] = None  # overrides CRYOSPARC_LICENSE env var for this run


@router.post("/api/cryosparc/execute", summary="Launch a real CryoSPARC SPA pipeline")
def execute_cryosparc(
    request: CryoSPARCExecuteRequest,
) -> Dict[str, Any]:
    """
    Submit a CryoSPARC SPA job on the dedicated GPU instance (us-east-1).
    Starts the EC2 instance automatically if stopped (~3-5 min cold start).
    Returns run_id immediately; execution continues in a background thread.

    Required parameter: movie_dir — path to EER/TIFF/MRC movies on the CryoSPARC host.
    Optional parameters: pixel_size, voltage, cs, amplitude_contrast, particle_diameter,
                         symmetry, num_movies, total_dose.
    """
    try:
        from galaxy.webapps.galaxy.api import cryosparc_executor as cs_exec
    except ImportError as exc:
        raise HTTPException(status_code=503, detail=f"CryoSPARC executor not available: {exc}")

    run_id = str(uuid.uuid4())
    params = dict(request.parameters or {})

    cs_exec.execute_spa_pipeline(
        run_id=run_id,
        params=params,
        user_id=request.user_id or "",
        license_key=request.license_key or "",
    )

    log.info("[CryoSPARC Route] Queued run %s with params %s", run_id, list(params.keys()))

    return {
        "success": True,
        "run_id": run_id,
        "invocation_id": run_id,
        "executor": "cryosparc",
        "message": "CryoSPARC SPA pipeline queued — GPU instance starting if stopped",
    }


@router.get("/api/cryosparc/status/{run_id}", summary="Get CryoSPARC run status")
def get_cryosparc_status(run_id: str) -> Dict[str, Any]:
    """Return current status of a CryoSPARC run."""
    try:
        from galaxy.webapps.galaxy.api import cryosparc_executor as cs_exec
    except ImportError as exc:
        raise HTTPException(status_code=503, detail=f"CryoSPARC executor not available: {exc}")

    status = cs_exec.get_run_status(run_id)
    if status is None:
        raise HTTPException(status_code=404, detail=f"CryoSPARC run not found: {run_id}")

    return status


# ---------------------------------------------------------------------------
# Index health check
# ---------------------------------------------------------------------------

@router.get("/api/admin/index-health", summary="Workflow index health by source")
def get_index_health() -> Dict[str, Any]:
    """Returns workflow index counts by source and staleness flags.

    A source is considered stale if its most-recent ``indexed_at`` timestamp
    is older than 7 days (or if no ``indexed_at`` value exists).
    """
    import sqlite3 as _sqlite3
    from datetime import datetime as _dt, timedelta as _td

    stale_threshold = _dt.utcnow() - _td(days=7)
    db_path = Path(__file__).resolve().parents[5] / "database" / "galaxy_ai_tools.db"

    if not db_path.exists():
        raise HTTPException(status_code=503, detail=f"Workflow database not found at {db_path}")

    try:
        conn = _sqlite3.connect(str(db_path))
        rows = conn.execute(
            "SELECT source, COUNT(*), MAX(indexed_at) FROM workflows GROUP BY source ORDER BY COUNT(*) DESC"
        ).fetchall()
        conn.close()
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"DB query failed: {exc}")

    sources = []
    any_stale = False
    for source, count, last_indexed in rows:
        if last_indexed:
            try:
                last_dt = _dt.fromisoformat(last_indexed.replace("Z", "+00:00").replace("+00:00", ""))
            except ValueError:
                last_dt = None
        else:
            last_dt = None

        is_stale = (last_dt is None) or (last_dt < stale_threshold)
        if is_stale:
            any_stale = True

        sources.append({
            "source": source,
            "count": count,
            "last_indexed": last_indexed,
            "is_stale": is_stale,
        })

    return {
        "sources": sources,
        "total": sum(s["count"] for s in sources),
        "health": "stale" if any_stale else "ok",
        "stale_threshold_days": 7,
        "checked_at": _dt.utcnow().isoformat() + "Z",
    }


# ---------------------------------------------------------------------------
# C1 — Preflight with pilot_analysis detection
# ---------------------------------------------------------------------------

class PreflightRequest(BaseModel):
    workflow_path: Optional[str] = None
    workflow_name: Optional[str] = None
    parameters: Optional[Dict[str, Any]] = None
    input_files: Optional[List[str]] = None
    required_params: Optional[List[Dict[str, Any]]] = None


def _detect_pilot_analyzers(input_files: List[str]) -> List[Dict[str, Any]]:
    """Return pilot analyzers applicable to the given input files based on extension."""
    from galaxy.ai.pilot_analysis.registry import PILOT_ANALYZERS

    ext_map: Dict[str, List[str]] = {}
    for f in input_files:
        ext = Path(f).suffix.lower().lstrip(".")
        ext_map.setdefault(ext, []).append(f)

    applicable = []
    seen: set = set()
    for name, spec in PILOT_ANALYZERS.items():
        required_type = spec.get("input_type", "")
        if required_type in ext_map and name not in seen:
            seen.add(name)
            applicable.append({
                "name": name,
                "description": spec.get("description", ""),
                "input_type": required_type,
                "runtime_estimate": spec.get("runtime_estimate", "~30s"),
                "max_runtime_seconds": spec.get("max_runtime_seconds", 60),
                "category": spec.get("category", "general"),
                "matched_files": ext_map[required_type],
            })
    return applicable


# C2 — File-type-based parameter suggestion table
# Maps file extension (or normalized type) → list of parameter suggestions.
# Each suggestion: {param_id, suggested_value, confidence, rationale}
_FILE_TYPE_PARAM_SUGGESTIONS: Dict[str, List[Dict[str, Any]]] = {
    # FASTQ / gzipped FASTQ
    "fastq": [
        {"param_id": "strandedness", "suggested_value": "auto", "confidence": 0.7,
         "rationale": "Auto-detect strandedness is recommended for FASTQ inputs unless library prep is known"},
        {"param_id": "skip_fastqc", "suggested_value": False, "confidence": 0.8,
         "rationale": "FastQC QC is always recommended for FASTQ data"},
    ],
    "fq": [
        {"param_id": "strandedness", "suggested_value": "auto", "confidence": 0.7,
         "rationale": "Auto-detect strandedness is recommended for FASTQ inputs"},
    ],
    "gz": [  # handles .fastq.gz / .fq.gz
        {"param_id": "strandedness", "suggested_value": "auto", "confidence": 0.65,
         "rationale": "Likely compressed FASTQ — auto-detecting strandedness recommended"},
    ],
    # BAM / CRAM
    "bam": [
        {"param_id": "skip_alignment", "suggested_value": True, "confidence": 0.9,
         "rationale": "Input is already aligned (BAM) — skip re-alignment step"},
        {"param_id": "aligner", "suggested_value": None, "confidence": 0.85,
         "rationale": "BAM is pre-aligned; aligner choice is not needed"},
    ],
    "cram": [
        {"param_id": "skip_alignment", "suggested_value": True, "confidence": 0.9,
         "rationale": "CRAM is a pre-aligned format — skip re-alignment"},
    ],
    # VCF
    "vcf": [
        {"param_id": "variant_caller", "suggested_value": "gatk", "confidence": 0.6,
         "rationale": "VCF files are typically from GATK or compatible callers"},
    ],
    # CSV / sample sheet
    "csv": [
        {"param_id": "input", "suggested_value": "<uploaded CSV>", "confidence": 0.8,
         "rationale": "CSV files are commonly used as nf-core sample sheets — set --input to this file"},
        {"param_id": "samplesheet", "suggested_value": "<uploaded CSV>", "confidence": 0.75,
         "rationale": "This CSV file may be the samplesheet for the workflow"},
    ],
    # FASTA
    "fasta": [
        {"param_id": "fasta", "suggested_value": "<uploaded FASTA>", "confidence": 0.8,
         "rationale": "FASTA file detected — likely the reference genome or sequence input"},
    ],
    "fa": [
        {"param_id": "fasta", "suggested_value": "<uploaded FASTA>", "confidence": 0.75,
         "rationale": "FASTA file detected — commonly used as reference or sequence input"},
    ],
    # H5AD (single-cell)
    "h5ad": [
        {"param_id": "input_format", "suggested_value": "h5ad", "confidence": 0.95,
         "rationale": "H5AD is AnnData format — standard for single-cell workflows"},
        {"param_id": "normalization_method", "suggested_value": "scran", "confidence": 0.6,
         "rationale": "Scran normalization is recommended for scRNA-seq data"},
    ],
    # MRC (Cryo-EM)
    "mrc": [
        {"param_id": "pixel_size", "suggested_value": None, "confidence": 0.5,
         "rationale": "MRC micrograph detected — pixel size (Å/pixel) is required"},
        {"param_id": "microscope_voltage", "suggested_value": 300, "confidence": 0.6,
         "rationale": "Most modern cryo-EM data is acquired at 300 kV"},
    ],
    # PDB (structural biology)
    "pdb": [
        {"param_id": "structure_file", "suggested_value": "<uploaded PDB>", "confidence": 0.9,
         "rationale": "PDB file is the protein structure input"},
    ],
}


def _infer_param_suggestions(input_files: List[str]) -> List[Dict[str, Any]]:
    """
    Return parameter suggestions derived purely from file extensions (no tool execution).
    This is C2 Phase 1: fast, zero-cost heuristic suggestions.
    """
    suggestions: List[Dict[str, Any]] = []
    seen_params: set = set()
    for f in input_files:
        fname = Path(f).name.lower()
        # Handle double extensions like .fastq.gz
        if fname.endswith(".fastq.gz") or fname.endswith(".fq.gz"):
            ext = "fastq"
        else:
            ext = Path(f).suffix.lower().lstrip(".")
        for suggestion in _FILE_TYPE_PARAM_SUGGESTIONS.get(ext, []):
            pid = suggestion["param_id"]
            if pid not in seen_params:
                seen_params.add(pid)
                suggestions.append({**suggestion, "source_file": Path(f).name})
    return suggestions


@router.post("/api/workflows/preflight", summary="Pre-flight validation with pilot analysis detection")
def workflow_preflight(request: PreflightRequest) -> Dict[str, Any]:
    """Three-phase preflight check plus pilot-analysis detector.

    Phases:
      1. parameters  — all required params present
      2. inputs      — input file types recognised; applicable pilot analyzers listed
      3. structure   — workflow path resolvable or known in catalog
    """
    phases: List[Dict[str, Any]] = []
    params = request.parameters or {}
    input_files = request.input_files or []
    required = request.required_params or []

    # Phase 1 — required parameters
    missing = [
        p.get("id") or p.get("name")
        for p in required
        if not (params.get(p.get("id") or p.get("name") or ""))
    ]
    phases.append({
        "id": "parameters",
        "status": "pass" if not missing else "fail",
        "message": (
            "All required parameters present"
            if not missing
            else f"Missing required parameters: {', '.join(str(m) for m in missing)}"
        ),
    })

    # Phase 2 — input files + pilot analysis detection + C2 parameter suggestions
    try:
        applicable = _detect_pilot_analyzers(input_files) if input_files else []
        total_est = sum(a["max_runtime_seconds"] for a in applicable)
        # C2: infer parameter suggestions from file types (no tool execution needed)
        param_suggestions = _infer_param_suggestions(input_files) if input_files else []
        phases.append({
            "id": "inputs",
            "status": "pass",
            "message": (
                f"Input files recognised — {len(applicable)} pilot analyzer(s) available"
                if applicable
                else "Input file types checked (no pilot analyzers matched)"
            ),
            "applicable_analyzers": applicable,
            "estimated_characterization_seconds": total_est,
            "parameter_suggestions": param_suggestions,
        })
    except Exception as exc:
        log.warning("preflight: pilot analyzer detection failed: %s", exc)
        phases.append({
            "id": "inputs",
            "status": "pass",
            "message": "Input file accessibility check complete",
            "applicable_analyzers": [],
            "parameter_suggestions": [],
        })

    # Phase 3 — workflow structure
    wf_path = request.workflow_path or ""
    path_ok = bool(wf_path) and Path(wf_path).exists() if wf_path else False
    if not wf_path:
        phases.append({
            "id": "structure",
            "status": "pass",
            "message": "Workflow structure valid (no path provided — catalog workflow)",
        })
    elif path_ok:
        phases.append({
            "id": "structure",
            "status": "pass",
            "message": f"Workflow path exists: {wf_path}",
        })
    else:
        phases.append({
            "id": "structure",
            "status": "warn",
            "message": f"Workflow path not found locally (may be remote): {wf_path}",
        })

    ready = all(p["status"] in ("pass", "warn") for p in phases) and all(
        p["status"] == "pass" for p in phases if p["id"] == "parameters"
    )
    return {"phases": phases, "ready": ready}


# ---------------------------------------------------------------------------
# D1 — Pre-run cost estimation
# ---------------------------------------------------------------------------

# AWS Batch on-demand instance cost table (USD/hr, approximate 2026 rates)
_BATCH_INSTANCE_COST_PER_HOUR: Dict[str, float] = {
    "c5.xlarge": 0.17,
    "c5.2xlarge": 0.34,
    "c5.4xlarge": 0.68,
    "c5.9xlarge": 1.53,
    "c5.18xlarge": 3.06,
    "r5.xlarge": 0.252,
    "r5.2xlarge": 0.504,
    "r5.4xlarge": 1.008,
    "r5.8xlarge": 2.016,
    "m5.xlarge": 0.192,
    "m5.2xlarge": 0.384,
    "m5.4xlarge": 0.768,
    "m5.8xlarge": 1.536,
    "g4dn.xlarge": 0.526,
    "g4dn.2xlarge": 0.752,
    "g4dn.4xlarge": 1.204,
}

# Rough domain → typical instance + hours range mapping
_DOMAIN_RUNTIME_HINTS: Dict[str, Dict[str, Any]] = {
    "rnaseq":     {"instance": "c5.4xlarge",  "min_h": 0.5, "max_h": 2.0},
    "chipseq":    {"instance": "c5.4xlarge",  "min_h": 1.0, "max_h": 4.0},
    "atacseq":    {"instance": "c5.2xlarge",  "min_h": 0.5, "max_h": 3.0},
    "sarek":      {"instance": "c5.9xlarge",  "min_h": 4.0, "max_h": 12.0},
    "scrnaseq":   {"instance": "r5.4xlarge",  "min_h": 1.0, "max_h": 6.0},
    "methylseq":  {"instance": "c5.9xlarge",  "min_h": 2.0, "max_h": 8.0},
    "cryoem":     {"instance": "g4dn.4xlarge","min_h": 2.0, "max_h": 8.0},
    "cryosparc":  {"instance": "g4dn.4xlarge","min_h": 1.0, "max_h": 6.0},
    "proteomics": {"instance": "c5.4xlarge",  "min_h": 0.5, "max_h": 2.0},
    "metagenomics":{"instance": "r5.4xlarge", "min_h": 2.0, "max_h": 10.0},
    "alphafold":  {"instance": "g4dn.4xlarge","min_h": 4.0, "max_h": 24.0},
    "default":    {"instance": "c5.2xlarge",  "min_h": 0.5, "max_h": 3.0},
}


class CostEstimateRequest(BaseModel):
    nextflow_path: Optional[str] = None
    workflow_name: Optional[str] = None
    params: Optional[Dict[str, Any]] = None


@router.post("/api/workflows/estimate_cost", summary="Estimate AWS Batch run cost before execution")
def estimate_workflow_cost(request: CostEstimateRequest) -> Dict[str, Any]:
    """Static pre-run cost estimate based on workflow domain and typical runtimes.

    Returns min/max USD range and assumptions used.
    """
    path = (request.nextflow_path or request.workflow_name or "").lower()

    # Pick domain hint by longest keyword match on path/name (more specific wins)
    hint = _DOMAIN_RUNTIME_HINTS["default"]
    best_len = 0
    for domain, h in _DOMAIN_RUNTIME_HINTS.items():
        if domain != "default" and domain in path and len(domain) > best_len:
            hint = h
            best_len = len(domain)

    instance = hint["instance"]
    cost_per_hour = _BATCH_INSTANCE_COST_PER_HOUR.get(instance, 0.34)
    min_cost = round(hint["min_h"] * cost_per_hour, 2)
    max_cost = round(hint["max_h"] * cost_per_hour * 1.15, 2)  # 15% buffer

    # Try to pull runtime_estimate from pilot_analysis registry for known tools
    try:
        from galaxy.ai.pilot_analysis.registry import PILOT_ANALYZERS
        relevant = [
            a for a in PILOT_ANALYZERS.values()
            if a.get("category", "") in path or path in a.get("category", "")
        ]
        if relevant:
            max_analyzer_s = max(a.get("max_runtime_seconds", 60) for a in relevant)
            if max_analyzer_s > 300:
                max_cost = round(max_cost * 1.3, 2)
    except Exception:
        pass

    return {
        "min_usd": min_cost,
        "max_usd": max_cost,
        "instance_type": instance,
        "cost_per_hour_usd": cost_per_hour,
        "assumptions": [
            f"Instance type: {instance} (${cost_per_hour:.3f}/hr on-demand)",
            f"Estimated runtime: {hint['min_h']:.1f}–{hint['max_h']:.1f} hours",
            "Does not include S3 data transfer costs (~$0.09/GB egress)",
            "AWS Spot pricing may reduce cost by 60–80%",
        ],
    }


# ---------------------------------------------------------------------------
# C3 — nf-core test profile runner
# ---------------------------------------------------------------------------

class ValidateProfileRequest(BaseModel):
    nextflow_path: str
    profile: Optional[str] = "test"
    timeout_seconds: Optional[int] = 300


@router.post("/api/workflows/validate_profile", summary="Validate pipeline runs with nf-core test profile")
def validate_workflow_profile(request: ValidateProfileRequest) -> Dict[str, Any]:
    """Run ``nextflow run {path} -profile test,docker`` on the smallest Batch
    instance to confirm the pipeline environment works end-to-end.

    Returns:
        status: "pass" | "fail" | "timeout" | "skipped"
        message: Human-readable summary
        log_tail: Last 20 lines of stdout/stderr
        duration_seconds: Actual wall time used
    """
    nf_path = request.nextflow_path.strip()
    if not nf_path:
        raise HTTPException(status_code=400, detail="nextflow_path is required")

    profile = request.profile or "test"
    timeout = min(max(int(request.timeout_seconds or 300), 30), 600)

    # Safety: only allow test/docker/singularity profiles; never run user data
    safe_profiles = {"test", "docker", "singularity", "podman", "conda", "test_full", "test_cache"}
    profile_parts = {p.strip() for p in profile.split(",")}
    if not profile_parts.issubset(safe_profiles):
        raise HTTPException(
            status_code=400,
            detail=f"Only safe profiles allowed: {safe_profiles}. Got: {profile_parts - safe_profiles}",
        )

    # Resolve pipeline path
    resolved_path = nf_path
    if not Path(nf_path).exists():
        # Try known nf-core local paths
        base = Path(__file__).resolve().parents[5] / "nf-core-workflows"
        pipeline_name = nf_path.split("/")[-1].replace("nf-core/", "")
        candidate = base / pipeline_name
        if candidate.exists():
            resolved_path = str(candidate)
        # Otherwise pass through as remote (nf-core/<name>) and let Nextflow resolve

    import time as _time
    cmd = ["nextflow", "run", resolved_path, f"-profile", profile, "--outdir", "/tmp/biomate_test_run"]
    start = _time.time()
    log_lines: List[str] = []
    status = "pass"
    message = ""

    try:
        proc = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
        duration = round(_time.time() - start, 1)
        combined_output = (proc.stdout or "") + (proc.stderr or "")
        log_lines = combined_output.splitlines()[-20:]

        if proc.returncode == 0:
            status = "pass"
            message = f"Pipeline environment validated in {duration}s — runs end-to-end"
        else:
            status = "fail"
            # Extract first error line from Nextflow output
            err_line = next(
                (l for l in combined_output.splitlines() if "ERROR" in l or "error" in l.lower()),
                f"Exit code {proc.returncode}"
            )
            message = f"Validation failed: {err_line[:200]}"

    except subprocess.TimeoutExpired:
        duration = timeout
        status = "timeout"
        message = f"Validation timed out after {timeout}s — pipeline may require more resources"
    except FileNotFoundError:
        duration = 0.0
        status = "skipped"
        message = "Nextflow binary not found — cannot validate profile locally"
    except Exception as exc:
        duration = round(_time.time() - start, 1)
        status = "fail"
        message = f"Unexpected error: {exc}"

    return {
        "status": status,
        "message": message,
        "log_tail": log_lines,
        "duration_seconds": duration,
        "profile_used": profile,
        "nextflow_path": nf_path,
    }
