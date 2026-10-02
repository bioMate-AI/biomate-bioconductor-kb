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


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--gtn", default=""); ap.add_argument("--out", required=True)
    a = ap.parse_args()
    docs = []
    if a.gtn:
        docs += gtn(a.gtn)
    import collections
    by_topic = collections.Counter(d["topic"] for d in docs)
    toks = sum(d["chars"] for d in docs) // 4
    with open(a.out, "w") as f:
        for d in docs:
            f.write(json.dumps(d) + "\n")
    print(f"BACKGROUND CORPUS: {len(docs)} concept docs, ~{toks:,} tokens -> {a.out}")
    print("by topic:", dict(by_topic.most_common()))


if __name__ == "__main__":
    raise SystemExit(main())
