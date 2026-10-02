"""Mine PMC full-text (pmc_concept.jsonl) into STRUCTURED scientific components by IMRaD section, and
emit (a) structured concept docs (problem -> method -> findings -> conclusion = the reasoning pattern)
for CPT, and (b) task-training pairs — notably findings_interpretation (results -> conclusion), which
is a 🔴 LLM-bound task we otherwise lack real data for.

  cat pmc_concept.jsonl | python3 pmc_miner.py --struct-out pmc_structured.jsonl --pairs-out pmc_pairs.jsonl
Reads stdin jsonl ({text,...}); section-splits on IMRaD header anchors; needs >=2 sections to emit.
"""
import sys, json, re, argparse, collections

# Section header anchors (word-boundary; title-case-ish). Map each to a canonical slot.
SLOT = [
    ("problem",    r"Introduction|Background"),
    ("method",     r"Materials and Methods|Methods|Materials And Methods|Experimental (?:Section|Procedures)"),
    ("findings",   r"Results(?: and Discussion)?|Findings"),
    ("conclusion", r"Discussion|Conclusions?|Concluding Remarks"),
]
HDR = re.compile(r"\b(" + "|".join(p for _, p in SLOT) + r")\b")
SLOTMAP = [(re.compile(p), slot) for slot, p in SLOT]


BILINGUAL = re.compile(r"\b(RESUMO|RESUMEN|ZUSAMMENFASSUNG|RÉSUMÉ|ABSTRACT|KEYWORDS?|Acknowledge?ments)\b")


def clean_sec(s):
    m = BILINGUAL.search(s[200:])          # cut trailing foreign-abstract / keyword bleed
    return (s[:200] + s[200:m.start()]).strip() if m else s.strip()


def slot_of(header):
    for rx, slot in SLOTMAP:
        if rx.fullmatch(header):
            return slot
    return None


def split_sections(text):
    marks = [(m.start(), m.group(1)) for m in HDR.finditer(text)]
    if len(marks) < 2:
        return {}
    secs = {}
    for i, (pos, hdr) in enumerate(marks):
        end = marks[i + 1][0] if i + 1 < len(marks) else len(text)
        slot = slot_of(hdr)
        if not slot:
            continue
        body = clean_sec(text[pos + len(hdr):end].strip(" :.-"))
        if len(body) > 120 and slot not in secs:   # first substantive occurrence wins
            secs[slot] = body[:3000]
    return secs


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--struct-out", required=True); ap.add_argument("--pairs-out", required=True)
    ap.add_argument("--sample", type=int, default=0)
    a = ap.parse_args()
    n = struct = pairs = 0; slotcnt = collections.Counter()
    fs = None if a.sample else open(a.struct_out, "w")
    fp = None if a.sample else open(a.pairs_out, "w")
    for line in sys.stdin:
        n += 1
        if a.sample and n > a.sample:
            break
        try:
            r = json.loads(line)
        except Exception:
            continue
        secs = split_sections(r.get("text", ""))
        if len(secs) < 2:
            continue
        for s in secs:
            slotcnt[s] += 1
        # (a) structured concept doc — the problem->method->finding reasoning pattern
        parts = [f"{k.capitalize()}: {secs[k]}" for k in ("problem", "method", "findings", "conclusion") if k in secs]
        rec = {"source": "pmc_structured", "sections": list(secs.keys()), "text": "\n\n".join(parts)}
        struct += 1
        if fs:
            fs.write(json.dumps(rec) + "\n")
        # (b) findings_interpretation pair: results -> conclusion (real interpretation gold)
        if "findings" in secs and "conclusion" in secs and len(secs["conclusion"]) >= 200 and len(secs["findings"]) >= 200:
            pair = {"task": "findings_interpretation", "source": "pmc_mined",
                    "messages": [{"role": "user", "content": "Interpret these results into the key findings and "
                                  "conclusion (what they MEAN).\n\nResults:\n" + secs["findings"]},
                                 {"role": "assistant", "content": secs["conclusion"]}]}
            pairs += 1
            if fp:
                fp.write(json.dumps(pair) + "\n")
    sys.stderr.write(f"PMC MINER: in={n} structured={struct} findings_pairs={pairs} "
                     f"slots={dict(slotcnt.most_common())}\n")
    if a.sample and struct:
        sys.stderr.write("--- sample structured ---\n" + json.dumps(rec)[:700] + "\n")


if __name__ == "__main__":
    raise SystemExit(main())
