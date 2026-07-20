#!/usr/bin/env python3
"""Layer 3a — identify the SOURCE PUBLICATIONS for the Census donors, so the
clinical-activity labels (SLEDAI / anti-dsDNA / complement) can be extracted from
them. Queries the CELLxGENE Discover curation API for datasets matching our
diseases and resolves each to its collection DOI + publisher metadata.

Runs anywhere (stdlib + requests). Output feeds the LLM extraction step.
"""
import csv, json, os, sys, time
import requests

HERE = os.path.dirname(os.path.abspath(__file__))
API = "https://api.cellxgene.cziscience.com/curation/v1"
DISEASE_LABELS = {
    "systemic lupus erythematosus": "SLE",
    "rheumatoid arthritis": "RA",
    "Crohn disease": "IBD", "ulcerative colitis": "IBD",
    "inflammatory bowel disease": "IBD",
    "multiple sclerosis": "MS",
}


def get(url, retries=3):
    for i in range(retries):
        try:
            r = requests.get(url, timeout=30)
            if r.status_code == 200:
                return r.json()
        except requests.RequestException as e:
            sys.stderr.write(f"  retry {i+1}: {e}\n")
        time.sleep(1.5)
    return None


def main():
    out = os.path.join(HERE, "results")
    os.makedirs(out, exist_ok=True)
    sys.stderr.write("fetching CELLxGENE dataset index…\n")
    datasets = get(f"{API}/datasets") or []
    sys.stderr.write(f"  {len(datasets)} public datasets\n")

    rows, collections = [], {}
    for d in datasets:
        dis = [x.get("label") for x in (d.get("disease") or [])]
        hit = [DISEASE_LABELS[x] for x in dis if x in DISEASE_LABELS]
        if not hit:
            continue
        cid = d.get("collection_id")
        rows.append({
            "group": ";".join(sorted(set(hit))),
            "disease_labels": ";".join([x for x in dis if x in DISEASE_LABELS]),
            "dataset_id": d.get("dataset_id"),
            "title": (d.get("title") or "").replace("\n", " ")[:160],
            "cell_count": d.get("cell_count"),
            "collection_id": cid,
        })
        collections.setdefault(cid, None)

    sys.stderr.write(f"  {len(rows)} datasets across {len(collections)} collections match our diseases\n")
    # resolve collection DOI + publication metadata
    for cid in list(collections):
        c = get(f"{API}/collections/{cid}")
        if not c:
            continue
        pm = c.get("publisher_metadata") or {}
        collections[cid] = {
            "doi": c.get("doi") or "",
            "journal": pm.get("journal", ""),
            "year": pm.get("published_year", ""),
            "pub_title": (pm.get("title") or c.get("name") or "")[:200],
        }
        time.sleep(0.2)

    for r in rows:
        meta = collections.get(r["collection_id"]) or {}
        r.update({k: meta.get(k, "") for k in ("doi", "journal", "year", "pub_title")})

    csv_path = os.path.join(out, "census_source_datasets.csv")
    with open(csv_path, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
        w.writeheader(); w.writerows(rows)
    json.dump(rows, open(os.path.join(out, "census_source_datasets.json"), "w"), indent=2)

    by = {}
    for r in rows:
        by[r["group"]] = by.get(r["group"], 0) + 1
    print(json.dumps({"datasets_matched": len(rows),
                      "collections": len(collections),
                      "by_group": by,
                      "with_doi": sum(1 for r in rows if r["doi"])}, indent=2))
    print(f"wrote {csv_path}")


if __name__ == "__main__":
    main()
