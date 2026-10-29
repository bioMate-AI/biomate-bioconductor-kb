"""K2 imports: fetch existing cyclic-peptide / macrocycle resources, parse, compute stereo-aware InChIKeys, JOIN to CycPeptMPDB.
Runs on EC2 (CPU). Amendment A2 of docs/20261031_ALLATOM_KNOWLEDGE_SCALE_PREREG.md. No row is discarded without being counted."""
import argparse, csv, gzip, hashlib, io, json, os, re, sys, time, urllib.request, zipfile

UA = {"User-Agent": "Mozilla/5.0 biomate-k2-import/1.0 (research)"}
ROUTES = {
    "cycpeptmpdb_peptides": "http://cycpeptmpdb.com/static//download/peptides/CycPeptMPDB_Peptide_All.csv",
    "cycpeptmpdb_monomers": "http://cycpeptmpdb.com/static//download/monomers/CycPeptMPDB_Monomer_All.csv",
    "swemacrocycledb_all": "https://swemacrocycledb.com/download_file_all/",
    "macrocycledb_all": "https://macro-db.dpbio.tech/Downloads/All.csv",
    "macrocycledb_pdb": "https://macro-db.dpbio.tech/Downloads/PDB.csv",
    "macrocycledb_clinical": "https://macro-db.dpbio.tech/Downloads/clinical.csv",
    "macrocycledb_fda": "https://macro-db.dpbio.tech/Downloads/FDA-approve_drug.csv",
    "macrocycledb_linker": "https://macro-db.dpbio.tech/Downloads/Linker.csv",
    "cremp_cycpeptmpdb_summary": "https://zenodo.org/api/records/13334335/files/summary_cycpeptmpdb.csv/content",
}
CP_BASE = "https://www.biosino.org/iMAC/cyclicpepedia/static/data/excel/"
CP_TABLES = ["Peptide_basic_info", "Peptide_sequence_info", "Peptide_structrure_info", "Peptide_to_source", "Peptide_to_function",
             "Peptide_to_family", "Peptide_to_target", "Bioassay", "Pubmed", "Source", "Function", "Family", "Target"]
for _t in CP_TABLES:
    ROUTES[f"cyclicpepedia_{_t}"] = CP_BASE + _t + ".xlsx"
ROUTES["cyclicpepedia_structure_2dmol_zip"] = "https://www.biosino.org/iMAC/cyclicpepedia/static/data/structure_2dmol.zip"
SMILES_COLS = ["smiles", "canonical_smiles", "isomeric_smiles", "structure", "molecule_smiles"]


def fetch(name, url, outdir, retries=3):
    path = os.path.join(outdir, "raw", name + (".xlsx" if url.endswith(".xlsx") else ".zip" if url.endswith(".zip") else ".csv"))
    os.makedirs(os.path.dirname(path), exist_ok=True)
    last = None
    for i in range(retries):
        try:
            req = urllib.request.Request(url, headers=UA)
            with urllib.request.urlopen(req, timeout=180) as r:
                data = r.read()
                hdr = dict(r.headers)
            open(path, "wb").write(data)
            return {"name": name, "url": url, "path": path, "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest(),
                    "http_date": hdr.get("Date"), "last_modified": hdr.get("Last-Modified"), "content_type": hdr.get("Content-Type"), "ok": True}
        except Exception as e:  # noqa: BLE001
            last = repr(e)
            time.sleep(3 * (i + 1))
    return {"name": name, "url": url, "ok": False, "error": last}


def read_csv_rows(path):
    raw = open(path, "rb").read()
    for enc in ("utf-8-sig", "utf-8", "latin-1"):
        try:
            txt = raw.decode(enc)
            break
        except UnicodeDecodeError:
            continue
    return list(csv.DictReader(io.StringIO(txt)))


def read_xlsx_rows(path):
    import openpyxl
    wb = openpyxl.load_workbook(path, read_only=True, data_only=True)
    ws = wb.active
    it = ws.iter_rows(values_only=True)
    hdr = [str(h) if h is not None else f"col{i}" for i, h in enumerate(next(it))]
    return [dict(zip(hdr, r)) for r in it]


def keys_for(smiles):
    from rdkit import Chem, RDLogger
    RDLogger.DisableLog("rdApp.*")
    if not smiles:
        return None, None, "empty"
    m = Chem.MolFromSmiles(str(smiles))
    if m is None:
        return None, None, "rdkit_parse"
    try:
        k = Chem.MolToInchiKey(m)
    except Exception:  # noqa: BLE001
        k = None
    if not k:
        return None, None, "inchikey_fail"
    return k, k.split("-")[0], "ok"


def find_smiles_col(cols):
    low = {c.lower(): c for c in cols}
    for c in SMILES_COLS:
        if c in low:
            return low[c]
    for c in cols:
        if "smiles" in c.lower():
            return c
    return None


def process_table(name, rows):
    if not rows:
        return {"name": name, "rows": 0}, []
    cols = list(rows[0].keys())
    sc = find_smiles_col(cols)
    st = {"name": name, "rows": len(rows), "columns": cols[:40], "smiles_col": sc, "parsed_ok": 0, "fail": {}}
    out = []
    if sc is None:
        st["note"] = "no SMILES column: metadata table"
        return st, out
    for r in rows:
        k, kf, why = keys_for(r.get(sc))
        if why == "ok":
            st["parsed_ok"] += 1
        else:
            st["fail"][why] = st["fail"].get(why, 0) + 1
        out.append((k, kf, r))
    return st, out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--outdir", required=True)
    ap.add_argument("--local-cycpeptmpdb", required=True, help="stratification/data/annotations.csv.gz")
    ap.add_argument("--only", nargs="*")
    a = ap.parse_args()
    os.makedirs(a.outdir, exist_ok=True)
    manifest, stats, tables = [], [], {}
    for name, url in ROUTES.items():
        if a.only and not any(name.startswith(o) for o in a.only):
            continue
        meta = fetch(name, url, a.outdir)
        manifest.append(meta)
        print(name, meta.get("ok"), meta.get("bytes"), flush=True)
        if not meta["ok"]:
            continue
        p = meta["path"]
        try:
            if p.endswith(".zip"):
                z = zipfile.ZipFile(p)
                meta["zip_members"] = len(z.namelist())
                meta["zip_member_sample"] = z.namelist()[:5]
                continue
            rows = read_xlsx_rows(p) if p.endswith(".xlsx") else read_csv_rows(p)
        except Exception as e:  # noqa: BLE001
            meta["parse_error"] = repr(e)
            continue
        st, out = process_table(name, rows)
        stats.append(st)
        tables[name] = out
    # local CycPeptMPDB keys
    loc = list(csv.DictReader(gzip.open(a.local_cycpeptmpdb, "rt", encoding="utf-8")))
    lsc = find_smiles_col(list(loc[0].keys()))
    lfull, lflat = set(), set()
    for r in loc:
        k, kf, why = keys_for(r.get(lsc))
        if k:
            lfull.add(k)
            lflat.add(kf)
    live = {k for k, kf, r in tables.get("cycpeptmpdb_peptides", []) if k}
    live_flat = {kf for k, kf, r in tables.get("cycpeptmpdb_peptides", []) if k}
    joins = {}
    for name, out in tables.items():
        n_key = sum(1 for k, kf, r in out if k)
        full_loc = sum(1 for k, kf, r in out if k in lfull)
        flat_loc = sum(1 for k, kf, r in out if kf in lflat)
        full_live = sum(1 for k, kf, r in out if k in live)
        flat_live = sum(1 for k, kf, r in out if kf in live_flat)
        joins[name] = {"rows": len(out), "with_inchikey": n_key, "full_join_local": full_loc, "flat_join_local": flat_loc,
                       "full_join_live_cycpeptmpdb": full_live, "flat_join_live_cycpeptmpdb": flat_live,
                       "unique_full_keys": len({k for k, kf, r in out if k})}
    # canonical output: resource tables with keys (gz jsonl) + join flags
    for name, out in tables.items():
        with gzip.open(os.path.join(a.outdir, f"{name}.canonical.jsonl.gz"), "wt", encoding="utf-8") as fh:
            for k, kf, r in out:
                fh.write(json.dumps({"resource": name, "inchikey_full": k, "inchikey_flat": kf, "in_cycpeptmpdb_local": bool(k and k in lfull),
                                     "in_cycpeptmpdb_flat_local": bool(kf and kf in lflat), "raw": {str(c): (None if v is None else str(v)) for c, v in r.items()}}) + "\n")
    summary = {"local_cycpeptmpdb_rows": len(loc), "local_unique_full_keys": len(lfull), "local_unique_flat_keys": len(lflat),
               "live_cycpeptmpdb_rows": len(tables.get("cycpeptmpdb_peptides", [])), "live_unique_full_keys": len(live),
               "manifest": manifest, "table_stats": stats, "joins": joins,
               "date_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())}
    json.dump(summary, open(os.path.join(a.outdir, "import_summary.json"), "w"), indent=1)
    print(json.dumps({k: v for k, v in summary.items() if k not in ("manifest", "table_stats")}, indent=1)[:3000])


if __name__ == "__main__":
    main()
