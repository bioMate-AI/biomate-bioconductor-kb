"""Build the domain-BACKGROUND corpus (concepts only, facts stripped) for CPT.

Source 1: Galaxy Training Network (CC-BY). Per tutorial.md keep the CONCEPT scaffold — frontmatter
questions/objectives/key_points + narrative prose — and STRIP the facts/procedure: hands_on boxes
(Galaxy clicks + tool params), code fences, Jinja/snippets, images, param tables. Output concept docs.

  python build_background_corpus.py --gtn /tmp/sftaudit/gtn --out /tmp/sftaudit/background_corpus.jsonl

Extensible: add --bioconductor / --pmc-reviews etc. later; each appends concept docs with provenance.
"""
import argparse, json, os, re, glob

FM = re.compile(r"^---\s*\n(.*?)\n---\s*\n", re.S)
CODE = re.compile(r"```.*?```", re.S)
JINJA = re.compile(r"\{\%.*?\%\}|\{\{.*?\}\}", re.S)
IMG = re.compile(r"!\[[^\]]*\]\([^)]*\)|\{\%\s*include.*?\%\}")
# GTN agenda/box markers that start PROCEDURE (strip the whole blockquote box)
PROC_BOX = re.compile(r"^>\s*<(hands_on|question|solution|tip)-title>", re.I)
UI = re.compile(r"\b(click|select|rename|drag|press the|in the .* menu|galaxy|upload|history|dataset)\b", re.I)


def yaml_list(fm, key):
    # grab a simple "key:\n- a\n- b" or "key: val" block from frontmatter (no yaml dep)
    m = re.search(rf"(?m)^{key}:\s*(.*)$", fm)
    if not m:
        return []
    if m.group(1).strip():
        return [m.group(1).strip().strip("'\"")]
    out = []
    for line in fm[m.end():].splitlines():
        if re.match(r"^\s*-\s+", line):
            out.append(re.sub(r"^\s*-\s+", "", line).strip().strip("'\""))
        elif line.strip() and not line.startswith(" "):
            break
    return out


def strip_proc_boxes(body):
    out, skip = [], False
    for line in body.splitlines():
        if PROC_BOX.match(line):
            skip = True; continue
        if skip:
            if line.startswith(">"):
                continue
            skip = False
        out.append(line)
    return "\n".join(out)


def clean_prose(body):
    body = CODE.sub(" ", body); body = JINJA.sub(" ", body); body = IMG.sub(" ", body)
    body = strip_proc_boxes(body)
    paras, buf = [], []
    for line in body.splitlines():
        s = line.strip()
        if not s:
            if buf:
                paras.append(" ".join(buf)); buf = []
            continue
        if s.startswith(("#", ">", "|", "-", "*", "{", "<")) or s.startswith("!["):
            continue                      # headings/boxes/tables/bullets/markup
        if UI.search(s) and len(s) < 160:  # drop short Galaxy-UI instruction lines
            continue
        buf.append(re.sub(r"\[([^\]]+)\]\([^)]*\)", r"\1", s))   # unlink markdown links
    if buf:
        paras.append(" ".join(buf))
    # keep only real prose paragraphs (>= 120 chars, has a verb-ish density)
    return [p for p in paras if len(p) >= 120 and p.count(" ") >= 18]


# bio/bioinformatics science topics only — drop platform-ops (admin/galaxy-interface/dev/teaching/
# contributing/community/fair) and other-domain (climate/materials-science/digital-humanities/ecology)
BIO_TOPICS = {"transcriptomics", "single-cell", "proteomics", "statistics", "data-science",
              "genome-annotation", "microbiome", "variant-analysis", "assembly", "sequence-analysis",
              "metabolomics", "epigenetics", "computational-chemistry", "evolution",
              "synthetic-biology", "imaging", "introduction", "visualisation"}


def gtn(root):
    docs = []
    for f in glob.glob(os.path.join(root, "topics", "*", "tutorials", "*", "tutorial.md")):
        topic = f.split("/topics/")[1].split("/")[0]
        if topic not in BIO_TOPICS:
            continue
        raw = open(f, encoding="utf-8", errors="replace").read()
        m = FM.search(raw); fm = m.group(1) if m else ""; body = raw[m.end():] if m else raw
        title = (yaml_list(fm, "title") or ["?"])[0]
        q = yaml_list(fm, "questions"); obj = yaml_list(fm, "objectives"); kp = yaml_list(fm, "key_points")
        header = f"# {title} ({topic})\n"
        if q: header += "Questions: " + "; ".join(q) + "\n"
        if obj: header += "Learning objectives: " + "; ".join(obj) + "\n"
        if kp: header += "Key points: " + "; ".join(kp) + "\n"
        prose = clean_prose(body)
        text = header + ("\n" + "\n\n".join(prose) if prose else "")
        if len(text) >= 300:   # must have real concept content
            docs.append({"text": text, "source": "gtn", "topic": topic, "title": title,
                         "license": "CC-BY-4.0", "chars": len(text), "concept_paras": len(prose)})
    return docs


def _sc_v2_concept(raw):
    """From scientific_context_v2 JSON keep CONCEPT fields (when_to_use/do_not_use/assumptions/
    pitfalls/description), drop FACT fields (primary_inputs/outputs/parameters)."""
    try:
        j = json.loads(raw)
    except Exception:
        return raw if len(raw) > 80 and "{" not in raw[:3] else ""
    parts = []
    for k in ("description", "when_to_use", "do_not_use_when", "key_assumptions", "common_pitfalls",
              "scientific_rationale", "biological_context"):
        v = j.get(k)
        if isinstance(v, list):
            v = "; ".join(str(x) for x in v)
        if v and isinstance(v, str) and len(v) > 10:
            parts.append(f"{k.replace('_', ' ').capitalize()}: {v}")
    return "\n".join(parts)


def db(path):
    import sqlite3
    c = sqlite3.connect(f"file:{path}?mode=ro", uri=True); c.row_factory = sqlite3.Row
    docs = []
    # tools — prefer enriched scientific_context_v2 (concepts) + scientific_context + help_text + usage_guide
    for r in c.execute("select name,category,scientific_context_v2,scientific_context,help_text,usage_guide,description "
                       "from tools"):
        blocks = []
        if r["scientific_context_v2"]:
            blocks.append(_sc_v2_concept(r["scientific_context_v2"]))
        for col in ("scientific_context", "usage_guide", "help_text", "description"):
            v = r[col]
            if v and len(v.strip()) > 80 and "{" not in v[:3]:
                blocks.append(v.strip())
        text = f"# {r['name']} ({r['category'] or 'tool'})\n" + "\n\n".join(b for b in blocks if b)
        if len(text) >= 220:
            docs.append({"text": text[:6000], "source": "db_tool", "topic": (r["category"] or "tool"),
                         "title": r["name"], "chars": min(len(text), 6000)})
    # workflows — rich CONCEPT doc: description + input/output TYPES (generalizable) + biological
    # PHASES & the steps in each phase (methodology structure). Specific param names/values are NOT
    # included (those are retrieval facts).
    def _types(raw):
        try:
            v = json.loads(raw)
            return ", ".join(str(x) for x in v) if isinstance(v, list) else str(v)
        except Exception:
            return (raw or "").strip()

    def _phases(raw):
        try:
            sm = json.loads(raw or "[]")
        except Exception:
            return ""
        from collections import OrderedDict
        ph = OrderedDict()
        for s in sm if isinstance(sm, list) else []:
            if not isinstance(s, dict):
                continue
            lab = s.get("phase") or s.get("phase_label") or "Steps"
            step = s.get("step") or s.get("name") or s.get("tool")
            if step:
                ph.setdefault(lab, []).append(str(step))
        return "\n".join(f"- {lab}: " + "; ".join(steps) for lab, steps in ph.items())

    for r in c.execute("select name,domain,description,input_types,output_types,step_metadata from workflows"):
        parts = [f"# {r['name']} ({r['domain']})"]
        if r["description"] and len(r["description"].strip()) > 40:
            parts.append(r["description"].strip())
        it = _types(r["input_types"]); ot = _types(r["output_types"])
        if it:
            parts.append(f"Required input data types: {it}")
        if ot:
            parts.append(f"Produces output data types: {ot}")
        ph = _phases(r["step_metadata"])
        if ph:
            parts.append("Biological analysis phases and the steps in each phase:\n" + ph)
        text = "\n".join(parts)
        if len(text) >= 160:   # must carry real methodology content
            docs.append({"text": text[:5000], "source": "db_workflow", "topic": r["domain"] or "workflow",
                         "title": r["name"], "chars": min(len(text), 5000)})
    # cryo-EM protocol knowledge (key_principles/use_cases/limitations/strategies) — rich concepts
    try:
        for r in c.execute("select display_name,use_cases,limitations,key_principles,picking_strategy,"
                           "refinement_strategy,model_building from cryo_em_protocols"):
            parts = [f"{k.replace('_', ' ')}: {r[k]}" for k in r.keys()
                     if k != "display_name" and r[k] and len(str(r[k])) > 40]
            if parts:
                docs.append({"text": f"# Cryo-EM: {r['display_name']}\n" + "\n".join(parts), "source": "db_cryoem",
                             "topic": "cryo_em", "title": r["display_name"], "chars": 0})
        for r in c.execute("select chunk_text from cryo_em_chunks where length(chunk_text)>120"):
            docs.append({"text": r["chunk_text"].strip()[:4000], "source": "db_cryoem_lit", "topic": "cryo_em",
                         "title": "", "chars": 0})
    except Exception:
        pass
    for d in docs:
        d["chars"] = len(d["text"])
    return docs


import urllib.request, urllib.parse, time
WIKIBOOKS = ["Pharmacology", "Cell_Biology", "Biochemistry", "Genetics", "Structural_Biochemistry",
             "Molecular_Biology", "Proteomics", "Next_Generation_Sequencing_(NGS)", "Bioinformatics",
             "Human_Physiology", "Microbiology", "Immunology"]


def _api(params):
    url = "https://en.wikibooks.org/w/api.php?" + urllib.parse.urlencode({**params, "format": "json"})
    req = urllib.request.Request(url, headers={"User-Agent": "BioMate-corpus/1.0 (research)"})
    return json.load(urllib.request.urlopen(req, timeout=40))


def wikibooks(books):
    docs = []
    for book in books:
        try:
            pages, cont = [], None
            for _ in range(6):   # paginate allpages under the book prefix
                p = {"action": "query", "list": "allpages", "apprefix": book + "/", "apnamespace": "0", "aplimit": "500"}
                if cont:
                    p["apcontinue"] = cont
                d = _api(p); pages += [x["title"] for x in d.get("query", {}).get("allpages", [])]
                cont = d.get("continue", {}).get("apcontinue")
                if not cont:
                    break
            pages = [book] + pages
            for title in pages[:120]:
                try:
                    d = _api({"action": "query", "prop": "extracts", "explaintext": "1", "titles": title})
                    for pg in d.get("query", {}).get("pages", {}).values():
                        txt = (pg.get("extract") or "").strip()
                        txt = re.sub(r"\n{3,}", "\n\n", txt)
                        if len(txt) >= 400 and txt.count(" ") >= 60:
                            docs.append({"text": txt[:8000], "source": "wikibook", "topic": book.lower(),
                                         "title": title, "license": "CC-BY-SA-3.0", "chars": min(len(txt), 8000)})
                    time.sleep(0.15)
                except Exception:
                    continue
        except Exception as e:
            print(f"  wikibook {book} failed: {e}")
    return docs


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--gtn", default=""); ap.add_argument("--db", default=""); ap.add_argument("--out", required=True)
    ap.add_argument("--wikibooks", action="store_true")
    a = ap.parse_args()
    docs = []
    if a.db:
        docs += db(a.db)
    if a.gtn:
        docs += gtn(a.gtn)
    if a.wikibooks:
        docs += wikibooks(WIKIBOOKS)
    import collections
    by_src = collections.Counter(d["source"] for d in docs)
    tok_by_src = collections.Counter()
    for d in docs:
        tok_by_src[d["source"]] += d["chars"] // 4
    toks = sum(d["chars"] for d in docs) // 4
    with open(a.out, "w") as f:
        for d in docs:
            f.write(json.dumps(d) + "\n")
    print(f"BACKGROUND CORPUS: {len(docs)} concept docs, ~{toks:,} tokens -> {a.out}")
    print("by source (docs):", dict(by_src.most_common()))
    print("by source (~tokens):", {k: f"{v:,}" for k, v in tok_by_src.most_common()})


if __name__ == "__main__":
    raise SystemExit(main())
