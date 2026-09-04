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

The point of the abstraction: swapping BRICS out for a real target-conditioned
generator is a one-line change at the call site (pass a different ``Generator``);
everything downstream (predict / GP-hypervolume score / rank) is untouched.
"""
from __future__ import annotations

import logging
from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from typing import Optional

log = logging.getLogger(__name__)

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

    # Common bioisosteric / decoration fragments (same set as the .nf process).
    _EXTRA_FRAGS = [
        "c1ccccc1", "c1ccncc1", "c1ccnc(N)c1", "c1cnc(N)cn1",
        "[*]C(=O)N", "[*]C(=O)O", "[*]S(=O)(=O)N", "[*]OC",
        "[*]CC", "[*]CCC", "[*]CF", "[*]CC(F)(F)F",
    ]

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

        # 1) Combinatorial BRICS reassembly of the seed itself.
        try:
            for mol in BRICS.BRICSBuild([seed_mol]):
                smi = Chem.MolToSmiles(mol)
                if smi and Chem.MolFromSmiles(smi):
                    candidates.add(smi)
                if len(candidates) >= target_pool:
                    break
        except Exception:  # pragma: no cover - BRICS can raise on odd inputs
            pass

        # 2) Pairwise assembly of seed fragments with the medchem fragment set.
        seed_frags = list(BRICS.BRICSDecompose(seed_mol))
        seed_frag_mols = [m for m in (Chem.MolFromSmiles(f) for f in seed_frags)
                          if m is not None]
        extra_mols = [m for m in (Chem.MolFromSmiles(f) for f in self._EXTRA_FRAGS)
                      if m is not None]

        for base_frag in seed_frag_mols[:5]:
            if len(candidates) >= target_pool:
                break
            for extra_frag in extra_mols:
                try:
                    for mol in BRICS.BRICSBuild([base_frag, extra_frag]):
                        smi = Chem.MolToSmiles(mol)
                        if smi and Chem.MolFromSmiles(smi):
                            candidates.add(smi)
                        if len(candidates) >= target_pool:
                            break
                except Exception:
                    pass
                if len(candidates) >= target_pool:
                    break

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
# Registry / factory
# ---------------------------------------------------------------------------

_GENERATORS = {
    "brics": BricsGenerator,
    "bionemo_genmol": lambda: BioNeMoGenerator(model="genmol"),
    "bionemo_molmim": lambda: BioNeMoGenerator(model="molmim"),
}


def get_generator(kind: str = "brics") -> Generator:
    """
    Factory for the built-in generators.

    Args:
        kind: 'brics' (default, deterministic enumeration),
              'bionemo_genmol' or 'bionemo_molmim' (learned, NIM-backed).

    Returns:
        A :class:`Generator` instance.
    """
    if kind not in _GENERATORS:
        raise ValueError(f"Unknown generator {kind!r}; "
                         f"available: {sorted(_GENERATORS)}")
    factory = _GENERATORS[kind]
    return factory()
