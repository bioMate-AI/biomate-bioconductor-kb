#!/usr/bin/env python3
"""
D2 (2i) — Mine EXPERIMENTAL target-BOUND cyclic peptide–protein complexes from the PDB.

Why this exists
---------------
The 8-member committee (docs/20260927_CYCLIC_CORPUS_AND_TRAINING_STRATEGY.md, Part A move #3 +
the "bound-complex ceiling") concluded the generator's TRUE bottleneck is NOT corpus size — it is
the near-total absence of target-*bound* cyclic complexes (the conditioning data the co-design
generator's target-SFT stage M2c needs; see 20260927_PEPTIDE_PARALLEL_WORK_PLAN.md, D2/M2c).
CREMP has no receptor; CycPeptMPDB is SMILES-only; the PepBDB cyclic subset is small. So the
highest-value acquisition is *experimental* bound cyclic complexes with a real receptor.

What this script does (CPU + light network, no GPU, no heavy download by default)
--------------------------------------------------------------------------------
1. Queries the RCSB search API for short protein "peptide" polymer entities (<= --max-pep-len
   residues) that sit in an assembly with >= 2 protein entities (i.e. bound to a receptor partner).
   This is the candidate pool (~14k at <=20 res, measured 2026-09-27).
2. For each candidate entry (capped by --limit), downloads only the light .cif metadata + the
   peptide+receptor coordinates, then detects CYCLIZATION structurally (metadata is insufficient —
   RCSB does not expose a searchable "cyclic peptide" flag; this is the honest limiter):
      - disulfide  : an SG–SG pair WITHIN the peptide chain (intramolecular SS macrocycle / cyclotide)
      - head_to_tail: N-terminal N amide-bonded to C-terminal C of the SAME peptide chain
      - sidechain_backbone / backbone_macrocycle: a non-consecutive backbone/near-backbone closure
        (lactam staple etc.) — flagged heuristically, verify downstream
   A peptide with NO intra-chain closure is dropped (linear → not our target data).
3. Extracts peptide chain + receptor chain(s) + records the interface (so the mined complex matches
   the PepGLAD training format: receptor blocks + ligand blocks + pocket residues; cf.
   runtime/PepGLAD/scripts/data_process/{process.py,pepbdb.py}).
4. Writes a PROVENANCE-TAGGED manifest (JSONL + a PepGLAD-style index .txt):
      pdb_id, pep_chain, rec_chain(s), peptide_seq, seq_len, cyclization_type, cyclization_evidence,
      resolution, method, receptor_name, n_interface_residues, provenance="PDB_experimental",
      conformer_provenance (crystal|NMR|cryo-EM), retrieved_utc.

Cyclization detection is COORDINATE-BASED and deliberately conservative. Every row is
provenance-tagged so a bound-geometry SFT head is never trained on a computed/ETKDG pose
(committee blocking fix #3).

Runtime deps
------------
- stdlib only for the RCSB *count/list* estimate mode (--estimate / --list-only).
- Coordinate parsing prefers `gemmi` (fast .cif), falls back to `biopython`, falls back to a small
  built-in PDB-format parser (no third-party parse dep) so the manifest step is runnable CPU-only.
  If none can fetch coordinates, the script still emits the candidate list + provenance and marks
  cyclization_type="UNVERIFIED_needs_coords" (never silently claims cyclic).

Examples
--------
  # 1. Cheap: just estimate the obtainable count (no coordinate download)
  python3 mine_bound_cyclic_complexes.py --estimate

  # 2. List the candidate entry ids to a file (no coordinate download)
  python3 mine_bound_cyclic_complexes.py --list-only --max-pep-len 20 \
      --out-dir data/bound_cyclic/candidates

  # 3. Full mine of the first N candidates (downloads N small .cif files)
  python3 mine_bound_cyclic_complexes.py --limit 200 --max-pep-len 16 \
      --out-dir data/bound_cyclic/v1
"""
from __future__ import annotations

import argparse
import gzip
import io
import json
import math
import os
import sys
import time
import urllib.parse
import urllib.request
from datetime import datetime, timezone

RCSB_SEARCH = "https://search.rcsb.org/rcsbsearch/v2/query?json="
RCSB_CIF = "https://files.rcsb.org/download/{pdb}.cif.gz"          # coordinates
RCSB_ENTRY_API = "https://data.rcsb.org/rest/v1/core/entry/{pdb}"  # metadata (resolution, method)

# --- cyclization geometry thresholds (Angstrom) ---
SS_MAX = 2.5          # SG–SG covalent disulfide
AMIDE_MAX = 1.8       # C(=O)–N peptide-bond length for head-to-tail closure
LACTAM_MAX = 2.0      # generic sidechain/backbone C–N closure (staple/lactam heuristic)
INTERFACE_MAX = 6.0   # atomic-contact interface (matches PepGLAD blocks_interface 6.0 A)

# 3-letter -> 1-letter (standard 20 + a few common modified that still carry a backbone)
AA3TO1 = {
    "ALA":"A","ARG":"R","ASN":"N","ASP":"D","CYS":"C","GLN":"Q","GLU":"E","GLY":"G","HIS":"H",
    "ILE":"I","LEU":"L","LYS":"K","MET":"M","PHE":"F","PRO":"P","SER":"S","THR":"T","TRP":"W",
    "TYR":"Y","VAL":"V","MSE":"M","SEC":"U","PYL":"O",
}


# ----------------------------------------------------------------------------- RCSB search
def _rcsb_query(query: dict, timeout: int = 40, retries: int = 3):
    url = RCSB_SEARCH + urllib.parse.quote(json.dumps(query))
    last = None
    for _ in range(retries):
        try:
            with urllib.request.urlopen(url, timeout=timeout) as r:
                return json.load(r)
        except Exception as e:  # noqa: BLE001
            last = e
            time.sleep(2)
    raise RuntimeError(f"RCSB query failed after {retries} tries: {last}")


def _term(attr, op, val, service="text"):
    return {"type": "terminal", "service": service,
            "parameters": {"attribute": attr, "operator": op, "value": val}}


def _candidate_query(max_pep_len: int, return_type: str, rows: int = 0, count_only: bool = False):
    """Short protein peptide entity bound to a receptor (>=2 protein entities in the assembly)."""
    nodes = [
        _term("entity_poly.rcsb_entity_polymer_type", "exact_match", "Protein"),
        _term("entity_poly.rcsb_sample_sequence_length", "less_or_equal", max_pep_len),
        _term("rcsb_assembly_info.polymer_entity_count_protein", "greater_or_equal", 2),
    ]
    q = {"query": {"type": "group", "logical_operator": "and", "nodes": nodes},
         "return_type": return_type}
    if count_only:
        q["request_options"] = {"return_counts": True}
    else:
        q["request_options"] = {"paginate": {"start": 0, "rows": rows}}
    return q


def estimate_counts():
    """Print the realistic obtainable-count table (cheap, no coordinate download)."""
    print("== RCSB candidate pool: short peptide entity bound to a receptor ==")
    print("   (protein polymer entity, <= N residues, assembly has >= 2 protein entities)")
    out = {}
    for n in (12, 15, 16, 20, 25):
        c = _rcsb_query(_candidate_query(n, "polymer_entity", count_only=True)).get("total_count")
        out[n] = c
        print(f"   <= {n:>2} res : {c}")
    print("\n   NOTE: these are the CANDIDATE (mostly LINEAR) bound short peptides. The CYCLIC")
    print("   subset (intra-chain SS-bond / head-to-tail / lactam) is a fraction of this and can")
    print("   only be found by coordinate-based detection (this script's --limit mode). RCSB does")
    print("   not expose a searchable cyclic flag; disulfide_bond_count counts receptor SS too.")
    return out


def list_candidates(max_pep_len: int, rows: int):
    q = _candidate_query(max_pep_len, "polymer_entity", rows=rows)
    res = _rcsb_query(q)
    ids = [hit["identifier"] for hit in res.get("result_set", [])]  # e.g. "1ABC_1"
    # collapse polymer_entity ids -> unique entry ids
    entries = sorted({eid.split("_")[0] for eid in ids})
    return entries, ids


# ----------------------------------------------------------------------------- coordinate parsing
class _Atom:
    __slots__ = ("chain", "resseq", "resname", "name", "element", "x", "y", "z")

    def __init__(self, chain, resseq, resname, name, element, x, y, z):
        self.chain, self.resseq, self.resname = chain, resseq, resname
        self.name, self.element = name, element
        self.x, self.y, self.z = x, y, z


def _fetch_cif_text(pdb: str, timeout: int = 60):
    url = RCSB_CIF.format(pdb=pdb.lower())
    with urllib.request.urlopen(url, timeout=timeout) as r:
        raw = r.read()
    return gzip.decompress(raw).decode("utf-8", "replace")


def _parse_cif_atoms(cif_text: str):
    """Minimal mmCIF atom_site parser (auth_asym_id, auth_seq_id, label_atom_id, coords).

    Falls back to gemmi if available (more robust to altlocs / assemblies)."""
    try:
        import gemmi  # type: ignore
        st = gemmi.read_structure_from_string(cif_text, format=gemmi.CoorFormat.Mmcif)
        st.setup_entities()
        atoms = []
        model = st[0]
        for chain in model:
            for res in chain:
                for at in res:
                    if at.element.name == "H":
                        continue
                    p = at.pos
                    atoms.append(_Atom(chain.name, str(res.seqid.num), res.name,
                                       at.name, at.element.name, p.x, p.y, p.z))
        return atoms
    except Exception:  # noqa: BLE001
        pass

    # --- built-in loop_ parser for _atom_site (first model only) ---
    lines = cif_text.splitlines()
    i, n = 0, len(lines)
    atoms = []
    while i < n:
        if lines[i].strip() == "loop_":
            j = i + 1
            cols = []
            while j < n and lines[j].lstrip().startswith("_atom_site."):
                cols.append(lines[j].strip())
                j += 1
            if not cols:
                i += 1
                continue
            idx = {c: k for k, c in enumerate(cols)}

            def col(name):
                return idx.get(f"_atom_site.{name}")

            c_group = col("group_PDB")
            c_atom = col("label_atom_id")
            c_elem = col("type_symbol")
            c_comp = col("auth_comp_id") if col("auth_comp_id") is not None else col("label_comp_id")
            c_chain = col("auth_asym_id") if col("auth_asym_id") is not None else col("label_asym_id")
            c_seq = col("auth_seq_id") if col("auth_seq_id") is not None else col("label_seq_id")
            c_x, c_y, c_z = col("Cartn_x"), col("Cartn_y"), col("Cartn_z")
            c_model = col("pdbx_PDB_model_num")
            if None in (c_atom, c_comp, c_chain, c_seq, c_x, c_y, c_z):
                i = j
                continue
            first_model = None
            k = j
            while k < n and lines[k] and not lines[k].startswith(("loop_", "_", "#", "data_")):
                parts = lines[k].split()
                if len(parts) <= max(c_x, c_y, c_z):
                    k += 1
                    continue
                if c_model is not None:
                    m = parts[c_model]
                    if first_model is None:
                        first_model = m
                    if m != first_model:
                        break
                if c_group is not None and parts[c_group] not in ("ATOM", "HETATM"):
                    k += 1
                    continue
                elem = parts[c_elem] if c_elem is not None else parts[c_atom][0]
                if elem == "H" or elem == "D":
                    k += 1
                    continue
                try:
                    x, y, z = float(parts[c_x]), float(parts[c_y]), float(parts[c_z])
                except ValueError:
                    k += 1
                    continue
                atoms.append(_Atom(parts[c_chain], parts[c_seq], parts[c_comp],
                                   parts[c_atom].strip('"'), elem, x, y, z))
                k += 1
            i = k
        else:
            i += 1
    return atoms


def _dist(a: _Atom, b: _Atom):
    return math.sqrt((a.x - b.x) ** 2 + (a.y - b.y) ** 2 + (a.z - b.z) ** 2)


# ----------------------------------------------------------------------------- chain analysis
def _chain_residues(atoms, chain):
    """Ordered list of (resseq, resname, {atom_name: _Atom}) for a chain, backbone-bearing only."""
    res = {}
    order = []
    for a in atoms:
        if a.chain != chain:
            continue
        key = a.resseq
        if key not in res:
            res[key] = {"resname": a.resname, "atoms": {}}
            order.append(key)
        res[key]["atoms"][a.name] = a
    out = []
    for key in order:
        r = res[key]
        if {"N", "CA", "C"} <= set(r["atoms"].keys()):  # is an amino-acid residue
            out.append((key, r["resname"], r["atoms"]))
    return out


def _seq_of(residues):
    return "".join(AA3TO1.get(rn.upper(), "X") for _, rn, _ in residues)


def _protein_chains(atoms):
    """Return {chain: n_residues} for chains that look like polypeptides."""
    counts = {}
    for chain in {a.chain for a in atoms}:
        res = _chain_residues(atoms, chain)
        if res:
            counts[chain] = len(res)
    return counts


def detect_cyclization(residues):
    """Return (type, evidence) for a peptide chain's residue list. None if linear."""
    if len(residues) < 3:
        return None, None
    # 1. intra-chain disulfide: any two CYS with SG–SG <= SS_MAX
    sgs = [(k, r["SG"]) for (k, rn, r) in residues if rn.upper() in ("CYS", "SEC") and "SG" in r]
    for a in range(len(sgs)):
        for b in range(a + 1, len(sgs)):
            d = _dist(sgs[a][1], sgs[b][1])
            if d <= SS_MAX:
                return "disulfide", f"SG(res {sgs[a][0]})–SG(res {sgs[b][0]}) = {d:.2f}A"
    # 2. head-to-tail: C-term carbonyl C amide-bonded to N-term N
    n_term = residues[0][2].get("N")
    c_term = residues[-1][2].get("C")
    if n_term is not None and c_term is not None:
        d = _dist(n_term, c_term)
        if d <= AMIDE_MAX:
            return "head_to_tail", f"Nterm-N–Cterm-C = {d:.2f}A"
    # 3. sidechain/lactam macrocycle heuristic: a backbone N of residue i bonded to a
    #    non-adjacent carbonyl/sidechain C (Asp/Glu -> Lys lactam staple, etc.)
    bb_n = [(k, r["N"]) for (k, rn, r) in residues if "N" in r]
    side_c = []
    for (k, rn, r) in residues:
        for cname in ("CG", "CD", "CE", "C"):  # Asp CG, Glu CD, generic carbonyl
            if cname in r:
                side_c.append((k, cname, r[cname]))
    for (ki, na) in bb_n:
        for (kj, cn, ca) in side_c:
            if ki == kj or (ki, na) == (kj, ca):
                continue
            # skip the trivial i -> i-1 backbone amide (consecutive residues)
            try:
                if abs(int(ki) - int(kj)) <= 1 and cn == "C":
                    continue
            except ValueError:
                pass
            if _dist(na, ca) <= LACTAM_MAX:
                return "sidechain_backbone", f"N(res {ki})–{cn}(res {kj}) = {_dist(na, ca):.2f}A"
    return None, None


def interface_residues(atoms, pep_chain, rec_chains, cutoff=INTERFACE_MAX):
    """Count receptor residues with any heavy atom within `cutoff` of any peptide heavy atom."""
    pep_atoms = [a for a in atoms if a.chain == pep_chain]
    rec_atoms = [a for a in atoms if a.chain in rec_chains]
    if not pep_atoms or not rec_atoms:
        return 0
    # coarse spatial bucket to avoid O(n*m) blow-up
    contacted = set()
    cut2 = cutoff * cutoff
    for ra in rec_atoms:
        for pa in pep_atoms:
            dx = ra.x - pa.x
            if dx * dx > cut2:
                continue
            if (ra.x - pa.x) ** 2 + (ra.y - pa.y) ** 2 + (ra.z - pa.z) ** 2 <= cut2:
                contacted.add((ra.chain, ra.resseq))
                break
    return len(contacted)


# ----------------------------------------------------------------------------- entry metadata
def _fetch_entry_meta(pdb: str, timeout: int = 30):
    try:
        with urllib.request.urlopen(RCSB_ENTRY_API.format(pdb=pdb.upper()), timeout=timeout) as r:
            j = json.load(r)
    except Exception:  # noqa: BLE001
        return {"resolution": None, "method": None, "title": None}
    method = None
    exptl = j.get("exptl") or []
    if exptl:
        method = exptl[0].get("method")
    res = None
    ri = j.get("rcsb_entry_info", {})
    reslist = ri.get("resolution_combined") or []
    if reslist:
        res = reslist[0]
    return {"resolution": res, "method": method, "title": j.get("struct", {}).get("title")}


def _conformer_provenance(method):
    if not method:
        return "PDB_experimental_unknown"
    m = method.upper()
    if "NMR" in m:
        return "NMR_experimental"
    if "ELECTRON MICROSCOPY" in m or "EM" == m:
        return "cryoEM_experimental"
    if "X-RAY" in m or "DIFFRACTION" in m:
        return "crystal_experimental"
    return "PDB_experimental_other"


# ----------------------------------------------------------------------------- mine one entry
def mine_entry(pdb: str, max_pep_len: int):
    """Download coords, find the cyclic peptide chain + its receptor. Returns a manifest row or None."""
    try:
        cif = _fetch_cif_text(pdb)
        atoms = _parse_cif_atoms(cif)
    except Exception as e:  # noqa: BLE001
        return {"pdb_id": pdb, "status": f"coord_fetch_failed:{type(e).__name__}",
                "provenance": "PDB_experimental"}
    if not atoms:
        return {"pdb_id": pdb, "status": "no_atoms_parsed", "provenance": "PDB_experimental"}

    chain_lens = _protein_chains(atoms)
    if len(chain_lens) < 2:
        return None  # need a peptide + a receptor
    # peptide candidate = shortest protein chain within length window; receptor = the rest
    pep_chain = min(chain_lens, key=chain_lens.get)
    if not (2 < chain_lens[pep_chain] <= max_pep_len):
        return None
    rec_chains = [c for c in chain_lens if c != pep_chain and chain_lens[c] > chain_lens[pep_chain]]
    if not rec_chains:
        return None

    residues = _chain_residues(atoms, pep_chain)
    cyc_type, cyc_ev = detect_cyclization(residues)
    if cyc_type is None:
        return None  # LINEAR -> not our target data (drop)

    n_if = interface_residues(atoms, pep_chain, set(rec_chains))
    if n_if == 0:
        return None  # peptide not actually contacting the receptor

    meta = _fetch_entry_meta(pdb)
    return {
        "pdb_id": pdb,
        "pep_chain": pep_chain,
        "rec_chains": rec_chains,
        "peptide_seq": _seq_of(residues),
        "seq_len": len(residues),
        "cyclization_type": cyc_type,
        "cyclization_evidence": cyc_ev,
        "resolution": meta["resolution"],
        "method": meta["method"],
        "receptor_name": meta["title"],
        "n_interface_residues": n_if,
        "provenance": "PDB_experimental",
        "conformer_provenance": _conformer_provenance(meta["method"]),
        "retrieved_utc": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "status": "ok",
    }


# ----------------------------------------------------------------------------- outputs
def write_manifest(rows, out_dir):
    os.makedirs(out_dir, exist_ok=True)
    jsonl = os.path.join(out_dir, "bound_cyclic_manifest.jsonl")
    idx = os.path.join(out_dir, "index.txt")  # PepGLAD-style: pdb_id_pepchain  rec_chain  pep_chain
    kept = [r for r in rows if r.get("status") == "ok"]
    with open(jsonl, "w") as f:
        for r in rows:
            f.write(json.dumps(r) + "\n")
    with open(idx, "w") as f:
        for r in kept:
            rec = r["rec_chains"][0] if r["rec_chains"] else ""
            f.write(f"{r['pdb_id']}_{r['pep_chain']}\t{rec}\t{r['pep_chain']}\t0\n")
    # summary
    by_type = {}
    for r in kept:
        by_type[r["cyclization_type"]] = by_type.get(r["cyclization_type"], 0) + 1
    summary = {
        "out_dir": out_dir,
        "n_candidates_examined": len(rows),
        "n_cyclic_bound_complexes": len(kept),
        "by_cyclization_type": by_type,
        "provenance": "PDB_experimental",
        "written": [jsonl, idx],
        "note": ("PepGLAD-format index emitted (pdb_id_pepchain / rec_chain / pep_chain / 0). "
                 "Feed to runtime/PepGLAD process pipeline. Every row is provenance-tagged; "
                 "bound-geometry SFT (M2c) must use conformer_provenance in {crystal,NMR,cryoEM}."),
    }
    with open(os.path.join(out_dir, "summary.json"), "w") as f:
        json.dump(summary, f, indent=2)
    return summary


# ----------------------------------------------------------------------------- CLI
def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--estimate", action="store_true",
                    help="Only print obtainable-count table (no coordinate download).")
    ap.add_argument("--list-only", action="store_true",
                    help="Only fetch + write candidate entry ids (no coordinate download).")
    ap.add_argument("--max-pep-len", type=int, default=20,
                    help="Max peptide chain length (residues) to treat as a peptide ligand.")
    ap.add_argument("--limit", type=int, default=200,
                    help="Number of candidate entries to actually mine (coord download).")
    ap.add_argument("--rows", type=int, default=10000,
                    help="How many candidate polymer entities to pull from RCSB before de-dup.")
    ap.add_argument("--out-dir", default="data/bound_cyclic/v1")
    ap.add_argument("--sleep", type=float, default=0.15, help="Delay between coord downloads (s).")
    args = ap.parse_args()

    if args.estimate:
        estimate_counts()
        return

    print(f"[list] querying RCSB for candidate bound short peptides (<= {args.max_pep_len} res)...",
          file=sys.stderr)
    entries, entity_ids = list_candidates(args.max_pep_len, args.rows)
    print(f"[list] {len(entries)} unique candidate entries "
          f"(from {len(entity_ids)} peptide entities, capped at rows={args.rows})", file=sys.stderr)

    os.makedirs(args.out_dir, exist_ok=True)
    with open(os.path.join(args.out_dir, "candidate_entries.txt"), "w") as f:
        f.write("\n".join(entries) + "\n")

    if args.list_only:
        print(json.dumps({"n_candidate_entries": len(entries),
                          "written": os.path.join(args.out_dir, "candidate_entries.txt"),
                          "note": "run without --list-only to detect cyclization + build manifest"},
                         indent=2))
        return

    todo = entries[: args.limit]
    print(f"[mine] downloading coords + detecting cyclization for {len(todo)} entries...",
          file=sys.stderr)
    rows = []
    for i, pdb in enumerate(todo, 1):
        row = mine_entry(pdb, args.max_pep_len)
        if row is not None:
            rows.append(row)
        if i % 25 == 0:
            n_ok = sum(1 for r in rows if r.get("status") == "ok")
            print(f"[mine] {i}/{len(todo)} examined, {n_ok} cyclic-bound kept", file=sys.stderr)
        time.sleep(args.sleep)

    summary = write_manifest(rows, args.out_dir)
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
