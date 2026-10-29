"""K4 stage 1 (EC2 CPU): candidate selection from SureChEMBL (+ verified CPC) per amendment A1, then polite retrieval of the pilot
patents from Google Patents /patent/ pages. Resumable via files in OUT. usage: select_and_fetch.py OUT [--fetch-n N]"""
import argparse, gzip, hashlib, json, multiprocessing as mp, os, random, re, subprocess, sys, time, urllib.request, urllib.error
import numpy as np, pyarrow as pa, pyarrow.compute as pc, pyarrow.parquet as pq
import config, gp_parse
from pm_filter import classify_chunk

D = "/w/data"
os.makedirs(D, exist_ok=True)

def log(msg, out):
    print(msg, flush=True)
    open(os.path.join(out, "stage.log"), "a").write(f"{time.strftime('%FT%TZ', time.gmtime())} {msg}\n")

def download(out):
    procs = []
    for f in ("compounds.parquet", "patent_compound_map.parquet", "patents.parquet"):
        p = os.path.join(D, f)
        if not os.path.exists(p + ".ok"):
            procs.append((f, subprocess.Popen(["curl", "-s", "-L", "--retry", "5", "--retry-delay", "5", "-o", p, f"{config.SURECHEMBL_BASE}/{f}"])))
    for f, pr in procs:
        rc = pr.wait()
        if rc != 0:
            raise RuntimeError(f"download failed {f} rc={rc}")
        open(os.path.join(D, f + ".ok"), "w").write("ok")
        log(f"downloaded {f} {os.path.getsize(os.path.join(D, f)) / 1e9:.2f} GB", out)

def classify_compounds(out):
    cache = os.path.join(out, "mp_compound_ids.npy")
    if os.path.exists(cache):
        return np.load(cache)
    pf = pq.ParquetFile(os.path.join(D, "compounds.parquet"))
    rows, n_all = [], 0
    for i in range(pf.metadata.num_row_groups):
        tb = pf.read_row_group(i, columns=["id", "smiles", "mol_weight"])
        n_all += tb.num_rows
        mw = tb["mol_weight"].to_numpy(zero_copy_only=False)
        keep = np.where((mw >= config.MW_MIN) & (mw <= config.MW_MAX))[0]
        ids, smi = tb["id"].to_numpy(), tb["smiles"].to_pylist()
        rows.extend((int(ids[k]), smi[k]) for k in keep)
    log(f"compounds total={n_all} in MW window={len(rows)}", out)
    chunks = [rows[i:i + 5000] for i in range(0, len(rows), 5000)]
    ok = []
    with mp.Pool(max(1, mp.cpu_count() - 1)) as pool:
        for r in pool.imap_unordered(classify_chunk, chunks, chunksize=2):
            ok.extend(r)
    arr = np.array(sorted(ok), dtype=np.int64)
    np.save(cache, arr)
    log(f"peptide-macrocycle compounds={len(arr)}", out)
    return arr

def scan_map(mp_ids, out):
    cache = os.path.join(out, "mp_patent_counts.json")
    if os.path.exists(cache):
        return {int(k): v for k, v in json.load(open(cache)).items()}
    vs = pa.array(mp_ids)
    pf = pq.ParquetFile(os.path.join(D, "patent_compound_map.parquet"))
    per = {}   # patent_id -> {"desc": set, "clms": set, "any": set}
    for i in range(pf.metadata.num_row_groups):
        tb = pf.read_row_group(i, columns=["patent_id", "compound_id", "field_id"])
        m = pc.is_in(tb["compound_id"], value_set=vs)
        if not pc.any(m).as_py():
            continue
        sub = tb.filter(m)
        for p, c, f in zip(sub["patent_id"].to_pylist(), sub["compound_id"].to_pylist(), sub["field_id"].to_pylist()):
            d = per.setdefault(p, {"any": set(), "f": {}})
            d["any"].add(c)
            d["f"].setdefault(f, set()).add(c)
        if i % 500 == 0:
            log(f"map row group {i}/{pf.metadata.num_row_groups} patents_with_mp={len(per)}", out)
    res = {p: {"n_any": len(d["any"]), "by_field": {str(f): len(s) for f, s in d["f"].items()}} for p, d in per.items()}
    json.dump(res, open(cache, "w"))
    log(f"patents with >=1 peptide-macrocycle compound={len(res)}", out)
    return res

def scan_patents(counts, out):
    cache = os.path.join(out, "patent_meta.jsonl.gz")
    if os.path.exists(cache):
        return [json.loads(l) for l in gzip.open(cache, "rt")]
    pf = pq.ParquetFile(os.path.join(D, "patents.parquet"))
    verified = pa.array(config.CPC_VERIFIED)
    keep_ids = set(counts)
    rows = []
    for i in range(pf.metadata.num_row_groups):
        tb = pf.read_row_group(i, columns=["id", "patent_number", "country", "publication_date", "family_id", "cpc", "asignee", "title"])
        cpc = tb["cpc"]
        flat = pc.list_flatten(cpc)
        parent = pc.list_parent_indices(cpc)
        flat_norm = pc.replace_substring(flat, " ", "")
        hit_flat = pc.is_in(flat_norm, value_set=verified)
        has_cpc = np.zeros(tb.num_rows, dtype=bool)
        if len(flat):
            has_cpc[np.unique(parent.to_numpy()[hit_flat.to_numpy(zero_copy_only=False)])] = True
        ids = tb["id"].to_numpy()
        in_counts = np.array([int(x) in keep_ids for x in ids])
        sel = np.where((has_cpc | in_counts))[0]
        if len(sel) == 0:
            continue
        sub = tb.take(pa.array(sel)).to_pylist()
        for r, k in zip(sub, sel):
            if r["country"] not in ("US", "WO", "EP"):
                continue
            pd_ = r["publication_date"]
            if pd_ is None or pd_.year < config.YEAR_MIN:
                continue
            c = counts.get(int(r["id"]), {"n_any": 0, "by_field": {}})
            rows.append({"id": int(r["id"]), "patent_number": r["patent_number"], "country": r["country"], "pub_date": str(pd_),
                         "family_id": r["family_id"], "assignee": (r["asignee"] or [])[:3], "title": r["title"],
                         "cpc_verified": bool(has_cpc[k]), "n_mp": c["n_any"], "by_field": c["by_field"]})
        if i % 200 == 0:
            log(f"patents row group {i}/{pf.metadata.num_row_groups} candidates={len(rows)}", out)
    with gzip.open(cache, "wt") as fh:
        for r in rows:
            fh.write(json.dumps(r) + "\n")
    log(f"candidate patents (US/WO/EP, >= {config.YEAR_MIN}, CPC-verified or >=1 mp compound)={len(rows)}", out)
    return rows

def google_number(pn):
    return re.sub(r"[^A-Z0-9]", "", pn.upper())

def dedupe_family(rows):
    best = {}
    for r in sorted(rows, key=lambda r: (r["pub_date"], r["patent_number"])):
        fam = r["family_id"] if r["family_id"] not in (None, 0) else f"solo{r['id']}"
        best.setdefault(fam, r)
    return list(best.values())

def select(rows, out):
    rng = random.Random(20261031)
    rows = dedupe_family(rows)
    stats = {"after_family_dedupe": len(rows)}
    D_pool = sorted([r for r in rows if r["n_mp"] >= 5], key=lambda r: (-r["n_mp"], r["patent_number"]))
    stats["D_pool"] = len(D_pool)
    D_top = D_pool[:60]
    nxt = D_pool[60:2060]
    D_rand = rng.sample(nxt, min(40, len(nxt)))
    D_spare = rng.sample([r for r in nxt if r not in D_rand], min(20, max(0, len(nxt) - len(D_rand))))
    taken = {r["id"] for r in D_top + D_rand + D_spare}
    C_pool = [r for r in rows if r["cpc_verified"] and r["n_mp"] >= 1 and r["id"] not in taken]
    stats["C_pool"] = len(C_pool)
    C_sel = rng.sample(C_pool, min(120, len(C_pool)))
    sel = [dict(r, stratum="D_top") for r in D_top] + [dict(r, stratum="D_rand") for r in D_rand] + [dict(r, stratum="C") for r in C_sel[:100]]
    spare = [dict(r, stratum="D_spare") for r in D_spare] + [dict(r, stratum="C_spare") for r in C_sel[100:]]
    stats["D_share_with_verified_cpc"] = round(sum(r["cpc_verified"] for r in D_top + D_rand) / max(1, len(D_top + D_rand)), 3)
    stats["selected"] = len(sel); stats["spare"] = len(spare)
    json.dump({"selected": sel, "spare": spare, "stats": stats}, open(os.path.join(out, "selection.json"), "w"), indent=1)
    log(f"selection {json.dumps(stats)}", out)
    return sel, spare

def fetch_one(pn):
    url = config.GP_URL.format(pn=google_number(pn))
    last = None
    for attempt in range(3):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": config.GP_UA, "Accept-Language": "en"})
            with urllib.request.urlopen(req, timeout=60) as r:
                return r.status, r.read().decode("utf-8", "replace")
        except urllib.error.HTTPError as e:
            last = e.code
            if e.code in (429, 403):
                return e.code, ""
            if e.code == 404:
                return 404, ""
            time.sleep(5 * (attempt + 1))
        except Exception:
            last = -1
            time.sleep(5 * (attempt + 1))
    return last, ""

def fetch_all(sel, spare, out, n):
    path = os.path.join(out, "corpus.jsonl.gz")
    have = set()
    if os.path.exists(path):
        for l in gzip.open(path, "rt"):
            have.add(json.loads(l)["patent_number"])
    fails, blocked = [], 0
    queue = [r for r in sel if r["patent_number"] not in have]
    spares = list(spare)
    with gzip.open(path, "at") as fh:
        while queue and len(have) < n:
            r = queue.pop(0)
            time.sleep(config.GP_DELAY_S)
            code, html = fetch_one(r["patent_number"])
            if code in (429, 403):
                blocked += 1
                log(f"HTTP {code} on {r['patent_number']} ({blocked} consecutive-ish)", out)
                if blocked >= 3:
                    log("STOP: repeated 403/429 from Google Patents; respecting the block", out)
                    break
                time.sleep(60); queue.insert(0, r); continue
            blocked = 0
            if code != 200 or not html:
                fails.append({"patent_number": r["patent_number"], "code": code, "stratum": r["stratum"]})
                if spares:
                    queue.append(spares.pop(0))
                continue
            d = gp_parse.parse(html)
            if not d["description"] or len(d["description"]) < 5000:
                fails.append({"patent_number": r["patent_number"], "code": "no_description", "stratum": r["stratum"]})
                if spares:
                    queue.append(spares.pop(0))
                continue
            text = "\n\n".join(x for x in (d["title"], d["abstract"], d["claims"] and "CLAIMS: " + d["claims"], d["description"]) if x)
            rec = {"patent_number": r["patent_number"], "google_number": google_number(r["patent_number"]), "stratum": r["stratum"],
                   "sc_id": r["id"], "n_mp_surechembl": r["n_mp"], "cpc_verified_surechembl": r["cpc_verified"],
                   "meta": {k: d[k] for k in ("title", "pub_date", "filing_date", "assignee", "inventors", "cpc", "kind")},
                   "claims": d["claims"], "description": d["description"], "text": text,
                   "text_sha256": hashlib.sha256(text.encode()).hexdigest(), "html_bytes": len(html),
                   "retrieved": time.strftime("%FT%TZ", time.gmtime()), "url": config.GP_URL.format(pn=google_number(r["patent_number"]))}
            fh.write(json.dumps(rec) + "\n"); fh.flush()
            have.add(r["patent_number"])
            if len(have) % 10 == 0:
                log(f"fetched {len(have)}", out)
    json.dump({"n_fetched": len(have), "fails": fails}, open(os.path.join(out, "fetch_summary.json"), "w"))
    log(f"fetch done: {len(have)} fetched, {len(fails)} failed", out)

def main():
    ap = argparse.ArgumentParser(); ap.add_argument("out"); ap.add_argument("--fetch-n", type=int, default=200)
    a = ap.parse_args(); os.makedirs(a.out, exist_ok=True)
    download(a.out)
    mp_ids = classify_compounds(a.out)
    counts = scan_map(mp_ids, a.out)
    rows = scan_patents(counts, a.out)
    sel, spare = select(rows, a.out)
    fetch_all(sel, spare, a.out, a.fetch_n)

if __name__ == "__main__":
    main()
