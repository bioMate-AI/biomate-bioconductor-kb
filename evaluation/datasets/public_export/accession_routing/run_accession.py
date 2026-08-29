#!/usr/bin/env python3
"""RealBio task #9 — accession_routing (L1 decision). Predict fine-grained DATA MODALITY
from an accession. --data selects the item set (data.jsonl [v1] or data_v2.jsonl [coverage grid]).

Conditions (RealBio C0/C1/C2):
  --mode bare   C0: accession ID only (parametric knowledge)
  --mode meta   C1: accession + the authoritative fetched record (equal-info RAG)
  --biomate     C2: BioMate's deterministic data-driven classifier over the SAME fetched record
                    (directly comparable to C1 = the LLM reading that record; C0 gets no record).
Labels are derived from the data file. Output: results/<model>/accession_routing_<mode>[_v2].jsonl
"""
import json, os, sys, argparse, time

HERE = os.path.dirname(os.path.abspath(__file__))

def load(dataf):
    rows = [json.loads(l) for l in open(os.path.join(HERE, dataf)) if l.strip()]
    labels = sorted({r["modality"] for r in rows})
    return rows, labels

def parse_label(text, labels):
    t = (text or "").strip().lower().replace("-", "_").replace(" ", "_")
    for l in sorted(labels, key=len, reverse=True):
        if l in t: return l
    return t.split()[0] if t else ""

# ---- BioMate C2: deterministic data-driven classifier over the authoritative record ----
# Ordered keyword rules (specific first) mapping the fetched-record text -> fine modality.
_RULES = [
 ("ms_proteomics_tmt", ["tmt", "itraq", "isobaric", "tmtpro"]),
 ("ms_proteomics_dia", ["dia", "swath"]),
 ("ms_proteomics_dda", ["label-free", "label free", "lfq", "dda", "shotgun", "bottom-up", "pride"]),
 ("structure",         ["x-ray", "cryo-em", "electron microscopy", "emdb", "rcsb", "diffraction", "structure determination"]),
 ("protein_seq",       ["uniprot", "swiss-prot", "sequence_function", "reviewed"]),
 ("metabolomics",      ["metabolom", "mtbls", "lc-ms metabol", "nmr metabol", "metabolights", "metabolomics workbench"]),
 ("amplicon_16s",      ["16s", "18s", "its amplicon", "amplicon: amplicon", "library_strategy: amplicon"]),
 ("metagenomics",      ["metagenom", "library_source: metagenomic", "shotgun metagenom", "mgnify"]),
 ("cutandrun",         ["cut&run", "cut&tag", "cutandrun", "cut and run", "cut and tag", "seacr", "pag-mnase", "pa-mnase"]),
 ("scatac_seq",        ["scatac", "single-cell atac", "single cell atac", "single-nucleus atac", "sci-atac", "snatac"]),
 ("atac_seq",          ["atac-seq", "atac_seq", "atac ", "transposase-accessible", "transposase accessible"]),
 ("multiome",          ["multiome", "cite-seq", "share-seq", "asap-seq", "wnn", "totalseq", "citeseq"]),
 ("chip_seq",          ["chip-seq", "chip_seq", "chip seq", "binding/occupancy", "histone chip", "tf chip"]),
 ("methylation_array", ["methylation profiling by array", "methylation profiling by genome tiling array",
                         "epic", "450k", "infinium methylation", "gpl21145", "gpl13534", "methylationepic"]),
 ("wgbs",              ["bisulfite", "wgbs", "rrbs", "methylation profiling by high throughput"]),
 ("hic",               ["hi-c", "hi c", "in situ hi", "chromatin conformation", "4dn"]),
 ("spatial_transcriptomics", ["visium", "xenium", "merfish", "slide-seq", "slide-seqv2", "spatial", "hdst", "merscope"]),
 ("snrna_seq",         ["single-nucleus", "single nucleus", "single nuclei", "snrna", "snrna-seq"]),
 ("scrna_seq",         ["single-cell", "single cell", "scrna", "10x chromium", "chromium", "drop-seq", "cell ranger"]),
 ("ribo_seq",          ["ribo-seq", "ribosome profiling", "ribo seq", "riboseq"]),
 ("small_rna",         ["small rna", "small-rna", "mirna", "microrna"]),
 ("clip_seq",          ["clip-seq", "eclip", "clip seq", "par-clip", "iclip"]),
 ("target_panel",      ["targeted-capture", "targeted capture", "amplicon; library_source: genomic",
                         "library_strategy: amplicon", "gene panel", "panel sequencing"]),
 ("wes",               ["wxs", "exome", "sureselect", "whole-exome", "whole exome"]),
 ("wgs",               ["library_strategy: wgs", "whole-genome sequencing", "whole genome sequencing", "wgs"]),
 ("microarray",        ["expression profiling by array", "affymetrix", "expression array", "beadchip array"]),
 ("bulk_rnaseq",       ["rna-seq", "rna_seq", "high throughput sequencing", "transcriptom", "expression profiling by high throughput"]),
]
def biomate_c2(metadata, labels):
    m = (metadata or "").lower()
    for mod, kws in _RULES:
        if mod not in labels: continue
        if any(k in m for k in kws): return mod
    return "abstain"

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--data", default="data.jsonl")
    ap.add_argument("--model", default=None)
    ap.add_argument("--base-url", default=None); ap.add_argument("--key-env", default="OPENAI_API_KEY")
    ap.add_argument("--mode", choices=["bare", "meta"], default="bare")
    ap.add_argument("--biomate", action="store_true")
    args = ap.parse_args()
    rows, labels = load(args.data)
    tagsuffix = "_v2" if "v2" in args.data else ""
    INSTR = ("Identify the DATA MODALITY of the dataset behind this public-database accession. "
             "Respond with EXACTLY ONE label from this list and nothing else:\n" + ", ".join(labels))

    if args.biomate:
        name = "BioMate"; tag = "biomate" + tagsuffix
        preds = [{"id": r["id"], "prediction": biomate_c2(r.get("metadata"), labels)} for r in rows]
    else:
        from openai import OpenAI
        client = OpenAI(base_url=args.base_url, api_key=os.environ[args.key_env])
        name = args.model; tag = args.mode + tagsuffix
        preds = []
        for r in rows:
            inp = (f"Accession: {r['accession']}\nFetched record: {r.get('metadata','')}"
                   if args.mode == "meta" else f"Accession: {r['accession']}")
            prompt = f"{INSTR}\n\nINPUT:\n{inp}"
            pred = ""
            for attempt in range(3):
                try:
                    resp = client.chat.completions.create(model=args.model,
                        messages=[{"role": "user", "content": prompt}], max_completion_tokens=200)
                    pred = parse_label(resp.choices[0].message.content, labels); break
                except Exception as e:
                    if attempt == 2: sys.stderr.write(f"[{r['id']}] ERR {e}\n")
                    else: time.sleep(2 * (attempt + 1))
            preds.append({"id": r["id"], "prediction": pred})
    outdir = os.path.join(HERE, "results", name.replace("/", "_")); os.makedirs(outdir, exist_ok=True)
    outpath = os.path.join(outdir, f"accession_routing_{tag}.jsonl")
    with open(outpath, "w") as f:
        for p in preds: f.write(json.dumps(p) + "\n")
    print(f"wrote {len(preds)} -> {outpath}")

if __name__ == "__main__":
    main()
