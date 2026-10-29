"""K4 stage 2 (EC2 GPU): passage-level extraction with an open-weight model (vLLM), deterministic verification.
Resumable (done_passages.txt); outputs append-only JSONL. usage: extract_patents.py --corpus corpus.jsonl.gz --outdir DIR [--max-passages-per-patent 40]"""
import argparse, gzip, json, os, re, time
import config
from verify_patent import verify, norm, item_id, KINDS, FORMATS

PROMPT_VERSION = "k4-prompt-v1"
INSTR = f"""You extract knowledge about cyclic peptides, macrocycles and peptide-like compounds from ONE passage of a PATENT document.
Output ONLY a JSON array (it may be empty). Each element is an object with these keys:
"kind": one of {KINDS} (example_compound = a named/numbered compound with an activity or property value; sar_statement = a statement about how a structural change affects potency/permeability/stability/selectivity; adme_permeability = permeability, solubility, stability or pharmacokinetic data; binding_mode = how a compound binds its target; design_rationale = why a design choice was made);
"statement": one concise sentence;
"compound_id": the identifier as written (for example "Compound 12" or "Example 5") or "";
"structure_string": a peptide sequence, HELM string or SMILES copied VERBATIM and unchanged from the passage, or "";
"structure_format": one of {FORMATS};
"activity": {{"assay": string, "value": number, "unit": string, "relation": "=" or "<" or ">"}} or null (only if a number is stated);
"target": the biological target named in the passage or "";
"quote": a fragment copied VERBATIM and unchanged from the passage, 6 to 40 words long (a table row is a valid quote), that contains the evidence;
Rules: use only information in the passage; never paraphrase the quote or the structure string; if the passage reports nothing of this kind output []; at most 8 items."""

SCORE_RX = re.compile(r"(Example|Table|IC50|EC50|Kd\b|Ki\b|nM\b|µM|uM\b|permeab|PAMPA|Caco|N-methyl|NMe|D-amino|cyclo|macrocycl|SEQ ID|ring size|stability|half-life)", re.I)

def passages(text, words=450, min_words=100, cap=30):
    """Split into <= `words`-word windows (long paragraphs are cut: the Google Patents description arrives as ONE paragraph), keep windows with
    >= 3 example/table/SAR pattern hits, at most `cap` per patent (highest hit count first, returned in document order)."""
    toks = []
    for para in [p for p in re.split(r"\n\s*\n", text) if p.strip()]:
        toks.extend(para.split())
        toks.append("\n")            # paragraph marker keeps boundaries between title / abstract / claims / description
    out, cur, n = [], [], 0
    for t in toks:
        if t == "\n":
            continue
        cur.append(t); n += 1
        if n >= words:
            out.append(" ".join(cur)); cur, n = [], 0
    if cur:
        out.append(" ".join(cur))
    scored = []
    for i, ps in enumerate(out):
        if len(ps.split()) < min_words:
            continue
        hits = len(SCORE_RX.findall(ps))
        if hits >= 3:
            scored.append((hits, i, ps))
    scored.sort(key=lambda x: (-x[0], x[1]))
    keep = sorted(scored[:cap], key=lambda x: x[1])
    return [(i, ps) for _, i, ps in keep]

def parse_json_array(s):
    a, b = s.find("["), s.rfind("]")
    if a < 0 or b < a:
        return None
    try:
        v = json.loads(s[a:b + 1])
        return v if isinstance(v, list) else None
    except json.JSONDecodeError:
        return None

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--corpus", required=True); ap.add_argument("--outdir", required=True)
    ap.add_argument("--chunk", type=int, default=128); ap.add_argument("--cap", type=int, default=30); ap.add_argument("--max-patents", type=int, default=0)
    a = ap.parse_args(); os.makedirs(a.outdir, exist_ok=True)
    from vllm import LLM, SamplingParams
    pats = [json.loads(l) for l in gzip.open(a.corpus, "rt", encoding="utf-8")]
    if a.max_patents:
        pats = pats[:a.max_patents]
    done_path = os.path.join(a.outdir, "done_passages.txt")
    done = set(open(done_path).read().split()) if os.path.exists(done_path) else set()
    ntext = {p["patent_number"]: norm(p["text"]) for p in pats}
    jobs = []
    for p in pats:
        for i, ps in passages(p["text"], cap=a.cap):
            pid = f"{p['patent_number']}:{i}"
            if pid not in done:
                jobs.append((pid, p, ps))
    print(f"patents={len(pats)} passages_todo={len(jobs)} done={len(done)}", flush=True)
    llm = LLM(model=config.MODEL, dtype="bfloat16", max_model_len=6144, gpu_memory_utilization=0.90, enable_prefix_caching=True)
    tok = llm.get_tokenizer()
    MAXIN = 6144 - 1600 - 64
    chat = lambda u: tok.apply_chat_template([{"role": "user", "content": u}], tokenize=False, add_generation_prompt=True, enable_thinking=False)
    sp = SamplingParams(temperature=0.0, max_tokens=1600)
    stats_path = os.path.join(a.outdir, "stats.json")
    stats = json.load(open(stats_path)) if os.path.exists(stats_path) else {"passages": 0, "raw_items": 0, "verified": 0, "rejected": {},
            "parse_fail_passages": 0, "prompt_tokens": 0, "completion_tokens": 0, "gen_seconds": 0.0}
    t_all = time.time()
    for c0 in range(0, len(jobs), a.chunk):
        chunk = jobs[c0:c0 + a.chunk]; t0 = time.time()
        fit = [len(tok(INSTR + "\n\nPASSAGE:\n" + ps)["input_ids"]) <= MAXIN for _, _, ps in chunk]
        stats["skipped_too_long"] = stats.get("skipped_too_long", 0) + fit.count(False)
        skipped = [j for j, f in zip(chunk, fit) if not f]
        chunk = [j for j, f in zip(chunk, fit) if f]
        if skipped:
            with open(done_path, "a") as fh:
                fh.write("\n".join(pid for pid, _, _ in skipped) + "\n")
        if not chunk:
            continue
        outs = llm.generate([chat(INSTR + "\n\nPASSAGE:\n" + ps) for _, _, ps in chunk], sp)
        kept, rej = [], []
        for (pid, p, ps), o in zip(chunk, outs):
            stats["passages"] += 1
            stats["prompt_tokens"] += len(o.prompt_token_ids); stats["completion_tokens"] += len(o.outputs[0].token_ids)
            arr = parse_json_array(o.outputs[0].text)
            if arr is None:
                stats["parse_fail_passages"] += 1; continue
            pn = norm(ps)
            for it in arr:
                if not isinstance(it, dict):
                    continue
                stats["raw_items"] += 1
                ok, why, enr = verify(it, ntext[p["patent_number"]], pn)
                if not ok:
                    stats["rejected"][why] = stats["rejected"].get(why, 0) + 1
                    rej.append({"patent": p["patent_number"], "passage": pid, "reason": why, "quote": it.get("quote")}); continue
                rec = {"item_id": item_id(p["patent_number"], it["quote"], it["statement"]), "tier": "P", "patent_number": p["patent_number"],
                       "kind_code": p["meta"].get("kind"), "pub_date": p["meta"].get("pub_date"), "assignee": p["meta"].get("assignee"),
                       "family_cpc": p["meta"].get("cpc"), "stratum": p["stratum"], "source_section": "description", "passage_id": pid,
                       "kind": it["kind"], "statement": norm(it["statement"]), "compound_id": norm(str(it.get("compound_id") or "")),
                       "structure_string": norm(str(it.get("structure_string") or "")), "structure_format": it.get("structure_format") or "none",
                       "activity": it.get("activity"), "target": norm(str(it.get("target") or "")), "quote": norm(it["quote"]),
                       "text_sha256": p["text_sha256"], "url": p["url"], "retrieved": p["retrieved"],
                       "extracted_by": f"{config.MODEL}/{PROMPT_VERSION}", "access_date": time.strftime("%Y-%m-%d"), **enr}
                kept.append(rec)
        stats["verified"] += len(kept); stats["gen_seconds"] += time.time() - t0
        with open(os.path.join(a.outdir, "items_verified.jsonl"), "a") as fh:
            for r in kept:
                fh.write(json.dumps(r) + "\n")
        with open(os.path.join(a.outdir, "items_rejected.jsonl"), "a") as fh:
            for r in rej:
                fh.write(json.dumps(r) + "\n")
        with open(done_path, "a") as fh:
            fh.write("\n".join(pid for pid, _, _ in chunk) + "\n")
        json.dump(stats, open(stats_path, "w"))
        print(f"chunk {c0 // a.chunk} verified={len(kept)} rejected={len(rej)} sec={time.time() - t0:.0f}", flush=True)
    stats["wall_seconds_this_run"] = time.time() - t_all
    json.dump(stats, open(stats_path, "w"))

if __name__ == "__main__":
    main()
