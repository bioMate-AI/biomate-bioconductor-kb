"""Paraphrase augmentation for GENUINE surface diversity (not template jitter).

format_jitter.py only swapped fixed delimiters/instruction fragments -> near-duplicates. This instead
REWORDS the natural-language REQUEST of each SFT example into K diverse variants sampled across a
persona/style bank (terse, verbose, non-native, typo-noisy, jargon-heavy, extra-irrelevant-context,
slack-msg, formal-grant). The assistant GOLD is kept identical, and any STRUCTURED block in the user
turn (parameter schema, retrieved-candidate list, error log) is preserved VERBATIM -- only the free-text
request is paraphrased. This is the Evol-Instruct/PersonaHub-style diversity the SFT set was missing:
it multiplies *distinct phrasings* the model must generalize over, without touching the label.

Cost control: K variants are produced in ONE call per example (JSON list). Structured blocks are split
out locally and re-attached, so the model only ever rewrites the short request span."""
import json, os, sys, re, time, random, urllib.request, hashlib
from concurrent.futures import ThreadPoolExecutor
random.seed(202); REPO="/Users/kky/biomate-review"; D=f"{REPO}/docs/20260912_onprem_llm/routing_data_v1"
KEY=os.environ["OPENAI_API_KEY"]; GEN="gpt-5-mini"

# style/persona bank -> each variant samples a distinct voice for real diversity
STYLES=[
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
# markers that delimit a STRUCTURED block we must keep verbatim; paraphrase only the request span
REQ_MARKERS=["\n\nRequest: ","\n\nRequest:\n","\n\nINPUT:\n","\n\n---\nUser query:\n","\n\nInput:\n"]

def split_request(u):
    """Return (prefix_verbatim, request_text, suffix_verbatim) or None if no clear request span.
    We paraphrase ONLY request_text; prefix (instruction+schema/candidates) and suffix stay fixed."""
    for m in REQ_MARKERS:
        i=u.rfind(m)
        if i!=-1:
            start=i+len(m); req=u[start:]
            # a trailing structured block after the request is rare; treat rest as request
            if 8<=len(req)<=1200: return u[:start], req, ""
    return None

def _call(p, n=800):
    body=json.dumps({"model":GEN,"messages":[{"role":"user","content":p}],
                     "max_completion_tokens":n,"reasoning_effort":"low"}).encode()
    for a in range(3):
        try:
            d=json.load(urllib.request.urlopen(urllib.request.Request(
              "https://api.openai.com/v1/chat/completions",data=body,
              headers={"Authorization":f"Bearer {KEY}","Content-Type":"application/json"}),timeout=60))
            return d["choices"][0]["message"]["content"].strip()
        except Exception: time.sleep(1.5*(a+1))
    return None

def paraphrase(req, k):
    styles=random.sample(STYLES,min(k,len(STYLES)))
    ask=("Rewrite the following bioinformatics REQUEST into "+str(len(styles))+" DIFFERENT surface forms "
         "that preserve its EXACT meaning, entities, values, file names and intent (do not add, drop, or "
         "change any technical detail). Each rewrite uses a distinct voice:\n"
         +"\n".join(f"{i+1}. {s}" for i,s in enumerate(styles))
         +f'\n\nREQUEST:\n{req}\n\nReply ONLY a JSON list of {len(styles)} strings, one per voice, in order.')
    out=_call(ask, n=500+240*len(styles))  # generous: 5 long paraphrases overflowed the old 700-cap -> truncated JSON -> 0 variants
    if not out: return []
    m=re.search(r"\[.*\]", out, re.S)
    if not m: return []
    try: arr=json.loads(m.group(0))
    except: return []
    seen=set(); res=[]
    for v in arr:
        v=str(v).strip()
        if len(v)<6: continue
        key=re.sub(r"[^a-z0-9]+"," ",v.lower()).strip()
        if key==re.sub(r"[^a-z0-9]+"," ",req.lower()).strip(): continue  # skip echo of original
        if key in seen: continue
        seen.add(key); res.append(v)
    return res

def gen(row, k):
    u=row["messages"][0]["content"]; a=row["messages"][1]
    sp=split_request(u)
    if not sp: return []
    prefix, req, suffix = sp
    variants=paraphrase(req, k)
    return [{"messages":[{"role":"user","content":prefix+v+suffix}, a], "aug":"paraphrase"} for v in variants]

def main():
    src=f"{D}/multitask_sft.jsonl"; out=f"{D}/multitask_sft_paraphrased.jsonl"
    K=int(sys.argv[1]) if len(sys.argv)>1 else 4
    rows=[json.loads(l) for l in open(src) if l.strip()]
    # skip paraphrasing rows whose "request" is really a fixed artifact (error logs): diag_fix/autofix
    def paraphrasable(r):
        u=r["messages"][0]["content"]
        return ("ERROR LOG" not in u and "Error log" not in u)  # keep real logs verbatim
    todo=[r for r in rows if paraphrasable(r) and split_request(r["messages"][0]["content"])]
    print(f"paraphrasable: {len(todo)}/{len(rows)} rows (rest kept verbatim: fixed error logs / no request span)")
    aug=[]
    with ThreadPoolExecutor(max_workers=12) as ex:
        for extra in ex.map(lambda r: gen(r, K), todo):
            aug.extend(extra)
    # global near-dup guard across the whole augmented set
    seen=set(); dedup=[]
    for r in aug:
        h=hashlib.md5(re.sub(r"[^a-z0-9]+"," ",r["messages"][0]["content"].lower()).strip().encode()).hexdigest()
        if h in seen: continue
        seen.add(h); dedup.append(r)
    combined=rows+dedup; random.shuffle(combined)
    open(out,"w").write("\n".join(json.dumps(r) for r in combined))
    open(f"{D}/paraphrase_aug_only.jsonl","w").write("\n".join(json.dumps(r) for r in dedup))
    print(f"PARAPHRASE-AUG: {len(rows)} -> {len(combined)} (+{len(dedup)} distinct paraphrase variants, K~{K})")

if __name__=="__main__": raise SystemExit(main())
