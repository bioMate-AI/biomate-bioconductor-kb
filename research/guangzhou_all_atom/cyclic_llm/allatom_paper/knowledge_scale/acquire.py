"""K2 stage A: Europe PMC open-access acquisition -> deterministic plain text per paper (the text used for quote verification)."""
import argparse, gzip, hashlib, json, random, sys, time, urllib.parse, urllib.request
import xml.etree.ElementTree as ET
from config import QUERIES, TIER_BY_PUBTYPE, QUERY_TOPICS

BASE = "https://www.ebi.ac.uk/europepmc/webservices/rest"
SKIP_TAGS = {"ref-list", "back", "ack", "fn-group", "glossary", "app-group", "notes"}


def _get(url, retries=4, pause=0.35, timeout=60):
    last = None
    for i in range(retries):
        try:
            time.sleep(pause)
            with urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": "biomate-k2/1.0 (research)"}), timeout=timeout) as r:
                return r.read()
        except Exception as e:  # noqa: BLE001
            last = e
            time.sleep(1.5 * (i + 1))
    raise RuntimeError(f"GET failed {url[:120]}: {last}")


def tier_from_pubtype(pub_type: str) -> str:
    p = (pub_type or "").lower()
    if "review" in p:
        return "T2"
    if "research-article" in p or "journal article" in p:
        return "T1"
    return TIER_BY_PUBTYPE.get(p, "T3")


def search(query: str, cap: int):
    out, cursor = [], "*"
    while len(out) < cap:
        url = f"{BASE}/search?query={urllib.parse.quote(query)}&format=json&pageSize=100&resultType=lite&cursorMark={urllib.parse.quote(cursor)}"
        d = json.loads(_get(url))
        res = d.get("resultList", {}).get("result", [])
        if not res:
            break
        out.extend(res)
        nxt = d.get("nextCursorMark")
        if not nxt or nxt == cursor:
            break
        cursor = nxt
    return out[:cap]


def _local(tag):
    return tag.split("}")[-1] if "}" in tag else tag


def _txt(el):
    return " ".join("".join(el.itertext()).split())


def _table(tw):
    parts = []
    for ch in tw:
        t = _local(ch.tag)
        if t in ("label", "caption"):
            parts.append(_txt(ch))
        elif t == "table":
            for tr in ch.iter():
                if _local(tr.tag) == "tr":
                    cells = [_txt(c) for c in tr if _local(c.tag) in ("td", "th")]
                    if any(cells):
                        parts.append(" | ".join(cells))
    return "\n".join(p for p in parts if p)


def _walk(el, out):
    t = _local(el.tag)
    if t in SKIP_TAGS:
        return
    if t == "title":
        s = _txt(el)
        if s:
            out.append(s)
        return
    if t == "p":
        s = _txt(el)
        if s:
            out.append(s)
        return
    if t == "table-wrap":
        s = _table(el)
        if s:
            out.append(s)
        return
    if t == "fig":
        for ch in el:
            if _local(ch.tag) in ("label", "caption"):
                s = _txt(ch)
                if s:
                    out.append(s)
        return
    for ch in el:
        _walk(ch, out)


def xml_to_text(xml_bytes: bytes) -> dict:
    root = ET.fromstring(xml_bytes)
    art = root if _local(root.tag) == "article" else next((e for e in root.iter() if _local(e.tag) == "article"), root)
    title, parts = "", []
    for e in art.iter():
        if _local(e.tag) == "article-title":
            title = _txt(e)
            break
    front = next((e for e in art if _local(e.tag) == "front"), None)
    body = next((e for e in art if _local(e.tag) == "body"), None)
    if title:
        parts.append(title)
    if front is not None:
        for e in front.iter():
            if _local(e.tag) == "abstract":
                _walk(e, parts)
    if body is not None:
        _walk(body, parts)
    text = "\n\n".join(parts)
    return {"title": title, "text": text}


def build_corpus(out_path, per_query, total, seed):
    rng = random.Random(seed)
    pool, seen = {}, set()
    topics_by_pm, queries_by_pm = {}, {}
    for qid, q in QUERIES:
        try:
            res = search(q, per_query * 3)
        except Exception as e:  # noqa: BLE001
            print("search failed", qid, e, file=sys.stderr)
            continue
        rng.shuffle(res)
        n = 0
        for r in res:
            pm = r.get("pmcid")
            if pm:
                topics_by_pm.setdefault(pm, set()).update(QUERY_TOPICS.get(qid, ["sar_rule"]))
                queries_by_pm.setdefault(pm, set()).add(qid)
            if not pm or pm in seen:
                continue
            seen.add(pm)
            r["_qid"] = qid
            pool.setdefault(qid, []).append(r)
            n += 1
            if n >= per_query:
                break
    chosen, i = [], 0
    qids = list(pool)
    while len(chosen) < total and any(pool.values()):
        qid = qids[i % len(qids)]
        i += 1
        if pool[qid]:
            chosen.append(pool[qid].pop(0))
    n_ok = 0
    with gzip.open(out_path, "wt", encoding="utf-8") as fh:
        for r in chosen:
            pm = r["pmcid"]
            try:
                d = xml_to_text(_get(f"{BASE}/{pm}/fullTextXML"))
            except Exception as e:  # noqa: BLE001
                print("fulltext failed", pm, e, file=sys.stderr)
                continue
            text = d["text"]
            if len(text.split()) < 800:
                continue
            rec = {"pmcid": pm, "doi": r.get("doi"), "title": r.get("title") or d["title"], "authors": r.get("authorString"),
                   "year": r.get("pubYear"), "pub_type": r.get("pubType"), "tier": tier_from_pubtype(r.get("pubType")),
                   "journal": r.get("journalTitle"), "query_id": r["_qid"], "query_ids": sorted(queries_by_pm.get(pm, [])),
                   "topics": sorted(topics_by_pm.get(pm, ["sar_rule"])), "text": text,
                   "text_sha256": hashlib.sha256(text.encode("utf-8")).hexdigest(), "n_words": len(text.split())}
            fh.write(json.dumps(rec) + "\n")
            n_ok += 1
    print(f"corpus: {n_ok} papers written of {len(chosen)} selected", flush=True)


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--per-query", type=int, default=8)
    ap.add_argument("--total", type=int, default=300)
    ap.add_argument("--seed", type=int, default=20261031)
    a = ap.parse_args()
    build_corpus(a.out, a.per_query, a.total, a.seed)
