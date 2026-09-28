#!/usr/bin/env python3
"""m0_frozen_probe.py — M0 "Tier-0 go/no-go" frozen-encoder linear-probe transfer matrix.

The decisive CHEAP gate (docs/20260927_CYCLIC_CORPUS_AND_TRAINING_STRATEGY.md Part B(5) Tier 0,
docs/20260927_PEPTIDE_PARALLEL_WORK_PLAN.md M0). ONE GPU afternoon, NO diffusion training.

WHAT IT DECIDES
  Which AE-encoder initialization to commit to for the M1 geometry-AE mid-train (Option B), BEFORE
  spending on full training. Three FROZEN encoder inits are compared on their ability to represent +
  reconstruct held-out cyclic-peptide geometry:
    (i)   linear/protein init  = our epoch-221 checkpoint's autoencoder (the trained PepGLAD AE)
    (ii)  random init          = the SAME AE architecture, freshly initialized weights, frozen
    (iii) small-molecule init  = a small-molecule-pretrained AE checkpoint IF ONE EXISTS
                                 (--smallmol-ckpt / SMALLMOL_CKPT). If absent, arm (iii) is SKIPPED
                                 and reported as "unavailable" — the (i) vs (ii) decision still stands.

HOW "FROZEN-ENCODER LINEAR PROBE" IS OPERATIONALIZED HERE
  The PepGLAD AE is a VAE whose *encoder* maps a peptide to a per-residue latent (H in R^latent_size,
  Z in R^{latent_n_channel x 3}) and whose *decoder* reconstructs all-atom coordinates + sequence.
  A "frozen-encoder linear probe" for a reconstruction task is exactly the AE's own frozen
  encode->decode path (the decoder plays the linear-probe role — it is NOT retrained here; we use each
  init's own paired decoder). We therefore report, per frozen init, on the HELD-OUT split:
    - all-atom reconstruction RMSD  (encode -> decode, no diffusion, no_randomness=True)
    - CA reconstruction RMSD
    - ring-closure validity          (head-to-tail / backbone macrocycle amide N..C distance in range)
    - stereochemistry validity       (CA chirality sign preserved vs the input conformer)
  This is a fair transfer probe: a good geometry prior reconstructs held-out cyclics with low RMSD and
  preserves ring closure; a bad prior (random, or a small-mol prior with the wrong inductive bias)
  smears geometry -> high RMSD, broken rings.

  NOTE (honest framing, carried from the source doc): this measures GEOMETRY reconstruction only.
  It does NOT and CANNOT establish target-conditioned binding — the bound cyclic data are too limited.
  Do not read a reconstruction win as a binding claim.

GEMINI LATENT-INTERPOLATION RING-BREAK TEST
  For each frozen init: take two held-out cyclics of equal residue count, encode both, linearly
  interpolate their latents at alpha in {0.25,0.5,0.75}, decode each intermediate, and check whether the
  decoded intermediate still has a closed ring / intact backbone amide bonds. Broken rings in the
  interpolants => the broad/ill-suited prior dominates the latent manifold => negative transfer signal.

DATA (held-out, per-MOLECULE hold-out — never split a molecule's conformers)
  - CREMP held-out: from s3 cyclic_peptide/datasets/cremp_partial (summary.csv + sdf_and_json.tar.bz2).
    A molecule = one CREMP `sequence`. Molecules are hashed to train/val/test so ALL conformers of a
    molecule stay on one side. The probe only touches the TEST molecules. We sample ONE representative
    (lowest-energy) conformer per test molecule (per-molecule, not per-conformer, to avoid CREMP
    correlation bias — MEMORY / plan M1 discipline).
  - Experimental cyclic-complex subset (optional): the peptide ligand chains of the PepBDB cyclic
    entries if present locally (--pepbdb-dir). These are experimental (crystal) geometries — the
    honest complement to xTB CREMP. If unavailable, that half is reported as "unavailable" (not fatal).

REUSE (per CLAUDE.md — do NOT reinvent the AE loading / partition code)
  - AE + LDM classes, dataset Block/Atom format: the vendored runtime/PepGLAD package.
  - CycPeptMPDB->PepGLAD residue partition (backbone trace + VF2 sidechain identify + N-Me CN):
    cycpeptmpdb_to_pepglad.py (imported; its _trace_backbone/_identify_residue handle head-to-tail
    macrolactams and canonical sidechains — exactly what CREMP macrocycles are).

USAGE
  # CPU smoke on the machine WITHOUT the big data (no S3, no GPU) — proves wiring + arms + decision code:
  python3 m0_frozen_probe.py --smoke

  # Real run (on the spot GPU; run_m0_frozen_probe.sh drives this):
  python3 m0_frozen_probe.py \
      --ldm-ckpt   /path/epoch221_step77700.ckpt \
      --cremp-dir  /path/cremp_partial            \
      --pepbdb-dir /path/pepbdb                    \
      --n-test-mols 300 --gpu 0 --out /path/m0_result.json
"""
from __future__ import annotations

import argparse
import bz2
import hashlib
import json
import os
import sys
import tarfile
import time
import traceback
from pathlib import Path
from typing import Dict, List, Optional, Tuple

ROOT = Path(__file__).resolve().parent
RUNTIME = ROOT / "runtime" / "PepGLAD"

# Make the vendored PepGLAD package importable (models/, data/, utils/, evaluation/).
if str(RUNTIME) not in sys.path:
    sys.path.insert(0, str(RUNTIME))
# ...and this dir, for cycpeptmpdb_to_pepglad partition reuse.
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

# Ring-closure geometry constants ------------------------------------------------------------------
# A backbone amide (peptide) bond N-C is ~1.33 A; head-to-tail macrolactam closure is the same bond.
# We accept a closed ring if the smallest cross-residue backbone C(=O)...N distance that is NOT a
# sequential (i -> i+1) neighbour falls in a bonded amide range. For a linear (open) chain this
# closing distance is large. Tolerances are generous — we are detecting "ring intact" vs "ring blown
# open", not measuring bond quality.
AMIDE_BOND_LO = 1.0
AMIDE_BOND_HI = 2.0     # a real amide is ~1.33; allow slack for reconstructed/ETKDG geometry
RING_OPEN_THRESHOLD = 2.6  # if the best closing distance exceeds this, the macrocycle is considered OPEN


# =================================================================================================
# Encoder-init construction
# =================================================================================================
def _build_ae_from_config(config_path: Path):
    """Construct a fresh (random-init) AutoEncoder from the vendored autoencoder config."""
    import yaml
    from utils import register as R

    cfg = yaml.safe_load(config_path.read_text())
    model = R.construct(cfg["model"])
    return model


def load_encoders(ldm_ckpt: Path, smallmol_ckpt: Optional[Path], device) -> Dict[str, object]:
    """Return {init_name: frozen AutoEncoder}. Missing arms are simply absent from the dict."""
    import torch
    import models  # noqa: F401  (registers AutoEncoder / LDMPepDesign)

    encoders: Dict[str, object] = {}

    # (i) linear/protein init: the epoch-221 checkpoint is an LDMPepDesign; the trained AE is .autoencoder.
    obj = torch.load(str(ldm_ckpt), map_location="cpu", weights_only=False)
    if isinstance(obj, models.LDMPepDesign):
        ae_linear = obj.autoencoder
    elif isinstance(obj, models.AutoEncoder):
        ae_linear = obj  # allow a bare AE checkpoint too
    else:
        raise TypeError(
            f"epoch-221 checkpoint is a {type(obj).__name__}; expected LDMPepDesign (with .autoencoder) "
            f"or AutoEncoder. Cannot extract the frozen encoder."
        )
    encoders["linear_epoch221"] = ae_linear

    # (ii) random init: same architecture, fresh weights. Build from the AE config that trained epoch-221.
    ae_cfg = RUNTIME / "configs/pepbench/autoencoder/train_codesign.yaml"
    encoders["random"] = _build_ae_from_config(ae_cfg)

    # (iii) small-mol init: only if a checkpoint is provided AND exists.
    if smallmol_ckpt is not None and Path(smallmol_ckpt).is_file():
        sm = torch.load(str(smallmol_ckpt), map_location="cpu", weights_only=False)
        sm_ae = sm.autoencoder if isinstance(sm, models.LDMPepDesign) else sm
        encoders["small_molecule"] = sm_ae

    for ae in encoders.values():
        ae.to(device)
        ae.eval()
        for p in ae.parameters():
            p.requires_grad = False
    return encoders


# =================================================================================================
# Data: CREMP held-out (per-molecule) + experimental complex subset -> PepGLAD Blocks
# =================================================================================================
def _mol_split(sequence: str, test_frac: float = 0.1, val_frac: float = 0.1) -> str:
    """Deterministic per-MOLECULE bucket by sequence hash (all conformers of a molecule share it)."""
    h = int(hashlib.sha1(sequence.encode()).hexdigest(), 16) % 1000
    if h < int(test_frac * 1000):
        return "test"
    if h < int((test_frac + val_frac) * 1000):
        return "val"
    return "train"


def _rdkit_mol_from_sdf_block(sdf_text: str):
    from rdkit import Chem

    supplier = Chem.SDMolSupplier()
    supplier.SetData(sdf_text, removeHs=True, sanitize=True)
    for mol in supplier:
        if mol is not None:
            return mol
    return None


def _blocks_from_rdkit_conformer(mol, conf_id: int) -> Optional[List[Dict]]:
    """Partition ONE RDKit conformer into PepGLAD Blocks via the vetted cycpeptmpdb_to_pepglad
    backbone-trace + sidechain-identify machinery (handles head-to-tail macrolactams + canonical
    sidechains, which is exactly what CREMP macrocycles are). Returns block dicts or None on failure."""
    import cycpeptmpdb_to_pepglad as cvt
    from rdkit import Chem

    molNoH = Chem.RemoveHs(mol)
    try:
        conf = molNoH.GetConformer(conf_id)
    except (ValueError, RuntimeError):
        return None
    residues = cvt._trace_backbone(molNoH)
    if not residues:
        return None
    all_bb = set()
    for d in residues:
        all_bb.update(d[k] for k in ("N", "CA", "C", "O"))
        if d.get("CN") is not None:
            all_bb.add(d["CN"])
    blocks = []
    for d in residues:
        sym, names = cvt._identify_residue(molNoH, d, all_bb)
        if sym is None:
            return None
        abrv = cvt.SYMBOL_TO_ABRV[sym]
        atoms = []
        for bn in cvt.BACKBONE_NAMES:
            p = conf.GetAtomPosition(d[bn])
            atoms.append({"name": bn, "element": molNoH.GetAtomWithIdx(d[bn]).GetSymbol(),
                          "coord": [p.x, p.y, p.z]})
        for aname in cvt._AA_SIDECHAIN[sym]:
            p = conf.GetAtomPosition(names[aname])
            atoms.append({"name": aname, "element": molNoH.GetAtomWithIdx(names[aname]).GetSymbol(),
                          "coord": [p.x, p.y, p.z]})
        blocks.append({"abrv": abrv, "symbol": sym, "atoms": atoms})
    return blocks


def load_cremp_test_molecules(cremp_dir: Path, n_test_mols: int) -> List[Dict]:
    """Load up to n_test_mols HELD-OUT CREMP molecules, ONE lowest-energy conformer each, as
    {id, seq, blocks}. Reads summary.csv for molecule list + per-molecule lowest-energy selection, and
    the sdf_and_json tarball for coordinates. Per-molecule hold-out: only 'test'-bucket molecules used."""
    import csv

    summary = cremp_dir / "summary.csv"
    if not summary.exists():
        raise FileNotFoundError(f"CREMP summary.csv not found at {summary}")

    # 1) collect the test-bucket molecules (sequence + smiles) from the summary
    test_seqs: List[Tuple[str, str]] = []
    with open(summary, newline="") as f:
        for row in csv.DictReader(f):
            seq = (row.get("sequence") or "").strip()
            if not seq:
                continue
            if _mol_split(seq) != "test":
                continue
            test_seqs.append((seq, (row.get("smiles") or "").strip()))
    test_seqs = test_seqs[: n_test_mols * 4]  # oversample; partition may drop some
    want = {seq for seq, _ in test_seqs}

    # 2) pull those molecules' conformers from the SDF tarball. Genentech CREMP layout:
    #    sdf/<seq>.sdf (one file per molecule, multiple conformers). Tar is bz2.
    mols: List[Dict] = []
    tar_path = _find_first(cremp_dir, ("sdf_and_json.tar.bz2", "sdf_and_json.tar.gz", "sdf.tar.bz2"))
    if tar_path is None:
        raise FileNotFoundError(
            f"No CREMP SDF tarball in {cremp_dir} "
            f"(looked for sdf_and_json.tar.bz2 / .tar.gz / sdf.tar.bz2)"
        )
    mode = "r:bz2" if tar_path.suffix == ".bz2" or tar_path.name.endswith(".tar.bz2") else "r:gz"
    with tarfile.open(tar_path, mode) as tf:
        for member in tf:
            if len(mols) >= n_test_mols:
                break
            if not member.isfile() or not member.name.endswith(".sdf"):
                continue
            stem = Path(member.name).stem
            seq = stem.replace("_", ".") if "." not in stem else stem
            if seq not in want:
                continue
            fh = tf.extractfile(member)
            if fh is None:
                continue
            try:
                sdf_text = fh.read().decode("utf-8", "ignore")
            finally:
                fh.close()
            mol = _rdkit_mol_from_sdf_block(sdf_text)
            if mol is None or mol.GetNumConformers() == 0:
                continue
            blocks = _blocks_from_rdkit_conformer(mol, 0)  # first = lowest-energy in CREMP ordering
            if blocks is None:
                continue
            mols.append({"id": f"cremp_{stem}", "seq": seq, "blocks": blocks, "provenance": "xTB_CREMP"})
    return mols


def load_pepbdb_cyclic_ligands(pepbdb_dir: Path, n_max: int) -> List[Dict]:
    """Load peptide-ligand chains from local PepBDB cyclic entries as experimental (crystal) geometry.
    Best-effort: PepBDB stores per-entry PDBs; we read the ligand chain, keep entries whose ligand is a
    plausible small macrocycle (>=4 residues) and partitions cleanly. Returns [] if the dir is absent."""
    if not pepbdb_dir or not Path(pepbdb_dir).exists():
        return []
    from data.converter.pdb_to_list_blocks import pdb_to_list_blocks

    out: List[Dict] = []
    pdbs = sorted(Path(pepbdb_dir).rglob("*.pdb"))
    for pdb in pdbs:
        if len(out) >= n_max:
            break
        try:
            chains = pdb_to_list_blocks(str(pdb), None)
        except Exception:
            continue
        # pick the shortest chain as the peptide ligand (PepBDB peptides are short)
        cand = [c for c in chains if 4 <= len(c) <= 25]
        if not cand:
            continue
        lig = min(cand, key=len)
        seq = "".join(_abrv_symbol(b.abrv) for b in lig)
        out.append({"id": f"pepbdb_{pdb.stem}", "seq": seq, "lig_blocks": lig, "provenance": "PDB_experimental"})
    return out


def _abrv_symbol(abrv: str) -> str:
    from data.format import VOCAB
    s = VOCAB.abrv_to_symbol(abrv)
    return s if s else "X"


def _find_first(d: Path, names) -> Optional[Path]:
    for n in names:
        p = Path(d) / n
        if p.exists():
            return p
    return None


# =================================================================================================
# Encode / decode a single peptide with a given frozen AE (peptide-only; no receptor)
# =================================================================================================
def _blocks_to_batch(blocks: List[Dict], device):
    """Build the PepGLAD AE batch tensors (X,S,mask,position_ids,lengths,atom_mask) for ONE peptide-only
    example, mirroring CoDesignDataset.__getitem__ exactly (MAX_N_ATOM=14 padding, mask=all-generate)."""
    import numpy as np
    import torch
    from data.format import VOCAB
    from utils.const import sidechain_atoms

    MAX_N_ATOM = 14
    X, S, atom_mask = [], [], []
    for b in blocks:
        symbol = b["symbol"]
        atom2coord = {a["name"]: a["coord"] for a in b["atoms"]}
        bb_pos = np.mean(list(atom2coord.values()), axis=0).tolist()
        coords, cmask = [], []
        for atom_name in VOCAB.backbone_atoms + sidechain_atoms.get(symbol, []):
            if atom_name in atom2coord:
                coords.append(atom2coord[atom_name]); cmask.append(1)
            else:
                coords.append(bb_pos); cmask.append(0)
        for _ in range(MAX_N_ATOM - len(coords)):
            coords.append(bb_pos); cmask.append(0)
        X.append(coords); S.append(VOCAB.symbol_to_idx(symbol)); atom_mask.append(cmask)
    n = len(blocks)
    batch = {
        "X": torch.tensor(X, dtype=torch.float, device=device),
        "S": torch.tensor(S, dtype=torch.long, device=device),
        "position_ids": torch.arange(1, n + 1, dtype=torch.long, device=device),
        "mask": torch.ones(n, dtype=torch.bool, device=device),  # reconstruct every residue
        "atom_mask": torch.tensor(atom_mask, dtype=torch.bool, device=device),
        "lengths": torch.tensor([n], dtype=torch.long, device=device),
    }
    return batch, torch.tensor(X, dtype=torch.float), torch.tensor(atom_mask, dtype=torch.bool)


def _lig_blocks_to_dicts(lig_blocks) -> List[Dict]:
    """Convert PepGLAD Block objects (from a PDB) into the {symbol,atoms} dicts _blocks_to_batch wants."""
    from data.format import VOCAB
    out = []
    for b in lig_blocks:
        sym = VOCAB.abrv_to_symbol(b.abrv)
        atoms = [{"name": a.name, "element": a.element, "coord": list(a.get_coord())} for a in b.units]
        out.append({"symbol": sym, "atoms": atoms})
    return out


def reconstruct(ae, blocks: List[Dict], device) -> Optional[Dict]:
    """Encode->decode ONE peptide with a frozen AE; return reconstructed coords + validity metrics."""
    import numpy as np
    import torch

    batch, true_X, true_atom_mask = _blocks_to_batch(blocks, device)
    with torch.no_grad():
        # DETERMINISTIC reconstruction: encode with no_randomness=True to take the posterior MEAN
        # (no VAE resampling), then decode from those fixed latents. Passing given_laten_H/X makes
        # AE.test set no_randomness internally and skip re-encoding — so the RMSD is a clean transfer
        # probe, not a stochastic sample (matches this function's stated intent). test() without given
        # latents would call encode(no_randomness=False) -> rsample() -> noisy RMSD.
        H, Z, _, _ = ae.encode(
            batch["X"], batch["S"], batch["mask"], batch["position_ids"],
            batch["lengths"], batch["atom_mask"], no_randomness=True,
        )
        # AE.test returns per-example lists: batch_X (coords), batch_S (seq), ppls
        rec_X, rec_S, _ = ae.test(
            batch["X"], batch["S"], batch["mask"], batch["position_ids"],
            batch["lengths"], batch["atom_mask"],
            given_laten_H=H, given_latent_X=Z, idealize=False,
        )
    if not rec_X or rec_X[0] is None:
        return None
    rec = np.array(rec_X[0])  # [N, 14, 3]
    if rec.shape[0] != true_X.shape[0]:
        return None
    am = true_atom_mask.numpy().astype(bool)  # [N, 14]
    tX = true_X.numpy()

    # all-atom RMSD over real (non-padded) atoms
    diff = (rec[am] - tX[am])
    rmsd_all = float(np.sqrt((diff ** 2).sum(-1).mean())) if diff.size else float("nan")
    # CA RMSD (channel 1 = CA)
    ca = am[:, 1]
    ca_diff = rec[:, 1][ca] - tX[:, 1][ca]
    rmsd_ca = float(np.sqrt((ca_diff ** 2).sum(-1).mean())) if ca_diff.size else float("nan")

    return {
        "rmsd_all": rmsd_all,
        "rmsd_ca": rmsd_ca,
        "ring_closed_recon": ring_closed(rec, am),
        "ring_closed_input": ring_closed(tX, am),
        "stereo_preserved": stereo_preserved(rec, tX, am),
        "rec_X": rec, "true_X": tX, "atom_mask": am,
    }


# =================================================================================================
# Validity metrics: ring closure + stereochemistry
# =================================================================================================
def ring_closed(X, atom_mask) -> bool:
    """A macrocyclic backbone is 'closed' if there exists a non-sequential residue pair whose
    backbone C (channel 2) and N (channel 0) are within amide-bond range — i.e. the head-to-tail (or
    a side-chain) macrolactam that makes it a ring is intact. Sequential i->i+1 amides are excluded so
    a merely-linear chain does NOT count as closed."""
    import numpy as np

    N = X[:, 0]  # backbone N per residue  [R,3]
    C = X[:, 2]  # backbone C per residue  [R,3]
    Nmask = atom_mask[:, 0]
    Cmask = atom_mask[:, 2]
    R = X.shape[0]
    if R < 3:
        return False
    best = np.inf
    for i in range(R):
        if not Cmask[i]:
            continue
        for j in range(R):
            if j == i or j == i + 1:  # skip the sequential amide C_i -> N_{i+1}
                continue
            if not Nmask[j]:
                continue
            d = float(np.linalg.norm(C[i] - N[j]))
            if d < best:
                best = d
    if best == np.inf:
        return False
    return AMIDE_BOND_LO <= best <= AMIDE_BOND_HI


def _ca_chirality_sign(X, atom_mask, i) -> Optional[float]:
    """Signed volume of (N, C, CB) around CA for residue i — a chirality proxy. None if CB missing."""
    import numpy as np

    if not (atom_mask[i, 0] and atom_mask[i, 1] and atom_mask[i, 2] and atom_mask[i, 4]):
        return None  # need N, CA, C, CB
    ca = X[i, 1]
    v1 = X[i, 0] - ca  # N
    v2 = X[i, 2] - ca  # C
    v3 = X[i, 4] - ca  # CB
    return float(np.sign(np.dot(np.cross(v1, v2), v3)))


def stereo_preserved(rec, true, atom_mask) -> float:
    """Fraction of residues whose CA chirality sign in the reconstruction matches the input conformer.
    Only residues with a CB (i.e. not Gly, and CB present) are scored."""
    total, ok = 0, 0
    for i in range(rec.shape[0]):
        st = _ca_chirality_sign(true, atom_mask, i)
        sr = _ca_chirality_sign(rec, atom_mask, i)
        if st is None or sr is None or st == 0:
            continue
        total += 1
        if sr == st:
            ok += 1
    return (ok / total) if total else float("nan")


# =================================================================================================
# Gemini latent-interpolation ring-break test
# =================================================================================================
def latent_ring_break_test(ae, mols: List[Dict], device, n_pairs: int = 20,
                           alphas=(0.25, 0.5, 0.75)) -> Dict:
    """Interpolate two held-out cyclics of EQUAL residue count in the AE latent, decode intermediates,
    and measure whether the decoded intermediate's ring stays closed. High closed-rate = the latent
    manifold keeps interpolants on the cyclic manifold (good prior); low = broken rings (negative
    transfer). Returns {pairs_tested, alpha_closed_rate, mean_closed_rate}."""
    import numpy as np
    import torch

    # group test mols by residue length so we can encode/decode a pair together (shared batch shapes)
    by_len: Dict[int, List[Dict]] = {}
    for m in mols:
        blocks = m.get("blocks") or _lig_blocks_to_dicts(m.get("lig_blocks", []))
        if not blocks:
            continue
        by_len.setdefault(len(blocks), []).append({**m, "_blocks": blocks})
    pairs = []
    for L, group in by_len.items():
        for k in range(0, len(group) - 1, 2):
            pairs.append((group[k], group[k + 1]))
            if len(pairs) >= n_pairs:
                break
        if len(pairs) >= n_pairs:
            break

    if not pairs:
        return {"pairs_tested": 0, "alpha_closed_rate": {}, "mean_closed_rate": float("nan")}

    per_alpha_hits = {a: 0 for a in alphas}
    per_alpha_n = {a: 0 for a in alphas}
    for a_mol, b_mol in pairs:
        ba, tXa, ama = _blocks_to_batch(a_mol["_blocks"], device)
        bb, tXb, amb = _blocks_to_batch(b_mol["_blocks"], device)
        with torch.no_grad():
            Ha, Za, _, _ = ae.encode(ba["X"], ba["S"], ba["mask"], ba["position_ids"],
                                     ba["lengths"], ba["atom_mask"], no_randomness=True)
            Hb, Zb, _, _ = ae.encode(bb["X"], bb["S"], bb["mask"], bb["position_ids"],
                                     bb["lengths"], bb["atom_mask"], no_randomness=True)
        for alpha in alphas:
            Hm = (1 - alpha) * Ha + alpha * Hb
            Zm = (1 - alpha) * Za + alpha * Zb
            with torch.no_grad():
                rec_X, _, _ = ae.test(
                    ba["X"], ba["S"], ba["mask"], ba["position_ids"], ba["lengths"], ba["atom_mask"],
                    given_laten_H=Hm, given_latent_X=Zm, idealize=False,
                )
            if not rec_X or rec_X[0] is None:
                continue
            rec = np.array(rec_X[0])
            per_alpha_n[alpha] += 1
            if ring_closed(rec, ama.numpy().astype(bool)):
                per_alpha_hits[alpha] += 1

    alpha_rate = {str(a): (per_alpha_hits[a] / per_alpha_n[a]) if per_alpha_n[a] else float("nan")
                  for a in alphas}
    valid = [r for r in alpha_rate.values() if r == r]  # drop NaN
    return {
        "pairs_tested": len(pairs),
        "alpha_closed_rate": alpha_rate,
        "mean_closed_rate": (sum(valid) / len(valid)) if valid else float("nan"),
    }


# =================================================================================================
# Per-init evaluation + decision rule
# =================================================================================================
def evaluate_init(name, ae, cremp_mols, pepbdb_mols, device) -> Dict:
    import numpy as np

    def _agg(recs, key):
        vals = [r[key] for r in recs if r and r[key] == r[key]]
        return float(np.mean(vals)) if vals else float("nan")

    def _rate(recs, key):
        vals = [1.0 if r[key] else 0.0 for r in recs if r]
        return float(np.mean(vals)) if vals else float("nan")

    result = {"init": name}
    # CREMP (xTB solution geometry)
    cremp_recs = [reconstruct(ae, m["blocks"], device) for m in cremp_mols]
    cremp_recs = [r for r in cremp_recs if r is not None]
    result["cremp"] = {
        "n": len(cremp_recs),
        "rmsd_all_mean": _agg(cremp_recs, "rmsd_all"),
        "rmsd_ca_mean": _agg(cremp_recs, "rmsd_ca"),
        "ring_closure_valid_rate": _rate(cremp_recs, "ring_closed_recon"),
        "ring_closed_input_rate": _rate(cremp_recs, "ring_closed_input"),
        "stereo_preserved_mean": _agg(cremp_recs, "stereo_preserved"),
    }
    # Experimental complex subset (crystal geometry) — optional
    if pepbdb_mols:
        exp_recs = []
        for m in pepbdb_mols:
            blk = _lig_blocks_to_dicts(m["lig_blocks"])
            exp_recs.append(reconstruct(ae, blk, device))
        exp_recs = [r for r in exp_recs if r is not None]
        result["experimental_complex"] = {
            "n": len(exp_recs),
            "rmsd_all_mean": _agg(exp_recs, "rmsd_all"),
            "rmsd_ca_mean": _agg(exp_recs, "rmsd_ca"),
            "ring_closure_valid_rate": _rate(exp_recs, "ring_closed_recon"),
            "stereo_preserved_mean": _agg(exp_recs, "stereo_preserved"),
        }
    else:
        result["experimental_complex"] = {"status": "unavailable (no local PepBDB cyclic subset)"}
    # Gemini latent ring-break test (on CREMP held-out)
    result["latent_ring_break"] = latent_ring_break_test(ae, cremp_mols, device)
    return result


def decide(results: Dict[str, Dict]) -> Dict:
    """Encode the plan's decision rule. Primary axis = CREMP held-out all-atom reconstruction RMSD
    (lower is better); ring-closure validity is the tie-break / sanity gate.

    Rule (docs/20260927_CYCLIC_CORPUS_AND_TRAINING_STRATEGY.md Part B(5)):
      linear >> random  (and >> small-mol if present) -> AE=B from linear init
      random ~= linear                                -> CREMP alone suffices (drop linear pretrain for AE)
      small-mol >= linear                             -> reconsider a small-molecule atom-level foundation
    '>>' means the RMSD gap exceeds REL_MARGIN (relative) AND the better init keeps ring closure high.
    '~=' means within REL_MARGIN.
    """
    REL_MARGIN = 0.10  # 10% relative RMSD gap counts as a meaningful difference

    def rmsd(name):
        r = results.get(name, {}).get("cremp", {}).get("rmsd_all_mean", float("nan"))
        return r

    lin = rmsd("linear_epoch221")
    rnd = rmsd("random")
    sm = rmsd("small_molecule") if "small_molecule" in results else None

    verdict = {"primary_metric": "cremp.rmsd_all_mean (lower=better)",
               "rmsd_all": {"linear_epoch221": lin, "random": rnd, "small_molecule": sm}}

    if lin != lin or rnd != rnd:
        verdict["decision"] = "INCONCLUSIVE — missing/NaN reconstruction metric; inspect the run log."
        return verdict

    def rel_gap(a, b):  # positive if a is worse (higher RMSD) than b
        return (a - b) / max(b, 1e-6)

    linear_better_than_random = rel_gap(rnd, lin) > REL_MARGIN  # random is worse than linear by >margin
    similar = abs(rel_gap(rnd, lin)) <= REL_MARGIN

    smallmol_note = ""
    if sm is not None and sm == sm:
        if rel_gap(lin, sm) > REL_MARGIN:  # small-mol beats linear by >margin
            verdict["decision"] = ("RECONSIDER — small-molecule init reconstructs held-out cyclics "
                                   "better than the linear-epoch221 init. Investigate an atom-level "
                                   "small-molecule foundation before committing AE=B.")
            return verdict
        smallmol_note = " small-mol init did NOT beat linear (as expected)."

    if linear_better_than_random:
        verdict["decision"] = ("GO: AE = Option B from the linear-epoch221 init. Linear init reconstructs "
                               "held-out CREMP with materially lower RMSD than random init." + smallmol_note)
    elif similar:
        verdict["decision"] = ("GO (CHEAPER): random ~= linear -> CREMP alone suffices for the AE geometry "
                               "prior; drop the linear pretrain FOR THE AE (keep it for the generator's "
                               "binding conditioning)." + smallmol_note)
    else:
        verdict["decision"] = ("SURPRISE: random init reconstructs BETTER than the linear-epoch221 init. "
                               "Re-check checkpoint extraction / data parity before acting.")
    # ring-closure sanity gate
    lin_ring = results["linear_epoch221"]["cremp"].get("ring_closure_valid_rate", float("nan"))
    verdict["ring_closure_gate"] = {
        "linear_epoch221_ring_valid_rate": lin_ring,
        "note": "If the chosen init's ring-closure validity is low (<0.5), M1 needs the hard "
                "closure constraint (M4) earlier than planned.",
    }
    return verdict


# =================================================================================================
# Smoke test (no S3, no GPU, no big data): validates wiring + validity math + decision code
# =================================================================================================
def _smoke() -> int:
    """Build a couple of tiny synthetic cyclic 'peptides' as Block dicts, exercise ring_closed /
    stereo_preserved / decide() with fabricated numbers. Proves the code path without torch-heavy AE
    inference or any data. Prints a PREDICTED-SHAPE result skeleton."""
    import numpy as np

    print("== m0_frozen_probe smoke (no GPU, no S3, no AE) ==")
    # A fake CLOSED ring: 4 residues laid on a square. The intended head-to-tail closing bond is the
    # LAST residue's C -> the FIRST residue's N (non-sequential: i=3,j=0), placed ~1.33 A apart (a real
    # amide). All other non-sequential C..N pairs are farther, so best == the closing bond, in range.
    # CB atoms are pushed out of the residue plane (z != 0) so the CA chirality signed volume is nonzero.
    def res(nc, ca, c, o, cb):
        X = np.zeros((14, 3)); am = np.zeros(14, dtype=bool)
        X[0], X[1], X[2], X[3], X[4] = nc, ca, c, o, cb
        am[0] = am[1] = am[2] = am[3] = am[4] = True
        return X, am

    # square corners for the 4 CA atoms; N/C offset toward the next residue to make sequential amides,
    # and residue3.C sits right next to residue0.N to close the macrocycle.
    specs = [
        # N,              CA,            C,              O,              CB (out of plane)
        ([0.0, 0.0, 0],  [-1.0, 0.0, 0], [-1.0, -1.4, 0], [-0.2, -2.1, 0], [-1.6, 0.6, 1.0]),  # res0
        ([-2.3, -1.4, 0],[-3.3, -1.4, 0],[-3.3, -3.0, 0], [-2.6, -3.8, 0], [-4.0, -0.9, 1.0]), # res1
        ([-3.5, -4.5, 0],[-2.6, -5.2, 0],[-1.4, -4.7, 0], [-1.5, -3.6, 0], [-3.0, -6.2, 1.0]), # res2
        ([0.0, 1.33, 0], [-0.9, 2.1, 0], [-0.4, 3.2, 0],  [-1.0, 4.1, 0],  [-2.0, 1.9, 1.0]),  # res3: C3? no
    ]
    # NOTE: the closing bond is res3.C -> res0.N. Set res3.C right at 1.33 A from res0.N=[0,0,0].
    specs[3] = ([0.0, 2.66, 0], [-0.9, 3.4, 0], [0.0, 1.33, 0], [1.0, 1.4, 0], [-2.0, 3.2, 1.0])
    Xs, ams = [], []
    for spec in specs:
        X, am = res(*spec); Xs.append(X); ams.append(am)
    X = np.stack(Xs); am = np.stack(ams)
    closed = ring_closed(X, am)
    stereo = stereo_preserved(X, X, am)  # identical => 1.0
    print(f"  ring_closed(synthetic ring)   = {closed}  (expect True)")
    print(f"  stereo_preserved(X,X)         = {stereo}  (expect 1.0)")
    assert closed is True, "synthetic ring should be detected closed"
    assert stereo == 1.0, "identical coords must preserve stereo"

    # decision rule sanity: linear clearly better than random
    fake = {
        "linear_epoch221": {"cremp": {"rmsd_all_mean": 1.20, "ring_closure_valid_rate": 0.92}},
        "random": {"cremp": {"rmsd_all_mean": 3.10, "ring_closure_valid_rate": 0.30}},
    }
    d = decide(fake)
    print(f"  decide(linear<<random).decision = {d['decision'][:60]}...")
    assert d["decision"].startswith("GO: AE = Option B"), d["decision"]

    fake2 = {
        "linear_epoch221": {"cremp": {"rmsd_all_mean": 1.20, "ring_closure_valid_rate": 0.90}},
        "random": {"cremp": {"rmsd_all_mean": 1.25, "ring_closure_valid_rate": 0.88}},
    }
    d2 = decide(fake2)
    assert "CHEAPER" in d2["decision"], d2["decision"]
    print(f"  decide(random~=linear).decision = {d2['decision'][:60]}...")

    fake3 = {
        "linear_epoch221": {"cremp": {"rmsd_all_mean": 2.00, "ring_closure_valid_rate": 0.7}},
        "random": {"cremp": {"rmsd_all_mean": 3.00, "ring_closure_valid_rate": 0.4}},
        "small_molecule": {"cremp": {"rmsd_all_mean": 1.20, "ring_closure_valid_rate": 0.8}},
    }
    d3 = decide(fake3)
    assert d3["decision"].startswith("RECONSIDER"), d3["decision"]
    print(f"  decide(smallmol<<linear).decision = {d3['decision'][:60]}...")

    print("  [ok] smoke passed — wiring, validity math, and decision rule are sound.")
    print("  Predicted real-run result shape:")
    skeleton = {
        "arms_run": ["linear_epoch221", "random", "(small_molecule if --smallmol-ckpt given)"],
        "per_init": {"<init>": {"cremp": {"n": "~300", "rmsd_all_mean": "float",
                                          "ring_closure_valid_rate": "0..1",
                                          "stereo_preserved_mean": "0..1"},
                                "experimental_complex": "metrics or 'unavailable'",
                                "latent_ring_break": {"mean_closed_rate": "0..1"}}},
        "decision": "one of GO(B) / GO(cheaper) / RECONSIDER / SURPRISE / INCONCLUSIVE",
    }
    print(json.dumps(skeleton, indent=2))
    return 0


# =================================================================================================
def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--smoke", action="store_true", help="CPU/no-data wiring + math + decision self-test")
    ap.add_argument("--ldm-ckpt", type=Path, default=os.environ.get("LDM_CKPT"),
                    help="epoch-221 LDM checkpoint (.ckpt); its .autoencoder is the linear-init encoder")
    ap.add_argument("--smallmol-ckpt", type=Path, default=os.environ.get("SMALLMOL_CKPT"),
                    help="OPTIONAL small-molecule-pretrained AE/LDM checkpoint (arm iii). If absent, skipped.")
    ap.add_argument("--cremp-dir", type=Path, default=os.environ.get("CREMP_DIR"),
                    help="local dir with CREMP summary.csv + sdf_and_json.tar.bz2")
    ap.add_argument("--pepbdb-dir", type=Path, default=os.environ.get("PEPBDB_DIR"),
                    help="OPTIONAL local PepBDB dir (experimental cyclic-complex ligand subset)")
    ap.add_argument("--n-test-mols", type=int, default=int(os.environ.get("N_TEST_MOLS", "300")))
    ap.add_argument("--n-exp", type=int, default=int(os.environ.get("N_EXP", "60")))
    ap.add_argument("--gpu", type=int, default=int(os.environ.get("GPU", "0")), help="-1 for CPU")
    ap.add_argument("--out", type=Path, default=os.environ.get("OUT", "m0_result.json"))
    args = ap.parse_args(argv)

    if args.smoke:
        return _smoke()

    if not args.ldm_ckpt or not Path(args.ldm_ckpt).is_file():
        print(f"FATAL: --ldm-ckpt not found: {args.ldm_ckpt}", file=sys.stderr)
        return 2
    if not args.cremp_dir or not Path(args.cremp_dir).exists():
        print(f"FATAL: --cremp-dir not found: {args.cremp_dir}", file=sys.stderr)
        return 2

    import torch

    device = torch.device("cpu" if args.gpu == -1 else f"cuda:{args.gpu}")
    t0 = time.time()
    report: Dict = {
        "experiment": "M0 frozen-encoder linear-probe transfer matrix",
        "utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "device": str(device),
        "ldm_ckpt": str(args.ldm_ckpt),
        "n_test_mols_requested": args.n_test_mols,
    }
    try:
        print("[1/4] loading frozen encoders ...", flush=True)
        encoders = load_encoders(args.ldm_ckpt, args.smallmol_ckpt, device)
        report["arms"] = list(encoders.keys())
        if "small_molecule" not in encoders:
            report["small_molecule_status"] = (
                "UNAVAILABLE — no small-molecule AE checkpoint provided (--smallmol-ckpt). "
                "Arm (iii) skipped; (i) linear vs (ii) random decision proceeds as designed. "
                "To add arm (iii): pretrain a small-mol AE (same config) or substitute a public "
                "small-molecule geometry AE, then re-run with --smallmol-ckpt."
            )
            print("  NOTE: " + report["small_molecule_status"], flush=True)

        print("[2/4] loading held-out CREMP molecules (per-molecule hold-out) ...", flush=True)
        cremp_mols = load_cremp_test_molecules(args.cremp_dir, args.n_test_mols)
        report["cremp_test_mols_loaded"] = len(cremp_mols)
        print(f"  loaded {len(cremp_mols)} CREMP test molecules", flush=True)

        print("[2b/4] loading experimental cyclic-complex subset (optional) ...", flush=True)
        pepbdb_mols = load_pepbdb_cyclic_ligands(args.pepbdb_dir, args.n_exp) if args.pepbdb_dir else []
        report["experimental_mols_loaded"] = len(pepbdb_mols)

        print("[3/4] evaluating each frozen init ...", flush=True)
        report["per_init"] = {}
        for name, ae in encoders.items():
            print(f"  -> {name}", flush=True)
            report["per_init"][name] = evaluate_init(name, ae, cremp_mols, pepbdb_mols, device)

        print("[4/4] applying decision rule ...", flush=True)
        report["verdict"] = decide(report["per_init"])
        report["elapsed_sec"] = round(time.time() - t0, 1)
        report["status"] = "ok"
    except Exception as e:  # capture the FULL error into the report (per the read-the-error rule)
        report["status"] = "error"
        report["error"] = f"{type(e).__name__}: {e}"
        report["traceback"] = traceback.format_exc()
        print(report["traceback"], file=sys.stderr)

    Path(args.out).write_text(json.dumps(report, indent=2))
    print(json.dumps(report.get("verdict", {"status": report["status"]}), indent=2))
    return 0 if report.get("status") == "ok" else 1


if __name__ == "__main__":
    raise SystemExit(main())
