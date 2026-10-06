"""Drug novelty / FTO gate — GENERAL (small molecule + peptide).

A modality-general pre-filter that answers, for each candidate drug, the question
a medicinal chemist / patent agent asks before committing synthesis spend:

    "Is this molecule already OCCUPIED — a re-discovery of a known active, or
     covered by an existing patent — or is it genuinely novel / free-to-operate?"

It belongs IN the validation+filtering pipeline, before expensive physics verify
and before any CRO order. The gate reduces to three honest axes:

  1. STRUCTURE axis (all modalities) — Morgan/ECFP Tanimoto nearest-neighbour vs a
     known-actives library (ChEMBL/BindingDB SMILES). `max_tanimoto >= cutoff`
     (default 0.85, the usual "materially distinct scaffold" line) => NOT novel.
     Reuses the SAME logic as backend compound_novelty_scorer; RDKit-native here
     so it runs locally without the mounted FPSim2 .h5.

  2. PATENT axis (opt-in, network) — coarse SureChEMBL/PubChem patent-presence for
     the candidate's canonical structure. Present => FTO risk flag. Same PubChem
     PUG-REST pattern as compound_novelty_scorer's check_patents path.

  3. SEQUENCE axis (peptides only, when a sequence-labelled reference is supplied)
     — normalised sequence identity (global alignment, pure-Python) vs known /
     patented peptide sequences. Catches claims that are text/sequence-based rather
     than structure-indexed. Secondary to axes 1-2.

Modality handling
-----------------
  * small molecule : pass `smiles=`. Axes 1-2 apply; axis 3 is N/A.
  * peptide        : pass `seq=` (one-letter). We build a head-to-tail cyclic (or
    linear) SMILES via RDKit, then run axes 1-2 on it; axis 3 runs if a sequence
    reference is given. `smiles=` may also be passed directly to override.

Honesty contract (mirrors compound_novelty_scorer)
--------------------------------------------------
  * Never fabricate a verdict. If an axis cannot run (RDKit missing, library
    missing, SMILES unbuildable, network down) it reports status="unavailable"
    for THAT axis; it does not silently score 0 / "novel".
  * `occupied` is True only when an axis that actually ran returned a hit. If no
    axis could run, verdict="unknown" and occupied=None (fail-OPEN by default so
    a broken scorer never silently kills a batch — the caller chooses the policy).

CPU only, no GPU/AWS. The structure library is fingerprinted once and cached.
"""
from __future__ import annotations

import json
import logging
import os
import pickle
import sys
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass, asdict, field
from pathlib import Path
from typing import Dict, List, Optional, Sequence, Tuple

log = logging.getLogger(__name__)
ROOT = Path(__file__).resolve().parent

# Default cutoffs — align with compound_novelty_scorer.
DEFAULT_TANIMOTO_CUTOFF = 0.85   # structure: max_tanimoto >= cutoff => not novel
DEFAULT_SEQ_ID_CUTOFF = 0.80     # sequence: identity >= cutoff => occupied (peptides)
MORGAN_RADIUS = 2
MORGAN_NBITS = 2048

# --------------------------------------------------------------------------------------------
# RDKit (optional at import; axes degrade honestly if absent)
# --------------------------------------------------------------------------------------------
try:
    from rdkit import Chem, RDLogger, DataStructs
    from rdkit.Chem import AllChem, Descriptors
    RDLogger.DisableLog("rdApp.*")
    _RDKIT = True
except Exception as _e:   # pragma: no cover - env without rdkit
    _RDKIT = False
    _RDKIT_ERR = str(_e)


# --------------------------------------------------------------------------------------------
# Peptide -> SMILES (RDKit-native): build linear with MolFromSequence, macrocyclise by RWMol.
# --------------------------------------------------------------------------------------------
# Average residue masses (for a construction sanity check only).
_AA_RES_MASS = {
    "A": 71.08, "R": 156.19, "N": 114.10, "D": 115.09, "C": 103.14, "E": 129.12,
    "Q": 128.13, "G": 57.05, "H": 137.14, "I": 113.16, "L": 113.16, "K": 128.17,
    "M": 131.19, "F": 147.18, "P": 97.12, "S": 87.08, "T": 101.10, "W": 186.21,
    "Y": 163.18, "V": 99.13,
}
_WATER = 18.015

# SMARTS to locate the backbone N-terminus and C-terminus unambiguously
# (disambiguated from Lys/Arg sidechain amines and Asp/Glu sidechain carboxyls:
# the backbone atoms sit on an alpha carbon that carries the opposite backbone group).
if _RDKIT:
    _NTERM = Chem.MolFromSmarts("[NX3;!$([NX3][CX3]=[OX1]);!$([NX3]=*)][CX4][CX3]=[OX1]")
    _CTERM = Chem.MolFromSmarts("[NX3][CX4][CX3](=[OX1])[OX2H1]")


def peptide_to_smiles(seq: str, cyclic: bool = True) -> Tuple[Optional[str], str]:
    """One-letter peptide -> canonical SMILES. Returns (smiles|None, status).

    cyclic=True builds a head-to-tail backbone macrocycle (our CRO panels). The
    construction is RDKit-native (correct stereo / residue chemistry) and is
    validated by molecular weight against the residue-sum formula before return.
    """
    if not _RDKIT:
        return None, "rdkit_unavailable"
    seq = (seq or "").strip().upper()
    if not seq or any(a not in _AA_RES_MASS for a in seq):
        return None, "bad_sequence"
    m = Chem.MolFromSequence(seq)
    if m is None:
        return None, "molfromsequence_failed"
    if not cyclic:
        return Chem.MolToSmiles(m), "ok_linear"

    # Macrocyclise: delete the C-terminal hydroxyl O, bond C-term carbonyl C -> N-term N.
    n_match = m.GetSubstructMatch(_NTERM)
    c_match = m.GetSubstructMatch(_CTERM)
    if not n_match or not c_match:
        # Fall back to the linear form rather than fabricate a ring.
        return Chem.MolToSmiles(m), "ok_linear_no_termini"
    n_idx = n_match[0]           # backbone N-terminal nitrogen
    c_carbonyl = c_match[2]      # C-terminal carbonyl carbon
    oh_oxygen = c_match[4]       # its hydroxyl oxygen (to delete)

    rw = Chem.RWMol(m)
    rw.AddBond(c_carbonyl, n_idx, Chem.BondType.SINGLE)
    rw.RemoveAtom(oh_oxygen)
    try:
        cyc = rw.GetMol()
        Chem.SanitizeMol(cyc)
    except Exception as e:
        return Chem.MolToSmiles(m), "ok_linear_sanitize_failed:" + str(e)[:60]

    # Validate by MW: cyclic head-to-tail MW ~= sum(residue avg masses) - 0 extra water
    # (each residue already = AA - H2O; head-to-tail closure removes the last water too,
    #  which is exactly sum of residue masses).
    exp_mw = sum(_AA_RES_MASS[a] for a in seq)
    got_mw = Descriptors.MolWt(cyc)
    if abs(got_mw - exp_mw) > 2.5:   # avg-mass tolerance over typical lengths
        return Chem.MolToSmiles(m), "ok_linear_mw_mismatch(%.1f vs %.1f)" % (got_mw, exp_mw)
    return Chem.MolToSmiles(cyc), "ok_cyclic"


# --------------------------------------------------------------------------------------------
# Structure axis — Morgan/ECFP Tanimoto vs a known-actives library.
# --------------------------------------------------------------------------------------------
def _morgan(smiles: str):
    if not _RDKIT:
        return None
    mol = Chem.MolFromSmiles(smiles)
    if mol is None:
        return None
    return AllChem.GetMorganFingerprintAsBitVect(mol, MORGAN_RADIUS, nBits=MORGAN_NBITS)


@dataclass
class KnownActivesLibrary:
    """Fingerprinted known-actives library for nearest-neighbour novelty."""
    fps: list                                   # list of rdkit ExplicitBitVect
    ids: List[str]
    smiles: List[str]
    tags: List[dict] = field(default_factory=list)   # per-row metadata (e.g. is_pdl1)

    def __len__(self):
        return len(self.fps)

    def nearest(self, query_fp, restrict_idx: Optional[Sequence[int]] = None):
        """Return (max_tanimoto, nearest_id, nearest_smiles, nearest_tag)."""
        if query_fp is None or not self.fps:
            return None
        idxs = range(len(self.fps)) if restrict_idx is None else restrict_idx
        best = -1.0
        best_i = -1
        for i in idxs:
            s = DataStructs.TanimotoSimilarity(query_fp, self.fps[i])
            if s > best:
                best, best_i = s, i
        if best_i < 0:
            return None
        return (round(best, 4), self.ids[best_i], self.smiles[best_i],
                self.tags[best_i] if self.tags else {})


def build_library(csv_path: str, smiles_col: str = "smiles", id_col: str = "id",
                  tag_cols: Sequence[str] = (), max_rows: Optional[int] = None,
                  cache_path: Optional[str] = None) -> KnownActivesLibrary:
    """Fingerprint a known-actives CSV once; cache to pickle keyed by (path,mtime,n,cols)."""
    import csv as _csv
    csv_path = str(csv_path)
    key = None
    if cache_path:
        try:
            mt = os.path.getmtime(csv_path)
        except OSError:
            mt = 0
        key = {"path": csv_path, "mtime": mt, "max_rows": max_rows,
               "smiles_col": smiles_col, "tag_cols": list(tag_cols),
               "radius": MORGAN_RADIUS, "nbits": MORGAN_NBITS}
        if os.path.exists(cache_path):
            try:
                with open(cache_path, "rb") as f:
                    blob = pickle.load(f)
                if blob.get("key") == key:
                    lib = blob["lib"]
                    log.info("novelty: loaded cached library (%d fps) from %s", len(lib), cache_path)
                    return lib
            except Exception as e:
                log.warning("novelty: cache read failed (%s); rebuilding", e)

    if not _RDKIT:
        raise RuntimeError("RDKit unavailable: cannot fingerprint library (%s)" % _RDKIT_ERR)

    fps, ids, smis, tags = [], [], [], []
    with open(csv_path, newline="") as f:
        rdr = _csv.DictReader(f)
        for i, row in enumerate(rdr):
            if max_rows is not None and i >= max_rows:
                break
            smi = (row.get(smiles_col) or "").strip()
            if not smi:
                continue
            fp = _morgan(smi)
            if fp is None:
                continue
            fps.append(fp)
            ids.append((row.get(id_col) or str(i)).strip())
            smis.append(smi)
            if tag_cols:
                tags.append({c: row.get(c) for c in tag_cols})
    lib = KnownActivesLibrary(fps=fps, ids=ids, smiles=smis, tags=tags)
    log.info("novelty: fingerprinted %d known actives from %s", len(lib), csv_path)
    if cache_path and key is not None:
        try:
            with open(cache_path, "wb") as f:
                pickle.dump({"key": key, "lib": lib}, f)
        except Exception as e:
            log.warning("novelty: cache write failed (%s)", e)
    return lib


# --------------------------------------------------------------------------------------------
# Sequence axis (peptides) — normalised global-alignment identity, pure Python.
# --------------------------------------------------------------------------------------------
def sequence_identity(a: str, b: str) -> float:
    """Normalised identity in [0,1] from a Needleman-Wunsch global alignment
    (match=1, mismatch=0, gap=-1), divided by the shorter length. Pure Python."""
    a = (a or "").upper(); b = (b or "").upper()
    if not a or not b:
        return 0.0
    la, lb = len(a), len(b)
    prev = list(range(0, -(lb + 1), -1))
    for i in range(1, la + 1):
        cur = [-i] + [0] * lb
        ai = a[i - 1]
        for j in range(1, lb + 1):
            diag = prev[j - 1] + (1 if ai == b[j - 1] else 0)
            cur[j] = max(diag, prev[j] - 1, cur[j - 1] - 1)
        prev = cur
    score = prev[lb]
    return max(0.0, score / float(min(la, lb)))


def nearest_sequence(query: str, ref_seqs: Sequence[str]) -> Tuple[float, Optional[int]]:
    best, best_i = 0.0, None
    for i, r in enumerate(ref_seqs):
        s = sequence_identity(query, r)
        if s > best:
            best, best_i = s, i
    return round(best, 4), best_i


# --------------------------------------------------------------------------------------------
# Patent axis (opt-in, network) — coarse SureChEMBL/PubChem presence.
# --------------------------------------------------------------------------------------------
def _urlopen_retry(req, timeout: int, retries: int = 3):
    """urlopen with backoff on PubChem throttling (429/503). Re-raises other HTTPErrors."""
    import time as _t
    for attempt in range(retries):
        try:
            return urllib.request.urlopen(req, timeout=timeout)
        except urllib.error.HTTPError as he:
            if he.code in (429, 503) and attempt < retries - 1:
                _t.sleep(0.5 * (2 ** attempt))   # PUG-REST ~5 req/s; back off politely
                continue
            raise


def patent_presence(smiles: str, timeout: int = 30) -> dict:
    """Coarse patent-presence via PubChem PUG-REST (SureChEMBL xrefs). Best-effort;
    records its own errors, never raises. Mirrors compound_novelty_scorer."""
    out = {"checked": True, "source": "surechembl_via_pubchem", "present": None, "n_patents": None}
    try:
        base = "https://pubchem.ncbi.nlm.nih.gov/rest/pug"
        # POST the SMILES in the body: cyclic-peptide SMILES are far too long for a GET URL
        # (the GET path 400s), so structure->CID resolution must go through POST.
        body = urllib.parse.urlencode({"smiles": smiles}).encode()
        cid_req = urllib.request.Request(base + "/compound/smiles/cids/JSON", data=body,
                                         headers={"Content-Type": "application/x-www-form-urlencoded"})
        try:
            with _urlopen_retry(cid_req, timeout) as r:
                cids = (json.loads(r.read().decode()).get("IdentifierList", {}) or {}).get("CID", [])
        except urllib.error.HTTPError as he:
            # 404 = SMILES not registered in PubChem: a real "not present" for exact structure.
            if he.code == 404:
                out["present"] = False; out["n_patents"] = 0; out["pubchem_cid"] = None
                return out
            raise
        cids = [c for c in cids if c]   # drop the 0 sentinel ("no match")
        if not cids:
            out["present"] = False; out["n_patents"] = 0; out["pubchem_cid"] = None
            return out
        cid = cids[0]; out["pubchem_cid"] = cid
        xr_url = base + "/compound/cid/" + str(cid) + "/xrefs/PatentID/JSON"
        try:
            with _urlopen_retry(urllib.request.Request(xr_url), timeout) as r:
                info = (json.loads(r.read().decode()).get("InformationList", {}) or {}).get("Information", [])
            pats = info[0].get("PatentID", []) if info else []
            out["present"] = len(pats) > 0
            out["n_patents"] = len(pats)
        except urllib.error.HTTPError as he:
            if he.code == 404:
                out["present"] = False; out["n_patents"] = 0
            else:
                out["error"] = "patent xref HTTP %d" % he.code
    except Exception as e:
        out["error"] = str(e)
    return out


# --------------------------------------------------------------------------------------------
# Verdict
# --------------------------------------------------------------------------------------------
@dataclass
class NoveltyVerdict:
    candidate_id: str
    modality: str
    smiles: Optional[str]
    seq: Optional[str]
    # structure axis
    structure_status: str = "unavailable"
    max_tanimoto: Optional[float] = None
    nearest_known_id: Optional[str] = None
    nearest_known_smiles: Optional[str] = None
    nearest_known_tag: dict = field(default_factory=dict)
    tanimoto_cutoff: float = DEFAULT_TANIMOTO_CUTOFF
    # sequence axis
    sequence_status: str = "not_run"
    max_seq_identity: Optional[float] = None
    nearest_seq: Optional[str] = None
    seq_id_cutoff: float = DEFAULT_SEQ_ID_CUTOFF
    # patent axis
    patent: dict = field(default_factory=lambda: {"checked": False})
    # verdict
    occupied: Optional[bool] = None          # True/False, or None if nothing ran (fail-open)
    verdict: str = "unknown"                  # novel | known_active | patent_risk | sequence_match | unknown
    reasons: List[str] = field(default_factory=list)

    def finalize(self):
        reasons, occ = [], False
        ran = False
        if self.structure_status.startswith("ok") and self.max_tanimoto is not None:
            ran = True
            if self.max_tanimoto >= self.tanimoto_cutoff:
                occ = True
                reasons.append("structure: max_tanimoto %.3f >= %.2f (nearest known %s)"
                               % (self.max_tanimoto, self.tanimoto_cutoff, self.nearest_known_id))
        if self.sequence_status.startswith("ok") and self.max_seq_identity is not None:
            ran = True
            if self.max_seq_identity >= self.seq_id_cutoff:
                occ = True
                reasons.append("sequence: identity %.3f >= %.2f" % (self.max_seq_identity, self.seq_id_cutoff))
        if self.patent.get("checked") and self.patent.get("present") is True:
            ran = True
            occ = True
            reasons.append("patent: present (n=%s)" % self.patent.get("n_patents"))
        if not ran:
            self.occupied = None
            self.verdict = "unknown"
            self.reasons = ["no axis could run (fail-open)"]
            return self
        self.occupied = occ
        if not occ:
            self.verdict = "novel"
            self.reasons = ["no known-active / patent / sequence hit above cutoffs"]
        else:
            if any(r.startswith("patent") for r in reasons):
                self.verdict = "patent_risk"
            elif any(r.startswith("structure") for r in reasons):
                self.verdict = "known_active"
            else:
                self.verdict = "sequence_match"
            self.reasons = reasons
        return self


def score_candidate(candidate_id: str,
                    smiles: Optional[str] = None,
                    seq: Optional[str] = None,
                    modality: str = "auto",
                    cyclic: bool = True,
                    library: Optional[KnownActivesLibrary] = None,
                    ref_seqs: Optional[Sequence[str]] = None,
                    restrict_tag: Optional[Tuple[str, str]] = None,
                    tanimoto_cutoff: float = DEFAULT_TANIMOTO_CUTOFF,
                    seq_id_cutoff: float = DEFAULT_SEQ_ID_CUTOFF,
                    check_patents: bool = False) -> NoveltyVerdict:
    """Score one candidate across the three axes and return a finalized verdict.

    restrict_tag: optional (col, value) to additionally report the nearest neighbour
    WITHIN a same-target subset (e.g. ("is_pdl1","True")) — the sharpest FTO signal.
    """
    if modality == "auto":
        modality = "peptide" if (seq and not smiles) else ("small_molecule" if smiles else "unknown")

    v = NoveltyVerdict(candidate_id=candidate_id, modality=modality, smiles=smiles, seq=seq,
                       tanimoto_cutoff=tanimoto_cutoff, seq_id_cutoff=seq_id_cutoff)

    # Build SMILES for peptides if not supplied.
    if smiles is None and seq:
        smiles, status = peptide_to_smiles(seq, cyclic=cyclic)
        v.smiles = smiles
        if smiles is None:
            v.structure_status = "smiles_build_failed:" + status
    # Structure axis
    if v.smiles and library is not None and len(library) > 0:
        qfp = _morgan(v.smiles)
        if qfp is None:
            v.structure_status = "query_unparseable"
        else:
            res = library.nearest(qfp)
            if res:
                v.max_tanimoto, v.nearest_known_id, v.nearest_known_smiles, v.nearest_known_tag = res
                v.structure_status = "ok"
                # same-target subset (sharpest FTO signal), reported in the tag.
                if restrict_tag and library.tags:
                    col, val = restrict_tag
                    sub = [i for i, t in enumerate(library.tags) if str(t.get(col)) == str(val)]
                    sub_res = library.nearest(qfp, restrict_idx=sub) if sub else None
                    if sub_res:
                        v.nearest_known_tag = dict(v.nearest_known_tag)
                        v.nearest_known_tag["same_target_max_tanimoto"] = sub_res[0]
                        v.nearest_known_tag["same_target_nearest_id"] = sub_res[1]
                        v.nearest_known_tag["same_target_subset"] = col + "=" + str(val)
            else:
                v.structure_status = "ok_empty"
    elif library is None:
        v.structure_status = "no_library"
    elif not v.smiles:
        pass  # structure_status already set to a build-failure reason

    # Sequence axis (peptides)
    if seq and ref_seqs:
        mi, _ = nearest_sequence(seq, ref_seqs)
        v.max_seq_identity = mi
        v.sequence_status = "ok"

    # Patent axis
    if check_patents and v.smiles:
        v.patent = patent_presence(v.smiles)

    return v.finalize()


# --------------------------------------------------------------------------------------------
# CLI — score a CRO panel / a single candidate.
# --------------------------------------------------------------------------------------------
def _default_library_cache() -> str:
    return str(ROOT / "data" / "_registry_cache" / "novelty_lib_binding_affinity_v1.pkl")


def main(argv=None):
    import argparse
    ap = argparse.ArgumentParser(description="Drug novelty / FTO gate (small molecule + peptide).")
    ap.add_argument("--panel", help="CSV with candidate rows")
    ap.add_argument("--id-col", default="Item")
    ap.add_argument("--seq-col", default="Sequence_N_to_C")
    ap.add_argument("--smiles-col", default=None, help="SMILES column (small-molecule panels)")
    ap.add_argument("--seq", help="single peptide sequence")
    ap.add_argument("--smiles", help="single SMILES")
    ap.add_argument("--linear", action="store_true", help="peptides are linear (default head-to-tail cyclic)")
    ap.add_argument("--library", default=str(ROOT / "data/raw/binding_affinity/binding_affinity_v1.csv"))
    ap.add_argument("--library-smiles-col", default="smiles")
    ap.add_argument("--library-id-col", default="id")
    ap.add_argument("--library-tag-cols", nargs="*", default=["is_pdl1", "is_avb6", "target_name"])
    ap.add_argument("--max-rows", type=int, default=None)
    ap.add_argument("--restrict-tag", nargs=2, metavar=("COL", "VAL"), default=None)
    ap.add_argument("--tanimoto-cutoff", type=float, default=DEFAULT_TANIMOTO_CUTOFF)
    ap.add_argument("--check-patents", action="store_true")
    ap.add_argument("--out", help="write verdicts JSON here")
    args = ap.parse_args(argv)

    logging.basicConfig(level=logging.INFO, format="%(message)s")
    cyclic = not args.linear

    lib = None
    if args.library and os.path.exists(args.library):
        lib = build_library(args.library, smiles_col=args.library_smiles_col,
                            id_col=args.library_id_col, tag_cols=args.library_tag_cols,
                            max_rows=args.max_rows, cache_path=_default_library_cache())
    else:
        log.warning("novelty: library not found at %s — structure axis will be unavailable", args.library)

    restrict = tuple(args.restrict_tag) if args.restrict_tag else None
    verdicts = []

    if args.seq or args.smiles:
        v = score_candidate("cli", smiles=args.smiles, seq=args.seq, cyclic=cyclic,
                            library=lib, restrict_tag=restrict,
                            tanimoto_cutoff=args.tanimoto_cutoff, check_patents=args.check_patents)
        verdicts.append(asdict(v))
    elif args.panel:
        import csv as _csv
        with open(args.panel, newline="") as f:
            for row in _csv.DictReader(f):
                cid = row.get(args.id_col) or ""
                seq = row.get(args.seq_col) if args.seq_col else None
                smi = row.get(args.smiles_col) if args.smiles_col else None
                # per-row target restriction if the panel names a target
                rt = restrict
                v = score_candidate(cid, smiles=smi, seq=seq, cyclic=cyclic, library=lib,
                                    restrict_tag=rt, tanimoto_cutoff=args.tanimoto_cutoff,
                                    check_patents=args.check_patents)
                verdicts.append(asdict(v))
                print("%-12s %-14s occupied=%s verdict=%-12s max_tanimoto=%s" %
                      (cid, (seq or smi or "")[:14], v.occupied, v.verdict, v.max_tanimoto))
    else:
        ap.error("provide --panel, or --seq/--smiles")

    summary = {
        "n": len(verdicts),
        "occupied": sum(1 for v in verdicts if v["occupied"] is True),
        "novel": sum(1 for v in verdicts if v["verdict"] == "novel"),
        "unknown": sum(1 for v in verdicts if v["verdict"] == "unknown"),
        "library_size": (len(lib) if lib else 0),
        "tanimoto_cutoff": args.tanimoto_cutoff,
        "patents_checked": bool(args.check_patents),
    }
    out = {"summary": summary, "verdicts": verdicts}
    if args.out:
        Path(args.out).parent.mkdir(parents=True, exist_ok=True)
        with open(args.out, "w") as f:
            json.dump(out, f, indent=2)
        log.info("novelty: wrote %s", args.out)
    print("SUMMARY:", json.dumps(summary))
    return out


if __name__ == "__main__":
    main()
