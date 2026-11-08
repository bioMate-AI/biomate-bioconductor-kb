"""Generalized prompt paraphrase augmentation (v2) — diversify the LOW-diversity tasks the v1
paraphraser missed (it only reached rows with a `Request:` marker; the enriched format has none).

Method (per docs/.../SFT_GENERATION_SURVEY.md — Unnatural-Instructions + PersonaHub):
  * rewrite ONLY the natural-language voice/surface-form of the USER turn into K persona variants,
  * PRESERVE verbatim every entity/value/filename/number and any structured block (error log, code
    fence, candidate list, param schema) — instructed to the model AND hard-verified after,
  * keep the SYSTEM + ASSISTANT (gold) turns identical,
  * drop any variant that loses a salient token (meaning-preservation guard) or dups.

Targets the measured low-diversity tasks only (quality>quantity). Usage:
  OPENAI_API_KEY=... python build_paraphrase_v2.py --in sft_train.jsonl --out sft_train_pv2.jsonl \
     --k 3 --tasks out_of_catalog_composition,autofix_repair,model_selection,design_constraint,dataset_prerequisite_check
"""
import argparse, json, os, re, time, random, hashlib, urllib.request
from concurrent.futures import ThreadPoolExecutor
random.seed(202)
KEY = os.environ["OPENAI_API_KEY"]; GEN = os.environ.get("PARA_MODEL", "gpt-5-mini")

STYLES = [
 "terse shorthand a busy bioinformatician would type (drop articles, abbreviations ok)",
 "verbose lab-notebook prose with background motivation",
 "non-native English speaker: slightly awkward grammar, correct meaning",
 "with 1-2 realistic typos and inconsistent capitalization",
 "heavy domain jargon and tool/assay acronyms",
 "casual Slack message to a core-facility colleague",
 "formal grant/methods-section register",
 "buries the request inside 1 sentence of irrelevant lab context",
 "a wet-lab biologist with limited computational vocabulary",
 "a PI dictating quickly, run-on sentence",
]


def salient(s):
    """meaning-preservation anchors: backtick/quoted names, filenames, numbers, ALLCAPS acronyms."""
    toks = set(re.findall(r"`[^`]+`|'[^']{2,}'|\b\w+\.\w{2,4}\b|\b\d+(?:\.\d+)?\b|\b[A-Z]{2,}\d*\b", s))
    return {t.lower().strip("`'") for t in toks}


def _call(p, n=900):
    body = json.dumps({"model": GEN, "messages": [{"role": "user", "content": p}],
                       "max_completion_tokens": n, "reasoning_effort": "low"}).encode()
    for a in range(3):
        try:
            d = json.load(urllib.request.urlopen(urllib.request.Request(
                "https://api.openai.com/v1/chat/completions", data=body,
                headers={"Authorization": f"Bearer {KEY}", "Content-Type": "application/json"}), timeout=90))
            return d["choices"][0]["message"]["content"].strip()
        except Exception:
            time.sleep(1.5 * (a + 1))
    return None


def paraphrase(user, k):
    styles = random.sample(STYLES, min(k, len(STYLES)))
    ask = ("Rewrite the following BioMate USER MESSAGE into " + str(len(styles)) + " different surface forms that "
           "preserve its EXACT meaning. RULES: keep every technical entity, value, file name, number, gene/tool "
           "name, and any code block / error log / candidate list / parameter schema EXACTLY as written "
           "(verbatim) — only change the natural-language wording and voice. Do NOT add, drop, or alter any "
           "technical detail. Each rewrite uses a distinct voice:\n"
           + "\n".join(f"{i+1}. {s}" for i, s in enumerate(styles))
           + f"\n\nUSER MESSAGE:\n{user}\n\nReply ONLY a JSON list of {len(styles)} strings, in order.")
    out = _call(ask, n=500 + 300 * len(styles))
    if not out:
        return []
    m = re.search(r"\[.*\]", out, re.S)
    if not m:
        return []
    try:
        arr = json.loads(m.group(0))
    except Exception:
        return []
    need = salient(user); orig_key = re.sub(r"[^a-z0-9]+", " ", user.lower()).strip()
    seen = set(); res = []
    for v in arr:
        v = str(v).strip()
        if len(v) < 6:
            continue
        key = re.sub(r"[^a-z0-9]+", " ", v.lower()).strip()
        if key == orig_key or key in seen:
            continue
        # meaning-preservation guard: every salient anchor from the original must survive
        if need and len(need - salient(v)) > 0:
            continue
        seen.add(key); res.append(v)
    return res


def roles(r):
    d = {m["role"]: i for i, m in enumerate(r["messages"])}
    return d


def gen(row, k):
    ri = roles(row)
    if "user" not in ri:
        return []
    ui = ri["user"]; user = row["messages"][ui]["content"]
    variants = paraphrase(user, k)
    out = []
    for v in variants:
        msgs = [dict(m) for m in row["messages"]]
        msgs[ui] = {"role": "user", "content": v}
        out.append({"messages": msgs, "task": row.get("task"), "source": (row.get("source", "") + "+para"), "aug": "paraphrase_v2"})
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--in", dest="inp", required=True); ap.add_argument("--out", required=True)
    ap.add_argument("--k", type=int, default=3)
    ap.add_argument("--tasks", default="out_of_catalog_composition,autofix_repair,model_selection,design_constraint,dataset_prerequisite_check")
    ap.add_argument("--workers", type=int, default=12)
    a = ap.parse_args()
    target = set(a.tasks.split(","))
    rows = [json.loads(l) for l in open(a.inp) if l.strip()]
    todo = [r for r in rows if r.get("task") in target]
    print(f"paraphrase-v2: {len(todo):,} target rows (tasks={sorted(target)}) of {len(rows):,}", flush=True)
    aug = []
    with ThreadPoolExecutor(max_workers=a.workers) as ex:
        for i, extra in enumerate(ex.map(lambda r: gen(r, a.k), todo)):
            aug.extend(extra)
            if i % 500 == 0:
                print(f"  {i}/{len(todo)} -> +{len(aug)} variants", flush=True)
    seen = set(); dedup = []
    for r in aug:
        u = next(m["content"] for m in r["messages"] if m["role"] == "user")
        h = hashlib.md5(re.sub(r"[^a-z0-9]+", " ", u.lower()).strip().encode()).hexdigest()
        if h in seen:
            continue
        seen.add(h); dedup.append(r)
    combined = rows + dedup; random.shuffle(combined)
    with open(a.out, "w") as f:
        for r in combined:
            f.write(json.dumps(r) + "\n")
    with open(a.out.replace(".jsonl", "_augonly.jsonl"), "w") as f:
        for r in dedup:
            f.write(json.dumps(r) + "\n")
    print(f"PARAPHRASE-V2: {len(rows):,} -> {len(combined):,} (+{len(dedup):,} verified distinct variants, k~{a.k})", flush=True)


if __name__ == "__main__":
    raise SystemExit(main())
