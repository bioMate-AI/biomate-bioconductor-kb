"""Extract the tools DB into a DEDUPED mid-training corpus with per-field preprocessing.

Measured field overlap (containment) drives the design:
  rawText ⊂ htmlContent = 0.99  -> htmlContent is redundant; use only as rawText fallback
  usage_guide ↔ examples ~0.95  -> near-dupes; keep one
  usage_guide/description mostly ⊂ rawText/help_text -> fold in, dedup
  help_text ↔ rawText ~0.5 each -> both partly unique; keep both, dedup shared lines
  scientific_context -> most UNIQUE (highest marginal value) but LLM-generated -> quality-gate

Per-field preprocessing (each field is different):
  htmlContent  : HTML->text, then discard (fallback only)
  rawText      : strip residual markup + boilerplate + whitespace  (prose)
  help_text    : PRESERVE CLI structure (flag/usage lines)          (params/usage)
  usage_guide  : treat as CODE (keep fences), dedup vs examples      (code)
  examples     : treat as CODE                                        (code)
  scientific_context[_v2]: prose clean, prefer v2, quality-gate       (narrative)
  description  : short abstract -> catalog only, NOT mid-train (redundant)
  parameters/inputs/outputs/edam : VERBALIZE (structured->sentences)  (dual-use)

Merge per tool -> one deduped doc via line-level near-dedup. Emits tools_corpus.jsonl + a manifest
with per-field kept/dropped token counts and dedup rate."""
import sqlite3, os, re, json, html as _html, hashlib, collections
REPO="/Users/kky/biomate-review"; OUT=f"{REPO}/docs/20260912_onprem_llm/midtrain_corpus"
DB=f"{REPO}/backend/database/galaxy_ai_tools.db"

def strip_html(s):
    s=re.sub(r"(?is)<(script|style)[^>]*>.*?</\1>"," ",s or "")
    s=re.sub(r"(?s)<[^>]+>"," ",s); return _html.unescape(s)
def norm_ws(s): return re.sub(r"[ \t]+"," ", re.sub(r"\n{3,}","\n\n",(s or "").strip()))
def norm_line(l): return re.sub(r"[^a-z0-9]+"," ", l.lower()).strip()
def toks(s): return int(len(re.findall(r"\S+", s or ""))*1.33)

BOILER=re.compile(r"(?i)^(license|copyright|table of contents|download|edit on github|\[!\[|badge)")
GALAXY_LEAK=re.compile(r"(base\.mako|Content-Type|text/html|/static/dist/|<head>|rel=\"index\"|charset=)")
def strip_noise(s):
    """strip HTML tags + drop leaked Galaxy page lines + drop JSON-ish lines (audit: rawText/examples
    carried HTML + Galaxy page markup + raw JSON that verbalization didn't cover)."""
    s=strip_html(s or "")
    out=[]
    for l in s.split("\n"):
        if GALAXY_LEAK.search(l): continue
        t=l.strip()
        if len(t)>=8 and sum(c in '{}[]":,' for c in t)/len(t) > 0.35: continue  # JSON-ish line
        out.append(l)
    return "\n".join(out)
def clean_prose(s):
    s=norm_ws(strip_noise(s)); out=[]
    for l in s.split("\n"):
        if BOILER.match(l.strip()): continue
        out.append(l)
    return "\n".join(out).strip()

SCI_SKIP={"information_sources","confidence","from_documentation","from_llm_knowledge",
          "error","raw","metadata","source"}
def _humanize(k): return str(k).replace("_"," ").strip().capitalize()
def _render(v):
    if isinstance(v,list): return "; ".join(_render(x) for x in v if x not in (None,"",[],{}))
    if isinstance(v,dict):
        return "; ".join(f"{_humanize(k)}: {_render(x)}" for k,x in v.items()
                         if k not in SCI_SKIP and x not in (None,"",[],{}))
    return str(v)
def verbalize_sci(raw):
    """scientific_context is JSON (two schemas). Parse -> verbalize to sentences; drop failed
    generations (error key / empty). Non-JSON substantial prose falls back to clean text."""
    raw=(raw or "").strip()
    if not raw: return None
    try: d=json.loads(raw)
    except Exception:
        p=clean_prose(raw); return p if len(p)>=80 else None   # legacy prose fallback
    if not isinstance(d,dict) or d.get("error"): return None    # failed generation
    lines=[]
    for k,v in d.items():
        if k in SCI_SKIP: continue
        rv=_render(v)
        if rv and len(rv)>2: lines.append(f"{_humanize(k)}: {rv}.")
    text=" ".join(lines)
    return text if len(text)>=60 else None                      # thin -> drop

def verbalize_help(raw):
    """help_text is often JSON {what_it_does, how_to_use, input_description, output_description,
    examples, full_text}. Extract the meaningful values (audit: raw JSON was leaking into 97% of docs).
    Non-JSON -> plain text (noise-stripped)."""
    raw=(raw or "").strip()
    if not raw: return ""
    if raw.startswith("{"):
        try: d=json.loads(raw)
        except Exception: return strip_noise(raw)
        if isinstance(d, dict):
            order=["what_it_does","how_to_use","input_description","output_description","examples","full_text"]
            segs=[]
            for k in order:
                v=d.get(k)
                if isinstance(v,str) and v.strip(): segs.append(strip_noise(v.strip()))
            for k,v in d.items():  # any other populated string keys
                if k not in order and isinstance(v,str) and v.strip(): segs.append(strip_noise(v.strip()))
            return "\n".join(segs).strip()
    return strip_noise(raw)

def verbalize_params(raw):
    try: p=json.loads(raw)
    except: return ""
    items=p if isinstance(p,list) else p.get("parameters",p) if isinstance(p,dict) else []
    if isinstance(items,dict): items=list(items.values())
    lines=[]
    for it in items if isinstance(items,list) else []:
        if not isinstance(it,dict): continue
        nm=it.get("name") or it.get("argument") or ""
        if not nm: continue
        t=it.get("type",""); d=it.get("description") or it.get("help") or ""
        dv=it.get("default"); req="required" if (it.get("optional") is False) else "optional"
        seg=f"Parameter {nm}"
        if t: seg+=f" ({t}, {req})"
        if dv not in (None,""): seg+=f", default {dv}"
        if d: seg+=f": {d}"
        lines.append(seg+".")
    return " ".join(lines[:60])

def dedup_append(base_lines_seen, text):
    """append lines from text whose normalized form isn't already present; returns kept text."""
    kept=[]
    for l in text.split("\n"):
        nl=norm_line(l)
        if len(nl)<4:  # keep short structural lines (blank, code punctuation) without dedup weight
            kept.append(l); continue
        if nl in base_lines_seen: continue
        base_lines_seen.add(nl); kept.append(l)
    return "\n".join(kept).strip()

def main():
    c=sqlite3.connect(f"file:{DB}?mode=ro",uri=True); c.row_factory=sqlite3.Row
    cols=["tool_id","name","version","category","rawText","htmlContent","help_text","usage_guide",
          "examples","scientific_context","scientific_context_v2","description","parameters",
          "inputs","outputs","edam_operations","edam_topics"]
    rows=[dict(r) for r in c.execute(f"select {','.join(cols)} from tools")]
    kept_tok=collections.Counter(); drop_tok=collections.Counter()
    docs=[]; seen_doc=set()
    for r in rows:
        name=(r.get("name") or r.get("tool_id") or "").strip()
        if not name: continue
        seen_lines=set(); parts=[f"# Tool: {name}"]
        if r.get("category"): parts.append(f"Category: {r['category']}")

        # 1) base prose: rawText, fallback to html-stripped htmlContent
        raw=r.get("rawText") or ""
        if not raw and r.get("htmlContent"): raw=strip_html(r["htmlContent"]);
        if r.get("htmlContent"): drop_tok["htmlContent(redundant)"]+=toks(strip_html(r["htmlContent"]))
        base=clean_prose(raw)
        if base:
            kept=dedup_append(seen_lines, base); parts.append(kept); kept_tok["rawText"]+=toks(kept)

        # 2) help_text: JSON-structured (what_it_does/full_text/...) -> extract values, dedup vs base
        if r.get("help_text"):
            ht=norm_ws(verbalize_help(r["help_text"])); kept=dedup_append(seen_lines, ht)
            if kept: parts.append("## Usage / help\n"+kept); kept_tok["help_text"]+=toks(kept); drop_tok["help_text(dup)"]+=toks(ht)-toks(kept)

        # 3) code: examples preferred, usage_guide only if not dup of examples (strip HTML/Galaxy leak)
        code=""
        if r.get("examples"): code=norm_ws(strip_noise(r["examples"]))
        if r.get("usage_guide"):
            ug=norm_ws(strip_noise(r["usage_guide"]))
            if not code or norm_line(ug)[:200] not in norm_line(code): code=(code+"\n\n"+ug).strip() if code else ug
            else: drop_tok["usage_guide(dup_of_examples)"]+=toks(ug)
        if code:
            kept=dedup_append(seen_lines, code)
            if kept: parts.append("## Examples\n"+kept); kept_tok["examples/usage"]+=toks(kept)

        # 4) scientific_context: JSON -> VERBALIZE (prefer v2), drop failed generations, mostly unique
        sci_raw=r.get("scientific_context_v2") or r.get("scientific_context") or ""
        sc=verbalize_sci(sci_raw)
        if sc:
            kept=dedup_append(seen_lines, sc)
            if kept: parts.append("## Scientific context\n"+kept); kept_tok["scientific_context(verbalized)"]+=toks(kept)
        elif sci_raw: drop_tok["scientific_context(failed_gen)"]+=toks(sci_raw)

        # 5) verbalize structured params (dual-use; different pipeline)
        pv=verbalize_params(r.get("parameters") or "")
        if pv: parts.append("## Parameters\n"+pv); kept_tok["parameters(verbalized)"]+=toks(pv)

        # description intentionally EXCLUDED from mid-train (85% redundant); kept for catalog elsewhere
        if r.get("description"): drop_tok["description(catalog_only)"]+=toks(r["description"])

        doc="\n\n".join(p for p in parts if p and p.strip())
        if toks(doc)<30: continue
        h=hashlib.md5(re.sub(r"[^a-z0-9]+"," ",doc.lower()).encode()).hexdigest()
        if h in seen_doc: drop_tok["cross_tool_dup"]+=toks(doc); continue
        seen_doc.add(h); docs.append({"text":doc,"source":"tools_db","tool":name,"version":r.get("version")})

    os.makedirs(OUT,exist_ok=True)
    with open(f"{OUT}/tools_corpus.jsonl","w") as f:
        for d in docs: f.write(json.dumps(d)+"\n")
    total_kept=sum(kept_tok.values()); total_drop=sum(drop_tok.values())
    manifest={"n_tools_in":len(rows),"n_docs_out":len(docs),
              "kept_tokens":total_kept,"dropped_tokens":total_drop,
              "dedup_ratio":round(total_drop/max(total_kept+total_drop,1),3),
              "kept_by_field":dict(kept_tok.most_common()),
              "dropped_by_reason":dict(drop_tok.most_common())}
    json.dump(manifest,open(f"{OUT}/tools_corpus_manifest.json","w"),indent=2)
    print(f"TOOLS_CORPUS: {len(docs)} docs, {total_kept:,} kept tok, {total_drop:,} dropped tok "
          f"(dedup/removed {manifest['dedup_ratio']:.0%})")
    print("kept by field:", dict(kept_tok.most_common()))
    print("dropped:", dict(drop_tok.most_common()))

if __name__=="__main__": raise SystemExit(main())
