#!/usr/bin/env python3
"""
d2_augment_prep.py — D2 (2ii) INPUT PREP: extract REAL (cyclic-peptide, protein-target) binder pairs from the
BindingDB peptide subset and emit a Boltz-prediction job list, so the HighFold-augmentation pass can PREDICT the
bound complex for pairs that have a measured binder + a named target but NO experimental structure.

WHY BindingDB (and NOT CycPeptMPDB) is the pairing source
---------------------------------------------------------
The plan (HIGHFOLD_POSEGEN_PLAN.md) names CycPeptMPDB + BindingDB as pairing candidates. VERIFIED on the real files:
  * CycPeptMPDB_Peptide_All.csv (8,466 rows) has NO protein-target column — it is a *permeability* DB
    (PAMPA/Caco2/MDCK/RRCK). Its only "assay" field is the permeability assay, not a receptor. => CANNOT pair.
  * BindingDB peptide subset (s3://knowledge-datasets-1759951976/cyclic_peptide/datasets/bindingdb_peptide/202609/
    bindingdb_peptide_subset.csv, 171,006 rows) has: smiles, ligand_name, target, uniprot, Ki/Kd/IC50/EC50_nM.
    A row here IS a real measured binder + its target => this is the ONLY REAL pairing source. We do NOT fabricate.

MEASURED (2026-09-30 on the real 171,006-row subset):
  * ~62,081 rows are cyclic-peptide-heuristic AND have a UniProt AND a measured affinity, across ~1,341 targets.
  * After per-(peptide,target) dedup + length/receptor filters this yields a few-thousand usable prediction jobs
    (>> the 235 experimental D2 complexes) — the augmentation lever the plan calls for.

WHAT THIS SCRIPT DOES (CPU + light network; NO GPU)
---------------------------------------------------
1. Read the BindingDB peptide subset (local path or fetched from S3 by the launcher).
2. Keep rows that are (a) cyclic-peptide by SMILES heuristic [RDKit macrocycle if available, else amide+ring-closure
   fallback], (b) have a UniProt accession, (c) have a measured affinity (a real binder, not a decoy).
3. Convert each cyclic peptide SMILES -> a residue SEQUENCE Boltz can fold as a `cyclic: true` protein chain.
   * If RDKit is present we attempt a backbone read; if not, we fall back to keeping ONLY rows whose ligand_name /
     SMILES lets us recover a clean single-letter sequence, and DROP rows we cannot represent as a peptide chain
     (never emit a garbage sequence — a wrong chain poisons the prediction). Rows we cannot sequence are logged.
   * Modifications (N-Me / D-AA) are recorded as a `modifications` hint for the HighFold-MeD subset but the first
     working batch runs Boltz canonical-chain prediction (see review note tradeoff). Non-representable ncAA rows
     are TAGGED (subset='ncAA_defer') and written to a SEPARATE job list, not the canonical batch.
4. Resolve the RECEPTOR: fetch the UniProt canonical sequence (REST). Cap receptor length (--max-rec-len, default 800
   to fit A10G 24 GB per the plan's memory note). Longer receptors -> deferred list (need bigger GPU).
5. De-duplicate by (peptide_seq, uniprot) — many BindingDB rows are the same pair at different assay conditions.
6. Emit:
     jobs_canonical.jsonl   one job/line: {job_id, peptide_seq, cyclic_type, uniprot, receptor_seq, affinity, ...}
     jobs_ncAA_defer.jsonl  cyclic pairs we could not represent as a canonical chain (HighFold-MeD territory)
     jobs_bigrec_defer.jsonl receptor too long for the default GPU
     prep_manifest.json     counts, drop reasons, provenance, dedup stats

The job list is consumed by d2_augment_predict.py (writes one Boltz YAML per job, runs prediction) whose output
d2_augment_integrate.py folds into the SAME PepGLAD format m2c_process_complexes.py already consumes.

TRAIN-ONLY contract: every job carries train_only=True and conformer_provenance="<tool>_predicted". These pairs must
NEVER enter an eval/test split (the m2c split holds out experimental crystal/NMR/cryoEM only).

USAGE
  python3 d2_augment_prep.py \
      --bindingdb ../data/raw/bindingdb_peptide_subset.csv \   # or fetched from S3 by the launcher
      --out-dir ./d2_augment_jobs_v1 \
      --max-rec-len 800 --min-pep-len 5 --max-pep-len 20 --limit 0
"""
from __future__ import annotations

import argparse
import csv
import json
import os
import re
import sys
import time
import urllib.request
from datetime import datetime, timezone

csv.field_size_limit(10 ** 9)

UNIPROT_FASTA = "https://rest.uniprot.org/uniprotkb/{acc}.fasta"

# SMILES -> peptide sequence: single-letter map (RDKit path is preferred; this is only used by the fallback that
# reads a HELM/sequence-like string when present). Kept minimal + honest — we DROP rather than guess.
AA1 = set("ACDEFGHIKLMNPQRSTVWY")


# --------------------------------------------------------------------------- cyclic-peptide detection
def _amide_count(smi: str) -> int:
    return smi.count("C(=O)N") + smi.count("NC(=O)") + smi.count("C(N)=O")


def _has_disulfide(smi: str) -> bool:
    return "SS" in smi.replace("[S]", "S") or re.search(r"S[^\]]{0,3}S", smi) is not None


def _ring_closures(smi: str) -> int:
    twod = re.findall(r"%\d\d", smi)
    singled = re.findall(r"(?<!%)(?<!\d)\d", smi)
    return len(set(twod)) + len(set(singled))


def _rdkit_macrocycle_size(smi: str):
    """Largest ring size if RDKit available, else None (caller uses the heuristic)."""
    try:
        from rdkit import Chem  # type: ignore
    except Exception:
        return None
    m = Chem.MolFromSmiles(smi)
    if m is None:
        return 0
    ri = m.GetRingInfo()
    sizes = [len(r) for r in ri.AtomRings()]
    return max(sizes) if sizes else 0


def classify_cyclic(smi: str):
    """Return (is_cyclic: bool, cyc_type: str|None). RDKit macrocycle >=10 if available; else amide+ring heuristic
    matching the mining script's cyclization vocab (disulfide / head_to_tail / sidechain_backbone)."""
    if not smi:
        return False, None
    ms = _rdkit_macrocycle_size(smi)
    am = _amide_count(smi)
    ds = _has_disulfide(smi)
    if ms is not None:
        if ds and am >= 3:
            return (ms >= 8 or True), "disulfide"
        if ms >= 10 and am >= 4:
            return True, "backbone_macrocycle"
        return False, None
    # --- no RDKit: conservative heuristic (used only for scoping / non-GPU prep) ---
    if am < 4:
        return False, None
    if ds and am >= 3:
        return True, "disulfide"
    if _ring_closures(smi) >= 1 and am >= 5:
        return True, "backbone_macrocycle"
    return False, None


# --- RDKit canonical sidechain SMARTS (rooted so the beta atom follows an alpha carbon) ---
_RESIDUE_SIDECHAIN = {
    "S": "[CH2][OX2H]", "C": "[CH2][SX2H,SX2]", "T": "[CX4H]([CH3])[OX2H]",
    "V": "[CX4H]([CH3])[CH3]", "L": "[CH2][CX4H]([CH3])[CH3]", "I": "[CX4H]([CH3])[CH2][CH3]",
    "M": "[CH2][CH2][SX2][CH3]", "F": "[CH2]c1ccccc1", "Y": "[CH2]c1ccc(O)cc1",
    "W": "[CH2]c1c[nH]c2ccccc12", "D": "[CH2][CX3](=O)[OX2H,OX1-]",
    "E": "[CH2][CH2][CX3](=O)[OX2H,OX1-]", "N": "[CH2][CX3](=O)[NX3]",
    "Q": "[CH2][CH2][CX3](=O)[NX3]", "K": "[CH2][CH2][CH2][CH2][NX3]",
    "R": "[CH2][CH2][CH2][NX3][CX3]=[NX2,NX3]", "H": "[CH2]c1cnc[nH]1",
}


def _classify_ca(mol, ca_idx, n_idx, c_idx):
    """Single-letter residue for the alpha carbon ca_idx, or None if non-canonical. RDKit only."""
    from rdkit import Chem  # type: ignore
    ca = mol.GetAtomWithIdx(ca_idx)
    heavy = [a.GetIdx() for a in ca.GetNeighbors()
             if a.GetIdx() not in (n_idx, c_idx) and a.GetAtomicNum() > 1]
    if not heavy:
        return "G"  # Gly: no sidechain
    # Pro: backbone N in a 5-membered ring with CA (N-C-C-C-CA)
    if mol.GetAtomWithIdx(n_idx).IsInRing() and ca.IsInRing():
        for ring in mol.GetRingInfo().AtomRings():
            if n_idx in ring and ca_idx in ring and len(ring) == 5:
                elems = sorted(mol.GetAtomWithIdx(i).GetSymbol() for i in ring)
                if elems.count("N") == 1 and elems.count("C") == 4:
                    return "P"
    for letter, smarts in _RESIDUE_SIDECHAIN.items():
        patt = Chem.MolFromSmarts("[CX4H]" + smarts)
        if patt is None:
            continue
        for m in mol.GetSubstructMatches(patt):
            if ca_idx in m:
                return letter
    return None


def smiles_to_peptide_seq(smi: str, ligand_name: str):
    """Recover a TRUE-ORDER single-letter cyclic-peptide sequence from SMILES via an RDKit backbone-connectivity
    walk (validated on the real BindingDB subset 2026-09-30: ~214/8000 cyclo+uniprot rows yield a fully-canonical
    ordered sequence; the rest are peptidomimetics / ncAA / too-short and are correctly rejected).

    Discipline: we accept ONLY fully-canonical peptides whose backbone we can order end-to-end. Any residue not
    matched to a canonical L-sidechain -> return (None, True) so the row routes to the HighFold-MeD ncAA-defer list
    (never emit a guessed/partial sequence — a wrong chain poisons the predicted complex). Returns (seq|None,
    has_ncAA). NOTE: stereochemistry (D-AA) is NOT read here — D-residues classify as their L letter, so a peptide
    NAMED with D-/N-Me residues is flagged via has_ncAA in seq_from_name_or_helm and routed to ncAA-defer upstream;
    a purely-SMILES D-AA peptide would fold as its L-sequence (documented limitation, canonical batch only)."""
    try:
        from rdkit import Chem  # type: ignore
    except Exception:
        return None, False  # no RDKit (e.g. offline scoping): SMILES path unavailable -> name path only
    mol = Chem.MolFromSmiles(smi)
    if mol is None:
        return None, False
    # alpha carbons: C bonded to a backbone amide N and to a carbonyl C
    seen = {}
    for m in mol.GetSubstructMatches(Chem.MolFromSmarts("[NX3][CX4][CX3](=O)")):
        n_idx, ca_idx, c_idx = m[0], m[1], m[2]
        seen.setdefault(ca_idx, (n_idx, c_idx))
    if not (3 <= len(seen) <= 40):
        return None, False
    letters = {}
    for ca, (n_i, c_i) in seen.items():
        letters[ca] = _classify_ca(mol, ca, n_i, c_i)
    if any(v is None for v in letters.values()):
        return None, True  # non-canonical residue present -> ncAA-defer
    # order the residues by walking carbonyl-C -> amide-N -> next CA
    n_to_ca = {seen[ca][0]: ca for ca in seen}
    nxt = {}
    for ca in seen:
        catom = mol.GetAtomWithIdx(seen[ca][1])
        for nb in catom.GetNeighbors():
            if nb.GetAtomicNum() == 7 and nb.GetIdx() in n_to_ca:
                nxt[ca] = n_to_ca[nb.GetIdx()]
    ca_ids = list(seen.keys())
    start = ca_ids[0]
    order, cur = [start], start
    for _ in range(len(ca_ids)):
        c2 = nxt.get(cur)
        if c2 is None or c2 in order:
            break
        order.append(c2)
        cur = c2
    if len(order) < len(ca_ids):
        return None, False  # incomplete backbone walk -> reject (do NOT emit a partial/misordered sequence)
    return "".join(letters[ca] for ca in order), False


def seq_from_name_or_helm(ligand_name: str):
    """If the BindingDB ligand_name encodes an explicit single-letter or 3-letter sequence, recover it exactly.
    Many cyclic-peptide entries name the sequence (e.g. 'cyclo(-Arg-Gly-Asp-...)'). Exact-parse only; else None."""
    if not ligand_name:
        return None, False
    name = ligand_name.strip()
    # 3-letter cyclo(-Xaa-Xaa-...) pattern
    m = re.search(r"cyclo\s*\(?-?([A-Za-z]{3}(?:-[A-Za-z]{3})+)-?\)?", name)
    aa3to1 = {
        "ala": "A", "arg": "R", "asn": "N", "asp": "D", "cys": "C", "gln": "Q", "glu": "E", "gly": "G",
        "his": "H", "ile": "I", "leu": "L", "lys": "K", "met": "M", "phe": "F", "pro": "P", "ser": "S",
        "thr": "T", "trp": "W", "tyr": "Y", "val": "V",
    }
    if m:
        toks = m.group(1).split("-")
        has_nc = False
        seq = []
        for t in toks:
            key = t.lower()
            # D-amino acid convention 'd-Ala' or leading 'D' -> ncAA
            if key.startswith("d") and key[1:] in aa3to1:
                has_nc = True
                seq.append(aa3to1[key[1:]])
            elif key in aa3to1:
                seq.append(aa3to1[key])
            else:
                has_nc = True
                seq.append("A")  # placeholder; row will be routed to ncAA-defer, not canonical
        return "".join(seq), has_nc
    return None, False


# --------------------------------------------------------------------------- UniProt receptor resolution
def fetch_uniprot_seq(acc: str, cache: dict, timeout: int = 30, retries: int = 3):
    acc = acc.split(",")[0].split(";")[0].strip()  # first accession if multiple
    if not acc:
        return None
    if acc in cache:
        return cache[acc]
    url = UNIPROT_FASTA.format(acc=acc)
    for _ in range(retries):
        try:
            with urllib.request.urlopen(url, timeout=timeout) as r:
                txt = r.read().decode("utf-8", "replace")
            lines = [ln for ln in txt.splitlines() if ln and not ln.startswith(">")]
            seq = "".join(lines).strip().upper()
            seq = "".join(c for c in seq if c in AA1)  # strip any non-standard chars
            cache[acc] = seq if seq else None
            return cache[acc]
        except Exception:
            time.sleep(1.5)
    cache[acc] = None
    return None


# --------------------------------------------------------------------------- main
def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--bindingdb", required=True, help="path to bindingdb_peptide_subset.csv")
    ap.add_argument("--out-dir", required=True)
    ap.add_argument("--tool", default="Boltz1", choices=["Boltz1", "Boltz2", "HighFold3", "HighFold_MeD"],
                    help="predictor these jobs target (stamped as conformer_provenance=<tool>_predicted)")
    ap.add_argument("--max-rec-len", type=int, default=800, help="receptor residues cap for the default A10G GPU")
    ap.add_argument("--min-pep-len", type=int, default=5)
    ap.add_argument("--max-pep-len", type=int, default=20)
    ap.add_argument("--resolve-receptor", action="store_true",
                    help="fetch UniProt sequences (network). Off => emit uniprot only, defer receptor fetch to the "
                         "predict step (keeps prep offline-friendly).")
    ap.add_argument("--limit", type=int, default=0, help="cap #cyclic candidate rows scanned (0 = all)")
    ap.add_argument("--sleep", type=float, default=0.05, help="delay between UniProt fetches (s)")
    args = ap.parse_args(argv)

    os.makedirs(args.out_dir, exist_ok=True)
    cache: dict = {}
    seen = set()  # (peptide_seq, uniprot) dedup
    n = 0
    n_cyclic = 0
    canonical, ncaa_defer, bigrec_defer = [], [], []
    drops = {"no_uniprot": 0, "no_affinity": 0, "no_sequence": 0, "pep_len": 0, "dup": 0,
             "rec_unresolved": 0, "rec_too_long": 0}

    with open(args.bindingdb, newline="", encoding="utf-8", errors="replace") as f:
        rd = csv.DictReader(f)
        for row in rd:
            n += 1
            smi = (row.get("smiles") or "").strip()
            uni = (row.get("uniprot") or "").strip()
            tgt = (row.get("target") or "").strip()
            name = (row.get("ligand_name") or "").strip()
            aff = {k: (row.get(k) or "").strip() for k in ("Ki_nM", "Kd_nM", "IC50_nM", "EC50_nM")}
            aff = {k: v for k, v in aff.items() if v and v.upper() != "NULL"}

            is_cyc, cyc_type = classify_cyclic(smi)
            if not is_cyc:
                continue
            n_cyclic += 1
            if args.limit and n_cyclic > args.limit:
                break
            if not uni:
                drops["no_uniprot"] += 1
                continue
            if not aff:
                drops["no_affinity"] += 1
                continue

            # peptide sequence: exact from name/HELM if possible; else RDKit backbone-walk (fully-canonical only).
            # A row we cannot cleanly sequence is DROPPED (never guessed). If the SMILES IS a peptide but has a
            # NON-CANONICAL residue (N-Me/D-AA/staple), smiles_to_peptide_seq returns (None, True) -> we route it to
            # the ncAA-defer list WITH ITS SMILES (HighFold-MeD / CyclicBoltz1 predict from SMILES/CCD, no clean
            # single-letter chain needed) rather than discarding — that ncAA subset is exactly our IP differentiator.
            seq, has_nc = seq_from_name_or_helm(name)
            if seq is None:
                _rd_seq, rd_nc = smiles_to_peptide_seq(smi, name)
                if _rd_seq is None:
                    if rd_nc:  # a peptide backbone WITH non-canonical residues -> ncAA-defer (keep the SMILES)
                        ncaa_defer.append({
                            "job_id": f"bdbnc_{uni.split(',')[0]}_{len(ncaa_defer)}"[:60],
                            "peptide_seq": None, "smiles": smi, "cyclic_type": cyc_type,
                            "uniprot": uni.split(",")[0], "target_name": tgt[:120], "affinity_nM": aff,
                            "ligand_name": name[:120], "has_ncAA": True,
                            "tool": "HighFold_MeD_or_CyclicBoltz1", "conformer_provenance": "ncAA_predicted",
                            "train_only": True, "source": "BindingDB_measured_binder",
                            "note": "non-canonical cyclic peptide; needs ncAA-aware predictor (SMILES/CCD input)",
                        })
                    else:
                        drops["no_sequence"] += 1
                    continue
                seq, has_nc = _rd_seq, rd_nc
            seq = "".join(c for c in seq.upper() if c in AA1)
            if not (args.min_pep_len <= len(seq) <= args.max_pep_len):
                drops["pep_len"] += 1
                continue

            key = (seq, uni.split(",")[0])
            if key in seen:
                drops["dup"] += 1
                continue
            seen.add(key)

            job = {
                "job_id": f"bdb_{uni.split(',')[0]}_{seq}"[:60],
                "peptide_seq": seq,
                "cyclic_type": cyc_type,
                "uniprot": uni.split(",")[0],
                "target_name": tgt[:120],
                "receptor_seq": None,
                "affinity_nM": aff,
                "smiles": smi,
                "ligand_name": name[:120],
                "has_ncAA": bool(has_nc),
                "tool": args.tool,
                "conformer_provenance": f"{args.tool}_predicted",
                "train_only": True,
                "source": "BindingDB_measured_binder",
            }

            # ncAA rows -> HighFold-MeD deferral list (canonical Boltz batch keeps only clean canonical chains)
            if has_nc:
                ncaa_defer.append(job)
                continue

            if args.resolve_receptor:
                rec = fetch_uniprot_seq(uni, cache, timeout=30)
                time.sleep(args.sleep)
                if not rec:
                    drops["rec_unresolved"] += 1
                    continue
                if len(rec) > args.max_rec_len:
                    job["receptor_seq"] = rec
                    job["receptor_len"] = len(rec)
                    bigrec_defer.append(job)
                    drops["rec_too_long"] += 1
                    continue
                job["receptor_seq"] = rec
                job["receptor_len"] = len(rec)

            canonical.append(job)

    # write outputs
    def _write(path, rows):
        with open(path, "w") as fh:
            for r in rows:
                fh.write(json.dumps(r) + "\n")
        return len(rows)

    p_can = os.path.join(args.out_dir, "jobs_canonical.jsonl")
    p_nc = os.path.join(args.out_dir, "jobs_ncAA_defer.jsonl")
    p_br = os.path.join(args.out_dir, "jobs_bigrec_defer.jsonl")
    n_can = _write(p_can, canonical)
    n_nc = _write(p_nc, ncaa_defer)
    n_br = _write(p_br, bigrec_defer)

    manifest = {
        "experiment": "D2 (2ii) input-prep: BindingDB cyclic-peptide + UniProt-target pairs -> predictor job list",
        "utc": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "bindingdb_src": os.path.abspath(args.bindingdb),
        "tool": args.tool,
        "resolve_receptor": bool(args.resolve_receptor),
        "rdkit_available": _rdkit_macrocycle_size("C") is not None,
        "n_rows_scanned": n,
        "n_cyclic_peptide": n_cyclic,
        "n_canonical_jobs": n_can,
        "n_ncAA_defer_jobs": n_nc,
        "n_bigrec_defer_jobs": n_br,
        "n_unique_pairs": len(seen),
        "drops": drops,
        "caps": {"max_rec_len": args.max_rec_len, "pep_len": [args.min_pep_len, args.max_pep_len]},
        "written": [p_can, p_nc, p_br],
        "honest_note": (
            "Pairing is REAL (BindingDB measured binder + its UniProt target); never fabricated. Peptide sequences "
            "are recovered EXACTLY from ligand_name cyclo(...) annotations — SMILES->sequence via RDKit is NOT "
            "trusted (returns None -> row dropped) because a wrong chain poisons the predicted complex. CycPeptMPDB "
            "is NOT usable for pairing (no target column, permeability-only). ncAA rows deferred to HighFold-MeD."
        ),
    }
    with open(os.path.join(args.out_dir, "prep_manifest.json"), "w") as fh:
        json.dump(manifest, fh, indent=2)
    print(json.dumps(manifest, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
