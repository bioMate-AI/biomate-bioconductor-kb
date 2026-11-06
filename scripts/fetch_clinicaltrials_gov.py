#!/usr/bin/env python3
"""Download the ENTIRE ClinicalTrials.gov registry through the official public API v2 (JSON), resumably.

  python3 scripts/fetch_clinicaltrials_gov.py OUT_DIR [--s3 s3://bucket/prefix/] [--max-pages N]

Writes OUT_DIR/studies_part_00001.jsonl.gz ... (1000 studies per part, one JSON study per line, full record) and a
manifest.json (source URL, API version, dataTimestamp, totalCount, per-part counts, final study count, start/end time).
Resumable: nextPageToken is stored in OUT_DIR/state.json after every page. Stdlib only. Run on EC2/Spark, not a laptop.
"""
import argparse, gzip, json, os, subprocess, sys, time, urllib.error, urllib.request

API = "https://clinicaltrials.gov/api/v2"


def get(url, tries=6):
    for i in range(tries):
        try:
            with urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": "BioMate-ctgov-mirror/1.0"}), timeout=90) as r:
                return json.loads(r.read().decode())
        except (urllib.error.URLError, TimeoutError, ValueError) as e:
            if i == tries - 1:
                raise
            time.sleep(min(60, 2 ** (i + 1)))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("out")
    ap.add_argument("--s3")
    ap.add_argument("--max-pages", type=int, default=0)
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    sp, mp = os.path.join(a.out, "state.json"), os.path.join(a.out, "manifest.json")
    st = json.load(open(sp)) if os.path.exists(sp) else {"token": None, "part": 0, "n": 0, "parts": {}, "started": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())}
    ver = get(API + "/version")
    total = get(API + "/studies?pageSize=1&countTotal=true&fields=NCTId").get("totalCount")
    print("api", ver, "total", total, "resume part", st["part"], flush=True)
    pages = 0
    while True:
        url = API + "/studies?pageSize=1000&format=json" + ("&pageToken=" + st["token"] if st["token"] else "")
        d = get(url)
        studies = d.get("studies") or []
        if studies:
            st["part"] += 1
            name = "studies_part_%05d.jsonl.gz" % st["part"]
            with gzip.open(os.path.join(a.out, name), "wt") as f:
                for s in studies:
                    f.write(json.dumps(s, separators=(",", ":")) + "\n")
            st["parts"][name] = len(studies)
            st["n"] += len(studies)
        st["token"] = d.get("nextPageToken")
        json.dump(st, open(sp, "w"))
        pages += 1
        if st["part"] % 25 == 0:
            print("part", st["part"], "studies", st["n"], flush=True)
        if not st["token"] or (a.max_pages and pages >= a.max_pages):
            break
        time.sleep(0.2)
    done = not st["token"]
    man = {"source": API + "/studies", "api_version": ver.get("apiVersion"), "data_timestamp": ver.get("dataTimestamp"),
           "total_count_reported": total, "studies_downloaded": st["n"], "complete": done, "parts": st["parts"],
           "started": st["started"], "finished": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())}
    json.dump(man, open(mp, "w"), indent=1)
    print("done" if done else "stopped early", st["n"], "of", total, flush=True)
    if a.s3:
        subprocess.check_call(["aws", "s3", "sync", a.out, a.s3, "--exclude", "state.json", "--only-show-errors"])
        print("uploaded to", a.s3, flush=True)
    return 0 if done and (total is None or abs(st["n"] - total) <= 50) else 2


if __name__ == "__main__":
    sys.exit(main())
