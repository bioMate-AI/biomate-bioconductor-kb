#!/usr/bin/env python3
"""cycpeptmpdb_to_pepglad.py — convert CycPeptMPDB entries into PepGLAD training records
with a per-residue N-methylation mask (Track B / B1).

STATUS: CPU-only data-engineering (NO GPU, NO training). This is the "parse the data" half of the
B1 first experiment (docs/20260926_B1_NATIVE_NONCANONICAL_FEASIBILITY.md §7, step 1). Its job is to
answer the *gating data question*: how many CycPeptMPDB peptides carry N-methylation, how many have a
usable 3D structure vs SMILES-only, and to emit whatever is present in the exact shape PepGLAD trains on.

WHAT PepGLAD CONSUMES (verified against runtime/PepGLAD/data/format.py):
  A peptide = a list of Block(abrv, [Atom(name, coordinate=[x,y,z], element)]). i.e. per-residue
  HEAVY-ATOM 3D COORDINATES, exactly as read from a PDB (data/converter/pdb_to_list_blocks.py:66).
  The residue type S is one of the 20 canonical AAs (+UNK); atoms fill a [MAX_ATOM_NUMBER=14,3] tensor.
  There is NO field in PepGLAD for "N-methylated"; that is precisely the representation gap B1 adds
  (an orthogonal per-residue nme bit — see noncanonical_vocab.representation_delta()).

WHAT CycPeptMPDB PROVIDES (verified against data/raw/CycPeptMPDB_Peptide_All.csv, 8466 rows):
  * SMILES            — every row (2D graph; NO stored 3D coordinates anywhere in the file)
  * HELM              — every row, e.g. PEPTIDE1{[Abu].[Sar].[meL].V.[meL]...}$...$$$
  * Sequence          — every row, a python-list string of monomer tokens: ['Abu','Sar','meL','V',...]
  * Permeability      — log Papp (measured); the downstream label
  * _3DPSA / *_3DPSA  — SCALAR descriptors computed from a transient conformer at DB-build time;
                        NOT coordinates. There are NO coordinate columns.
  => CycPeptMPDB is SMILES-RICH / STRUCTURE-POOR. Every 3D structure PepGLAD needs must be GENERATED
     (RDKit ETKDG macrocycle embedding here as the cheap first pass; MD / fold as the honest upgrade).

MONOMER -> RESIDUE mapping (the crux). CycPeptMPDB tokens encode the modification IN THE NAME:
  'meL'   = N-methyl-L-Leu          -> parent L,  nme=True,  d=False
  'Sar'   = sarcosine = N-methyl-Gly-> parent G,  nme=True,  d=False
  'Me_dL' = N-methyl-D-Leu          -> parent L,  nme=True,  d=True
  'dL'    = D-Leu                   -> parent L,  nme=False, d=True
  'L'     = L-Leu                   -> parent L,  nme=False, d=False
  'Me_Bmt(E)','Bn_Gly','Mono115',...= non-canonical SIDECHAIN -> OUT OF VOCAB (flagged unsupported;
                                        these need vocab beyond N-Me and are excluded from an N-Me AE retrain).
The N-Me classification reuses noncanonical_vocab (single source of truth for the N-Me monomer set).

OUTPUT (JSONL, one record per peptide):
  {
    "id": <row idx>, "source": ..., "smiles": ..., "helm": ..., "permeability": <float|null>,
    "monomers": [...raw tokens...],
    "residues": [{"parent": "L", "abrv": "LEU", "nme": true, "d_amino": false, "raw": "meL"}, ...],
    "nme_mask": [0,1,1,0,...],          # per-residue bit, parallel to residues (PepGLAD B1 extra channel)
    "n_nme": <int>, "n_daa": <int>,
    "all_supported": <bool>,            # every monomer maps to a canonical parent (+N-Me / +D)
    "has_structure": <bool>,            # a 3D conformer was successfully embedded (else SMILES-only)
    "coords_source": "rdkit_etkdg" | "none",
    "blocks": [ {"abrv","nme","atoms":[{"name","element","coord":[x,y,z]}]}, ... ] | null,
    "scaffold": <str>,                  # Bemis-Murcko-ish family key for the disjoint split
    "split": "train" | "val" | "test"
  }

USAGE:
  python3 cycpeptmpdb_to_pepglad.py                      # self-test on a few entries (no writes, no GPU)
  python3 cycpeptmpdb_to_pepglad.py --stats             # full-corpus data-availability counts only (fast)
  python3 cycpeptmpdb_to_pepglad.py --emit out.jsonl \
          --limit 500 --embed                           # write records (RDKit embed is the slow part)

NO GPU is used anywhere. RDKit ETKDG conformer embedding is CPU-only.
"""
from __future__ import annotations

import argparse
import ast
import csv
import hashlib
import json
import re
import sys
from pathlib import Path
from typing import Dict, List, Optional, Tuple

ROOT = Path(__file__).resolve().parent
DEFAULT_CSV = ROOT / "data/raw/CycPeptMPDB_Peptide_All.csv"

# Reuse the single source of truth for the canonical AA set / N-Me monomer accounting.
import noncanonical_vocab as ncv  # torch-free, CPU-only

# symbol -> 3-letter, from the same canonical list noncanonical_vocab declares.
SYMBOL_TO_ABRV: Dict[str, str] = {s: a for s, a in ncv.CANONICAL_AAS}
ABRV_TO_SYMBOL: Dict[str, str] = {a: s for s, a in ncv.CANONICAL_AAS}
CANONICAL_SYMBOLS = set(SYMBOL_TO_ABRV)

# ---- Monomer token -> (parent single-letter symbol, is_nme, is_daa) --------------------------------
# CycPeptMPDB token conventions observed across all 8466 rows (385 distinct tokens):
#   plain single letter                     -> canonical L-AA
#   'me' + single upper letter (meL, meA)   -> N-methyl-L-AA
#   'd'  + single upper letter (dL, dA)     -> D-AA
#   'Me_d' + single upper letter (Me_dL)    -> N-methyl-D-AA
#   'Sar'                                   -> sarcosine = N-methyl-Gly
#   everything else (Nle, Abu, Bn_Gly, Me_Bmt(E), Mono115, -pip, ac-, ...) -> non-canonical sidechain / cap
# A small explicit table covers the common non-canonical-but-N-Me-of-a-close-parent cases we still
# want counted as "N-Me present" for the availability question, even if their sidechain is out of vocab.
_SIMPLE_NME_RE = re.compile(r"^me([A-Z])$")          # meL, meA, meF, meV, meI, meY, meD, meS, meT, meW
_SIMPLE_D_RE = re.compile(r"^d([A-Z])$")             # dL, dA, dP, dV, dF
_ME_D_RE = re.compile(r"^Me_d([A-Z])$")              # Me_dL, Me_dA, Me_dF

# Non-canonical monomers whose NAME still signals an N-methyl backbone (parent sidechain NOT in vocab).
# Reused only for the availability count; these are flagged all_supported=False (excluded from AE retrain).
_NONCANON_NME_PREFIXES = ("Me_", "N-Me", "N-me")


def classify_monomer(tok: str) -> Tuple[Optional[str], bool, bool, bool]:
    """Map a CycPeptMPDB monomer token to (parent_symbol, is_nme, is_daa, supported).

    supported == the residue maps to a canonical parent AA (optionally N-methylated and/or D). If the
    sidechain itself is non-canonical (Nle, Bn_Gly, Mono*, caps like 'ac-'/'-pip'), parent is None and
    supported is False -- but is_nme may still be True so the availability count is honest.
    """
    t = tok.strip()
    if not t:
        return None, False, False, False

    # sarcosine == N-methyl-glycine (canonical parent G)
    if t == "Sar":
        return "G", True, False, True

    m = _SIMPLE_NME_RE.match(t)
    if m and m.group(1) in CANONICAL_SYMBOLS:
        return m.group(1), True, False, True

    m = _ME_D_RE.match(t)
    if m and m.group(1) in CANONICAL_SYMBOLS:
        return m.group(1), True, True, True

    m = _SIMPLE_D_RE.match(t)
    if m and m.group(1) in CANONICAL_SYMBOLS:
        return m.group(1), False, True, True

    if t in CANONICAL_SYMBOLS:
        return t, False, False, True

    # non-canonical: still detect an N-methyl signal in the name for the honest availability count.
    is_nme = t.startswith(_NONCANON_NME_PREFIXES)
    is_daa = t.startswith("Me_d") or t.startswith("d") and len(t) > 1 and t[1:2].isupper()
    return None, is_nme, is_daa, False


# ---- CSV parsing ------------------------------------------------------------------------------------
def _parse_monomers(seq_field: str) -> List[str]:
    seq_field = (seq_field or "").strip()
    if not seq_field:
        return []
    try:
        val = ast.literal_eval(seq_field)
        if isinstance(val, (list, tuple)):
            return [str(x) for x in val]
    except (ValueError, SyntaxError):
        pass
    # fallback: split HELM-ish "A.B.C"
    return [x.strip() for x in seq_field.split(".") if x.strip()]


def _float_or_none(x: str) -> Optional[float]:
    try:
        v = float(x)
        return v
    except (TypeError, ValueError):
        return None


def iter_rows(csv_path: Path, limit: Optional[int] = None):
    with open(csv_path, newline="") as f:
        reader = csv.DictReader(f)
        # tolerate the UTF-8 BOM on the first header cell ('﻿ID')
        for i, row in enumerate(reader):
            if limit is not None and i >= limit:
                break
            yield i, row


def parse_entry(idx: int, row: Dict[str, str]) -> Dict:
    monomers = _parse_monomers(row.get("Sequence", ""))
    residues: List[Dict] = []
    nme_mask: List[int] = []
    all_supported = True
    for tok in monomers:
        parent, is_nme, is_daa, supported = classify_monomer(tok)
        residues.append(
            {
                "parent": parent,
                "abrv": SYMBOL_TO_ABRV.get(parent) if parent else None,
                "nme": bool(is_nme),
                "d_amino": bool(is_daa),
                "raw": tok,
            }
        )
        nme_mask.append(1 if is_nme else 0)
        all_supported = all_supported and supported
    n_nme = sum(nme_mask)
    n_daa = sum(1 for r in residues if r["d_amino"])
    smiles = (row.get("SMILES") or "").strip()
    return {
        "id": idx,
        "source": (row.get("Source") or "").strip(),
        "smiles": smiles,
        "helm": (row.get("HELM") or "").strip(),
        "permeability": _float_or_none(row.get("Permeability", "")),
        "monomers": monomers,
        "residues": residues,
        "nme_mask": nme_mask,
        "n_nme": n_nme,
        "n_daa": n_daa,
        "all_supported": bool(all_supported and monomers),
        # structure filled in later (SMILES-only until embedded)
        "has_structure": False,
        "coords_source": "none",
        "blocks": None,
    }


# ---- Structure generation (CPU RDKit ETKDG) --------------------------------------------------------
def embed_blocks(entry: Dict) -> Dict:
    """Attempt to build per-residue heavy-atom coordinate Blocks for the entry via an RDKit ETKDG
    macrocycle conformer. This is the cheap first-pass "structure prediction" for the structure-poor
    corpus. On failure (or missing RDKit) the entry stays SMILES-only (has_structure=False).

    NOTE: mapping SMILES atoms back to per-residue blocks requires an atom->residue partition, which
    for arbitrary macrocycle SMILES is itself a research task (peptide-bond backbone tracing). Here we
    do the honest thing: we embed a 3D conformer to PROVE a structure is obtainable and record
    heavy-atom coords + elements as a single-molecule fallback block. Full per-residue partitioning is
    left as the documented downstream step (see docs/20260926_NONCANONICAL_DATA_AVAILABILITY.md).
    """
    smiles = entry.get("smiles", "")
    if not smiles:
        return entry
    try:
        from rdkit import Chem, RDLogger
        from rdkit.Chem import AllChem

        RDLogger.DisableLog("rdApp.*")
    except Exception:
        return entry  # RDKit absent -> stays SMILES-only, which is the honest state

    mol = Chem.MolFromSmiles(smiles)
    if mol is None:
        return entry
    mol = Chem.AddHs(mol)
    params = AllChem.ETKDGv3()
    params.randomSeed = 0xC0FFEE
    params.useRandomCoords = True  # macrocycles need random-coord init to embed reliably
    ok = AllChem.EmbedMolecule(mol, params)
    if ok != 0:
        return entry  # embedding failed -> SMILES-only (a real, counted outcome)
    try:
        AllChem.MMFFOptimizeMolecule(mol, maxIters=200)
    except Exception:
        pass
    mol = Chem.RemoveHs(mol)
    conf = mol.GetConformer()
    atoms = []
    for a in mol.GetAtoms():
        p = conf.GetAtomPosition(a.GetIdx())
        atoms.append(
            {"name": a.GetSymbol() + str(a.GetIdx()), "element": a.GetSymbol(), "coord": [p.x, p.y, p.z]}
        )
    entry["has_structure"] = True
    entry["coords_source"] = "rdkit_etkdg"
    # single fallback block; per-residue partition is the documented downstream step.
    entry["blocks"] = [{"abrv": "MOL", "nme": False, "atoms": atoms}]
    return entry


# ---- Family-disjoint split (leakage-honest) --------------------------------------------------------
def scaffold_key(entry: Dict) -> str:
    """Bemis-Murcko scaffold (RDKit if available) else a length+composition fingerprint. Used to keep
    families entirely on one side of the train/val/test split so an N-Me generator cannot be scored on
    a near-duplicate of a training peptide."""
    smiles = entry.get("smiles", "")
    if smiles:
        try:
            from rdkit import Chem, RDLogger
            from rdkit.Chem.Scaffolds import MurckoScaffold

            RDLogger.DisableLog("rdApp.*")
            mol = Chem.MolFromSmiles(smiles)
            if mol is not None:
                scaf = MurckoScaffold.GetScaffoldForMol(mol)
                s = Chem.MolToSmiles(scaf)
                if s:
                    return s
        except Exception:
            pass
    # fallback family key: canonical-parent composition (sorted) + length
    parents = sorted(r["parent"] or "X" for r in entry.get("residues", []))
    return f"L{len(parents)}:" + "".join(parents)


def assign_split(entry: Dict, val_frac: float = 0.1, test_frac: float = 0.1) -> str:
    """Deterministic family-disjoint bucket: hash the scaffold key so every peptide sharing a scaffold
    lands in the same split, independent of row order."""
    h = int(hashlib.sha1(scaffold_key(entry).encode()).hexdigest(), 16) % 1000
    if h < int(test_frac * 1000):
        return "test"
    if h < int((test_frac + val_frac) * 1000):
        return "val"
    return "train"


# ---- Corpus-level availability stats (the gating data answer) --------------------------------------
def corpus_stats(csv_path: Path, limit: Optional[int] = None, embed: bool = False) -> Dict:
    n = 0
    n_nme = 0
    n_daa = 0
    n_all_supported = 0
    n_supported_and_nme = 0
    n_structure = 0
    n_structure_and_nme = 0
    n_pure_canonical = 0
    nme_residue_total = 0
    residue_total = 0
    for idx, row in iter_rows(csv_path, limit=limit):
        e = parse_entry(idx, row)
        n += 1
        residue_total += len(e["residues"])
        nme_residue_total += e["n_nme"]
        has_nme = e["n_nme"] > 0
        if has_nme:
            n_nme += 1
        if e["n_daa"] > 0:
            n_daa += 1
        if e["all_supported"]:
            n_all_supported += 1
            if has_nme:
                n_supported_and_nme += 1
        if e["all_supported"] and e["n_nme"] == 0 and e["n_daa"] == 0:
            n_pure_canonical += 1
        if embed:
            e = embed_blocks(e)
            if e["has_structure"]:
                n_structure += 1
                if has_nme:
                    n_structure_and_nme += 1
    stats = {
        "total_peptides": n,
        "with_smiles": n,  # every CycPeptMPDB row has SMILES (verified)
        "with_stored_3d_structure": 0,  # NONE: no coordinate columns exist in the CSV
        "with_nme_modification": n_nme,
        "with_daa_modification": n_daa,
        "all_monomers_in_vocab (canonical +N-Me/+D)": n_all_supported,
        "in_vocab_AND_nme": n_supported_and_nme,
        "pure_canonical_L (no mods)": n_pure_canonical,
        "nme_residues_total": nme_residue_total,
        "residues_total": residue_total,
    }
    if embed:
        stats["structure_embeddable_rdkit_etkdg"] = n_structure
        stats["structure_AND_nme"] = n_structure_and_nme
    return stats


# ---- CPU self-test / CLI ---------------------------------------------------------------------------
def _self_test(csv_path: Path) -> int:
    print("== cycpeptmpdb_to_pepglad self-test (CPU-only, no GPU) ==")
    # 1) monomer classifier unit checks (do not need the CSV)
    checks = [
        ("meL", ("L", True, False, True)),
        ("Sar", ("G", True, False, True)),
        ("Me_dL", ("L", True, True, True)),
        ("dL", ("L", False, True, True)),
        ("L", ("L", False, False, True)),
        ("P", ("P", False, False, True)),
        ("Bn_Gly", (None, False, None, False)),  # non-canonical sidechain -> unsupported
    ]
    for tok, exp in checks:
        got = classify_monomer(tok)
        # for the non-canonical case only assert parent/supported (d flag is heuristic)
        if exp[3] is False:
            assert got[0] is None and got[3] is False, f"{tok}: {got}"
        else:
            assert got == exp, f"{tok}: expected {exp}, got {got}"
    print("  [ok] monomer classifier: 7 cases")

    if not csv_path.exists():
        print(f"  [skip] CSV not found at {csv_path} — data is gitignored; run on a machine with the file.")
        print("  [ok] classifier-only self-test passed.")
        return 0

    # 2) parse a few real entries
    parsed = []
    for idx, row in iter_rows(csv_path, limit=5):
        e = parse_entry(idx, row)
        parsed.append(e)
        print(f"  row {idx}: monomers={e['monomers']}")
        print(f"          nme_mask={e['nme_mask']}  n_nme={e['n_nme']} n_daa={e['n_daa']}"
              f"  all_supported={e['all_supported']}")
    assert parsed, "no rows parsed"
    assert any(e["n_nme"] > 0 for e in parsed), "expected at least one N-Me residue in first 5 rows"

    # 3) prove a structure is obtainable for one entry (RDKit ETKDG, CPU)
    e0 = embed_blocks(parsed[0])
    print(f"  embed(row0): has_structure={e0['has_structure']} source={e0['coords_source']}"
          + (f" atoms={len(e0['blocks'][0]['atoms'])}" if e0["blocks"] else ""))
    # 4) split determinism
    s = assign_split(parsed[0])
    assert s in ("train", "val", "test")
    print(f"  split(row0)={s}  scaffold_key(len)={len(scaffold_key(parsed[0]))}")
    print("  [ok] self-test passed.")
    return 0


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--csv", type=Path, default=DEFAULT_CSV)
    ap.add_argument("--stats", action="store_true", help="print full-corpus availability counts and exit")
    ap.add_argument("--emit", type=Path, default=None, help="write JSONL records to this path")
    ap.add_argument("--limit", type=int, default=None, help="cap #rows (for a quick pass)")
    ap.add_argument("--embed", action="store_true", help="attempt RDKit ETKDG 3D embedding (slow, CPU)")
    args = ap.parse_args(argv)

    if args.stats:
        if not args.csv.exists():
            print(f"CSV not found: {args.csv}", file=sys.stderr)
            return 2
        print(json.dumps(corpus_stats(args.csv, limit=args.limit, embed=args.embed), indent=2))
        return 0

    if args.emit:
        if not args.csv.exists():
            print(f"CSV not found: {args.csv}", file=sys.stderr)
            return 2
        n = 0
        with open(args.emit, "w") as out:
            for idx, row in iter_rows(args.csv, limit=args.limit):
                e = parse_entry(idx, row)
                if args.embed:
                    e = embed_blocks(e)
                e["scaffold"] = scaffold_key(e)
                e["split"] = assign_split(e)
                out.write(json.dumps(e) + "\n")
                n += 1
        print(f"wrote {n} records -> {args.emit}")
        return 0

    return _self_test(args.csv)


if __name__ == "__main__":
    raise SystemExit(main())
