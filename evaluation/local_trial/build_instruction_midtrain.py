"""Task-aware (instruction) mid-train data — converts raw domain corpora into TASK-STRUCTURED examples so
continued pre-training rehearses the ultimate-goal skills instead of flat next-token LM (which HURT us:
degenerate KG triples raised perplexity but transferred nothing — see 20260928_ROOT_CAUSE_WHOLE_PROCESS.md
D4). Division of labor: mid-train teaches STABLE/transferable knowledge+reasoning; the VOLATILE catalog
routing stays in open-book SFT+DPO+retrieval (build_contrastive.py).

Generators (deterministic unless noted):
  kg_multihop  : parse verbalized KG triples -> entity adjacency -> 2-hop REASONING QA (fixes degenerate KG)
  tooldoc_qa   : tool/workflow catalog fields -> usage/param knowledge QA
  lit_extract  : (LLM, sampled) abstract -> method/organism/finding extraction QA

Emits {"text": "<instruction>\n\n<response>", "source": "task_<gen>"} for causal-LM mid-train. Usage:
  python build_instruction_midtrain.py --kg kg_corpus.jsonl --dbcat db_catalog_corpus.jsonl \
     --lit literature_corpus.jsonl --out instruction_midtrain.jsonl \
     --kg-n 200000 --tooldoc-n 60000 --lit-n 40000
"""
import argparse, json, os, re, random, collections, time, urllib.request
from concurrent.futures import ThreadPoolExecutor
random.seed(23)

TRIPLE = re.compile(r"^(\S+) \(([^)]+)\) (.+?) (\S+) \(([^)]+)\)\.\s*$")


def kg_multihop(path, n, cap_lines=3_000_000):
    """Build 2-hop reasoning QA from verbalized KG triples. Sample lines to bound memory."""
    adj = collections.defaultdict(list); types = {}
    seen = 0
    for line in open(path):
        if seen >= cap_lines:
            break
        try:
            t = json.loads(line).get("text", "")
        except Exception:
            continue
        m = TRIPLE.match(t)
        if not m:
            continue
        h, ht, rel, tl, tt = m.groups()
        adj[h].append((rel, tl)); types[h] = ht; types[tl] = tt
        seen += 1
    ents = [e for e in adj if adj[e]]
    random.shuffle(ents)
    out = []
    for a in ents:
        if len(out) >= n:
            break
        r1, b = random.choice(adj[a])
        if b not in adj or not adj[b]:
            continue
        r2, c = random.choice(adj[b])
        if c == a:
            continue
        q = (f"In a biomedical knowledge graph, {a} ({types.get(a,'entity')}) {r1} {b}. "
             f"{b} {r2} {c} ({types.get(c,'entity')}). "
             f"Question: through which intermediate entity is {a} connected to {c}, and by what relations?")
        ans = (f"{a} is connected to {c} via {b}: {a} {r1} {b}, and {b} {r2} {c}. "
               f"So {a} links to {c} through the intermediate {b}.")
        out.append({"text": q + "\n\n" + ans, "source": "task_kg_multihop"})
    return out


def _field(js, k):
    try:
        d = json.loads(js); return (d.get(k) or "").strip()
    except Exception:
        return ""


def tooldoc_qa(path, n):
    """Usage/param QA from catalog tool + workflow entries (only where fields are non-empty)."""
    out = []
    for line in open(path):
        if len(out) >= n:
            break
        try:
            t = json.loads(line).get("text", "")
        except Exception:
            continue
        # workflow entry
        m = re.search(r"^Name:\s*(.+)$", t, re.M)
        if m and "Description:" in t:
            name = m.group(1).strip()
            desc = (re.search(r"^Description:\s*(.+)$", t, re.M) or [None, ""])[1].strip() if re.search(r"^Description:\s*(.+)$", t, re.M) else ""
            inp = (re.search(r"^Inputs:\s*(.+)$", t, re.M).group(1).strip() if re.search(r"^Inputs:\s*(.+)$", t, re.M) else "")
            out_t = (re.search(r"^Outputs:\s*(.+)$", t, re.M).group(1).strip() if re.search(r"^Outputs:\s*(.+)$", t, re.M) else "")
            if desc and len(desc) > 30:
                out.append({"text": f"What does the {name} workflow do, and what are its inputs and outputs?\n\n"
                                    f"The {name} workflow {desc}" + (f" It takes {inp} as input." if inp else "")
                                    + (f" It produces {out_t}." if out_t else ""), "source": "task_tooldoc"})
            continue
        # tool entry with embedded JSON help
        mt = re.search(r"`([^`]+)` tool", t)
        if mt:
            name = mt.group(1)
            jstart = t.find("{")
            what = _field(t[jstart:], "what_it_does") if jstart != -1 else ""
            howto = _field(t[jstart:], "how_to_use") if jstart != -1 else ""
            body = what or howto
            if body and len(body) > 30:
                out.append({"text": f"What is the {name} tool used for?\n\nThe {name} tool {body}", "source": "task_tooldoc"})
    random.shuffle(out)
    return out[:n]


def lit_findings(path, n, workers=12):
    """(LLM) literature -> BioMate-ALIGNED tasks: interpret results -> FINDINGS, and draw CONCLUSIONS +
    implications/next-steps. Mirrors BioMate's findings_interpretation / analyze_results / conclusion_drawing
    skills (NOT generic knowledge trivia). Prefers full-text (real Results/Discussion) over bare abstracts."""
    key = os.environ.get("OPENAI_API_KEY")
    if not key:
        print("[lit_findings] no OPENAI_API_KEY — skipping LLM literature tasks", flush=True)
        return []
    model = os.environ.get("PARA_MODEL", "gpt-5-mini")
    texts = []
    for line in open(path):
        try:
            t = json.loads(line).get("text", "")
        except Exception:
            continue
        if 500 < len(t) < 12000:
            texts.append(t)
        if len(texts) >= n * 4:
            break
    random.shuffle(texts); texts = texts[:n]

    def one(t):
        ask = ("You are building training data that teaches an agent to INTERPRET analysis results and "
               "GENERATE FINDINGS — like a bioinformatician reading pipeline outputs. From this biomedical "
               "text, produce ONE example as JSON with THREE fields, all grounded ONLY in the text:\n"
               "  \"results\": the study's concrete RESULTS/DATA (numbers, effects, comparisons) as an "
               "analyst would see them — no interpretation;\n"
               "  \"findings\": the key FINDINGS interpreting those results (what they mean);\n"
               "  \"conclusion\": the CONCLUSION + implications or next steps.\n"
               "Reply ONLY the JSON.\n\nTEXT:\n" + t[:8000])
        body = json.dumps({"model": model, "messages": [{"role": "user", "content": ask}],
                           "max_completion_tokens": 600, "reasoning_effort": "low"}).encode()
        for _ in range(3):
            try:
                d = json.load(urllib.request.urlopen(urllib.request.Request(
                    "https://api.openai.com/v1/chat/completions", data=body,
                    headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json"}), timeout=90))
                o = d["choices"][0]["message"]["content"]
                m = re.search(r"\{.*\}", o, re.S)
                if not m:
                    return []
                r = json.loads(m.group(0))
                res, fnd, con = (r.get("results") or "").strip(), (r.get("findings") or "").strip(), (r.get("conclusion") or "").strip()
                out = []
                if res and fnd and len(res) > 40:
                    out.append({"text": f"Here are the analysis results:\n{res}\n\nInterpret these results and "
                                        f"state the key findings.\n\n{fnd}", "source": "task_findings_interpretation"})
                if res and con and len(con) > 40:
                    out.append({"text": f"Given these results:\n{res}\n\nWhat can be concluded, and what are the "
                                        f"implications or next steps?\n\n{con}", "source": "task_conclusion_drawing"})
                return out
            except Exception:
                time.sleep(1.5)
        return []
    out = []
    with ThreadPoolExecutor(max_workers=workers) as ex:
        for i, rs in enumerate(ex.map(one, texts)):
            out.extend(rs)
            if i % 500 == 0:
                print(f"  lit_findings {i}/{len(texts)} -> {len(out)}", flush=True)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--kg", default=""); ap.add_argument("--dbcat", default=""); ap.add_argument("--lit", default="")
    ap.add_argument("--out", required=True)
    ap.add_argument("--kg-n", type=int, default=200000); ap.add_argument("--tooldoc-n", type=int, default=60000)
    ap.add_argument("--lit-n", type=int, default=40000)
    a = ap.parse_args()
    allrows = []
    if a.kg and os.path.exists(a.kg):
        r = kg_multihop(a.kg, a.kg_n); print(f"kg_multihop: {len(r):,}", flush=True); allrows += r
    if a.dbcat and os.path.exists(a.dbcat):
        r = tooldoc_qa(a.dbcat, a.tooldoc_n); print(f"tooldoc_qa: {len(r):,}", flush=True); allrows += r
    if a.lit and os.path.exists(a.lit):
        r = lit_findings(a.lit, a.lit_n); print(f"lit_findings: {len(r):,}", flush=True); allrows += r
    random.shuffle(allrows)
    with open(a.out, "w") as f:
        for r in allrows:
            f.write(json.dumps(r) + "\n")
    print(f"INSTRUCTION MIDTRAIN: {len(allrows):,} task examples -> {a.out} "
          f"({dict(collections.Counter(r['source'] for r in allrows))})", flush=True)


if __name__ == "__main__":
    raise SystemExit(main())
