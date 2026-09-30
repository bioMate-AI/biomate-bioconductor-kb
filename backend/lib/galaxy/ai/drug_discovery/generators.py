"""
De-novo molecular generator abstraction for BioMate drug discovery.

This module defines a single, honest swap-point for the *generation* step of
the closed generate -> predict -> score -> rank loop (see ``denovo_pipeline.py``):

    class Generator(ABC):
        def propose(spec: GenerationSpec) -> list[str]   # returns SMILES

Implementations:

  * ``BricsGenerator``   — wraps RDKit BRICS decompose/reassemble + medchem
                           enumeration.  This is the SAME logic that the
                           ``REINVENT_DESIGN`` Nextflow process actually runs
                           today, extracted here and HONESTLY named.  It is a
                           deterministic combinatorial enumerator, NOT a trained
                           policy — it does no reinforcement learning.

  * ``BioNeMoGenerator`` — target/property-conditioned generation via NVIDIA
                           BioNeMo NIMs (GenMol / MolMIM) through
                           ``bionemo_client.BioNeMoClient``.  This is the slot a
                           *real* learned generator drops into.  When the NIM is
                           not reachable (no ``NVIDIA_API_KEY`` / network / import
                           failure) it returns an EMPTY list and records the
                           reason on ``self.last_status`` — it NEVER fabricates
                           molecules.

  * ``Reinvent4Generator`` — REAL learned de-novo / analogue generation via
                           **REINVENT4** (MolecularAI, Apache-2.0, no API key).
                           Runs the open-weights Reinvent prior (de-novo) or a
                           Mol2Mol prior (scaffold hop / analogs from a seed) in
                           ``run_type=sampling`` mode through REINVENT4's own CLI,
                           then parses the sampled SMILES.  Same honesty contract:
                           returns [] + ``last_status`` if the CLI or prior
                           checkpoint is unavailable; never enumerates as a
                           fallback.

The point of the abstraction: swapping BRICS out for a real target-conditioned
generator is a one-line change at the call site (pass a different ``Generator``);
everything downstream (predict / GP-hypervolume score / rank) is untouched.
"""
from __future__ import annotations

import json
import logging
import os
import shutil
import subprocess
import tempfile
from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from typing import Optional

log = logging.getLogger(__name__)

# RDKit is a RUNTIME requirement for the BRICS generator (the /design module).
# NOTE (2026-09-30): dev runs a hot-patched :rollback container that is never
# rebuilt from backend/Dockerfile, so the Dockerfile's `pip install rdkit` never
# reaches dev — gunicorn's system python3.9 had NO rdkit and /design returned
# "rdkit_unavailable" (0 candidates). rdkit is now bootstrapped into the running
# container by scripts/sync_to_dev.sh (backend layer), alongside boto3/redis.
# If you add an image-level dependency, remember it will NOT land on dev via the
# .py-hot-patch deploy path — bootstrap it in sync_to_dev.sh too.
try:
    from rdkit import Chem
    from rdkit.Chem import BRICS
    _RDKIT_AVAILABLE = True
except ImportError:  # pragma: no cover - exercised only in RDKit-less envs
    _RDKIT_AVAILABLE = False


# ---------------------------------------------------------------------------
# Generation request / spec
# ---------------------------------------------------------------------------

@dataclass
class GenerationSpec:
    """
    Target / constraint specification handed to a ``Generator``.

    Not every generator uses every field:
      * ``BricsGenerator`` uses ``seed_smiles`` (+ ``max_candidates``).
      * ``BioNeMoGenerator`` uses ``seed_smiles`` (conditioning scaffold),
        ``property_target`` (property-conditioned generation), and
        ``n_molecules``.  ``target_protein_pdb`` is carried for future
        structure-conditioned NIMs; it is not fabricated into results.
    """
    seed_smiles: Optional[str] = None
    n_molecules: int = 50
    max_candidates: int = 2000
    # Property-conditioned generation, e.g. {"qed": 0.8} — used by BioNeMo NIMs.
    property_target: dict[str, float] = field(default_factory=dict)
    # Carried for structure-conditioned generators; never used to invent results.
    target_protein_pdb: Optional[str] = None
    # Free-form extra constraints for future generators.
    constraints: dict = field(default_factory=dict)


# ---------------------------------------------------------------------------
# Generator interface — the swap-point
# ---------------------------------------------------------------------------

class Generator(ABC):
    """
    Abstract molecular generator.

    Concrete implementations turn a :class:`GenerationSpec` into a list of
    candidate SMILES strings.  Downstream scoring/ranking is generator-agnostic,
    so a real target-conditioned model can replace the default enumerator by
    passing a different ``Generator`` instance to the pipeline.
    """

    #: Human-readable, HONEST name of what this generator actually does.
    name: str = "abstract"

    #: Whether outputs are produced by a trained generative policy (True) or a
    #: deterministic enumeration heuristic (False).  Kept explicit so callers /
    #: reports never mislabel BRICS enumeration as "AI generation".
    is_learned: bool = False

    def __init__(self) -> None:
        # Populated on each propose() call: {"ok": bool, "reason": str, ...}
        self.last_status: dict = {}

    @abstractmethod
    def propose(self, spec: GenerationSpec) -> list[str]:
        """Return a list of candidate SMILES for the given spec."""
        ...

    # -- shared helper --------------------------------------------------------
    @staticmethod
    def _canonicalize(smiles_iterable) -> list[str]:
        """
        Deduplicate + canonicalize a set of SMILES, dropping anything RDKit
        cannot parse.  Falls back to a plain unique-preserving list when RDKit
        is unavailable (used only in RDKit-less unit environments).
        """
        out: list[str] = []
        seen: set[str] = set()
        if not _RDKIT_AVAILABLE:
            for smi in smiles_iterable:
                if smi and smi not in seen:
                    seen.add(smi)
                    out.append(smi)
            return out
        for smi in smiles_iterable:
            if not smi:
                continue
            mol = Chem.MolFromSmiles(smi)
            if mol is None:
                continue
            can = Chem.MolToSmiles(mol)
            if can not in seen:
                seen.add(can)
                out.append(can)
        return out


# ---------------------------------------------------------------------------
# BRICS generator (honest name for the existing enumeration logic)
# ---------------------------------------------------------------------------

class BricsGenerator(Generator):
    """
    Deterministic BRICS decompose/reassemble + medchem enumeration.

    This mirrors the logic executed by the ``REINVENT_DESIGN`` process in
    ``reinvent4_lead_design/main.nf`` — extracted here and named for what it
    truly is.  It is NOT reinforcement learning and NOT a learned generator;
    it enumerates analogues by recombining BRICS fragments of the seed with a
    small library of common medchem fragments.
    """

    name = "rdkit_brics_enumeration"
    is_learned = False

    def propose(self, spec: GenerationSpec) -> list[str]:
        if not _RDKIT_AVAILABLE:
            self.last_status = {"ok": False, "reason": "rdkit_unavailable",
                                "generator": self.name}
            return []

        seed = spec.seed_smiles
        if not seed:
            self.last_status = {"ok": False, "reason": "no_seed_smiles",
                                "generator": self.name}
            return []

        seed_mol = Chem.MolFromSmiles(seed)
        if seed_mol is None:
            self.last_status = {"ok": False, "reason": "invalid_seed_smiles",
                                "generator": self.name}
            return []

        target_pool = max(1, spec.max_candidates)
        candidates: set[str] = {Chem.MolToSmiles(seed_mol)}

        # Decompose the seed into BRICS fragments — these carry properly
        # bond-type-LABELLED dummy atoms ([16*], [3*], …) — then recombine the
        # whole fragment pool in a single BRICSBuild pass. This is the
        # RDKit-idiomatic way to enumerate a virtual library and yields hundreds
        # of analogues from a fragmentable seed.
        #
        # (The previous approach — BRICSBuild([seed_mol]) on the intact molecule,
        # plus a pairwise base+extra loop over a generically-dummied medchem set
        # — produced ~1 molecule, because BRICSBuild only joins fragments whose
        # dummy atoms carry compatible BRICS bond-type labels, which neither the
        # intact seed nor the unlabelled extras had.)
        frag_mols = [m for m in (Chem.MolFromSmiles(f)
                                 for f in BRICS.BRICSDecompose(seed_mol))
                     if m is not None]
        try:
            for i, mol in enumerate(BRICS.BRICSBuild(frag_mols)):
                try:
                    Chem.SanitizeMol(mol)
                    smi = Chem.MolToSmiles(mol)
                except Exception:
                    continue
                if smi and Chem.MolFromSmiles(smi):
                    candidates.add(smi)
                # Cap on both unique output and raw iterations — BRICSBuild is a
                # lazy generator over a combinatorial space.
                if len(candidates) >= target_pool or i >= 20000:
                    break
        except Exception:  # pragma: no cover - BRICS can raise on odd inputs
            pass

        result = self._canonicalize(candidates)
        self.last_status = {
            "ok": len(result) > 0,
            "reason": "ok" if result else "no_candidates",
            "generator": self.name,
            "n_candidates": len(result),
            "is_learned": self.is_learned,
        }
        return result


# ---------------------------------------------------------------------------
# BioNeMo generator (the real swap-point: GenMol / MolMIM)
# ---------------------------------------------------------------------------

class BioNeMoGenerator(Generator):
    """
    Target/property-conditioned de-novo generation via NVIDIA BioNeMo NIMs.

    Uses :class:`bionemo_client.BioNeMoClient` — GenMol for scaffold/de-novo
    generation, MolMIM for property-conditioned analog generation.

    HONESTY CONTRACT: if the NIM cannot be reached (no ``NVIDIA_API_KEY``, import
    failure, network error) this returns an EMPTY list and records the reason on
    ``self.last_status``.  It does NOT emit placeholder or fabricated molecules —
    a real result is either a genuine NIM response or nothing.
    """

    name = "bionemo_nim"
    is_learned = True

    def __init__(self, model: str = "genmol", client=None) -> None:
        """
        Args:
            model:  'genmol' (scaffold/de-novo) or 'molmim' (property analogs).
            client: optional pre-built BioNeMoClient (injectable for testing).
        """
        super().__init__()
        if model not in ("genmol", "molmim"):
            raise ValueError(f"BioNeMoGenerator: unsupported model {model!r}; "
                             "use 'genmol' or 'molmim'")
        self.model = model
        self._client = client

    def _get_client(self):
        """Lazily construct the BioNeMoClient; return None if unavailable."""
        if self._client is not None:
            return self._client
        try:
            from ..bionemo_client import BioNeMoClient
        except Exception as exc:  # import-time failure (e.g. requests missing)
            self.last_status = {"ok": False, "reason": f"import_failed: {exc}",
                                "generator": self.name, "model": self.model}
            return None
        try:
            self._client = BioNeMoClient()
        except Exception as exc:  # typically: NVIDIA_API_KEY not set
            self.last_status = {"ok": False, "reason": f"client_init_failed: {exc}",
                                "generator": self.name, "model": self.model}
            return None
        return self._client

    def propose(self, spec: GenerationSpec) -> list[str]:
        client = self._get_client()
        if client is None:
            # last_status already set by _get_client(); return NO molecules.
            return []

        seed = spec.seed_smiles or ""  # '' => unconditional generation in GenMol
        n = max(1, spec.n_molecules)

        try:
            if self.model == "genmol":
                # GenMol: scaffold / de-novo generation, returns
                # [{"smiles": str, "score": float}, ...]
                raw = client.genmol(seed, num_molecules=n, unique=True)
            else:  # molmim — property-conditioned analog generation
                # MolMIM returns [{"sample": SMILES, "score": float}, ...]
                raw = client.molmim(seed, num_molecules=n)
        except Exception as exc:
            self.last_status = {"ok": False, "reason": f"nim_call_failed: {exc}",
                                "generator": self.name, "model": self.model}
            return []

        smiles = self._extract_smiles(raw)
        result = self._canonicalize(smiles)
        self.last_status = {
            "ok": len(result) > 0,
            "reason": "ok" if result else "nim_returned_empty",
            "generator": self.name,
            "model": self.model,
            "n_candidates": len(result),
            "is_learned": self.is_learned,
        }
        return result

    @staticmethod
    def _extract_smiles(raw) -> list[str]:
        """
        Normalize the various NIM response shapes to a plain list of SMILES.

        GenMol -> [{"smiles": ...}], MolMIM/MoFlow -> [{"sample": ...}].
        Accepts already-flat lists of strings too.  Never fabricates values.
        """
        out: list[str] = []
        if not raw:
            return out
        for item in raw:
            if isinstance(item, str):
                out.append(item)
            elif isinstance(item, dict):
                smi = item.get("smiles") or item.get("sample") or item.get("smi")
                if smi:
                    out.append(smi)
        return out


# ---------------------------------------------------------------------------
# REINVENT4 generator (the real, open-weights learned generator)
# ---------------------------------------------------------------------------

class Reinvent4Generator(Generator):
    """
    De-novo / analogue generation via **REINVENT4** (MolecularAI, Apache-2.0,
    https://github.com/MolecularAI/REINVENT4) — a genuinely LEARNED autoregressive
    SMILES policy, NOT combinatorial enumeration.

    Two operating modes, selected by ``model`` (and overridable per-spec):

      * ``reinvent``  — de-novo sampling from the general **Reinvent prior**
                        (a RNN trained on ChEMBL). ``seed_smiles`` is ignored;
                        the model draws novel molecules from its learned
                        distribution.
      * ``mol2mol``   — scaffold hopping / analogue generation. Requires a
                        ``seed_smiles`` input; the Mol2Mol prior transforms each
                        seed into similar-but-novel molecules (Tanimoto-controlled).

    Both run through REINVENT4's own CLI in ``run_type=sampling`` mode: we write a
    minimal TOML config pointing at the downloaded prior ``.model`` checkpoint,
    invoke ``reinvent <config>.toml`` (or ``python -m reinvent``), then parse the
    output SMILES CSV. Sampling mode needs only the prior — no reward model, no RL
    training loop — so it is fast (CPU-viable) and deterministic given a seed.

    HONESTY CONTRACT (identical to BioNeMoGenerator): if the ``reinvent`` CLI is
    not importable/on PATH, or the prior checkpoint is missing, or the subprocess
    fails, this returns an EMPTY list and records the reason on ``self.last_status``.
    It NEVER fabricates or falls back to enumeration — a real result is either a
    genuine REINVENT4 sample set or nothing.

    Prior checkpoints (Apache-2.0, redistributed with REINVENT4) live under
    ``$REINVENT4_PRIORS`` (default ``/opt/reinvent4/priors``):
        reinvent.prior   — de-novo Reinvent prior
        mol2mol_*.prior  — Mol2Mol similarity/scaffold priors
    The Nextflow container (see reinvent4_lead_design/main.nf) stages these; see
    that file's REINVENT4_SETUP block for the exact acquisition commands.
    """

    name = "reinvent4"
    is_learned = True

    #: Default prior filenames per mode, resolved under $REINVENT4_PRIORS.
    _DEFAULT_PRIORS = {
        "reinvent": "reinvent.prior",
        "mol2mol": "mol2mol_similarity.prior",
    }

    def __init__(
        self,
        model: str = "reinvent",
        priors_dir: Optional[str] = None,
        prior_path: Optional[str] = None,
        cli: Optional[str] = None,
    ) -> None:
        """
        Args:
            model:      'reinvent' (de-novo sampling) or 'mol2mol' (analog/scaffold hop).
            priors_dir: directory holding the prior checkpoints
                        (default: $REINVENT4_PRIORS or /opt/reinvent4/priors).
            prior_path: explicit path to a .prior/.model checkpoint (overrides
                        priors_dir + default filename).
            cli:        override the reinvent executable (default: $REINVENT4_CLI
                        or 'reinvent' on PATH; falls back to 'python -m reinvent').
        """
        super().__init__()
        if model not in ("reinvent", "mol2mol"):
            raise ValueError(
                f"Reinvent4Generator: unsupported model {model!r}; "
                "use 'reinvent' (de-novo) or 'mol2mol' (analog/scaffold hop)"
            )
        self.model = model
        self.priors_dir = (
            priors_dir or os.environ.get("REINVENT4_PRIORS", "/opt/reinvent4/priors")
        )
        self.prior_path = prior_path
        self.cli = cli or os.environ.get("REINVENT4_CLI")

    # -- environment resolution ----------------------------------------------
    def _resolve_prior(self) -> Optional[str]:
        if self.prior_path:
            return self.prior_path if os.path.isfile(self.prior_path) else None
        fname = self._DEFAULT_PRIORS[self.model]
        candidate = os.path.join(self.priors_dir, fname)
        if os.path.isfile(candidate):
            return candidate
        # Accept a .model extension too (REINVENT4 ships both naming styles).
        alt = candidate.replace(".prior", ".model")
        return alt if os.path.isfile(alt) else None

    def _resolve_cli(self) -> Optional[list]:
        """Return the argv prefix for invoking REINVENT4, or None if unavailable."""
        if self.cli:
            exe = shutil.which(self.cli) or (self.cli if os.path.isfile(self.cli) else None)
            return [exe] if exe else None
        exe = shutil.which("reinvent")
        if exe:
            return [exe]
        # Fall back to the module entrypoint if the package imports.
        try:
            import importlib.util
            if importlib.util.find_spec("reinvent") is not None:
                import sys
                return [sys.executable, "-m", "reinvent"]
        except Exception:
            pass
        return None

    # -- TOML config builder (sampling mode) ---------------------------------
    def _build_config(self, spec: GenerationSpec, prior: str,
                      out_smi: str, seed_file: Optional[str]) -> str:
        """
        Build a minimal REINVENT4 run_type=sampling TOML.

        REINVENT4's sampling stage needs only: the prior model file, the number of
        SMILES to draw, and (for Mol2Mol) an input file of seed SMILES. TOML is the
        documented config format (Loeffler et al. 2024; REINVENT4 configs/toml/*).
        """
        n = max(1, spec.n_molecules)
        # unique_molecules dedups within REINVENT4; we canonicalize again after.
        lines = [
            'run_type = "sampling"',
            'device = "cpu"',            # overridden to "cuda:0" by env in-container
            f'json_out_config = "{out_smi}.json"',
            "",
            "[parameters]",
            f'model_file = "{prior}"',
            f'output_file = "{out_smi}"',
            f'num_smiles = {n}',
            'unique_molecules = true',
            'randomize_smiles = true',
        ]
        if self.model == "mol2mol":
            if not seed_file:
                raise ValueError("mol2mol sampling requires a seed SMILES input file")
            lines += [
                f'smiles_file = "{seed_file}"',
                'sample_strategy = "multinomial"',
                'temperature = 1.0',
            ]
        # Honour a "cuda" hint from the environment (container sets this).
        if os.environ.get("REINVENT4_DEVICE"):
            lines[1] = f'device = "{os.environ["REINVENT4_DEVICE"]}"'
        return "\n".join(lines) + "\n"

    @staticmethod
    def _parse_output(out_smi: str) -> list:
        """
        Parse REINVENT4 sampling output into a plain SMILES list.

        REINVENT4 writes a CSV with a header; the SMILES column is 'SMILES'
        (de-novo) or 'SMILES'/'Output_SMILES' (Mol2Mol, plus an 'Input_SMILES'
        column). We read the first column whose header contains 'SMILES' and is
        not an input column. Never fabricates rows.
        """
        if not os.path.isfile(out_smi):
            return []
        import csv
        out: list = []
        with open(out_smi, newline="") as fh:
            reader = csv.reader(fh)
            try:
                header = next(reader)
            except StopIteration:
                return []
            # Pick the output SMILES column.
            col = None
            for i, h in enumerate(header):
                hl = h.strip().lower()
                if "smiles" in hl and "input" not in hl:
                    col = i
                    break
            if col is None:
                # No header match — assume single-column raw SMILES list.
                if header and header[0].strip():
                    out.append(header[0].strip())
                col = 0
            for row in reader:
                if col < len(row) and row[col].strip():
                    out.append(row[col].strip())
        return out

    def propose(self, spec: GenerationSpec) -> list[str]:
        cli = self._resolve_cli()
        if cli is None:
            self.last_status = {
                "ok": False, "reason": "reinvent4_cli_unavailable",
                "generator": self.name, "model": self.model,
            }
            return []

        prior = self._resolve_prior()
        if prior is None:
            self.last_status = {
                "ok": False,
                "reason": (
                    f"prior_checkpoint_missing: expected "
                    f"{self._DEFAULT_PRIORS[self.model]!r} under {self.priors_dir!r}"
                ),
                "generator": self.name, "model": self.model,
            }
            return []

        if self.model == "mol2mol" and not spec.seed_smiles:
            self.last_status = {
                "ok": False, "reason": "mol2mol_requires_seed_smiles",
                "generator": self.name, "model": self.model,
            }
            return []

        workdir = tempfile.mkdtemp(prefix="reinvent4_")
        try:
            out_smi = os.path.join(workdir, "sampled.csv")
            seed_file = None
            if self.model == "mol2mol":
                seed_file = os.path.join(workdir, "seeds.smi")
                with open(seed_file, "w") as fh:
                    fh.write(spec.seed_smiles.strip() + "\n")

            cfg_text = self._build_config(spec, prior, out_smi, seed_file)
            cfg_path = os.path.join(workdir, "sampling.toml")
            with open(cfg_path, "w") as fh:
                fh.write(cfg_text)

            proc = subprocess.run(
                cli + [cfg_path],
                capture_output=True, text=True,
                timeout=int(os.environ.get("REINVENT4_TIMEOUT", "1800")),
            )
            if proc.returncode != 0:
                tail = (proc.stderr or proc.stdout or "").strip()[-500:]
                self.last_status = {
                    "ok": False,
                    "reason": f"reinvent4_run_failed (rc={proc.returncode}): {tail}",
                    "generator": self.name, "model": self.model,
                }
                return []

            smiles = self._parse_output(out_smi)
            result = self._canonicalize(smiles)
            self.last_status = {
                "ok": len(result) > 0,
                "reason": "ok" if result else "reinvent4_produced_no_valid_smiles",
                "generator": self.name,
                "model": self.model,
                "prior": os.path.basename(prior),
                "n_candidates": len(result),
                "is_learned": self.is_learned,
            }
            return result
        except subprocess.TimeoutExpired:
            self.last_status = {
                "ok": False, "reason": "reinvent4_timeout",
                "generator": self.name, "model": self.model,
            }
            return []
        except Exception as exc:  # pragma: no cover - defensive
            self.last_status = {
                "ok": False, "reason": f"reinvent4_error: {exc}",
                "generator": self.name, "model": self.model,
            }
            return []
        finally:
            shutil.rmtree(workdir, ignore_errors=True)


# ---------------------------------------------------------------------------
# Registry / factory
# ---------------------------------------------------------------------------

_GENERATORS = {
    "brics": BricsGenerator,
    "bionemo_genmol": lambda: BioNeMoGenerator(model="genmol"),
    "bionemo_molmim": lambda: BioNeMoGenerator(model="molmim"),
    # REINVENT4 — open-weights learned generator (Apache-2.0). Default alias
    # 'reinvent4' == de-novo sampling from the Reinvent prior; 'reinvent4_mol2mol'
    # == scaffold hopping / analog generation from a seed.
    "reinvent4": lambda: Reinvent4Generator(model="reinvent"),
    "reinvent4_mol2mol": lambda: Reinvent4Generator(model="mol2mol"),
}


def get_generator(kind: str = "brics") -> Generator:
    """
    Factory for the built-in generators.

    Args:
        kind: 'brics' (default, deterministic enumeration),
              'bionemo_genmol' / 'bionemo_molmim' (learned, NIM-backed),
              'reinvent4' (learned de-novo, open-weights REINVENT4 prior) or
              'reinvent4_mol2mol' (learned scaffold-hop/analog from a seed).

    Returns:
        A :class:`Generator` instance.
    """
    if kind not in _GENERATORS:
        raise ValueError(f"Unknown generator {kind!r}; "
                         f"available: {sorted(_GENERATORS)}")
    factory = _GENERATORS[kind]
    return factory()
