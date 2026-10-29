"""K4 route probe (runs on EC2): schemas of the SureChEMBL parquet files (HTTP range reads, no full download), BindingDB patent TSV
header/counts, Google Patents fetch + parse test on 3 patents. Writes /w/out/probe.json. No LLM, no heavy compute."""
import json, os, re, sys, time, io, zipfile, urllib.request
import config, gp_parse
OUT = sys.argv[1] if len(sys.argv) > 1 else "/w/out"
os.makedirs(OUT, exist_ok=True)
res = {"started": time.strftime("%FT%TZ", time.gmtime())}

def http(url, binary=False, headers=None, timeout=60):
    req = urllib.request.Request(url, headers={"User-Agent": config.GP_UA, **(headers or {})})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        b = r.read()
        return b if binary else b.decode("utf-8", "replace")

# 1) SureChEMBL parquet schemas via duckdb over HTTPS
try:
    import duckdb
    con = duckdb.connect()
    con.execute("INSTALL httpfs; LOAD httpfs;")
    res["surechembl"] = {}
    for f in config.SURECHEMBL_FILES:
        url = f"{config.SURECHEMBL_BASE}/{f}"
        try:
            d = con.execute(f"DESCRIBE SELECT * FROM read_parquet('{url}')").fetchall()
            n = con.execute(f"SELECT count(*) FROM read_parquet('{url}')").fetchone()[0]
            s = con.execute(f"SELECT * FROM read_parquet('{url}') LIMIT 3").fetchall()
            res["surechembl"][f] = {"columns": [(x[0], x[1]) for x in d], "rows": n, "sample": [[str(c)[:120] for c in r] for r in s]}
        except Exception as e:
            res["surechembl"][f] = {"error": repr(e)[:300]}
except Exception as e:
    res["surechembl_error"] = repr(e)[:300]

# 2) BindingDB patent TSV
try:
    t0 = time.time()
    b = http(config.BINDINGDB_PATENT_TSV, binary=True, timeout=600)
    res["bindingdb"] = {"bytes": len(b), "seconds": round(time.time() - t0, 1), "head": b[:4].hex()}
    z = zipfile.ZipFile(io.BytesIO(b))
    name = z.namelist()[0]
    res["bindingdb"]["file"] = name
    import pandas as pd
    df = pd.read_csv(z.open(name), sep="\t", low_memory=False, on_bad_lines="skip", nrows=200000)
    res["bindingdb"]["columns"] = list(df.columns)[:60]
    res["bindingdb"]["n_columns"] = len(df.columns)
    pc = [c for c in df.columns if "atent" in c]
    res["bindingdb"]["patent_columns"] = pc
    if pc:
        res["bindingdb"]["sample_patents"] = [str(x) for x in df[pc[0]].dropna().unique()[:5]]
    open(os.path.join(OUT, "bindingdb_patents.tsv.zip"), "wb").write(b)
except Exception as e:
    res["bindingdb_error"] = repr(e)[:300]

# 3) Google Patents fetch + parse test (polite delay)
tests = ["US10590171B2"]
try:
    pats = res.get("bindingdb", {}).get("sample_patents", [])[:2]
    for p in pats:
        m = re.sub(r"[^A-Z0-9]", "", str(p).upper())
        if m and not m.startswith("US"):
            m = "US" + m
        tests.append(m)
except Exception:
    pass
res["google_patents"] = []
for pn in tests:
    time.sleep(config.GP_DELAY_S)
    try:
        html = http(config.GP_URL.format(pn=pn), timeout=60)
        d = gp_parse.parse(html)
        res["google_patents"].append({"pn": pn, "html_bytes": len(html), "coverage": gp_parse.coverage(d), "title": (d["title"] or "")[:100],
                                      "cpc_n": len(d["cpc"]), "claims_chars": len(d["claims"] or ""), "desc_chars": len(d["description"] or ""),
                                      "pub_date": d["pub_date"], "assignee": d["assignee"]})
        open(os.path.join(OUT, f"gp_{pn}.html"), "w").write(html[:400000])
    except Exception as e:
        res["google_patents"].append({"pn": pn, "error": repr(e)[:200]})
res["finished"] = time.strftime("%FT%TZ", time.gmtime())
json.dump(res, open(os.path.join(OUT, "probe.json"), "w"), indent=1, default=str)
print(json.dumps({k: (v if k != "surechembl" else {f: x.get("rows", x.get("error")) for f, x in v.items()}) for k, v in res.items() if k != "google_patents"}, default=str)[:1500])
print(json.dumps(res["google_patents"], default=str)[:1500])
