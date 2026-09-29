"""Build the mid-train DOMAIN mixture = literature (PubMed) + structured (midtrain_all), with the
tiny structured corpus upweighted by repetition so it isn't drowned by the ~6B-token literature.
General-replay (FineWeb-Edu) is mixed at TRAIN time via midtrain_run --replay/--replay-frac, so it's
not included here. Reports exact token composition. Usage:
  python build_midtrain_mix.py --lit literature_corpus.jsonl --struct midtrain_all.jsonl \
     --struct-repeat 8 --lit-cap-tokens 0 --out midtrain_domain.jsonl
"""
import argparse, hashlib, json, os, random, re
random.seed(17)


def toks(s): return max(1, len(s) // 4)


# --- quality + dedup (the preprocessing the first mid-train lacked) ---
_WS = re.compile(r"\s+")


def norm_key(t):
    """normalized near-dup key: lowercase, collapse whitespace, hash first 400 chars.
    Catches exact dups + boilerplate-prefixed near-dups (PubMed reprints, mirrored abstracts)."""
    s = _WS.sub(" ", t.lower()).strip()[:400]
    return hashlib.blake2b(s.encode("utf-8", "ignore"), digest_size=12).digest()


def quality_ok(t, min_chars):
    if len(t) < min_chars:
        return False
    alpha = sum(c.isalpha() or c.isspace() for c in t[:2000])
    return alpha / max(1, len(t[:2000])) >= 0.55  # drop tables/garbled/mostly-symbol docs


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--lit", required=True); ap.add_argument("--struct", required=True)
    ap.add_argument("--kg", default="", help="verbalized KG corpus (PrimeKG+MAP-KG); optional")
    ap.add_argument("--kg-repeat", type=int, default=1, help="repeat KG N times to upweight it")
    ap.add_argument("--extra", action="append", default=[], help="path:source:repeat extra corpus "
                    "(pmc full-text, tool-docs, db-catalog); repeatable")
    ap.add_argument("--out", required=True)
    ap.add_argument("--struct-repeat", type=int, default=8, help="repeat structured N times to upweight it")
    ap.add_argument("--lit-keep-every", type=int, default=1, help="keep 1 of every N abstracts (uniform "
                    "sample across ALL years/topics; e.g. 5 -> ~2.1B of 10.7B tokens). 1 = use ALL")
    ap.add_argument("--dedup", action="store_true", help="near-dup + quality filter on lit/extra (not struct/kg)")
    ap.add_argument("--min-chars", type=int, default=200)
    a = ap.parse_args()
    lit_t = struct_t = lit_n = struct_n = kg_t = kg_n = 0
    seen = set(); drop_dup = drop_q = 0
    extra_stats = {}
    with open(a.out, "w") as fo:
        # literature — STRIDE sample uniformly across the whole corpus (shards are PMID-ordered, so a
        # sequential cap would bias to 1970s abstracts; modulo keeps all eras/topics represented)
        for i, line in enumerate(open(a.lit)):
            if a.lit_keep_every > 1 and (i % a.lit_keep_every) != 0: continue
            try: t = json.loads(line).get("text", "")
            except Exception: continue
            if not t: continue
            if a.dedup:
                if not quality_ok(t, a.min_chars): drop_q += 1; continue
                k = norm_key(t)
                if k in seen: drop_dup += 1; continue
                seen.add(k)
            fo.write(line if line.endswith("\n") else line + "\n")
            lit_t += toks(t); lit_n += 1
        # extra full-text / tool-docs / DB-catalog sources (deduped against literature + each other)
        for spec in a.extra:
            parts = spec.split(":"); path = parts[0]; src = parts[1] if len(parts) > 1 else "extra"
            rep = int(parts[2]) if len(parts) > 2 else 1
            if not os.path.exists(path): print(f"[mix] extra missing, skip: {path}", flush=True); continue
            rows = []
            for line in open(path):
                try: t = json.loads(line).get("text", "")
                except Exception: continue
                if not t: continue
                if a.dedup:
                    if not quality_ok(t, a.min_chars): drop_q += 1; continue
                    k = norm_key(t)
                    if k in seen: drop_dup += 1; continue
                    seen.add(k)
                rows.append(json.dumps({"text": t[:16000], "source": src}))
            et = 0
            for _ in range(rep):
                for r in rows:
                    fo.write(r + "\n"); et += toks(json.loads(r)["text"])
            extra_stats[src] = {"unique_rows": len(rows), "repeat": rep, "~tokens": et}
        # structured, repeated N times (upweight the small BioMate-specific corpus)
        struct_rows = []
        for line in open(a.struct):
            try: r = json.loads(line)
            except Exception: continue
            t = r.get("text") or r.get("content") or ""
            if not t: continue
            struct_rows.append(json.dumps({"text": t[:16000], "source": "structured"}))
        for _ in range(a.struct_repeat):
            for r in struct_rows:
                fo.write(r + "\n")
                struct_t += toks(json.loads(r)["text"]); struct_n += 1
        # verbalized KG (PrimeKG + MAP-KG), optionally upweighted
        if a.kg and os.path.exists(a.kg):
            kg_rows = [l for l in open(a.kg) if l.strip()]
            for _ in range(a.kg_repeat):
                for l in kg_rows:
                    fo.write(l if l.endswith("\n") else l + "\n")
                    try: kg_t += toks(json.loads(l).get("text", ""))
                    except Exception: pass
                    kg_n += 1
    extra_t = sum(v["~tokens"] for v in extra_stats.values())
    total = lit_t + struct_t + kg_t + extra_t
    comp = {"literature": {"rows": lit_n, "~tokens": lit_t, "pct": round(100 * lit_t / total, 1)},
            "extra": {**extra_stats, "~tokens": extra_t, "pct": round(100 * extra_t / total, 1)},
            "dedup": {"dropped_dup": drop_dup, "dropped_lowquality": drop_q, "enabled": a.dedup},
            "structured": {"rows": struct_n, "~tokens": struct_t, "pct": round(100 * struct_t / total, 1),
                           "repeat": a.struct_repeat, "unique_rows": len(struct_rows)},
            "kg": {"rows": kg_n, "~tokens": kg_t, "pct": round(100 * kg_t / total, 1), "repeat": a.kg_repeat},
            "domain_total": {"rows": lit_n + struct_n + kg_n, "~tokens": total}}
    json.dump(comp, open(a.out + ".composition.json", "w"), indent=2)
    print("MIX COMPOSITION:", json.dumps(comp), flush=True)


if __name__ == "__main__":
    raise SystemExit(main())
