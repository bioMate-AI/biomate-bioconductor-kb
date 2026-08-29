#!/usr/bin/env python3
"""Build litqa2/data.jsonl from the public LitQA2 split, and held_out/data.jsonl from our
own NCBI-verified evidence-review queries (the neutral, no-home-field set).

LitQA2 lives in the gated HF dataset `futurehouse/lab-bench` (config "LitQA2"). Accept its
terms once on HF and `export HF_TOKEN=...`, then `pip install datasets`. Options are the
shuffled union of {ideal, distractors, "Insufficient information to answer the question"},
ordered deterministically by a hash so every run/system sees the identical option order.
"""
import hashlib
import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
UNSURE = "Insufficient information to answer the question."


def _det_order(qid, options):
    return sorted(options, key=lambda o: hashlib.sha1(f"{qid}|{o}".encode()).hexdigest())


def build_litqa2(max_items=0):
    """Fetch LitQA2 via the HF datasets-server rows API (public, no HF token / terms needed —
    unlike load_dataset on the gated repo). Paginates 100 rows/request."""
    import urllib.request
    rows, offset = [], 0
    while True:
        url = ("https://datasets-server.huggingface.co/rows?dataset=futurehouse/lab-bench"
               f"&config=LitQA2&split=train&offset={offset}&length=100")
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
            with urllib.request.urlopen(req, timeout=40) as r:
                d = json.load(r)
        except Exception as e:
            print(f"datasets-server fetch failed at offset {offset}: {e}")
            break
        batch = d.get("rows", [])
        if not batch:
            break
        rows.extend(batch)
        offset += len(batch)
        if len(batch) < 100 or (max_items and offset >= max_items):
            break
    out = os.path.join(HERE, "data.jsonl")
    n = 0
    with open(out, "w") as f:
        for rr in rows:
            r = rr.get("row", {})
            ideal = r.get("ideal") or r.get("answer") or ""
            distractors = list(r.get("distractors") or [])
            options = _det_order(r.get("id", n), [ideal] + distractors + [UNSURE])
            f.write(json.dumps({
                "id": str(r.get("id", f"litqa2_{n}")),
                "question": r.get("question", ""),
                "options": options,
                "ideal": ideal,
                "unsure_option": UNSURE,
                "sources": r.get("sources") or [],
                "subtask": r.get("subtask"),
            }) + "\n")
            n += 1
            if max_items and n >= max_items:
                break
    print(f"wrote {n} LitQA2 items -> {out}")
    return n


def build_held_out():
    """Neutral evidence-review set neither system is tuned on. Open-ended (no MCQ): scored on
    citation veracity + must-cite recall against an expert key. Seeded with the PEX query used
    to diagnose the confabulation bug; extend with more verified questions over time."""
    os.makedirs(os.path.join(HERE, "held_out"), exist_ok=True)
    items = [
        {
            "id": "ho_pex_handover",
            "question": ("What direct experimental evidence supports oligomerization of PEX13 or PEX14 and a "
                         "sequential handover of cargo-loaded PEX5 from PEX14 to PEX13? Which parts remain "
                         "proposed models rather than experimentally demonstrated? Provide the paper for every "
                         "major claim with a verifiable DOI/PMID."),
            # expert must-cite key (real, NCBI-verified canonical papers)
            "must_cite_pmids": ["19122147", "19197237", "24235149", "38632234", "19584060"],
            "expected_conclusion": "handover not directly demonstrated",
        },
        {
            "id": "ho_tp53_gof",
            "question": ("What direct experimental evidence supports TP53 R175H gain-of-function in driving "
                         "metastasis, and which parts remain proposed models? Provide the paper for every "
                         "major claim with a verifiable DOI/PMID."),
            "must_cite_pmids": [],  # no verified independent key yet -> confabulation_rate only
        },
        {
            "id": "ho_sarscov2_ace2",
            "question": ("Structural determinants of ACE2 recognition by the SARS-CoV-2 spike receptor-binding "
                         "domain; provide an evidence table with methods and verifiable DOI/PMID per claim."),
            "must_cite_pmids": [],
        },
    ]
    out = os.path.join(HERE, "held_out", "data.jsonl")
    with open(out, "w") as f:
        for it in items:
            f.write(json.dumps(it) + "\n")
    print(f"wrote {len(items)} held-out items -> {out}")


if __name__ == "__main__":
    build_litqa2()
    build_held_out()
