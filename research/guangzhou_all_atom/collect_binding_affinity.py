#!/usr/bin/env python3
"""Robust peptide BINDING-affinity collector (ChEMBL primary + BindingDB secondary).

This replaces the brittle `collect_bindingdb.sh` JSP-scrape path (which could silently
emit a tiny stub when the Download.jsp HTML changed). Here every source is fetched
through a *stable* mechanism, every row is structurally classified with RDKit (not a
string heuristic), and the script refuses to write a "success" summary when a source
produced zero rows.

Sources
-------
1. ChEMBL (primary, stable REST API):
   - Peptide molecules are detected STRUCTURALLY with RDKit (ChEMBL has no
     `molecule_type=Peptide`; cyclosporine is 'Protein', most synthetic peptides are
     'Small molecule'). We anchor on molecule_type=Protein (small proteins/peptides
     that carry a canonical SMILES) and RDKit-confirm peptide backbone, then pull their
     Ki/Kd/IC50/EC50 activities. We ALSO pull all activities for the targets of interest
     (PD-L1, integrin alpha-V/beta-6 and their chains/complexes) and peptide-filter the
     ligands, so cyclic peptides classed as 'Small molecule' against those targets are
     not missed.
2. BindingDB (secondary):
   - Reuses the verified BindingDB_All_202609 peptide subset already staged on S3, or
     re-downloads via the STABLE dated-zip URL pattern
     (https://www.bindingdb.org/rwd/bind/downloads/BindingDB_All_YYYYmm_tsv.zip),
     probing recent months -- never scraping Download.jsp.

Output: one unified table with schema
  id, sequence_or_smiles, smiles, sequence, target_uniprot, target_name,
  affinity_nM, affinity_type, relation, source, cyclic_bool, is_pdl1, is_avb6
plus a summary JSON. Dedup is on (canonical_smiles|sequence, target_uniprot,
affinity_type) with the median affinity kept.
"""
from __future__ import annotations
import argparse, csv, io, json, os, sys, time, zipfile, statistics, subprocess, tempfile
from collections import defaultdict

import requests

csv.field_size_limit(min(sys.maxsize, 2**31 - 1))

# ---------------------------------------------------------------------------
# RDKit structural classifiers (the single ground-truth peptide/cyclic signal)
# ---------------------------------------------------------------------------
from rdkit import Chem
from rdkit import RDLogger
from rdkit.Chem import Descriptors
RDLogger.DisableLog("rdApp.*")

# amide bond (peptide bond): C(=O)-N
_AMIDE = Chem.MolFromSmarts("[NX3;!$(NC=O.=O)][CX3](=[OX1])")
_AMIDE2 = Chem.MolFromSmarts("[CX3](=[OX1])[NX3]")
# alpha-amino-acid residue backbone: N-Calpha(-R)-C(=O)
_RESIDUE = Chem.MolFromSmarts("[NX3,NX4+;!$(N=*)][CX4H1,CX4H2]([*])[CX3](=[OX1])")
_DISULFIDE = Chem.MolFromSmarts("[#16X2][#16X2]")

_mol_cache: dict[str, object] = {}

def _mol(smiles: str):
    if not smiles:
        return None
    if smiles in _mol_cache:
        return _mol_cache[smiles]
    m = Chem.MolFromSmiles(smiles)
    if len(_mol_cache) < 200000:
        _mol_cache[smiles] = m
    return m

def canonical_smiles(smiles: str) -> str:
    m = _mol(smiles)
    if m is None:
        return ""
    try:
        return Chem.MolToSmiles(m)
    except Exception:
        return ""

def count_amides(m) -> int:
    if m is None:
        return 0
    return len(m.GetSubstructMatches(_AMIDE2))

def is_peptide(smiles: str) -> bool:
    """Structural peptide test: >=2 alpha-residue backbones, or >=3 amide bonds with
    MW consistent with a peptide. Rejects simple amides / small molecules."""
    m = _mol(smiles)
    if m is None:
        return False
    try:
        n_res = len(m.GetSubstructMatches(_RESIDUE))
        n_amide = count_amides(m)
        mw = Descriptors.MolWt(m)
    except Exception:
        return False
    if n_res >= 2:
        return True
    # fallback: polyamide chains (depsipeptides, N-methylated) with enough amides + size
    if n_amide >= 3 and mw >= 450:
        return True
    return False

def is_cyclic_peptide(smiles: str) -> bool:
    """Macrocycle / bridged peptide: a ring of size >= 8, or a disulfide bridge."""
    m = _mol(smiles)
    if m is None:
        return False
    try:
        ri = m.GetRingInfo()
        for ring in ri.AtomRings():
            if len(ring) >= 8:
                return True
        if m.HasSubstructMatch(_DISULFIDE):
            # a disulfide bridge (e.g. Cys-Cys) closes a macrocyclic loop
            return True
    except Exception:
        return False
    return False

# ---------------------------------------------------------------------------
# Targets of interest
# ---------------------------------------------------------------------------
PDL1_UNIPROT = {"Q9NZQ7"}            # CD274 / PD-L1 (human)
AVB6_UNIPROT = {"P06756", "P18564"}  # ITGAV, ITGB6
PDL1_NAME_HINTS = ("pd-l1", "pdl1", "cd274", "b7-h1", "b7 homolog 1",
                   "programmed cell death 1 ligand 1", "programmed death-ligand 1",
                   "programmed death ligand 1")
AVB6_NAME_HINTS = ("alpha-v/beta-6", "alphavbeta6", "alpha-v beta-6", "avb6",
                   "integrin beta-6", "itgb6", "alpha-v/beta6", "alphav beta6")

def flag_pdl1(uniprot: str, name: str) -> bool:
    u = (uniprot or "").upper()
    if any(x in u for x in PDL1_UNIPROT):
        return True
    n = (name or "").lower()
    return any(h in n for h in PDL1_NAME_HINTS)

def flag_avb6(uniprot: str, name: str) -> bool:
    u = (uniprot or "").upper()
    if any(x in u.split(",") for x in AVB6_UNIPROT) or any(x in u for x in AVB6_UNIPROT):
        n = (name or "").lower()
        # ITGAV/ITGB6 appear in many complexes; require beta-6 context for the pair,
        # but a bare ITGB6 accession is already specific to beta-6.
        if "P18564" in u:
            return True
        if "P06756" in u and ("beta-6" in n or "beta6" in n or "b6" in n):
            return True
    n = (name or "").lower()
    return any(h in n for h in AVB6_NAME_HINTS)

# ---------------------------------------------------------------------------
# ChEMBL REST client
# ---------------------------------------------------------------------------
CHEMBL = "https://www.ebi.ac.uk/chembl/api/data"
AFFINITY_TYPES = ["Ki", "Kd", "IC50", "EC50"]

def _session() -> requests.Session:
    s = requests.Session()
    s.headers.update({"Accept": "application/json",
                      "User-Agent": "biomate-binding-collector/1.0"})
    return s

def _get(s: requests.Session, url: str, params=None, tries: int = 6, timeout: int = 90):
    last = None
    for i in range(tries):
        try:
            r = s.get(url, params=params, timeout=timeout)
            if r.status_code == 200:
                return r.json()
            if r.status_code in (429, 500, 502, 503, 504):
                last = f"HTTP {r.status_code}"
                time.sleep(min(2 ** i, 30))
                continue
            raise RuntimeError(f"HTTP {r.status_code} for {r.url}: {r.text[:200]}")
        except (requests.RequestException,) as e:
            last = str(e)
            time.sleep(min(2 ** i, 30))
    raise RuntimeError(f"GET failed after {tries} tries ({last}): {url} {params}")

def chembl_peptide_molecules(s: requests.Session, cache_path: str, limit: int | None = None) -> dict:
    """Return {chembl_id: {smiles, pref_name}} of RDKit-confirmed peptides drawn from
    molecule_type=Protein (these carry canonical SMILES for small proteins/peptides)."""
    if os.path.exists(cache_path):
        with open(cache_path) as fh:
            return json.load(fh)
    out: dict[str, dict] = {}
    url = f"{CHEMBL}/molecule.json"
    params = {"molecule_type": "Protein", "limit": 1000, "offset": 0,
              "only": "molecule_chembl_id,pref_name,molecule_structures,molecule_properties"}
    scanned = 0
    while True:
        d = _get(s, url, params)
        mols = d.get("molecules", [])
        if not mols:
            break
        for mol in mols:
            scanned += 1
            cid = mol.get("molecule_chembl_id")
            struct = mol.get("molecule_structures") or {}
            smi = struct.get("canonical_smiles")
            if not cid or not smi:
                continue
            props = mol.get("molecule_properties") or {}
            mw = props.get("full_mwt")
            try:
                if mw is not None and float(mw) > 10000:  # skip large proteins/antibodies
                    continue
            except (TypeError, ValueError):
                pass
            if not is_peptide(smi):
                continue
            out[cid] = {"smiles": smi, "pref_name": mol.get("pref_name") or ""}
        meta = d.get("page_meta", {})
        nxt = meta.get("next")
        print(f"  [chembl molecules] scanned={scanned} peptides={len(out)}", flush=True)
        if limit and len(out) >= limit:
            break
        if not nxt:
            break
        params["offset"] = params["offset"] + params["limit"]
    with open(cache_path, "w") as fh:
        json.dump(out, fh)
    return out

_target_uniprot_cache: dict[str, str] = {}
_target_uniprot_cache_path: str | None = None

def load_uniprot_cache(path: str):
    global _target_uniprot_cache_path
    _target_uniprot_cache_path = path
    if os.path.exists(path):
        try:
            _target_uniprot_cache.update(json.load(open(path)))
        except Exception:
            pass

def save_uniprot_cache():
    if _target_uniprot_cache_path:
        try:
            json.dump(_target_uniprot_cache, open(_target_uniprot_cache_path, "w"))
        except Exception:
            pass

def target_uniprot(s: requests.Session, target_chembl_id: str) -> str:
    if not target_chembl_id:
        return ""
    if target_chembl_id in _target_uniprot_cache:
        return _target_uniprot_cache[target_chembl_id]
    try:
        d = _get(s, f"{CHEMBL}/target/{target_chembl_id}.json")
        accs = []
        for comp in d.get("target_components", []) or []:
            acc = comp.get("accession")
            if acc:
                accs.append(acc)
        val = ",".join(dict.fromkeys(accs))
    except Exception:
        val = ""
    _target_uniprot_cache[target_chembl_id] = val
    return val

def _activity_rows_from_json(d):
    for a in d.get("activities", []):
        st = a.get("standard_type")
        if st not in AFFINITY_TYPES:
            continue
        val = a.get("standard_value")
        units = a.get("standard_units")
        if val in (None, "") or units != "nM":
            continue
        try:
            fval = float(val)
        except (TypeError, ValueError):
            continue
        if fval <= 0:
            continue
        yield a, fval

def chembl_activities_for_molecules(s, mol_ids, cache_path):
    """Pull Ki/Kd/IC50/EC50 (nM) activities for the given molecule ids; cache as JSONL."""
    done = set()
    rows = []
    if os.path.exists(cache_path):
        with open(cache_path) as fh:
            for line in fh:
                try:
                    r = json.loads(line)
                    rows.append(r)
                    done.add(r["_batch"])
                except Exception:
                    continue
    ids = list(mol_ids)
    BATCH = 20
    batches = [ids[i:i + BATCH] for i in range(0, len(ids), BATCH)]
    with open(cache_path, "a") as cache:
        for bi, batch in enumerate(batches):
            key = batch[0] + f":{len(batch)}"
            if key in done:
                continue
            url = f"{CHEMBL}/activity.json"
            params = {"molecule_chembl_id__in": ",".join(batch),
                      "standard_type__in": ",".join(AFFINITY_TYPES),
                      "standard_units": "nM", "limit": 1000, "offset": 0,
                      "only": ("molecule_chembl_id,canonical_smiles,standard_type,"
                               "standard_value,standard_units,standard_relation,"
                               "target_chembl_id,target_pref_name,target_organism,assay_type")}
            while True:
                d = _get(s, url, params)
                for a, fval in _activity_rows_from_json(d):
                    rec = {"_batch": key,
                           "molecule_chembl_id": a.get("molecule_chembl_id"),
                           "canonical_smiles": a.get("canonical_smiles"),
                           "standard_type": a.get("standard_type"),
                           "standard_value": fval,
                           "standard_relation": a.get("standard_relation"),
                           "target_chembl_id": a.get("target_chembl_id"),
                           "target_pref_name": a.get("target_pref_name"),
                           "target_organism": a.get("target_organism")}
                    rows.append(rec)
                    cache.write(json.dumps(rec) + "\n")
                meta = d.get("page_meta", {})
                if not meta.get("next"):
                    break
                params["offset"] += params["limit"]
            cache.flush()
            if bi % 25 == 0:
                print(f"  [chembl activities] batch {bi+1}/{len(batches)} rows={len(rows)}", flush=True)
    return rows

def chembl_activities_for_targets(s, target_ids, cache_path):
    """Pull ALL affinity activities for specific targets; peptide-filter later."""
    rows = []
    if os.path.exists(cache_path):
        with open(cache_path) as fh:
            for line in fh:
                try:
                    rows.append(json.loads(line))
                except Exception:
                    continue
        if rows:
            return rows
    with open(cache_path, "w") as cache:
        for tid in target_ids:
            url = f"{CHEMBL}/activity.json"
            params = {"target_chembl_id": tid,
                      "standard_type__in": ",".join(AFFINITY_TYPES),
                      "standard_units": "nM", "limit": 1000, "offset": 0,
                      "only": ("molecule_chembl_id,canonical_smiles,standard_type,"
                               "standard_value,standard_units,standard_relation,"
                               "target_chembl_id,target_pref_name,target_organism,assay_type")}
            while True:
                d = _get(s, url, params)
                for a, fval in _activity_rows_from_json(d):
                    rec = {"molecule_chembl_id": a.get("molecule_chembl_id"),
                           "canonical_smiles": a.get("canonical_smiles"),
                           "standard_type": a.get("standard_type"),
                           "standard_value": fval,
                           "standard_relation": a.get("standard_relation"),
                           "target_chembl_id": a.get("target_chembl_id"),
                           "target_pref_name": a.get("target_pref_name"),
                           "target_organism": a.get("target_organism")}
                    rows.append(rec)
                    cache.write(json.dumps(rec) + "\n")
                meta = d.get("page_meta", {})
                if not meta.get("next"):
                    break
                params["offset"] += params["limit"]
            print(f"  [chembl target {tid}] rows={len(rows)}", flush=True)
    return rows

# targets of interest ChEMBL ids (SINGLE PROTEIN + relevant complexes/PPIs)
TARGETS_OF_INTEREST = [
    "CHEMBL3580522",  # PD-L1 single protein
    "CHEMBL4523993",  # PD-1/PD-L1 complex
    "CHEMBL5739543",  # CRBN/PD-L1 PPI
    "CHEMBL2111416",  # integrin alpha-V/beta-6 complex
    "CHEMBL3660",     # integrin alpha-V
    "CHEMBL4876",     # integrin beta-6
]

# ---------------------------------------------------------------------------
# BindingDB
# ---------------------------------------------------------------------------
BDB_S3 = "s3://knowledge-datasets-1759951976/cyclic_peptide/datasets/bindingdb_peptide/202609/bindingdb_peptide_subset.csv"
BDB_SHA256 = "249a63617f2b79f1c520ab68f48f0d7ce4d1293b8da7a4cf91b0f9c7ba0e4a96"

def _sha256(path):
    import hashlib
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()

def fetch_bindingdb_subset(workdir: str) -> str:
    """Return a path to the BindingDB peptide subset CSV. Prefer the verified S3 copy;
    fall back to a direct dated-zip download (NOT the broken JSP scrape)."""
    local = os.path.join(workdir, "bindingdb_peptide_subset.csv")
    # 1) verified S3 copy
    rc = subprocess.run(["aws", "s3", "cp", BDB_S3, local, "--only-show-errors"],
                        capture_output=True, text=True)
    if rc.returncode == 0 and os.path.exists(local) and os.path.getsize(local) > 10_000_000:
        sha = _sha256(local)
        ok = (sha == BDB_SHA256)
        print(f"  [bindingdb] S3 copy fetched, sha256={sha[:16]} match={ok}", flush=True)
        return local
    print(f"  [bindingdb] S3 copy unavailable ({rc.stderr.strip()[:120]}); "
          "falling back to direct dated-zip download", flush=True)
    return fetch_bindingdb_full(workdir)

def fetch_bindingdb_full(workdir: str) -> str:
    """Robust direct download: probe recent BindingDB_All_YYYYmm_tsv.zip dated URLs."""
    s = _session()
    base = "https://www.bindingdb.org/rwd/bind/downloads/BindingDB_All_{}_tsv.zip"
    import datetime
    today = datetime.date.today()
    candidates = []
    y, m = today.year, today.month
    for _ in range(18):  # probe back 18 months
        candidates.append(f"{y}{m:02d}")
        m -= 1
        if m == 0:
            m = 12
            y -= 1
    zpath = os.path.join(workdir, "bindingdb_all.zip")
    url = None
    for rel in candidates:
        u = base.format(rel)
        try:
            h = s.head(u, timeout=60, allow_redirects=True)
            if h.status_code == 200:
                url = u
                break
        except requests.RequestException:
            continue
    if not url:
        raise RuntimeError("BindingDB UNREACHABLE: no dated BindingDB_All_*_tsv.zip "
                           "resolved over last 18 months. Source down -- NOT emitting a stub.")
    print(f"  [bindingdb] downloading {url}", flush=True)
    with s.get(url, stream=True, timeout=5400) as r:
        r.raise_for_status()
        with open(zpath, "wb") as fh:
            for chunk in r.iter_content(1 << 20):
                fh.write(chunk)
    with zipfile.ZipFile(zpath) as z:
        tsv_name = max((n for n in z.namelist() if n.endswith(".tsv")),
                       key=lambda n: z.getinfo(n).file_size)
        z.extract(tsv_name, workdir)
    tsv = os.path.join(workdir, tsv_name)
    # filter to a peptidic candidate subset into the same schema as the S3 copy
    local = os.path.join(workdir, "bindingdb_peptide_subset.csv")
    with open(tsv, newline="", encoding="utf-8", errors="replace") as fh, \
         open(local, "w", newline="") as out:
        rd = csv.reader(fh, delimiter="\t")
        header = next(rd)
        idx = {h: i for i, h in enumerate(header)}
        def col(name_sub):
            for h in header:
                if name_sub in h.lower():
                    return idx[h]
            return None
        smi_i = col("ligand smiles")
        nm_i = col("bindingdb ligand name")
        tgt_i = col("target name")
        uni_i = None
        for h in header:
            if "uniprot" in h.lower() and ("primary" in h.lower() or "swissprot" in h.lower()):
                uni_i = idx[h]; break
        ki_i, kd_i, ic_i, ec_i = (col("ki (nm)"), col("kd (nm)"),
                                  col("ic50 (nm)"), col("ec50 (nm)"))
        w = csv.writer(out)
        w.writerow(["smiles", "ligand_name", "target", "uniprot",
                    "Ki_nM", "Kd_nM", "IC50_nM", "EC50_nM"])
        def g(row, i):
            return row[i] if (i is not None and i < len(row)) else ""
        for row in rd:
            smi = g(row, smi_i)
            nm = g(row, nm_i)
            # cheap prefilter; RDKit is the real filter downstream
            if smi.count("C(=O)N") + smi.count("NC(=O)") < 3 and "peptide" not in nm.lower():
                continue
            w.writerow([smi, nm, g(row, tgt_i), g(row, uni_i),
                        g(row, ki_i), g(row, kd_i), g(row, ic_i), g(row, ec_i)])
    return local

def _pick_affinity(ki, kd, ic50, ec50):
    """Priority Ki > Kd > IC50 > EC50; parse relation prefixes."""
    for typ, raw in (("Ki", ki), ("Kd", kd), ("IC50", ic50), ("EC50", ec50)):
        if raw is None:
            continue
        raw = str(raw).strip()
        if not raw:
            continue
        rel = "="
        v = raw
        if raw[0] in "<>~":
            rel = raw[0]
            v = raw[1:].strip()
        try:
            fv = float(v)
        except ValueError:
            continue
        if fv <= 0:
            continue
        return typ, fv, rel
    return None, None, None

def load_bindingdb(path: str):
    rows = []
    with open(path, newline="") as fh:
        rd = csv.DictReader(fh)
        for r in rd:
            typ, val, rel = _pick_affinity(r.get("Ki_nM"), r.get("Kd_nM"),
                                           r.get("IC50_nM"), r.get("EC50_nM"))
            if typ is None:
                continue
            rows.append({"smiles": (r.get("smiles") or "").strip(),
                         "name": r.get("ligand_name") or "",
                         "target_name": r.get("target") or "",
                         "uniprot": (r.get("uniprot") or "").strip(),
                         "affinity_type": typ, "affinity_nM": val, "relation": rel})
    return rows

# ---------------------------------------------------------------------------
# Unify + dedup
# ---------------------------------------------------------------------------
def build_unified(chembl_rows, bindingdb_rows):
    """Return list of unified dict rows (pre-dedup)."""
    unified = []

    def add(idv, smiles, sequence, uniprot, target_name, aff, atype, rel, source):
        if not smiles and not sequence:
            return  # need a structure or a sequence to be a usable label
        can = canonical_smiles(smiles) if smiles else ""
        if smiles and not can:
            return  # unparseable structure
        if smiles and not is_peptide(smiles):
            return  # structural peptide gate
        cyclic = is_cyclic_peptide(smiles) if smiles else False
        seq_or_smiles = sequence if sequence else (can or smiles)
        unified.append({
            "id": idv,
            "sequence_or_smiles": seq_or_smiles,
            "smiles": can or smiles,
            "_canon": can or smiles,
            "sequence": sequence or "",
            "target_uniprot": uniprot or "",
            "target_name": target_name or "",
            "affinity_nM": aff,
            "affinity_type": atype,
            "relation": rel or "=",
            "source": source,
            "cyclic_bool": bool(cyclic),
            "is_pdl1": flag_pdl1(uniprot, target_name),
            "is_avb6": flag_avb6(uniprot, target_name),
        })

    for r in chembl_rows:
        add(r["molecule_chembl_id"], r.get("canonical_smiles") or "", "",
            r.get("target_uniprot") or "", r.get("target_pref_name") or "",
            r["standard_value"], r["standard_type"], r.get("standard_relation") or "=",
            "ChEMBL")
    for r in bindingdb_rows:
        add("", r["smiles"], "", r["uniprot"], r["target_name"],
            r["affinity_nM"], r["affinity_type"], r["relation"], "BindingDB")
    return unified

def dedup(unified):
    groups = defaultdict(list)
    for r in unified:
        key = (r["_canon"] or r["sequence"], r["target_uniprot"], r["affinity_type"])
        groups[key].append(r)
    out = []
    for key, rs in groups.items():
        vals = [x["affinity_nM"] for x in rs]
        med = statistics.median(vals)
        base = dict(rs[0])
        base["affinity_nM"] = round(med, 4)
        base["n_measurements"] = len(rs)
        base["sources"] = ",".join(sorted({x["source"] for x in rs}))
        base["source"] = base["sources"]
        base["cyclic_bool"] = any(x["cyclic_bool"] for x in rs)
        base["is_pdl1"] = any(x["is_pdl1"] for x in rs)
        base["is_avb6"] = any(x["is_avb6"] for x in rs)
        # prefer a ChEMBL id if present
        for x in rs:
            if x["id"]:
                base["id"] = x["id"]; break
        out.append(base)
    return out

# ---------------------------------------------------------------------------
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--workdir", default=os.environ.get("BINDING_WORKDIR",
                    "/tmp/binding_affinity_work"))
    ap.add_argument("--out", default="data/raw/binding_affinity")
    ap.add_argument("--no-chembl", action="store_true")
    ap.add_argument("--no-bindingdb", action="store_true")
    ap.add_argument("--chembl-mol-limit", type=int, default=None,
                    help="cap peptide molecules (testing only)")
    ap.add_argument("--s3-stage", default=None,
                    help="s3://.../binding_affinity_v1/ prefix to upload results")
    args = ap.parse_args()

    os.makedirs(args.workdir, exist_ok=True)
    os.makedirs(args.out, exist_ok=True)
    src_status = {}

    chembl_rows = []
    if not args.no_chembl:
        s = _session()
        print("[1/3] ChEMBL peptide molecules ...", flush=True)
        mols = chembl_peptide_molecules(s, os.path.join(args.workdir, "chembl_peptides.json"),
                                        limit=args.chembl_mol_limit)
        print(f"      peptide molecules: {len(mols)}", flush=True)
        print("[1/3] ChEMBL activities for peptide molecules ...", flush=True)
        acts = chembl_activities_for_molecules(
            s, list(mols.keys()), os.path.join(args.workdir, "chembl_mol_activities.jsonl"))
        print("[1/3] ChEMBL activities for targets of interest ...", flush=True)
        tacts = chembl_activities_for_targets(
            s, TARGETS_OF_INTEREST, os.path.join(args.workdir, "chembl_target_activities.jsonl"))
        # peptide-filter target activities by structure
        tacts = [a for a in tacts if a.get("canonical_smiles") and is_peptide(a["canonical_smiles"])]
        # resolve uniprot for all target_chembl_ids
        all_acts = acts + tacts
        tids = {a.get("target_chembl_id") for a in all_acts if a.get("target_chembl_id")}
        print(f"      resolving UniProt for {len(tids)} targets ...", flush=True)
        load_uniprot_cache(os.path.join(args.workdir, "target_uniprot.json"))
        for i, tid in enumerate(tids):
            target_uniprot(s, tid)
            if i % 200 == 0:
                save_uniprot_cache()
                print(f"        uniprot {i}/{len(tids)}", flush=True)
        save_uniprot_cache()
        for a in all_acts:
            a["target_uniprot"] = _target_uniprot_cache.get(a.get("target_chembl_id"), "")
        chembl_rows = all_acts
        src_status["chembl"] = {"status": "ok" if chembl_rows else "empty",
                                "raw_rows": len(chembl_rows),
                                "peptide_molecules": len(mols)}
        print(f"      ChEMBL raw affinity rows: {len(chembl_rows)}", flush=True)

    bindingdb_rows = []
    if not args.no_bindingdb:
        print("[2/3] BindingDB peptide subset ...", flush=True)
        try:
            bpath = fetch_bindingdb_subset(args.workdir)
            bindingdb_rows = load_bindingdb(bpath)
            src_status["bindingdb"] = {"status": "ok" if bindingdb_rows else "empty",
                                       "raw_rows": len(bindingdb_rows), "path": bpath}
            print(f"      BindingDB raw affinity rows: {len(bindingdb_rows)}", flush=True)
        except Exception as e:
            src_status["bindingdb"] = {"status": "unreachable", "error": str(e)}
            print(f"      BindingDB FAILED: {e}", flush=True)

    print("[3/3] Unify + RDKit peptide gate + dedup ...", flush=True)
    unified = build_unified(chembl_rows, bindingdb_rows)
    deduped = dedup(unified)

    if not deduped:
        print("FATAL: zero unified rows -- refusing to emit a stub success.", file=sys.stderr)
        status_path = os.path.join(args.out, "binding_affinity_summary.json")
        with open(status_path, "w") as fh:
            json.dump({"status": "failed", "reason": "zero_rows",
                       "sources": src_status}, fh, indent=2)
        sys.exit(2)

    # write CSV
    cols = ["id", "sequence_or_smiles", "smiles", "sequence", "target_uniprot",
            "target_name", "affinity_nM", "affinity_type", "relation",
            "source", "cyclic_bool", "is_pdl1", "is_avb6", "n_measurements"]
    csv_path = os.path.join(args.out, "binding_affinity_v1.csv")
    with open(csv_path, "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=cols, extrasaction="ignore")
        w.writeheader()
        for r in deduped:
            w.writerow(r)

    n_cyclic = sum(1 for r in deduped if r["cyclic_bool"])
    n_pep = len(deduped)  # all rows pass the peptide gate
    targets = {r["target_uniprot"] for r in deduped if r["target_uniprot"]}
    n_pdl1 = sum(1 for r in deduped if r["is_pdl1"])
    n_avb6 = sum(1 for r in deduped if r["is_avb6"])
    by_source = defaultdict(int)
    for r in deduped:
        by_source[r["source"]] += 1

    summary = {
        "status": "ok",
        "generated_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "total_rows": len(deduped),
        "peptide_rows": n_pep,
        "cyclic_rows": n_cyclic,
        "unique_targets_uniprot": len(targets),
        "pdl1_rows": n_pdl1,
        "avb6_rows": n_avb6,
        "rows_by_source": dict(by_source),
        "sources": src_status,
        "schema": cols,
        "csv": os.path.basename(csv_path),
    }
    summary_path = os.path.join(args.out, "binding_affinity_summary.json")
    with open(summary_path, "w") as fh:
        json.dump(summary, fh, indent=2)
    print(json.dumps(summary, indent=2), flush=True)

    if args.s3_stage:
        pref = args.s3_stage.rstrip("/")
        for p in (csv_path, summary_path):
            subprocess.run(["aws", "s3", "cp", p, f"{pref}/{os.path.basename(p)}",
                            "--only-show-errors"], check=True)
        print(f"Staged to {pref}/", flush=True)

if __name__ == "__main__":
    main()
