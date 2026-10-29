"""K4 stage 3: manifest, statistics, overlap/novelty, author-audit sample. usage: postprocess.py --extract DIR --corpus corpus.jsonl.gz --out DIR
[--bindingdb zip] [--cmpdb annotations.csv.gz] [--cost-hours H --cost-rate R]"""
import argparse, collections, csv, gzip, hashlib, json, os, random, re, zipfile
import pandas as pd

def ik14(x):
    return str(x).split("-")[0] if isinstance(x, str) and "-" in x else None

def pn_norm(x):
    return re.sub(r"[^A-Z0-9]", "", str(x).upper())

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--extract", required=True); ap.add_argument("--corpus", required=True); ap.add_argument("--out", required=True)
    ap.add_argument("--bindingdb"); ap.add_argument("--cmpdb"); ap.add_argument("--cost-hours", type=float, default=0.0); ap.add_argument("--cost-rate", type=float, default=0.0)
    a = ap.parse_args(); os.makedirs(a.out, exist_ok=True)
    items = {}
    for l in open(os.path.join(a.extract, "items_verified.jsonl")):
        r = json.loads(l); items.setdefault(r["item_id"], r)
    items = list(items.values())
    rej = collections.Counter(json.loads(l)["reason"] for l in open(os.path.join(a.extract, "items_rejected.jsonl"))) if os.path.exists(os.path.join(a.extract, "items_rejected.jsonl")) else {}
    stats = json.load(open(os.path.join(a.extract, "stats.json")))
    pats = [json.loads(l) for l in gzip.open(a.corpus, "rt")]
    pset = {p["patent_number"] for p in pats}
    M = {"n_patents": len(pats), "n_items_verified_unique": len(items), "raw_items": stats["raw_items"], "passages": stats["passages"],
         "parse_fail_passages": stats["parse_fail_passages"], "rejected_by_reason": dict(rej), "prompt_tokens": stats["prompt_tokens"],
         "completion_tokens": stats["completion_tokens"], "gen_seconds": stats["gen_seconds"],
         "reject_rate": round(1 - len(items) / max(1, stats["raw_items"]), 3)}
    M["by_kind"] = dict(collections.Counter(r["kind"] for r in items))
    M["by_stratum"] = dict(collections.Counter(r["stratum"] for r in items))
    M["patents_with_items"] = len({r["patent_number"] for r in items})
    M["patents_by_stratum"] = dict(collections.Counter(p["stratum"] for p in pats))
    ex = [r for r in items if r["kind"] == "example_compound"]
    M["example_compounds"] = len(ex)
    M["patents_with_example_compounds"] = len({r["patent_number"] for r in ex})
    withstruct = [r for r in ex if r.get("structure_string")]
    M["example_with_structure_string"] = len(withstruct)
    okst = [r for r in withstruct if str(r.get("structure_status", "")).startswith("ok")]
    M["structure_parse_success"] = {"n_ok": len(okst), "n_total": len(withstruct), "rate": round(len(okst) / max(1, len(withstruct)), 3),
                                    "status_counts": dict(collections.Counter(str(r.get("structure_status", "none")).split(":")[0] for r in withstruct))}
    M["with_activity_value"] = sum(1 for r in items if r.get("activity") and r["activity"].get("value") is not None)
    M["top_targets"] = collections.Counter(r["target"].lower() for r in items if r.get("target")).most_common(15)
    cpc_ver = sum(1 for p in pats if any(c.replace(" ", "") in __import__("config").CPC_VERIFIED for c in p["meta"].get("cpc", [])))
    M["pilot_patents_with_verified_cpc_in_google_page"] = cpc_ver
    # overlap / novelty
    if a.bindingdb and os.path.exists(a.bindingdb):
        z = zipfile.ZipFile(a.bindingdb)
        df = pd.read_csv(z.open(z.namelist()[0]), sep="\t", low_memory=False, on_bad_lines="skip",
                         usecols=["Ligand InChI Key", "Patent Number"])
        df["ik14"] = df["Ligand InChI Key"].map(ik14); df["pn"] = df["Patent Number"].map(pn_norm)
        bd_ik, bd_pn = set(df["ik14"].dropna()), set(df["pn"].dropna())
        in_any = sum(1 for r in okst if ik14(r.get("inchikey")) in bd_ik)
        by_pn = collections.defaultdict(set)
        for pn_, k in zip(df["pn"], df["ik14"]):
            by_pn[pn_].add(k)
        in_same = sum(1 for r in okst if ik14(r.get("inchikey")) in by_pn.get(pn_norm(r["patent_number"]).replace("A1", "").replace("B2", "").replace("B1", ""), set()))
        M["bindingdb_overlap"] = {"n_structures": len(okst), "in_bindingdb_patents_any": in_any, "in_same_patent_in_bindingdb": in_same,
                                  "not_in_bindingdb_any": len(okst) - in_any,
                                  "pilot_patents_present_in_bindingdb": sum(1 for p in pset if pn_norm(p).rstrip("ABC0123456789")[:0] or any(q.startswith(pn_norm(p)[:-2]) for q in list(bd_pn)[:0])) }
        bdp = {re.sub(r"(A\d?|B\d?)$", "", pn_norm(p)) for p in pset}
        M["bindingdb_overlap"]["pilot_patents_present_in_bindingdb"] = len(bdp & {re.sub(r"(A\d?|B\d?)$", "", x) for x in bd_pn})
    if a.cmpdb and os.path.exists(a.cmpdb):
        cm = pd.read_csv(a.cmpdb)
        cols = [c for c in cm.columns if "inchi" in c.lower()]
        if cols:
            cm_ik = {ik14(x) for x in cm[cols[0]].dropna()}
            M["cycpeptmpdb_overlap"] = {"inchikey_col": cols[0], "n_in": sum(1 for r in okst if ik14(r.get("inchikey")) in cm_ik)}
        else:
            M["cycpeptmpdb_overlap"] = {"note": "no InChIKey column in annotation file"}
    M["cost"] = {"gpu_instance_hours": a.cost_hours, "rate_usd_per_hour": a.cost_rate, "estimated_usd": round(a.cost_hours * a.cost_rate, 3),
                 "patents_per_gpu_hour": round(len(pats) / a.cost_hours, 1) if a.cost_hours else None}
    # audit sample (author audit; seed 20261031): >= 8 per kind where available, up to 50
    rng = random.Random(20261031)
    bykind = collections.defaultdict(list)
    for r in items:
        bykind[r["kind"]].append(r)
    samp = []
    for k, rs in sorted(bykind.items()):
        samp += rng.sample(rs, min(10, len(rs)))
    rest = [r for r in items if r not in samp]
    samp += rng.sample(rest, max(0, min(50 - len(samp), len(rest)))) if len(samp) < 50 else []
    samp = samp[:60]
    ctx = {p["patent_number"]: p["text"] for p in pats}
    with open(os.path.join(a.out, "audit_sample.csv"), "w", newline="") as fh:
        w = csv.writer(fh)
        w.writerow(["item_id", "patent_number", "kind", "statement", "compound_id", "structure_string", "structure_status", "activity", "quote", "context", "AUDIT_correct(1/0)", "AUDIT_note"])
        for r in samp:
            t = ctx[r["patent_number"]]; i = t.find(r["quote"][:60]); c = t[max(0, i - 300):i + len(r["quote"]) + 300] if i >= 0 else ""
            w.writerow([r["item_id"], r["patent_number"], r["kind"], r["statement"], r["compound_id"], r["structure_string"], r.get("structure_status", ""),
                        json.dumps(r.get("activity")), r["quote"], re.sub(r"\s+", " ", c), "", ""])
    M["audit_sample_n"] = len(samp)
    pk = os.path.join(a.out, "patent_kb_pilot.jsonl")
    with open(pk, "w") as fh:
        for r in items:
            fh.write(json.dumps(r) + "\n")
    M["patent_kb_pilot_sha256"] = hashlib.sha256(open(pk, "rb").read()).hexdigest()
    json.dump(M, open(os.path.join(a.out, "measure.json"), "w"), indent=1, default=str)
    open(os.path.join(a.out, "patent_kb_pilot.sha256"), "w").write(M["patent_kb_pilot_sha256"] + "\n")
    print(json.dumps(M, indent=1, default=str)[:3000])

if __name__ == "__main__":
    main()
