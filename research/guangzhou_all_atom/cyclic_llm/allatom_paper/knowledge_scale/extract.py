"""K2 stage B: passage extraction with an open-weight instruct model (vLLM), deterministic verification, proxy entailment.
Resumable: processed passage ids are tracked in done_passages.txt; outputs are append-only JSONL."""
import argparse, gzip, hashlib, json, os, re, sys, time
from config import (MODEL, PASSAGE_WORDS, TOPIC_RE, PROPERTIES, SUBSTRUCTURES, DIRECTIONS, TOPICS, LESSON_TYPES,
                    STRUCT_FEATURES, TARGETS)
from verify import norm, verify_rule, rule_id

PROMPT_VERSION = "k2-prompt-v2-a1"
_COMMON = f"""Output ONLY a JSON array (it may be empty). Each element is an object with these keys:
"statement": one concise sentence;
"direction": one of {DIRECTIONS} (use "qualitative" or "conditional" when no single direction applies);
"property": one of {PROPERTIES};
"substructure_class": one of {SUBSTRUCTURES};
"scope": the peptide class / series / target the statement applies to (short phrase);
"effect_size": {{"value": number, "unit": string, "comparison": string}} or null;
"assay": the assay or measurement named in the passage, or "";
"quote": a sentence fragment copied VERBATIM and unchanged from the passage, 6 to 30 words long, that contains the evidence;
"confidence": number between 0 and 1;"""
_TAIL = """
Rules: use only information in the passage; never paraphrase the quote; if the passage reports nothing of this kind output []; at most 6 items."""
INSTR = {
    "sar_rule": "You extract design, structure-activity and property RULES about cyclic peptides, macrocycles and related peptides from ONE passage of a scientific paper.\n" + _COMMON + '\n"topic": "sar_rule".' + _TAIL,
    "structure_property": "You extract STRUCTURE-PROPERTY FUNDAMENTALS about cyclic peptides and macrocycles from ONE passage: mechanisms and physical explanations (permeability mechanism, desolvation, intramolecular hydrogen bonds and chameleonicity, 3D polar surface area, cis/trans amides and N-methylation conformations, ring strain and conformational ensembles, stereochemistry effects, proteolytic stability, solubility and aggregation).\n" + _COMMON + '\n"topic": "structure_property",\n"mechanism": short phrase naming the physical mechanism or explanation given.' + _TAIL,
    "prior_work": f"You extract PRIOR-WORK KNOWLEDGE from ONE passage: what cyclic-peptide / macrocycle design or optimisation campaigns designed, which methods were used, hit rates and outcomes, failure modes and lessons.\n" + _COMMON + f'\n"topic": "prior_work",\n"lesson_type": one of {LESSON_TYPES},\n"designed_what": what was designed or optimised (short phrase),\n"method": the method or platform used (short phrase),\n"outcome": the reported outcome in a short phrase (put a hit rate or counts into effect_size when stated).' + _TAIL,
    "target_structure": f"You extract TARGET-STRUCTURE statements from ONE passage about how cyclic peptides / macrocycles / peptide ligands bind their target: binding mode, key contacts, bound conformation, turn types, hot-spot residues.\n" + _COMMON + f'\n"topic": "target_structure",\n"target": one of {TARGETS} (the target the statement concerns, using the id that best matches; omit the item if none matches),\n"structure_feature": one of {STRUCT_FEATURES},\n"residues": list of residue/position names exactly as written in the passage (e.g. "Asp218"), possibly empty,\n"pdb": a PDB id exactly as written in the passage, or "".' + _TAIL,
}
EXTRA_KEYS = ["mechanism", "lesson_type", "designed_what", "method", "outcome", "target", "structure_feature", "residues", "pdb"]


def passages(text: str, target_words=PASSAGE_WORDS):
    paras = [p for p in text.split("\n\n") if p.strip()]
    cur, n, out = [], 0, []
    for p in paras:
        w = len(p.split())
        if cur and n + w > target_words:
            out.append("\n\n".join(cur))
            cur, n = [], 0
        cur.append(p)
        n += w
    if cur:
        out.append("\n\n".join(cur))
    rx = re.compile(TOPIC_RE, re.I)
    keep = []
    for i, ps in enumerate(out):
        if len({m.group(0).lower() for m in rx.finditer(ps)}) >= 2 and len(ps.split()) >= 120:
            keep.append((i, ps))
    return keep


def parse_json_array(s: str):
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
    ap.add_argument("--corpus", required=True)
    ap.add_argument("--outdir", required=True)
    ap.add_argument("--chunk", type=int, default=256)
    ap.add_argument("--max-papers", type=int, default=0)
    a = ap.parse_args()
    os.makedirs(a.outdir, exist_ok=True)
    from vllm import LLM, SamplingParams
    papers = [json.loads(l) for l in gzip.open(a.corpus, "rt", encoding="utf-8")]
    if a.max_papers:
        papers = papers[:a.max_papers]
    done_path = os.path.join(a.outdir, "done_passages.txt")
    done = set(open(done_path).read().split()) if os.path.exists(done_path) else set()
    jobs = []
    for p in papers:
        for i, ps in passages(p["text"]):
            for topic in p.get("topics") or ["sar_rule"]:
                pid = f"{p['pmcid']}:{i}:{topic}"
                if pid not in done:
                    jobs.append((pid, p, ps))
    print(f"papers={len(papers)} passages_todo={len(jobs)} already_done={len(done)}", flush=True)
    quant = os.environ.get("K2_QUANT") or None          # None = bf16 weights (pre-registered); "fp8" only as a recorded fallback on 24 GB GPUs
    max_seqs = int(os.environ.get("K2_MAX_SEQS", "64"))
    kw = dict(model=MODEL, dtype="bfloat16", max_model_len=6144, gpu_memory_utilization=0.92, enable_prefix_caching=True, max_num_seqs=max_seqs)
    if quant:
        kw["quantization"] = quant
    json.dump({"model": MODEL, "quantization": quant, "max_num_seqs": max_seqs, "prompt_version": PROMPT_VERSION,
               "gpu": os.popen("nvidia-smi --query-gpu=name,memory.total --format=csv,noheader").read().strip()},
              open(os.path.join(a.outdir, "extract_config.json"), "w"))
    llm = LLM(**kw)
    tok = llm.get_tokenizer()

    def chat(user):
        return tok.apply_chat_template([{"role": "user", "content": user}], tokenize=False, add_generation_prompt=True, enable_thinking=False)

    sp_ext = SamplingParams(temperature=0.0, max_tokens=1400)
    sp_ent = SamplingParams(temperature=0.0, max_tokens=3)
    ntext = {p["pmcid"]: norm(p["text"]) for p in papers}
    stats_path = os.path.join(a.outdir, "stats.json")
    stats = json.load(open(stats_path)) if os.path.exists(stats_path) else {
        "raw_rules": 0, "parse_fail_passages": 0, "verified": 0, "rejected": {}, "entail_yes": 0, "entail_no": 0,
        "prompt_tokens": 0, "completion_tokens": 0, "gen_seconds": 0.0, "passages": 0}
    t_all = time.time()
    for c0 in range(0, len(jobs), a.chunk):
        chunk = jobs[c0:c0 + a.chunk]
        t0 = time.time()
        outs = llm.generate([chat(INSTR[pid.rsplit(":", 1)[1]] + "\n\nPASSAGE:\n" + ps) for pid, _, ps in chunk], sp_ext)
        ver, rej, ent_prompts, ent_idx = [], [], [], []
        for (pid, p, ps), o in zip(chunk, outs):
            txt = o.outputs[0].text
            stats["prompt_tokens"] += len(o.prompt_token_ids)
            stats["completion_tokens"] += len(o.outputs[0].token_ids)
            stats["passages"] += 1
            arr = parse_json_array(txt)
            if arr is None:
                stats["parse_fail_passages"] += 1
                continue
            pn = norm(ps)
            for r in arr:
                if not isinstance(r, dict):
                    continue
                stats["raw_rules"] += 1
                topic = pid.rsplit(":", 1)[1]
                r["topic"] = topic
                ok, why = verify_rule(r, ntext[p["pmcid"]], pn)
                if not ok:
                    key = why.split(":")[0]
                    stats["rejected"][key] = stats["rejected"].get(key, 0) + 1
                    rej.append({"pmcid": p["pmcid"], "passage": pid, "reason": why, "quote": r.get("quote")})
                    continue
                rule = {
                    "rule_id": rule_id(p["pmcid"], r["quote"], r["statement"]),
                    "statement": norm(r["statement"]), "direction": r["direction"], "property": r["property"],
                    "substructure_class": r["substructure_class"], "scope": norm(str(r["scope"])),
                    "effect_size": r.get("effect_size"), "assay": norm(str(r.get("assay") or "")),
                    "evidence_tier": p["tier"], "quote": norm(r["quote"]), "confidence": float(r["confidence"]),
                    "citation": {"pmcid": p["pmcid"], "doi": p.get("doi"), "title": p.get("title"), "year": p.get("year"),
                                 "journal": p.get("journal"), "authors": p.get("authors"),
                                 "url": f"https://europepmc.org/article/PMC/{p['pmcid']}"},
                    "access_date": time.strftime("%Y-%m-%d"), "extracted_by": f"{MODEL}/{PROMPT_VERSION}",
                    "source_text_sha256": p["text_sha256"], "passage_id": pid, "topic": topic}
                for k in EXTRA_KEYS:
                    if r.get(k) not in (None, "", []):
                        rule[k] = r[k]
                ver.append(rule)
        for j, r in enumerate(ver):
            ent_prompts.append(chat(f"Quote: \"{r['quote']}\"\nStatement: {r['statement']}\nDirection: {r['direction']}\n"
                                    "Does the quote, read on its own, directly support this statement AND this direction? Answer YES or NO only."))
            ent_idx.append(j)
        if ent_prompts:
            eo = llm.generate(ent_prompts, sp_ent)
            for j, o in zip(ent_idx, eo):
                yes = o.outputs[0].text.strip().upper().startswith("YES")
                ver[j]["proxy_entailment"] = "YES" if yes else "NO"
                stats["entail_yes" if yes else "entail_no"] += 1
        stats["verified"] += len(ver)
        stats["gen_seconds"] += time.time() - t0
        with open(os.path.join(a.outdir, "rules_verified.jsonl"), "a") as fh:
            for r in ver:
                fh.write(json.dumps(r) + "\n")
        with open(os.path.join(a.outdir, "rules_rejected.jsonl"), "a") as fh:
            for r in rej:
                fh.write(json.dumps(r) + "\n")
        with open(done_path, "a") as fh:
            fh.write("\n".join(pid for pid, _, _ in chunk) + "\n")
        json.dump(stats, open(stats_path, "w"))
        print(f"chunk {c0 // a.chunk} passages={len(chunk)} verified={len(ver)} rejected={len(rej)} sec={time.time() - t0:.0f}", flush=True)
    stats["wall_seconds_this_run"] = time.time() - t_all
    json.dump(stats, open(stats_path, "w"))


if __name__ == "__main__":
    main()
