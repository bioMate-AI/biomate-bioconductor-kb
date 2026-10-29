"""Retrieval store: known peptides with measured / verifier values and provenance (document id + year).

Design points (plan section 3, I-B):
  * every row carries `doc` / `doc_year` so the arm-G blind rule can exclude documents and enforce a temporal cut;
  * rows with an unknown document are kept but flagged (`doc is None`); strict mode excludes them under any year rule;
  * canonical SMILES are stereo-aware (isomeric); `flat_key` is the non-isomeric canonical form (stereoisomer group).
"""
from __future__ import annotations

import csv
import gzip
from dataclasses import dataclass, field
from typing import Dict, Iterable, List, Optional, Tuple

try:
    from rdkit import Chem, RDLogger

    RDLogger.DisableLog("rdApp.*")
    HAVE_RDKIT = True
except Exception:  # pragma: no cover
    HAVE_RDKIT = False


def canon(smiles: str) -> Optional[Tuple[str, str]]:
    """(isomeric canonical SMILES, flat canonical SMILES) or None if unparsable."""
    if not isinstance(smiles, str) or not smiles or not HAVE_RDKIT:
        return None
    m = Chem.MolFromSmiles(smiles)
    if m is None:
        return None
    return Chem.MolToSmiles(m, isomericSmiles=True), Chem.MolToSmiles(m, isomericSmiles=False)


@dataclass(frozen=True)
class Row:
    smiles: str                 # canonical isomeric SMILES
    flat_key: str               # canonical non-isomeric SMILES
    values: Dict[str, float] = field(default_factory=dict)   # e.g. {"pact": 7.3} or verifier scores
    doc: Optional[str] = None
    doc_year: Optional[int] = None
    target: Optional[str] = None
    source: str = ""            # provenance tag of the builder


class RetrievalStore:
    def __init__(self, rows: Optional[Iterable[Row]] = None):
        self.rows: List[Row] = list(rows or [])

    def __len__(self) -> int:
        return len(self.rows)

    def add(self, smiles: str, values: Dict[str, float], doc: Optional[str] = None, doc_year: Optional[int] = None,
            target: Optional[str] = None, source: str = "online") -> Optional[Row]:
        c = canon(smiles)
        if c is None:
            return None
        r = Row(c[0], c[1], dict(values), doc, doc_year, target, source)
        self.rows.append(r)
        return r

    def mask(self, exclude_docs=None, exclude_flat=None, min_year=None, max_year=None, strict_docs=False,
             target=None) -> List[bool]:
        """Boolean allowed-mask over rows. Year rules need doc_year; with strict_docs a row whose date is unknown is
        EXCLUDED under any year rule (it cannot be shown to satisfy the cut)."""
        ex_docs = frozenset(exclude_docs or ())
        ex_flat = frozenset(exclude_flat or ())
        out = []
        for r in self.rows:
            ok = True
            if r.doc is not None and r.doc in ex_docs:
                ok = False
            if r.flat_key in ex_flat:
                ok = False
            if target is not None and r.target != target:
                ok = False
            if (min_year is not None or max_year is not None):
                if r.doc_year is None:
                    if strict_docs:
                        ok = False
                else:
                    if min_year is not None and r.doc_year < min_year:
                        ok = False
                    if max_year is not None and r.doc_year > max_year:
                        ok = False
            if strict_docs and ex_docs and r.doc is None:
                ok = False      # unknown provenance cannot be shown to be outside the excluded documents
            out.append(ok)
        return out

    # ---- builders from existing assets ---------------------------------------------------------------------------
    @classmethod
    def from_long_all(cls, path: str, targets: Optional[Iterable[str]] = None, exact_only: bool = True) -> "RetrievalStore":
        """integrin_chembl/data/long_all.csv.gz (columns: smiles, target, pact, censor, doc, doc_year). Document ids and
        years exist ONLY for this 8-target set; this is the arm-G store."""
        keep = set(targets) if targets else None
        rows = []
        opener = gzip.open if str(path).endswith(".gz") else open
        with opener(path, "rt", newline="") as fh:
            for rec in csv.DictReader(fh):
                if keep is not None and rec["target"] not in keep:
                    continue
                if exact_only and rec.get("censor", "eq") not in ("eq", "", "="):
                    continue
                c = canon(rec["smiles"])
                if c is None:
                    continue
                try:
                    pact = float(rec["pact"])
                except (TypeError, ValueError):
                    continue
                yr = rec.get("doc_year")
                rows.append(Row(c[0], c[1], {"pact": pact}, rec.get("doc") or None,
                                int(float(yr)) if yr not in (None, "", "nan") else None, rec["target"], "long_all"))
        return cls(rows)

    @classmethod
    def from_pair_labels(cls, pair_labels: str, compounds: str, exact_only: bool = True) -> "RetrievalStore":
        """retro_recovery pair_labels.csv.gz + compounds.csv.gz: 793 targets, exact potencies; NO document ids in these
        files, so `doc`/`doc_year` stay None (strict blind rules exclude these rows; use only where the arm allows)."""
        import math
        smi = {}
        with gzip.open(compounds, "rt", newline="") as fh:
            for rec in csv.DictReader(fh):
                smi[rec["compound_id"]] = rec["iso_smiles"]
        rows = []
        with gzip.open(pair_labels, "rt", newline="") as fh:
            for rec in csv.DictReader(fh):
                if exact_only and str(rec.get("relations", "")) != "=":
                    continue
                s = smi.get(rec["compound_id"])
                c = canon(s) if s else None
                if c is None:
                    continue
                try:
                    pact = -math.log10(float(rec["value_nM"]) * 1e-9)
                except (TypeError, ValueError):
                    continue
                rows.append(Row(c[0], c[1], {"pact": pact}, None, None, rec["target_key"], "pair_labels"))
        return cls(rows)
