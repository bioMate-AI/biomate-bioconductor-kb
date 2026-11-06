"""Format jittering (committee anti-overfit fix): our fine-tuning gains were prompt-format-SPECIFIC,
so present each task in MULTIPLE equivalent surface templates. Local transform (no API): for a fraction
of the joint SFT set, rewrite the user turn into an equivalent template variant (varied instruction
phrasing, delimiters, option-list style) while keeping the assistant target identical. Prevents the
model from memorizing one exact key sequence and improves transfer to the production format."""
import json, os, re, random
random.seed(101); D="/Users/kky/biomate-review/docs/20260912_onprem_llm/routing_data_v1"
src=f"{D}/multitask_sft.jsonl"; out=f"{D}/multitask_sft_jittered.jsonl"

# equivalent rephrasings for common instruction fragments (semantics preserved)
SUByes = [
    ("Respond with EXACTLY ONE option from this list and nothing else:", "Choose exactly one of the following (reply with only that option):"),
    ("Respond with EXACTLY ONE option from this list and nothing else:", "Pick the single best option below and output only it:"),
    ("\n\nINPUT:\n", "\n\nRequest:\n"),
    ("\n\nINPUT:\n", "\n\n---\nUser query:\n"),
    ("Reply with ONLY the single canonical workflow name", "Answer with just the canonical workflow name"),
    ("Reply with ONLY a JSON object", "Output only a JSON object"),
    ("Reply with JSON only.", "Return JSON only."),
]
def jitter(u):
    v=u; applied=0
    for a,b in SUByes:
        if a in v and random.random()<0.7:
            v=v.replace(a,b,1); applied+=1
    return v if applied else None

rows=[json.loads(l) for l in open(src)]
res=list(rows); n=0
for r in rows:
    if random.random()<0.5:  # jitter ~half into an extra variant (keep original too)
        u=r["messages"][0]["content"]; jv=jitter(u)
        if jv and jv!=u:
            res.append({"messages":[{"role":"user","content":jv},r["messages"][1]]}); n+=1
random.shuffle(res)
open(out,"w").write("\n".join(json.dumps(r) for r in res))
print(f"format-jitter: {len(rows)} -> {len(res)} ({n} template-variant copies added)")
