"""Build the mid-train DOMAIN mixture = literature (PubMed) + structured (midtrain_all), with the
tiny structured corpus upweighted by repetition so it isn't drowned by the ~6B-token literature.
General-replay (FineWeb-Edu) is mixed at TRAIN time via midtrain_run --replay/--replay-frac, so it's
not included here. Reports exact token composition. Usage:
  python build_midtrain_mix.py --lit literature_corpus.jsonl --struct midtrain_all.jsonl \
     --struct-repeat 8 --lit-cap-tokens 0 --out midtrain_domain.jsonl
"""
import argparse, json, os, random
random.seed(17)


def toks(s): return max(1, len(s) // 4)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--lit", required=True); ap.add_argument("--struct", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--struct-repeat", type=int, default=8, help="repeat structured N times to upweight it")
    ap.add_argument("--lit-cap-tokens", type=int, default=0, help="0 = use ALL literature")
    a = ap.parse_args()
    lit_t = struct_t = lit_n = struct_n = 0
    with open(a.out, "w") as fo:
        # literature (optionally capped)
        for line in open(a.lit):
            try: t = json.loads(line).get("text", "")
            except Exception: continue
            if not t: continue
            fo.write(line if line.endswith("\n") else line + "\n")
            lit_t += toks(t); lit_n += 1
            if a.lit_cap_tokens and lit_t >= a.lit_cap_tokens: break
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
    total = lit_t + struct_t
    comp = {"literature": {"rows": lit_n, "~tokens": lit_t, "pct": round(100 * lit_t / total, 1)},
            "structured": {"rows": struct_n, "~tokens": struct_t, "pct": round(100 * struct_t / total, 1),
                           "repeat": a.struct_repeat, "unique_rows": len(struct_rows)},
            "domain_total": {"rows": lit_n + struct_n, "~tokens": total}}
    json.dump(comp, open(a.out + ".composition.json", "w"), indent=2)
    print("MIX COMPOSITION:", json.dumps(comp), flush=True)


if __name__ == "__main__":
    raise SystemExit(main())
