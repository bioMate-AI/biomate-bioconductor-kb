"""Crawl bioinformatics FORUMS (public, no auth) -> Q&A corpus for domain mid-training.
Sources: StackExchange data dumps (Bioinformatics/Biology/Stats.SE — official 7z), Bioconductor support
(open Biostar API), Galaxy Help (Discourse JSON), Reddit r/bioinformatics (public JSON, real UA).
Emits {"text": "Q: ...\nA: ...", "source": "forum_<site>"}. stdlib + optional py7zr for SE dumps.
Usage: python build_forum_corpus.py --out forum_corpus.jsonl --sources se,bioc,galaxy,reddit
"""
import argparse, io, json, os, re, time, urllib.request, xml.etree.ElementTree as ET

UA = {"User-Agent": "Mozilla/5.0 (research corpus builder; contact biomate)"}


def get(url, timeout=60, raw=False):
    for a in range(4):
        try:
            r = urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=timeout)
            return r.read() if raw else r.read().decode("utf-8", "ignore")
        except Exception:
            time.sleep(2 * (a + 1))
    return b"" if raw else ""


def html_strip(s): return re.sub(r"\s+", " ", re.sub(r"<[^>]+>", " ", s or "")).strip()


def se_dump(site, fo):
    # StackExchange official dump: Posts.xml (PostTypeId 1=question w/ Title+Body, 2=answer w/ ParentId)
    import py7zr
    url = f"https://archive.org/download/stackexchange/{site}.7z"
    data = get(url, timeout=300, raw=True)
    if not data: print(f"  {site}: download failed", flush=True); return 0
    n = 0
    with py7zr.SevenZipFile(io.BytesIO(data)) as z:
        posts = z.read(["Posts.xml"]).get("Posts.xml")
        if not posts: return 0
        q = {}; ans = {}
        for _, el in ET.iterparse(posts, events=("end",)):
            if el.tag != "row": continue
            pt = el.get("PostTypeId")
            if pt == "1": q[el.get("Id")] = (el.get("Title", ""), html_strip(el.get("Body")))
            elif pt == "2":
                p = el.get("ParentId"); sc = int(el.get("Score", "0") or 0)
                if p and (p not in ans or sc > ans[p][0]): ans[p] = (sc, html_strip(el.get("Body")))
            el.clear()
        for qid, (title, body) in q.items():
            if qid in ans and len(ans[qid][1]) > 40:
                fo.write(json.dumps({"text": f"Q: {title}\n{body[:1500]}\n\nA: {ans[qid][1][:2000]}",
                                     "source": f"forum_{site.split('.')[0]}"}) + "\n"); n += 1
    print(f"  {site}: {n} QA", flush=True); return n


def bioc(fo, maxid=45000):
    n = 0
    for pid in range(1, maxid):
        if pid % 2000 == 0: print(f"  bioc {pid}/{maxid} -> {n}", flush=True)
        try: d = json.loads(get(f"https://support.bioconductor.org/api/post/{pid}/", timeout=20) or "{}")
        except Exception: continue
        t = html_strip(d.get("content") or d.get("text"))
        if d.get("title") and len(t) > 60:
            fo.write(json.dumps({"text": f"Q: {d['title']}\n{t[:2500]}", "source": "forum_bioconductor"}) + "\n"); n += 1
    print(f"  bioconductor: {n}", flush=True); return n


def galaxy(fo, pages=200):
    n = 0
    for pg in range(pages):
        d = json.loads(get(f"https://help.galaxyproject.org/latest.json?page={pg}", timeout=30) or "{}")
        tops = (d.get("topic_list") or {}).get("topics") or []
        if not tops: break
        for tp in tops:
            td = json.loads(get(f"https://help.galaxyproject.org/t/{tp['id']}.json", timeout=20) or "{}")
            posts = [html_strip(p.get("cooked")) for p in (td.get("post_stream") or {}).get("posts", [])]
            posts = [p for p in posts if len(p) > 30]
            if len(posts) >= 2:
                fo.write(json.dumps({"text": f"Q: {tp.get('title','')}\n{posts[0][:1500]}\n\nA: {posts[1][:2000]}",
                                     "source": "forum_galaxy"}) + "\n"); n += 1
        print(f"  galaxy pg{pg} -> {n}", flush=True)
    return n


def reddit(fo, subs=("bioinformatics",)):
    n = 0
    for sub in subs:
        after = ""
        for _ in range(40):
            d = json.loads(get(f"https://www.reddit.com/r/{sub}/top.json?limit=100&t=all&after={after}", timeout=30) or "{}")
            ch = (d.get("data") or {}).get("children") or []
            if not ch: break
            for c in ch:
                p = c["data"]; body = html_strip(p.get("selftext"))
                if p.get("title") and len(body) > 80:
                    fo.write(json.dumps({"text": f"Q: {p['title']}\n{body[:2000]}", "source": f"forum_reddit_{sub}"}) + "\n"); n += 1
            after = (d.get("data") or {}).get("after") or ""
            if not after: break
            time.sleep(1)
    print(f"  reddit: {n}", flush=True); return n


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True); ap.add_argument("--sources", default="se,bioc,galaxy,reddit")
    a = ap.parse_args()
    src = set(a.sources.split(","))
    tot = 0
    with open(a.out, "w") as fo:
        if "se" in src:
            for site in ("bioinformatics.stackexchange.com", "biology.stackexchange.com"):
                try: tot += se_dump(site, fo)
                except Exception as e: print(f"  {site} ERR {e}", flush=True)
        if "galaxy" in src: tot += galaxy(fo)
        if "reddit" in src: tot += reddit(fo)
        if "bioc" in src: tot += bioc(fo)
    print(f"FORUM CORPUS DONE: {tot} QA -> {a.out}", flush=True)


if __name__ == "__main__":
    raise SystemExit(main())
