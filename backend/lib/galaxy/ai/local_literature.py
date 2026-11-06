"""Offline lexical literature retrieval. Build from provenance-bearing JSONL on stdin."""
import argparse
from contextlib import closing
import hashlib
import json
from pathlib import Path
import re
import sqlite3
import sys


def build(stream, path):
    path = Path(path)
    # Never replace an existing reviewed index implicitly.
    with path.open("xb"):
        pass
    counts = {"documents": 0, "chunks": 0, "missing_identity": 0, "duplicate_articles": 0}
    digest = hashlib.sha256()
    with closing(sqlite3.connect(path)) as db:
        db.executescript("""
            CREATE TABLE documents(id INTEGER PRIMARY KEY, pmcid TEXT UNIQUE NOT NULL,
                                   pmid TEXT, title TEXT, year INTEGER, licence TEXT, url TEXT);
            CREATE VIRTUAL TABLE chunks USING fts5(document_id UNINDEXED, text);
        """)
        for raw in stream:
            digest.update(raw.encode())
            if not raw.strip():
                continue
            row = json.loads(raw)
            pmcid, text = row.get("pmcid", ""), row.get("text", "")
            if not re.fullmatch(r"PMC\d+", pmcid or "") or not isinstance(text, str) or not text.strip():
                counts["missing_identity"] += 1
                continue
            inserted = db.execute("INSERT OR IGNORE INTO documents(pmcid,pmid,title,year,licence,url) VALUES(?,?,?,?,?,?)",
                                  (pmcid, row.get("pmid"), row.get("title"), row.get("year"), row.get("licence"),
                                   f"https://pmc.ncbi.nlm.nih.gov/articles/{pmcid}/"))
            if not inserted.rowcount:
                counts["duplicate_articles"] += 1
                continue
            counts["documents"] += 1
            for start in range(0, len(text), 1800):
                db.execute("INSERT INTO chunks(document_id,text) VALUES(?,?)", (inserted.lastrowid, text[start:start + 2000]))
                counts["chunks"] += 1
            if counts["documents"] % 1000 == 0:
                db.commit()
        db.commit()
        db.execute("INSERT INTO chunks(chunks) VALUES('optimize')")
        db.commit()
        if db.execute("PRAGMA integrity_check").fetchone()[0] != "ok":
            raise ValueError("literature index integrity check failed")
    if not counts["documents"]:
        raise ValueError("no identified literature documents; index is not ready")
    report = {**counts, "input_sha256": digest.hexdigest(), "retrieval": "sqlite_fts5_bm25",
              "citation_policy": "Only explicit PMC article IDs; no inferred paper identity.",
              "quality_status": "retrieval baseline; not a relevance or license audit"}
    path.with_suffix(path.suffix + ".manifest.json").write_text(json.dumps(report, indent=2) + "\n")
    return report


def search(path, query, limit=5):
    if not 1 <= limit <= 20 or len(query) > 1000:
        raise ValueError("query/limit exceeds retrieval bounds")
    terms = list(dict.fromkeys(re.findall(r"\w+", query.lower())))[:32]
    if not terms:
        return []
    expression = " OR ".join('"' + term + '"' for term in terms)
    with closing(sqlite3.connect(Path(path).resolve().as_uri() + "?mode=ro", uri=True)) as db:
        db.row_factory = sqlite3.Row
        rows = db.execute("""
            SELECT d.*, chunks.text AS excerpt, bm25(chunks) AS rank
            FROM chunks JOIN documents d ON d.id = chunks.document_id
            WHERE chunks MATCH ? ORDER BY rank LIMIT ?
        """, (expression, limit * 20)).fetchall()
    results, seen = [], set()
    for row in rows:
        if row["pmcid"] not in seen:
            seen.add(row["pmcid"])
            results.append(dict(row))
            if len(results) == limit:
                break
    return results


def resolve(path, url, payload=None):
    from urllib.parse import urlsplit, parse_qs
    parsed = urlsplit(url)
    if payload is not None or parsed.hostname != "www.ebi.ac.uk" or parsed.path != "/europepmc/webservices/rest/search":
        return None
    query = parse_qs(parsed.query).get("query", [""])[0]
    rows = search(path, query)
    return {"resultList": {"result": [
        {"pmid": row["pmid"], "title": row["title"] or row["pmcid"], "pubYear": row["year"],
         "abstractText": row["excerpt"], "fullTextUrlList": {"fullTextUrl": [{"url": row["url"]}]},
         "evidence_kind": "local_fulltext_excerpt", "pmcid": row["pmcid"], "licence": row["licence"]}
        for row in rows]}}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build", required=True)
    args = parser.parse_args()
    print(json.dumps(build(sys.stdin, args.build)))
