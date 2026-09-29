"""Build OPEN-BOOK candidate-grounded routing data + CONTRASTIVE (DPO) pairs — the fix for the
closed-book memorization disease (hallucination + upgrade-fragility + sibling confusion).

Deterministic, ZERO LLM calls: hard negatives are mined from the catalog itself.
  * open-book SFT: prompt = request + retrieved candidates (gold + K siblings, shuffled); target = exact gold.
  * DPO pairs: chosen = exact gold; rejected = hardest hard-negative, where hardness =
      (a) same-domain sibling with the highest description-token Jaccard to the gold (most confusable), and
      (b) a MANGLED spelling of the gold itself (teaches exact string; off-by-case/underscore is a real
          failure mode we measured), and
      (c) an OFF-CATALOG plausible name (teaches "never emit a name not in the candidates").
Candidates come from the LIVE catalog, so a tool rename = re-mine, no retrain (future-proof by design).

Usage:
  python build_contrastive.py --sft sft_train.jsonl --dbcat db_catalog.jsonl \
     --out-sft routing_openbook_sft.jsonl --out-dpo routing_dpo_pairs.jsonl --k 8
"""
import argparse, json, re, random, collections
random.seed(41)

SYS = ("You are BioMate. Given the user request and the retrieved candidate workflows, choose the single "
       "best-matching workflow and reply with ONLY its exact name, copied verbatim from the candidates.")
# non-real catalog entries that must never be a routing target or a candidate
JUNK = re.compile(r"\b(test|testpipeline|hackathon|demo|mock|sandbox|template|tutorial|example|dummy|placeholder)\b", re.I)


def canon(s): return re.sub(r"[\s_./-]+", " ", s.lower()).strip()


def toks(s): return set(re.sub(r"[^a-z0-9 ]", " ", (s or "").lower()).split())


def primary(a):
    m = re.search(r"`([^`]+)`", a) or re.search(r"['\"]([A-Za-z][\w .:/-]{2,60})['\"]", a)
    if m:
        return m.group(1).strip().strip(".,:;()*")
    m = re.search(r"(?:run|use|recommend|choose|select)\s+(?:the\s+)?([A-Za-z][\w/-]{2,60})", a)
    return m.group(1).strip().strip(".,:;()*") if m else ""


def mangle(name):
    v = name
    if "_" in v: v = v.replace("_", " ").title()
    elif " " in v: v = v.replace(" ", "_").lower()
    else: v = v.upper() if v.islower() else v.lower()
    return v if v != name else name.title()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--sft", required=True); ap.add_argument("--dbcat", required=True)
    ap.add_argument("--out-sft", required=True); ap.add_argument("--out-dpo", required=True)
    ap.add_argument("--k", type=int, default=8, help="candidates per prompt (1 gold + k-1 siblings)")
    a = ap.parse_args()
    # catalog: name -> (domain, description); domain -> [names]
    name_dom = {}; name_desc = {}; by_dom = collections.defaultdict(list)
    for l in open(a.dbcat):
        t = json.loads(l)["text"]
        m = re.search(r"^Name:\s*(.+)$", t, re.M); d = re.search(r"^Domain:\s*(.+)$", t, re.M)
        de = re.search(r"^Description:\s*(.+)$", t, re.M)
        if m:
            nm = m.group(1).strip(); dom = (d.group(1).strip() if d else "general")
            name_dom[canon(nm)] = (nm, dom); name_desc[canon(nm)] = (de.group(1) if de else "")
            by_dom[dom].append(nm)
    for k in by_dom: by_dom[k] = sorted(set(by_dom[k]))
    allnames = [v[0] for v in name_dom.values()]
    rows = [json.loads(l) for l in open(a.sft)]
    routing = [r for r in rows if r.get("task") == "workflow_routing"]
    sft_out = []; dpo_out = []
    kept = miss = 0
    for r in routing:
        u = next((m["content"] for m in r["messages"] if m["role"] == "user"), "")
        a_ans = next((m["content"] for m in r["messages"] if m["role"] == "assistant"), "")
        g = primary(a_ans)
        if not g or canon(g) not in name_dom:
            miss += 1; continue
        gold, dom = name_dom[canon(g)]
        if JUNK.search(gold):
            miss += 1; continue
        sibs = [n for n in by_dom.get(dom, []) if canon(n) != canon(gold)]
        if len(sibs) < 2:
            miss += 1; continue
        # SEMI-HARD sibling: confusable but NOT a near-duplicate. Two false-negative traps to avoid:
        #  (a) substring-related names (foo vs foo_advanced) — the sibling may also be valid → exclude.
        #  (b) VERY-high description overlap (>=0.5 Jaccard) — either genuinely interchangeable OR a
        #      boilerplate artifact (nf-core stubs share template text -> mitodetect~sopa at J=0.96) → exclude.
        # Pick the HARDEST sibling in the semi-hard band [floor, 0.5).
        cg = canon(gold)
        def jacc(n):
            A = toks(name_desc.get(cg, "") + " " + gold); B = toks(name_desc.get(canon(n), "") + " " + n)
            return len(A & B) / max(1, len(A | B))
        def unrelated(n): cn = canon(n); return cn not in cg and cg not in cn
        band = [(jacc(s), s) for s in sibs if unrelated(s) and not JUNK.search(s)]
        band = sorted([(j, s) for j, s in band if j < 0.5], reverse=True)  # drop near-dups/boilerplate
        if len(band) < 2:
            miss += 1; continue
        sibs_scored = [s for _, s in band]
        kept += 1
        hard = sibs_scored[0]
        cands = [gold, hard] + random.sample([s for s in sibs_scored[1:] if s != hard], min(a.k - 2, max(0, len(sibs_scored) - 1)))
        cands = list(dict.fromkeys(cands)); random.shuffle(cands)
        prompt = (f"Retrieved candidates:\n" + "\n".join(f"- {c}" for c in cands) + f"\n\nRequest: {u}")
        # open-book SFT (target = exact gold — this alone teaches exact spelling/casing, so no spelling-DPO)
        sft_out.append({"messages": [{"role": "system", "content": SYS},
                                     {"role": "user", "content": prompt},
                                     {"role": "assistant", "content": gold}],
                        "task": "workflow_routing_openbook", "source": "contrastive_openbook"})
        # DPO pairs: chosen=gold; hard sibling (confusable, distinct) + off-catalog (never emit off-list).
        # (spelling flavor dropped — near-identical strings are a weak/unstable DPO signal, already covered by SFT.)
        full = SYS + "\n\n" + prompt
        dpo_out.append({"prompt": full, "chosen": gold, "rejected": hard, "task": "routing_sibling"})
        offcat = random.choice(allnames)
        while offcat in cands or canon(offcat) == cg: offcat = random.choice(allnames)
        dpo_out.append({"prompt": full, "chosen": gold, "rejected": offcat, "task": "routing_offcatalog"})
    random.shuffle(sft_out); random.shuffle(dpo_out)
    with open(a.out_sft, "w") as f:
        for r in sft_out: f.write(json.dumps(r) + "\n")
    with open(a.out_dpo, "w") as f:
        for r in dpo_out: f.write(json.dumps(r) + "\n")
    print(f"CONTRASTIVE: kept {kept} routing rows (dropped {miss} non-catalog/thin-domain)", flush=True)
    print(f"  open-book SFT: {len(sft_out):,}  |  DPO pairs: {len(dpo_out):,} "
          f"({collections.Counter(d['task'] for d in dpo_out)})", flush=True)


if __name__ == "__main__":
    raise SystemExit(main())
