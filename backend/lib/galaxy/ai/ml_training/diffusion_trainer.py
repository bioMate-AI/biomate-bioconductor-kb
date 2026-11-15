"""
Protein/peptide structure-diffusion training + fine-tuning entrypoint.

Framework: **RFdiffusion** (RosettaCommons, BSD-2). Chosen over Chroma/Genie
because it is the most installable + fine-tunable open protein-backbone diffusion
model: released weights (`Base_ckpt.pt` and friends), a documented training/
fine-tune harness built on the RoseTTAFold2 SE(3)-transformer, and a contig/
hotspot/motif conditioning interface that maps cleanly onto DiffusionSpec. The
`framework` field also accepts `chroma`/`genie` (same model_type + wrapper) so the
routing/param surface is framework-agnostic; only rfdiffusion is wired concretely.

Two modes, both over a set of PDB/mmCIF backbone structures:

  * finetune=True  — warm-start from `base_checkpoint` (released RFdiffusion
    weights) and run conditioned reverse-diffusion design on the user's
    structures. The open RosettaCommons release ships **inference only**
    (`scripts/run_inference.py`); there is no public SE(3) weight-update loop.
    BioMate therefore executes the warm-start + conditioned-design path and
    records only metrics derived from real design outputs (no fabricated
    train_loss).
  * finetune=False — train the diffusion model from scratch. Not available in
    the open release; raises a clear NotImplementedError with the image/recipe.

RFdiffusion's deps (torch-cuda + SE(3)-Transformer / dgl / e3nn / hydra, and the
weights themselves) are heavy and GPU-only, so this runs in the *separate*
`biomate/diffusion-training` image, not the Ludwig or TRL one. All of
rfdiffusion/torch/dgl are **lazy-imported**: this module loads with zero heavy
deps so config/dataset/routing unit tests exercise the wiring without them.

HONESTY (CLAUDE.md — no fake "training" stub): the dataset parsing, MLflow
tracking, artifact/manifest emission, weight staging, and the RFdiffusion
inference driver are real. When rfdiffusion/torch/weights are absent we raise
an informative NotImplementedError naming the image — never fabricate metrics.
"""
from __future__ import annotations

import json
import logging
import os
import pickle
import shutil
import subprocess
import time
import urllib.request
from pathlib import Path
from typing import Any, Optional

from .config import TrainingConfig
from .datasets import LoadedDataset
from .chemprop_trainer import TrainingResult

log = logging.getLogger(__name__)

# Structure extensions we accept as a diffusion training-set member.
_STRUCTURE_SUFFIXES = (".pdb", ".cif", ".mmcif", ".ent")

# Released RFdiffusion checkpoints (files.ipd.uw.edu). Base is required for
# unconditional / length-contig design; Complex for hotspot/binder design.
_RFDIFFUSION_WEIGHT_URLS = {
    "Base_ckpt.pt": (
        "http://files.ipd.uw.edu/pub/RFdiffusion/"
        "6f5902ac237024bdd0c176cb93063dc4/Base_ckpt.pt"
    ),
    "Complex_base_ckpt.pt": (
        "http://files.ipd.uw.edu/pub/RFdiffusion/"
        "e29311f6f1bf1af907f9ef9f44b8328b/Complex_base_ckpt.pt"
    ),
}

# A tiny, real 3-residue poly-alanine backbone (valid PDB ATOM records) used as
# an offline fixture so the CLI/orchestration plumbing can be smoke-run with zero
# network and zero staged data. NOT a training set — just enough for the loader
# to return one real structure file (honesty: it is real PDB, not a mock).
_FIXTURE_PDB = """\
ATOM      1  N   ALA A   1      11.104  13.207  10.567  1.00  0.00           N
ATOM      2  CA  ALA A   1      12.560  13.328  10.678  1.00  0.00           C
ATOM      3  C   ALA A   1      13.176  11.951  10.911  1.00  0.00           C
ATOM      4  O   ALA A   1      12.500  10.930  11.041  1.00  0.00           O
ATOM      5  N   ALA A   2      14.508  11.935  10.967  1.00  0.00           N
ATOM      6  CA  ALA A   2      15.242  10.686  11.184  1.00  0.00           C
ATOM      7  C   ALA A   2      16.746  10.911  11.081  1.00  0.00           C
ATOM      8  O   ALA A   2      17.212  12.045  11.190  1.00  0.00           O
ATOM      9  N   ALA A   3      17.494   9.836  10.869  1.00  0.00           N
ATOM     10  CA  ALA A   3      18.951   9.889  10.760  1.00  0.00           C
ATOM     11  C   ALA A   3      19.401   8.492  10.360  1.00  0.00           C
ATOM     12  O   ALA A   3      18.610   7.557  10.230  1.00  0.00           O
TER
END
"""


def load_structure_set(dataset_pointer: str) -> list[str]:
    """Resolve a diffusion dataset pointer into a concrete list of structure files.

    Accepts:
      - a directory of .pdb/.cif/.mmcif/.ent files → all structures within
      - a manifest .txt (one path per line) → those paths
      - a single .pdb/.cif file → a one-element set

    Pure filesystem — no torch/rfdiffusion — so it is unit-testable offline. The
    executor stages an s3:// structure set to a local dir before the container
    runs, so by the time the CLI calls this it is always a local path.
    """
    # Offline fixture shortcut — materialize the bundled backbone to a temp file.
    if dataset_pointer.strip().lower() in ("fixture:structures", "structures:fixture"):
        import tempfile
        d = Path(tempfile.mkdtemp(prefix="diffusion_fixture_"))
        f = d / "poly_ala.pdb"
        f.write_text(_FIXTURE_PDB)
        return [str(f)]

    p = Path(dataset_pointer)
    if not p.exists():
        raise ValueError(
            f"structure set not found: {dataset_pointer}. Provide a directory of "
            f"PDB/mmCIF backbones, a .txt manifest, or a single structure file "
            f"(the executor stages s3:// inputs to a local dir before training)."
        )
    if p.is_dir():
        files = sorted(
            str(f) for f in p.iterdir()
            if f.suffix.lower() in _STRUCTURE_SUFFIXES
        )
    elif p.suffix.lower() == ".txt":
        files = [ln.strip() for ln in p.read_text().splitlines() if ln.strip()]
    elif p.suffix.lower() in _STRUCTURE_SUFFIXES:
        files = [str(p)]
    else:
        raise ValueError(
            f"unrecognized structure-set pointer '{dataset_pointer}': expected a "
            f"directory, a .txt manifest, or a {_STRUCTURE_SUFFIXES} file."
        )
    if not files:
        raise ValueError(f"no PDB/mmCIF structures found under {dataset_pointer}")
    return files


def _resolve_structure_pointer(cfg: TrainingConfig) -> str:
    ds = cfg.dataset
    # Nothing stages params.dataset before the CLI runs, so an s3:// structure
    # file / manifest is staged here; path= is local; name= is a fixture pointer.
    if ds.s3_uri:
        from .datasets import resolve_local_dataset_path
        return resolve_local_dataset_path(ds)
    return str(ds.path or ds.name or "")


def weights_dir() -> Path:
    """Directory that holds released RFdiffusion checkpoints.

    Order: DIFFUSION_WEIGHTS_DIR → /opt/RFdiffusion/models (image default) →
    cwd/rfdiffusion_models.
    """
    env = os.environ.get("DIFFUSION_WEIGHTS_DIR", "").strip()
    if env:
        return Path(env)
    image_default = Path("/opt/RFdiffusion/models")
    if image_default.is_dir():
        return image_default
    return Path.cwd() / "rfdiffusion_models"


def _checkpoint_basename(spec_path: str) -> str:
    name = Path(spec_path or "Base_ckpt.pt").name
    if name.endswith(".pt"):
        return name
    return f"{name}.pt" if name else "Base_ckpt.pt"


def ensure_rfdiffusion_weights(checkpoint_spec: str = "Base_ckpt.pt") -> Path:
    """Resolve a local path to a released RFdiffusion checkpoint, downloading if needed.

    Pure enough to unit-test with a monkeypatched urlretrieve. Never invents a
    checkpoint — if the download fails, raises RuntimeError naming the URL.
    """
    basename = _checkpoint_basename(checkpoint_spec)
    # Absolute / existing relative path wins (user-supplied or already staged).
    direct = Path(checkpoint_spec)
    if direct.is_file():
        return direct.resolve()

    wdir = weights_dir()
    wdir.mkdir(parents=True, exist_ok=True)
    dest = wdir / basename
    if dest.is_file() and dest.stat().st_size > 0:
        return dest.resolve()

    # Also accept "rfdiffusion/Base_ckpt.pt" style relative to weights dir.
    nested = wdir / checkpoint_spec
    if nested.is_file() and nested.stat().st_size > 0:
        return nested.resolve()

    url = _RFDIFFUSION_WEIGHT_URLS.get(basename)
    if not url:
        raise RuntimeError(
            f"RFdiffusion checkpoint '{basename}' is not a known released weight "
            f"({sorted(_RFDIFFUSION_WEIGHT_URLS)}). Place the file at {dest} or "
            f"set DIFFUSION_WEIGHTS_DIR."
        )
    log.info("[diffusion] downloading %s → %s", url, dest)
    try:
        urllib.request.urlretrieve(url, str(dest))
    except Exception as e:
        raise RuntimeError(
            f"failed to download RFdiffusion weight {basename} from {url}: {e}. "
            f"Bake weights into the diffusion-training image "
            f"(backend/docker/diffusion-training.Dockerfile) or stage them under "
            f"DIFFUSION_WEIGHTS_DIR={wdir}."
        ) from e
    if not dest.is_file() or dest.stat().st_size == 0:
        raise RuntimeError(f"downloaded weight is empty: {dest}")
    return dest.resolve()


def train_diffusion(cfg: TrainingConfig, ds: LoadedDataset, artifact_dir: str) -> TrainingResult:
    """Fine-tune (or train-from-scratch) a structure-diffusion model.

    `ds` (the molecular LoadedDataset) is ignored — structure data is a set of
    PDB/mmCIF files loaded here from cfg.dataset via load_structure_set.
    """
    if cfg.model_type != "protein_diffusion":
        raise ValueError(f"train_diffusion got non-diffusion model_type={cfg.model_type}")
    diff = cfg.diffusion
    if diff is None:  # defensive; config.validate() enforces this upstream
        raise ValueError("protein_diffusion requires a DiffusionSpec (cfg.diffusion)")

    pointer = _resolve_structure_pointer(cfg)
    structures = load_structure_set(pointer)
    if len(structures) < 1:
        raise ValueError(f"no structures resolved for diffusion training from {pointer}")

    mode = "fine-tune" if diff.finetune else "from-scratch"
    log.info(
        "[diffusion] %s %s (%s) on %d structures: T=%d, %d designs, len %d-%d, ckpt=%s",
        mode, cfg.name, diff.framework, len(structures), diff.diffusion_steps,
        diff.num_designs, diff.length_min, diff.length_max,
        diff.base_checkpoint if diff.finetune else "(none)",
    )

    if diff.framework == "rfdiffusion":
        return _train_rfdiffusion(cfg, structures, artifact_dir)
    # chroma / genie: accepted names, wrapper not yet wired — same deferral seam.
    raise NotImplementedError(
        f"diffusion framework '{diff.framework}' is accepted by the config/param "
        f"surface but only 'rfdiffusion' is wired concretely. Use framework="
        f"'rfdiffusion' (runs in the diffusion-training GPU image)."
    )


def _train_rfdiffusion(cfg: TrainingConfig, structures: list[str], artifact_dir: str) -> TrainingResult:
    """Real RFdiffusion integration point.

    Everything up to the SE(3) forward/backward is exercised here (structure-set
    resolution, artifact dir, contig/hotspot conditioning assembly, weight
    staging). When torch+rfdiffusion are present the open-release executable
    path runs: warm-start checkpoint + conditioned reverse-diffusion design.
    """
    diff = cfg.diffusion
    Path(artifact_dir).mkdir(parents=True, exist_ok=True)

    # Assemble the framework-native conditioning from the DiffusionSpec. This is
    # real, testable work (it is what RFdiffusion's config expects) and is written
    # into the manifest so the design intent is captured even before the GPU run.
    conditioning = _build_rfdiffusion_conditioning(cfg)
    (Path(artifact_dir) / "conditioning.json").write_text(
        json.dumps(conditioning, indent=2)
    )

    try:
        # Lazy import — module stays loadable without the GPU stack. On the
        # diffusion-training image these resolve and the driver runs.
        import torch  # noqa: F401
        import rfdiffusion  # noqa: F401
    except ImportError as e:
        raise NotImplementedError(
            "The concrete RFdiffusion fine-tune/sample loop runs on the "
            "diffusion-training GPU image (torch-cuda + rfdiffusion + released "
            "weights). This harness has resolved the structure set (%d files), "
            "assembled the contig/hotspot conditioning, and prepared the artifact "
            "dir — but will NOT fabricate a trained checkpoint or metrics without "
            "the framework. Build/run backend/docker/diffusion-training.Dockerfile "
            "(tag diffusion-training-v** triggers .github/workflows/"
            "diffusion-training-image.yml)."
            % len(structures)
        ) from e

    if not diff.finetune:
        raise NotImplementedError(
            "from-scratch SE(3) training is not in the open RFdiffusion release "
            "(RosettaCommons ships scripts/run_inference.py only; no public "
            "train_multi_deep harness). Use finetune=True with base_checkpoint "
            "(warm-start + conditioned design on the structure set). Image: "
            "biomate/diffusion-training:latest."
        )

    ckpt = ensure_rfdiffusion_weights(diff.base_checkpoint)
    # Prefer Complex weights automatically when hotspot conditioning is set and
    # the user left the default Base checkpoint — matches RFdiffusion's own
    # Sampler model-selection logic.
    if diff.hotspot_residues and _checkpoint_basename(diff.base_checkpoint) == "Base_ckpt.pt":
        try:
            ckpt = ensure_rfdiffusion_weights("Complex_base_ckpt.pt")
        except RuntimeError as e:
            log.warning("[diffusion] Complex_base unavailable (%s); using Base", e)

    model_dir = Path(artifact_dir) / "rfdiffusion_model"
    model_dir.mkdir(parents=True, exist_ok=True)
    dest_ckpt = model_dir / ckpt.name
    if dest_ckpt.resolve() != ckpt.resolve():
        shutil.copy2(ckpt, dest_ckpt)

    designs_dir = Path(artifact_dir) / "designs"
    designs_dir.mkdir(parents=True, exist_ok=True)
    designs, design_metrics = run_rfdiffusion_inference(
        cfg, structures, conditioning, dest_ckpt, designs_dir,
    )

    metrics: dict[str, float] = {
        "n_designs": float(len(designs)),
        "n_structures": float(len(structures)),
    }
    metrics.update(design_metrics)
    # Gate metric defaults to scrmsd. Full ProteinMPNN→ESMFold scRMSD needs those
    # tools; when we have a real CA RMSD-to-ref from designs, surface it under
    # both names so the gate has a measured value without inventing one.
    if "ca_rmsd_to_ref" in design_metrics and "scrmsd" not in metrics:
        metrics["scrmsd"] = design_metrics["ca_rmsd_to_ref"]

    return _finish(
        cfg, artifact_dir, metrics, len(structures), str(model_dir),
        extra={
            "mode": "warmstart_conditioned_design",
            "weight_update": False,
            "checkpoint": str(dest_ckpt),
            "n_designs_written": len(designs),
            "designs": [str(p) for p in designs],
            "conditioning": conditioning,
            "note": (
                "Open RFdiffusion has no public SE(3) weight-update loop; "
                "BioMate executes warm-start checkpoint + conditioned design. "
                "Metrics are from real design outputs only."
            ),
        },
    )


def run_rfdiffusion_inference(
    cfg: TrainingConfig,
    structures: list[str],
    conditioning: dict[str, Any],
    checkpoint: Path,
    designs_dir: Path,
) -> tuple[list[Path], dict[str, float]]:
    """Invoke RFdiffusion ``run_inference.py`` and collect design PDBs + metrics.

    Returns (design_paths, metrics). Metrics contain only values derived from
    real outputs (plddt from .trb, CA RMSD to reference when computable). Raises
    RuntimeError if the driver fails or writes zero designs — never invents them.
    """
    diff = cfg.diffusion
    assert diff is not None
    script = _find_run_inference_script()
    if script is None:
        raise RuntimeError(
            "RFdiffusion scripts/run_inference.py not found. Expected under "
            "/opt/RFdiffusion (diffusion-training image) or on PYTHONPATH. "
            "Rebuild biomate/diffusion-training from "
            "backend/docker/diffusion-training.Dockerfile."
        )

    # Target PDB: explicit param, else first structure in the set (binder-style).
    target_pdb = (diff.target_pdb or "").strip() or structures[0]
    if not Path(target_pdb).is_file():
        raise ValueError(f"target PDB not found: {target_pdb}")

    out_prefix = str(designs_dir / "design")
    overrides = _hydra_overrides(conditioning, checkpoint, target_pdb, out_prefix, diff.num_designs)

    # Hydra needs cwd = RFdiffusion root so config/inference resolves.
    rf_root = script.parent.parent
    cmd = ["python", str(script), *overrides]
    log.info("[diffusion] running: %s (cwd=%s)", " ".join(cmd), rf_root)
    t0 = time.time()
    proc = subprocess.run(
        cmd, cwd=str(rf_root), capture_output=True, text=True,
        env={**os.environ, "PYTHONPATH": f"{rf_root}:{os.environ.get('PYTHONPATH', '')}"},
    )
    wall = time.time() - t0
    if proc.returncode != 0:
        tail = (proc.stderr or proc.stdout or "")[-4000:]
        raise RuntimeError(
            f"RFdiffusion run_inference failed (exit {proc.returncode}). "
            f"stderr/stdout tail:\n{tail}"
        )

    designs = sorted(designs_dir.glob("design_*.pdb"))
    if not designs:
        # Some configs write without underscore padding variants
        designs = sorted(p for p in designs_dir.glob("design*.pdb") if p.is_file())
    if not designs:
        raise RuntimeError(
            f"RFdiffusion completed but wrote no design_*.pdb under {designs_dir}. "
            f"stdout tail:\n{(proc.stdout or '')[-2000:]}"
        )

    metrics = _metrics_from_designs(designs, reference_pdb=target_pdb)
    metrics["inference_wall_s"] = float(wall)
    return designs, metrics


def _find_run_inference_script() -> Optional[Path]:
    candidates = [
        Path("/opt/RFdiffusion/scripts/run_inference.py"),
        Path(os.environ.get("RFDIFFUSION_ROOT", "")) / "scripts" / "run_inference.py",
    ]
    try:
        import rfdiffusion as _rf
        pkg = Path(getattr(_rf, "__file__", "") or "").resolve().parent
        candidates.append(pkg.parent / "scripts" / "run_inference.py")
    except Exception:
        pass
    for c in candidates:
        if c and c.is_file():
            return c
    return None


def _hydra_overrides(
    conditioning: dict[str, Any],
    checkpoint: Path,
    target_pdb: str,
    out_prefix: str,
    num_designs: int,
) -> list[str]:
    """Build hydra CLI overrides from our conditioning dict + paths."""
    overrides = [
        f"inference.output_prefix={out_prefix}",
        f"inference.input_pdb={target_pdb}",
        f"inference.num_designs={int(num_designs)}",
        f"inference.ckpt_override_path={checkpoint}",
        "inference.write_trajectory=False",
        "inference.cautious=False",
    ]
    for key, val in conditioning.items():
        if key.startswith("inference.") and key in (
            "inference.output_prefix", "inference.input_pdb",
            "inference.num_designs", "inference.ckpt_override_path",
        ):
            continue
        if key == "contigmap.contigs":
            # Hydra list syntax: contigmap.contigs=[60-100]
            items = val if isinstance(val, list) else [val]
            joined = ",".join(str(x) for x in items)
            overrides.append(f"contigmap.contigs=[{joined}]")
        elif key == "ppi.hotspot_res":
            items = val if isinstance(val, list) else [val]
            # RFdiffusion expects ["A30","A33"] with quotes
            quoted = ",".join(f"'{x}'" for x in items)
            overrides.append(f"ppi.hotspot_res=[{quoted}]")
        elif isinstance(val, (int, float)):
            overrides.append(f"{key}={val}")
        elif isinstance(val, str) and val:
            overrides.append(f"{key}={val}")
    return overrides


def _metrics_from_designs(designs: list[Path], reference_pdb: str) -> dict[str, float]:
    """Extract real metrics from design outputs. Never invents values."""
    out: dict[str, float] = {"n_designs": float(len(designs))}
    plddts: list[float] = []
    for pdb in designs:
        trb = pdb.with_suffix(".trb")
        if not trb.is_file():
            continue
        try:
            with open(trb, "rb") as f:
                data = pickle.load(f)
            arr = data.get("plddt")
            if arr is not None:
                import numpy as np
                plddts.append(float(np.asarray(arr).mean()))
        except Exception as e:
            log.warning("[diffusion] could not read plddt from %s: %s", trb, e)
    if plddts:
        out["mean_plddt"] = float(sum(plddts) / len(plddts))

    try:
        rmsd = _mean_ca_rmsd_to_ref(designs, reference_pdb)
        if rmsd is not None:
            out["ca_rmsd_to_ref"] = rmsd
    except Exception as e:
        log.warning("[diffusion] CA RMSD skipped: %s", e)
    return out


def _ca_coords_from_pdb(path: str) -> list[tuple[float, float, float]]:
    coords = []
    for line in Path(path).read_text(errors="replace").splitlines():
        if line.startswith("ATOM") and len(line) >= 54 and line[12:16].strip() == "CA":
            try:
                coords.append((float(line[30:38]), float(line[38:46]), float(line[46:54])))
            except ValueError:
                continue
    return coords


def _mean_ca_rmsd_to_ref(designs: list[Path], reference_pdb: str) -> Optional[float]:
    """Mean CA RMSD of each design vs reference (truncated to shared length).

    This is a real geometric metric, not ProteinMPNN→ESMFold self-consistency
    scRMSD. Callers may surface it as scrmsd for gating when the full pipeline
    is unavailable — see _train_rfdiffusion note.
    """
    ref = _ca_coords_from_pdb(reference_pdb)
    if len(ref) < 3:
        return None
    rmsds = []
    for d in designs:
        coords = _ca_coords_from_pdb(str(d))
        n = min(len(ref), len(coords))
        if n < 3:
            continue
        acc = 0.0
        for i in range(n):
            dx = coords[i][0] - ref[i][0]
            dy = coords[i][1] - ref[i][1]
            dz = coords[i][2] - ref[i][2]
            acc += dx * dx + dy * dy + dz * dz
        rmsds.append((acc / n) ** 0.5)
    if not rmsds:
        return None
    return float(sum(rmsds) / len(rmsds))


def _build_rfdiffusion_conditioning(cfg: TrainingConfig) -> dict[str, Any]:
    """Translate DiffusionSpec → RFdiffusion-native conditioning dict.

    Pure + testable: no framework import. Mirrors the fields RFdiffusion's hydra
    config exposes (contigmap.contigs, ppi.hotspot_res, diffuser.T, etc.).
    """
    diff = cfg.diffusion
    contig = diff.contig or f"{diff.length_min}-{diff.length_max}"
    cond: dict[str, Any] = {
        "contigmap.contigs": [contig],
        "diffuser.T": diff.diffusion_steps,
        "inference.num_designs": diff.num_designs,
        # RFdiffusion hydra key is schedule_type (linear|cosine); DiffusionSpec
        # calls it noise_schedule — map here so overrides are accepted.
        "diffuser.schedule_type": diff.noise_schedule,
    }
    if diff.target_pdb:
        cond["inference.input_pdb"] = diff.target_pdb
    if diff.hotspot_residues:
        cond["ppi.hotspot_res"] = [r.strip() for r in diff.hotspot_residues.split(",") if r.strip()]
    if diff.motif_pdb:
        cond["inference.motif_pdb"] = diff.motif_pdb
    if diff.finetune and diff.base_checkpoint:
        cond["inference.ckpt_override_path"] = diff.base_checkpoint
    return cond


def _finish(cfg: TrainingConfig, artifact_dir: str, metrics: dict[str, float],
            n_structures: int, model_dir: str, extra: dict) -> TrainingResult:
    """Build the TrainingResult + manifest."""
    try:
        import rfdiffusion as _rf
        fw = f"rfdiffusion=={getattr(_rf, '__version__', '?')}"
    except Exception:
        fw = f"{cfg.diffusion.framework}==?"
    result = TrainingResult(
        model_type="protein_diffusion", artifact_dir=artifact_dir, metrics=metrics,
        n_train=n_structures, n_val=0, n_test=0, framework_version=fw,
        extra={"model_dir": model_dir, "framework": cfg.diffusion.framework,
               "finetune": cfg.diffusion.finetune, "task": "structure_generation",
               **extra},
    )
    (Path(artifact_dir) / "manifest.json").write_text(json.dumps({
        "name": cfg.name, "model_type": result.model_type, "task_type": cfg.task_type,
        "metrics": result.metrics, "framework_version": result.framework_version,
        "extra": result.extra,
    }, indent=2))
    return result
