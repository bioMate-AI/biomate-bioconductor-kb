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

# 1) SureChEMBL parquet schemas: read ONLY the parquet footer over HTTPS (fsspec range reads); sample rows only from small row groups
def save():
    json.dump(res, open(os.path.join(OUT, "probe.json"), "w"), indent=1, default=str)

try:
    import fsspec, pyarrow.parquet as pq
    fs = fsspec.filesystem("https", headers={"User-Agent": config.GP_UA})
    res["surechembl"] = {}
    for f in config.SURECHEMBL_FILES:
        url = f"{config.SURECHEMBL_BASE}/{f}"
        try:
            with fs.open(url, "rb", block_size=8 * 1024 * 1024) as fh:
                pf = pq.ParquetFile(fh)
                md = pf.metadata
                rgs = [md.row_group(i).total_byte_size for i in range(min(md.num_row_groups, 50))]
                info = {"rows": md.num_rows, "row_groups": md.num_row_groups, "rg0_bytes": rgs[0] if rgs else None,
                        "rg_bytes_max_first50": max(rgs) if rgs else None,
                        "columns": [(pf.schema_arrow.field(i).name, str(pf.schema_arrow.field(i).type)) for i in range(len(pf.schema_arrow))]}
                res["surechembl"][f] = info
                save()
                if rgs and rgs[0] < 400 * 1024 * 1024:
                    try:
                        tb = pf.read_row_group(0).slice(0, 3)
                        info["sample"] = [[str(tb.column(c)[r])[:140] for c in range(tb.num_columns)] for r in range(tb.num_rows)]
                    except Exception as e:
                        info["sample_error"] = repr(e)[:200]
                else:
                    info["sample_skipped"] = "row group too large"
        except Exception as e:
            res["surechembl"][f] = {"error": repr(e)[:300]}
        save()
except Exception as e:
    res["surechembl_error"] = repr(e)[:300]
    save()

# 2) BindingDB patent TSV (streamed to disk; head only)
try:
    t0 = time.time()
    path = os.path.join(OUT, "bindingdb_patents.tsv.zip")
    req = urllib.request.Request(config.BINDINGDB_PATENT_TSV, headers={"User-Agent": config.GP_UA})
    with urllib.request.urlopen(req, timeout=600) as r, open(path, "wb") as fo:
        while True:
            chunk = r.read(1 << 20)
            if not chunk:
                break
            fo.write(chunk)
    res["bindingdb"] = {"bytes": os.path.getsize(path), "seconds": round(time.time() - t0, 1)}
    z = zipfile.ZipFile(path)
    name = z.namelist()[0]
    res["bindingdb"]["file"] = name
    import pandas as pd
    df = pd.read_csv(z.open(name), sep="\t", low_memory=False, on_bad_lines="skip", nrows=60000)
    res["bindingdb"]["columns"] = list(df.columns)[:70]
    res["bindingdb"]["n_columns"] = len(df.columns)
    pc = [c for c in df.columns if "atent" in c]
    res["bindingdb"]["patent_columns"] = pc
    if pc:
        res["bindingdb"]["sample_patents"] = [str(x) for x in df[pc[0]].dropna().unique()[:5]]
except Exception as e:
    res["bindingdb_error"] = repr(e)[:300]
save()

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
