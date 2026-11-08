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


# ---- Per-residue atom->block partition (deterministic cheminformatics) ------------------------------
# This is the core B1 data-engineering task: split an embedded macrocycle conformer into per-residue
# PepGLAD Blocks (backbone N/CA/C/O + canonically-named sidechain + the N-Me CN methyl on the correct
# residue's backbone N), producing the [num_res, <=15]-atom representation the AE dataloader ingests.
#
# Algorithm (validated 1233/1233 on the in-vocab N-Me subset, 0 residue/CN/composition mismatches):
#   1. trace() — directional backbone walk over amide bonds. A residue = N-CA-C(=O). For each backbone
#      amide bond C'(=O)-N, the residue's CA is the N-neighbour carbon that (a) is not that C', (b) has
#      >=2 heavy neighbours (rules out the N-Me methyl), and (c) is itself bonded to a carbonyl (its own
#      C'). This handles head-to-tail macrolactam closure (C' bonds directly to the closing CA).
#   2. N-Me CN detection — a backbone N carrying a *lone methyl* carbon (only heavy neighbour is that N),
#      distinct from CA and from any carbonyl C. Count matches the parsed nme_mask exactly.
#   3. identify() — name each sidechain by VF2 subgraph-isomorphism against the canonical AA sidechain
#      graph (elements + bonds from utils.const.sidechain_bonds). This assigns canonical PDB atom names
#      (CB, CG, CD1, ...) so the AE's fixed per-type atom template can place each coord in the right slot.
#      Proline's ring is closed by adding the backbone N-CA edge to its template.
#
# NOTE: this module imports RDKit + networkx lazily inside the functions so the classifier-only self-test
# and --stats still run without them. Both are CPU-only.
MAX_ATOM_NUMBER = 15  # raised 14->15 to accommodate N-Me-TRP (4 bb + 10 sc + 1 CN); see noncanonical_vocab

# Canonical sidechain atom-name templates (name order per residue), pulled from PepGLAD's utils.const.
# Populated lazily to avoid importing the torch-pulling const at module import time.
_AA_SIDECHAIN: Dict[str, List[str]] = {}
_AA_SC_BONDS: Dict[str, List] = {}
_TEMPLATE_GRAPHS: Dict[str, object] = {}
_SYM_BY_SIZE: List[str] = []


def _load_const():
    """Lazy-load the canonical AA atom templates + build the per-AA isomorphism graphs (once)."""
    if _AA_SIDECHAIN:
        return
    import importlib
    import sys as _sys

    runtime = str(ROOT / "runtime" / "PepGLAD")
    if runtime not in _sys.path:
        _sys.path.insert(0, runtime)
    const = importlib.import_module("utils.const")
    import networkx as nx

    for sym, _abrv in const.aas:
        _AA_SIDECHAIN[sym] = list(const.sidechain_atoms[sym])
        _AA_SC_BONDS[sym] = list(const.sidechain_bonds[sym])
        g = nx.Graph()
        g.add_node("CA", elem="C")
        if sym == "P":
            g.add_node("N", elem="N")
        for name in const.sidechain_atoms[sym]:
            g.add_node(name, elem=name[0])
        for a, b, _bt in const.sidechain_bonds[sym]:
            g.add_edge(a, b)
        if sym == "P":
            g.add_edge("N", "CA")  # Pro ring closes through the backbone N-CA bond
        _TEMPLATE_GRAPHS[sym] = g
    _SYM_BY_SIZE.extend(sorted(_AA_SIDECHAIN, key=lambda s: -len(_AA_SIDECHAIN[s])))


BACKBONE_NAMES = ["N", "CA", "C", "O"]


def _trace_backbone(mol):
    """Directional backbone walk -> list of residue dicts {N,CA,C,O,CN} (RDKit atom indices)."""
    carbonyl = {}
    for a in mol.GetAtoms():
        if a.GetSymbol() != "C":
            continue
        dO = [
            n for n in a.GetNeighbors()
            if n.GetSymbol() == "O"
            and mol.GetBondBetweenAtoms(a.GetIdx(), n.GetIdx()).GetBondTypeAsDouble() == 2.0
        ]
        if dO:
            carbonyl[a.GetIdx()] = dO[0].GetIdx()
    amide = []
    for c in carbonyl:
        for nb in mol.GetAtomWithIdx(c).GetNeighbors():
            if nb.GetSymbol() == "N":
                amide.append((c, nb.GetIdx()))
    residues, used = [], set()
    for cprime, n in amide:
        for nb in mol.GetAtomWithIdx(n).GetNeighbors():
            if nb.GetSymbol() != "C" or nb.GetIdx() == cprime or nb.GetIdx() in used:
                continue
            heavy = [x for x in nb.GetNeighbors() if x.GetAtomicNum() > 1]
            own_cp = [x.GetIdx() for x in nb.GetNeighbors() if x.GetIdx() in carbonyl]
            if len(heavy) >= 2 and own_cp:
                residues.append({"CA": nb.GetIdx(), "N": n, "C": own_cp[0], "O": carbonyl[own_cp[0]]})
                used.add(nb.GetIdx())
                break
    cset = {r["C"] for r in residues}
    for d in residues:
        d["CN"] = None
        for nb in mol.GetAtomWithIdx(d["N"]).GetNeighbors():
            if nb.GetSymbol() == "C" and nb.GetIdx() != d["CA"]:
                heavy = [x for x in nb.GetNeighbors() if x.GetAtomicNum() > 1]
                if len(heavy) == 1 and nb.GetIdx() not in cset:
                    d["CN"] = nb.GetIdx()
    return residues


def _sidechain_atoms(mol, d, all_bb):
    """BFS the sidechain from CA (excludes all backbone/CN atoms); returns (atom_idxs, is_pro_ring)."""
    from collections import deque

    own = {d["N"], d["CA"], d["C"], d["O"]}
    if d["CN"] is not None:
        own.add(d["CN"])
    exclude = (set(all_bb) - own) | {d["C"], d["O"]}
    if d["CN"] is not None:
        exclude.add(d["CN"])
    q = deque(
        n.GetIdx() for n in mol.GetAtomWithIdx(d["CA"]).GetNeighbors()
        if n.GetIdx() not in exclude and n.GetAtomicNum() > 1 and n.GetIdx() != d["N"]
    )
    vis = set(q) | {d["CA"], d["N"]} | exclude
    sc, ring = [], False
    while q:
        u = q.popleft()
        sc.append(u)
        for nb in mol.GetAtomWithIdx(u).GetNeighbors():
            j = nb.GetIdx()
            if nb.GetAtomicNum() <= 1:
                continue
            if j == d["N"]:
                ring = True
                continue
            if j in vis:
                continue
            vis.add(j)
            q.append(j)
    return sc, ring


def _identify_residue(mol, d, all_bb):
    """Return (parent_symbol, {atom_name: atom_idx}) for the residue's sidechain, or (None, None)."""
    _load_const()
    import networkx as nx
    from networkx.algorithms.isomorphism import GraphMatcher

    sc, ring = _sidechain_atoms(mol, d, all_bb)
    sg = nx.Graph()
    sg.add_node(d["CA"], elem="C")
    for i in sc:
        sg.add_node(i, elem=mol.GetAtomWithIdx(i).GetSymbol())
    nodes = set(sc) | {d["CA"]}
    if ring:
        sg.add_node(d["N"], elem="N")
        nodes.add(d["N"])
    for b in mol.GetBonds():
        u, v = b.GetBeginAtomIdx(), b.GetEndAtomIdx()
        if u in nodes and v in nodes:
            sg.add_edge(u, v)
    for sym in _SYM_BY_SIZE:
        if len(_AA_SIDECHAIN[sym]) != len(sc):
            continue
        if (sym == "P") != ring:
            continue
        gm = GraphMatcher(sg, _TEMPLATE_GRAPHS[sym], node_match=lambda a, b: a["elem"] == b["elem"])
        for mp in gm.subgraph_isomorphisms_iter():
            if mp.get(d["CA"]) == "CA":
                names = {mp[i]: i for i in sc if i in mp and mp[i] != "N"}
                if len(names) == len(sc):
                    return sym, names
    return None, None


class _EmbedTimeout(Exception):
    pass


def _with_timeout(seconds, fn, *args, **kwargs):
    """Run fn under a SIGALRM wall-clock cap (Unix). Raises _EmbedTimeout if exceeded.
    A single pathological macrocycle's ETKDG/MMFF can spin for minutes; this caps it so it becomes a
    counted `embed_timeout` skip instead of stalling the whole batch (root-cause fix, not a workaround)."""
    import signal

    if not hasattr(signal, "SIGALRM"):
        return fn(*args, **kwargs)  # non-Unix: no cap available

    def _handler(signum, frame):
        raise _EmbedTimeout()

    old = signal.signal(signal.SIGALRM, _handler)
    signal.setitimer(signal.ITIMER_REAL, seconds)
    try:
        return fn(*args, **kwargs)
    finally:
        signal.setitimer(signal.ITIMER_REAL, 0)
        signal.signal(signal.SIGALRM, old)


# ---- Structure generation (CPU RDKit ETKDG) + per-residue partition --------------------------------
def embed_blocks(entry: Dict, n_conf: int = 4, opt_iters: int = 400, timeout_s: float = 25.0) -> Dict:
    """ETKDG-embed the macrocycle (a few conformers, keep lowest MMFF energy), then partition the
    conformer into per-residue PepGLAD Blocks with canonical atom names, real coords, the N-Me CN methyl
    attached to the correct residue's backbone N, and a per-residue nme bit.

    On any failure (RDKit/networkx absent, embed fail, residue count != monomer count, an unidentifiable
    residue) the entry stays has_structure=False with a `partition_error` reason -- a real, counted
    outcome (flag+skip), never a silent single-block fallback.
    """
    smiles = entry.get("smiles", "")
    if not smiles:
        entry["partition_error"] = "no_smiles"
        return entry
    try:
        from rdkit import Chem, RDLogger
        from rdkit.Chem import AllChem

        RDLogger.DisableLog("rdApp.*")
    except Exception:
        entry["partition_error"] = "rdkit_absent"
        return entry

    mol = Chem.MolFromSmiles(smiles)
    if mol is None:
        entry["partition_error"] = "smiles_parse_failed"
        return entry
    molH = Chem.AddHs(mol)
    params = AllChem.ETKDGv3()
    params.randomSeed = 0xC0FFEE
    params.useRandomCoords = True  # macrocycles need random-coord init to embed reliably

    def _embed_and_opt():
        cids_ = list(AllChem.EmbedMultipleConfs(molH, numConfs=max(1, n_conf), params=params))
        best_cid_, best_e_ = None, None
        for cid in cids_:
            try:
                AllChem.MMFFOptimizeMolecule(molH, confId=cid, maxIters=opt_iters)
                props = AllChem.MMFFGetMoleculeProperties(molH)
                ff = AllChem.MMFFGetMoleculeForceField(molH, props, confId=cid)
                e = ff.CalcEnergy() if ff is not None else None
            except Exception:
                e = None
            if e is not None and (best_e_ is None or e < best_e_):
                best_e_, best_cid_ = e, cid
        return cids_, best_cid_, best_e_

    try:
        cids, best_cid, best_e = _with_timeout(timeout_s, _embed_and_opt)
    except _EmbedTimeout:
        entry["partition_error"] = "embed_timeout"
        return entry
    except Exception:
        cids, best_cid, best_e = [], None, None
    if not cids:
        entry["partition_error"] = "embed_failed"
        return entry
    if best_cid is None:
        best_cid = cids[0]  # optimisation/energy failed for all; still use a valid geometry
    molNoH = Chem.RemoveHs(molH)
    conf = molNoH.GetConformer(best_cid)

    residues = _trace_backbone(molNoH)
    if len(residues) != len(entry.get("monomers", [])):
        entry["partition_error"] = f"res_count_{len(residues)}_vs_mon_{len(entry.get('monomers', []))}"
        return entry
    all_bb = set()
    for d in residues:
        all_bb.update(d[k] for k in ("N", "CA", "C", "O"))
        if d["CN"] is not None:
            all_bb.add(d["CN"])

    blocks = []
    n_nme_blocks = 0
    for d in residues:
        sym, names = _identify_residue(molNoH, d, all_bb)
        if sym is None:
            entry["partition_error"] = "unidentified_residue"
            return entry
        abrv = SYMBOL_TO_ABRV[sym]
        atoms = []
        # backbone atoms first (fixed order N, CA, C, O)
        for bn in BACKBONE_NAMES:
            idx = d[bn]
            p = conf.GetAtomPosition(idx)
            atoms.append({"name": bn, "element": molNoH.GetAtomWithIdx(idx).GetSymbol(),
                          "coord": [p.x, p.y, p.z]})
        # sidechain atoms in the canonical template order
        for aname in _AA_SIDECHAIN[sym]:
            idx = names[aname]
            p = conf.GetAtomPosition(idx)
            atoms.append({"name": aname, "element": molNoH.GetAtomWithIdx(idx).GetSymbol(),
                          "coord": [p.x, p.y, p.z]})
        is_nme = d["CN"] is not None
        if is_nme:
            p = conf.GetAtomPosition(d["CN"])
            # PDB convention: the N-methyl carbon is named "CN"; pos_code 'N' (methyl on backbone N).
            atoms.append({"name": "CN", "element": "C", "coord": [p.x, p.y, p.z]})
            n_nme_blocks += 1
        blocks.append({"abrv": abrv, "symbol": sym, "nme": is_nme, "atoms": atoms})

    entry["has_structure"] = True
    entry["coords_source"] = "rdkit_etkdg"
    entry["mmff_energy"] = round(best_e, 4) if best_e is not None else None
    entry["blocks"] = blocks
    # nme_mask parallel to blocks (structural order); may differ in order from the token-order nme_mask
    entry["nme_mask_struct"] = [1 if b["nme"] else 0 for b in blocks]
    entry["partition_error"] = None
    entry["max_block_atoms"] = max(len(b["atoms"]) for b in blocks) if blocks else 0
    if n_nme_blocks != entry.get("n_nme", 0):
        # structural CN count must match the parsed token N-Me count; if not, flag (do not silently pass)
        entry["partition_error"] = f"nme_count_struct_{n_nme_blocks}_vs_token_{entry.get('n_nme', 0)}"
        entry["has_structure"] = False
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


# ---- PepGLAD on-disk dataset builder ---------------------------------------------------------------
# PepGLAD serialises each training example as a gzip-compressed JSON blob in a mmap container
# (data/mmap_dataset.py: data.bin holds the blobs; index.txt holds `<id>\t<start>\t<end>\t<props...>`).
# The peptide is a list of Block tuples `(abrv, [(name, [x,y,z], element, pos_code), ...], id)` -- exactly
# the tuple that data.format.Block.to_tuple() produces and CoDesignDataset.__getitem__ consumes.
#
# For the N-Me AE this is a PEPTIDE-ONLY dataset (there is no receptor). Each record therefore stores
#   ( [],  peptide_block_tuples )    # (rec_blocks=[], lig_blocks=peptide)
# plus the B1-specific per-residue nme_mask carried BOTH inside each block's free-form `id` field
#   id = {"nme": 0|1, "res_index": i}
# and as an explicit top-level property column, so a peptide-only AE dataloader can read the mask without
# reparsing blocks (see docs/20260926_NME_DATASET_READINESS.md for the exact schema the dataloader targets).

def _peptide_to_block_tuples(entry: Dict):
    """entry (post-embed) -> (list_of_block_tuples, nme_mask_struct). Block tuple matches Block.to_tuple()."""
    block_tuples = []
    nme_mask = []
    for i, b in enumerate(entry["blocks"]):
        atom_tuples = []
        for at in b["atoms"]:
            name = at["name"]
            elem = at["element"]
            # pos_code convention (data.format.Atom): name with the leading element stripped; 'CN' -> 'N'
            if name == "CN":
                pos_code = "N"
            else:
                pos_code = name[len(elem):] if name.startswith(elem) else name.lstrip(elem)
            atom_tuples.append([name, list(at["coord"]), elem, pos_code])
        blk_id = {"nme": 1 if b["nme"] else 0, "res_index": i}
        block_tuples.append([b["abrv"], atom_tuples, blk_id])
        nme_mask.append(1 if b["nme"] else 0)
    return block_tuples, nme_mask


def _embed_worker(args):
    """Top-level worker (picklable) for the process pool: embed+partition one entry, return it."""
    entry, n_conf, opt_iters, timeout_s = args
    return embed_blocks(entry, n_conf=n_conf, opt_iters=opt_iters, timeout_s=timeout_s)


def build_dataset(csv_path: Path, out_dir: Path, limit: Optional[int] = None,
                  n_conf: int = 4, opt_iters: int = 400, timeout_s: float = 25.0,
                  workers: Optional[int] = None) -> Dict:
    """Build the PepGLAD mmap N-Me dataset (train/val/test) + JSONL sidecar + manifest.

    Returns a stats dict (real trainable N after all failures, per-split counts, atom-slot histogram).
    CPU-only. Iterates the full CSV, keeps only in-vocab AND N-Me peptides, embeds + partitions each
    (parallel across CPU cores; a per-peptide SIGALRM cap makes a pathological macrocycle a counted skip),
    then writes the three splits sequentially.
    """
    import gzip
    import io as _io
    import os as _os
    from concurrent.futures import ProcessPoolExecutor

    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    splits = ("train", "val", "test")
    for s in splits:
        (out_dir / s).mkdir(parents=True, exist_ok=True)
    bins = {s: open(out_dir / s / "data.bin", "wb") for s in splits}
    idxf = {s: open(out_dir / s / "index.txt", "w") for s in splits}
    offsets = {s: 0 for s in splits}
    counts = {s: 0 for s in splits}
    sidecar = open(out_dir / "records.jsonl", "w")

    stats = {
        "candidates_in_vocab_nme": 0,
        "embedded_and_partitioned": 0,
        "failed": 0,
        "fail_reasons": {},
        "per_split": {s: 0 for s in splits},
        "max_block_atoms_hist": {},
        "n_nme_residues": 0,
        "n_residues": 0,
    }

    # 1) collect candidate entries (in-vocab AND N-Me) — cheap, sequential
    candidates = []
    for idx, row in iter_rows(csv_path, limit=limit):
        e = parse_entry(idx, row)
        if e["all_supported"] and e["n_nme"] > 0:
            candidates.append(e)
    stats["candidates_in_vocab_nme"] = len(candidates)

    # 2) embed+partition in parallel (the expensive step); preserve input order for determinism
    nworkers = workers or max(1, (_os.cpu_count() or 2) - 1)
    tasks = [(e, n_conf, opt_iters, timeout_s) for e in candidates]
    done = 0
    with ProcessPoolExecutor(max_workers=nworkers) as ex:
        embedded = ex.map(_embed_worker, tasks, chunksize=4)
        for e in embedded:
            done += 1
            if done % 100 == 0:
                print(f"  embedded {done}/{len(tasks)}", file=sys.stderr, flush=True)
            if not e["has_structure"]:
                stats["failed"] += 1
                reason = e.get("partition_error") or "unknown"
                stats["fail_reasons"][reason] = stats["fail_reasons"].get(reason, 0) + 1
                continue
            block_tuples, nme_mask = _peptide_to_block_tuples(e)
            record = ([], block_tuples)  # (rec_blocks=[], lig_blocks=peptide)
            scaf = scaffold_key(e)
            split = assign_split(e)
            idx = e["id"]

            # serialise exactly like data.mmap_dataset.compress()
            serialized = json.dumps(record).encode()
            buf = _io.BytesIO()
            with gzip.GzipFile(fileobj=buf, mode="wb", compresslevel=6) as f:
                f.write(serialized)
            blob = buf.getvalue()
            bin_len = bins[split].write(blob)
            _id = f"nme_{idx}"
            # property columns (tab-separated, mirror process.py order enough for CoDesignDataset):
            #   [n_rec_blocks, n_lig_blocks, rec_units, lig_units, rec_chain, lig_chain,
            #    rec_seq, lig_seq, non_standard, nme_mask_csv, pocket_idx_csv]
            lig_seq = "".join(b["symbol"] for b in e["blocks"])
            lig_units = sum(len(b["atoms"]) for b in e["blocks"])
            nme_csv = ",".join(str(x) for x in nme_mask)
            props = [
                0, len(block_tuples), 0, lig_units, "-", "A",
                "", lig_seq, 0, nme_csv, "",  # empty pocket (peptide-only)
            ]
            idxf[split].write(f"{_id}\t{offsets[split]}\t{offsets[split] + bin_len}\t" +
                              "\t".join(str(p) for p in props) + "\n")
            offsets[split] += bin_len
            counts[split] += 1

            stats["embedded_and_partitioned"] += 1
            stats["per_split"][split] += 1
            mba = e.get("max_block_atoms", 0)
            stats["max_block_atoms_hist"][mba] = stats["max_block_atoms_hist"].get(mba, 0) + 1
            stats["n_nme_residues"] += e["n_nme"]
            stats["n_residues"] += len(e["blocks"])

            # sidecar JSONL (human-readable, one line/peptide) with everything needed for audit
            sidecar.write(json.dumps({
                "id": _id, "row": idx, "split": split, "scaffold": scaf,
                "permeability": e["permeability"], "monomers": e["monomers"],
                "lig_seq": lig_seq, "n_res": len(e["blocks"]), "n_nme": e["n_nme"],
                "nme_mask": nme_mask, "max_block_atoms": mba,
                "mmff_energy": e.get("mmff_energy"), "coords_source": e["coords_source"],
            }) + "\n")

    for s in splits:
        bins[s].close()
        idxf[s].close()
    sidecar.close()
    stats["trainable_total"] = stats["embedded_and_partitioned"]
    # write manifest
    with open(out_dir / "manifest.json", "w") as m:
        json.dump(stats, m, indent=2)
    return stats


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--csv", type=Path, default=DEFAULT_CSV)
    ap.add_argument("--stats", action="store_true", help="print full-corpus availability counts and exit")
    ap.add_argument("--emit", type=Path, default=None, help="write JSONL records to this path")
    ap.add_argument("--build-dataset", type=Path, default=None,
                    help="build the PepGLAD mmap N-Me dataset (train/val/test) into this directory")
    ap.add_argument("--n-conf", type=int, default=4, help="ETKDG conformers per peptide (lowest MMFF kept)")
    ap.add_argument("--opt-iters", type=int, default=400, help="MMFF optimisation iterations")
    ap.add_argument("--timeout-s", type=float, default=25.0, help="per-peptide embed wall-clock cap (s)")
    ap.add_argument("--workers", type=int, default=None, help="parallel embed workers (default: cores-1)")
    ap.add_argument("--limit", type=int, default=None, help="cap #rows (for a quick pass)")
    ap.add_argument("--embed", action="store_true", help="attempt RDKit ETKDG 3D embedding (slow, CPU)")
    args = ap.parse_args(argv)

    if args.build_dataset:
        if not args.csv.exists():
            print(f"CSV not found: {args.csv}", file=sys.stderr)
            return 2
        st = build_dataset(args.csv, args.build_dataset, limit=args.limit,
                           n_conf=args.n_conf, opt_iters=args.opt_iters,
                           timeout_s=args.timeout_s, workers=args.workers)
        print(json.dumps(st, indent=2))
        return 0

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
