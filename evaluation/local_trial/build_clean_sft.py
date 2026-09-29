"""Assemble the CLEAN v5 SFT set: remove the 3 confirmed defects from the base, then merge the open-book
routing + paraphrase augmentation. Defects (measured in the 2nd-pass review):
  1. drop 'rt'-stripped corrupted answers (~594, medmcqa knowledge_recall) — unrepairable, drop.
  2. drop task_decomposition claude-log scaffold artifacts (~1,578, "voter N/3 adversarial claim verifier").
  3. strip citation/HTML cruft from answers (<img>/<tags>, trailing "REF: ..." textbook citations).
Then + open-book routing SFT + paraphrase variants; dedup. Usage:
  python build_clean_sft.py --base sft_train.jsonl --openbook routing_openbook_sft.jsonl \
     --para sft_train_pv2_augonly.jsonl --out multitask_sft_v5.jsonl
"""
import argparse, json, re, hashlib, collections

CORRUPT = re.compile(r"\b(impoant|impoance|impoantly|suppoed|suppoing|paicular|paicipants?|paial|paition|"
                     r"moality|moalities|quaer|coex|fouh|veebrae|veebral|depament|repoed|repoing|staed|"
                     r"staing|paner|propey|poion|poions|aery|aeries|cein|cetain|conves|expoed|assoed)\b")
SCAFFOLD = re.compile(r"adversarial claim verifier|voter \d\s*/\s*\d|you are (a )?(voter|verifier)", re.I)
IMG = re.compile(r"<[^>]+>")
REFTAIL = re.compile(r"\s*(REF:|Ref:|Reference:).*$", re.S)


def msgs(r):
    return {i: m for i, m in enumerate(r.get("messages", []))}


def clean_answer(a):
    a = IMG.sub(" ", a)                 # strip HTML tags (<img …>, <div>…)
    a = REFTAIL.sub("", a)              # drop trailing textbook citation blocks
    a = re.sub(r"\s+", " ", a).strip()
    return a


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", required=True); ap.add_argument("--openbook", default="")
    ap.add_argument("--para", default=""); ap.add_argument("--out", required=True)
    ap.add_argument("--para-cap-mult", type=float, default=1.0,
                    help="cap paraphrase variants added per task to mult × the task's base count (avoid skew)")
    a = ap.parse_args()
    base = [json.loads(l) for l in open(a.base) if l.strip()]
    kept = []; dropped_corrupt = dropped_scaffold = cleaned = 0
    for r in base:
        ms = r.get("messages", [])
        ai = next((i for i, m in enumerate(ms) if m["role"] == "assistant"), None)
        ui = next((i for i, m in enumerate(ms) if m["role"] == "user"), None)
        if ai is None:
            continue
        ans = ms[ai]["content"]; usr = ms[ui]["content"] if ui is not None else ""
        if CORRUPT.search(ans) or CORRUPT.search(usr):
            dropped_corrupt += 1; continue
        if r.get("task") == "task_decomposition" and (SCAFFOLD.search(ans) or SCAFFOLD.search(usr)):
            dropped_scaffold += 1; continue
        ca = clean_answer(ans)
        if ca != ans:
            cleaned += 1; ms[ai] = {"role": "assistant", "content": ca}
        kept.append(r)
    base_task_ct = collections.Counter(r.get("task") for r in kept)
    add = 0
    if a.openbook:
        for l in open(a.openbook):
            if l.strip():
                kept.append(json.loads(l)); add += 1
    if a.para:
        # cap per-task paraphrase additions to para_cap_mult × base count (prevents one task dominating)
        para_added = collections.Counter(); capped = 0
        for l in open(a.para):
            if not l.strip():
                continue
            r = json.loads(l); t = r.get("task")
            if para_added[t] >= a.para_cap_mult * max(1, base_task_ct.get(t, 0)):
                capped += 1; continue
            para_added[t] += 1; kept.append(r); add += 1
        print(f"  paraphrase added per task (capped {capped}): {dict(para_added)}")
    # global dedup on (user+assistant)
    seen = set(); final = []
    for r in kept:
        ms = {m["role"]: m["content"] for m in r.get("messages", [])}
        h = hashlib.md5((re.sub(r"\s+", " ", ms.get("user", "")) + "||" + re.sub(r"\s+", " ", ms.get("assistant", ""))).lower().encode()).hexdigest()
        if h in seen:
            continue
        seen.add(h); final.append(r)
    with open(a.out, "w") as f:
        for r in final:
            f.write(json.dumps(r) + "\n")
    print(f"CLEAN v5: base {len(base):,} -> dropped(corrupt={dropped_corrupt}, scaffold={dropped_scaffold}) "
          f"cleaned-answers={cleaned} | +added({add:,}) | dedup -> {len(final):,}")
    print("  final task dist:", dict(collections.Counter(r.get("task", "?") for r in final).most_common()))


if __name__ == "__main__":
    raise SystemExit(main())
