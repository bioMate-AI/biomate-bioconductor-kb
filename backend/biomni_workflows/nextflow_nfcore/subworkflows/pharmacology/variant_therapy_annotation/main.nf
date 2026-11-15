#!/usr/bin/env nextflow
/*
 * pharmacology/variant_therapy_annotation
 *
 * VARIANT -> THERAPY ANNOTATION. Given somatic variants (gene + protein change,
 * or an annotated VCF) this matches each variant to therapy associations —
 * drug(s), association type (sensitivity / resistance), evidence level
 * (OncoKB-style level 1..4 / R1, with a CIViC A..E tier analogue), and the
 * tumor-type context — then emits a ranked actionability report. This is the
 * precision-oncology "what is this mutation actionable with?" step
 * (OncoKB / CIViC-style matching).
 *
 * HONESTY CONSTRAINT — THE KNOWLEDGE BASE IS A DEMO STUB, NOT A CLINICAL DB:
 *   This workflow ships a SMALL, clearly-labelled BUILT-IN DEMO knowledge table
 *   of a handful of well-established gene->drug associations (BRAF V600E ->
 *   vemurafenib/dabrafenib, EGFR L858R -> osimertinib, KRAS G12C -> sotorasib,
 *   EGFR T790M -> osimertinib sensitivity + 1st-gen-TKI resistance, ERBB2
 *   amplification -> trastuzumab). It is ILLUSTRATIVE ONLY — NOT complete and
 *   NOT clinically validated. A real deployment MUST wire a licensed OncoKB /
 *   CIViC feed through params.knowledge_tsv (which, when supplied, fully
 *   replaces the demo table). Associations are looked up, never fabricated: a
 *   variant with no entry is reported as "no_actionable_match", not invented.
 *
 * Inputs (params, all have demo defaults so it runs with no input):
 *   params.variants      JSON list of {gene, protein_change, tumor_type} somatic
 *                        variants. Demo default covers several demo associations
 *                        plus one deliberate no-match (TP53 R175H).
 *   params.vcf           optional path to an annotated VCF (SnpEff/VEP ANN=). When
 *                        set, gene + HGVS.p are parsed from the ANN field and ADDED
 *                        to the variant set. '' = unused (demo variants only).
 *   params.knowledge_tsv optional path to a user-supplied real knowledge base TSV
 *                        (columns: gene, alteration, drug, association,
 *                        evidence_level, tumor_type, source). When set, it
 *                        REPLACES the built-in demo table. '' = use demo table.
 *   params.tumor_type    default tumor-type context for variants that do not carry
 *                        their own (metadata; matching is not hard-filtered by it).
 *   params.outdir        output directory (default 'results').
 *
 * Outputs:
 *   actionable_variants.csv      gene, protein_change, drug, association,
 *                                evidence_level, tumor_type, source (one row per
 *                                variant x matched therapy; no-match variants
 *                                carried as association=no_actionable_match).
 *   actionability_summary.json   n variants, n actionable, highest evidence level,
 *                                drugs matched, per-association rollup.
 *   qc_metrics.json              run QC (counts, actionable fraction, KB source).
 *
 * Container: a LIGHTWEIGHT python-only image (python3 + stdlib; pandas optional,
 * unused here — matching is pure json/csv stdlib). Named biomate/variant-annot;
 * build + push before first run (Dockerfile: FROM python:3.11-slim; pip install
 * pandas is optional and only needed if a future stage adopts it). CPU only,
 * no GPU, no model weights.
 */

nextflow.enable.dsl = 2

// Note: do NOT add `import groovy.json.JsonSlurper` here — unused and rejected as a
// script compile error on some Batch Nextflow heads (same class as antibody_antigen_complex).

// Demo defaults (overridden by BioMate's executor at launch). The variant set
// intentionally includes TP53 R175H, which has NO entry in the demo table, to
// exercise the "no actionable match" path.
params.variants = '[{"gene":"BRAF","protein_change":"V600E","tumor_type":"Melanoma"},{"gene":"EGFR","protein_change":"L858R","tumor_type":"Non-Small Cell Lung Cancer"},{"gene":"KRAS","protein_change":"G12C","tumor_type":"Non-Small Cell Lung Cancer"},{"gene":"ERBB2","protein_change":"amplification","tumor_type":"Breast Cancer"},{"gene":"TP53","protein_change":"R175H","tumor_type":"Ovarian Cancer"}]'
params.vcf           = ''
params.knowledge_tsv = ''
params.tumor_type    = 'any'
params.outdir        = 'results'

process ANNOTATE_VARIANTS {
    tag "variant_therapy"
    label 'process_low'
    publishDir { "${params.outdir}/variant_therapy_annotation" }, mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/variant-annot:x86' : 'biomate/variant-annot:latest'

    input:
    val variants_json

    output:
    path "actionable_variants.csv", emit: actionable
    path "versions.yml",            emit: versions

    script:
    """
    export VARIANTS_JSON='${variants_json}'
    export VCF_PATH='${params.vcf}'
    export KNOWLEDGE_TSV='${params.knowledge_tsv}'
    export DEFAULT_TUMOR='${params.tumor_type}'

    python3 << 'PYEOF'
import os, json, csv

variants_json = os.environ.get("VARIANTS_JSON") or "[]"
vcf_path      = (os.environ.get("VCF_PATH") or "").strip()
kb_tsv        = (os.environ.get("KNOWLEDGE_TSV") or "").strip()
default_tumor = (os.environ.get("DEFAULT_TUMOR") or "any").strip()

# -------------------------------------------------------------------------
# BUILT-IN ILLUSTRATIVE DEMO KNOWLEDGE TABLE.
# NOT a complete or clinically validated database — a handful of
# well-established gene->drug associations for demonstration / smoke-testing
# only. Evidence levels use OncoKB-style tiering (1 = FDA-recognised
# biomarker, highest, through 4 = compelling biological evidence; R1 =
# standard-care resistance). A CIViC A..E tier analogue is carried alongside.
# REAL DEPLOYMENT MUST REPLACE THIS via params.knowledge_tsv (licensed
# OncoKB / CIViC feed).
# -------------------------------------------------------------------------
DEMO_KB = [
    {"gene": "BRAF",  "alteration": "V600E",         "drug": "vemurafenib", "association": "sensitivity", "evidence_level": "1",  "tumor_type": "Melanoma",                     "source": "demo_kb (OncoKB/CIViC-style, ILLUSTRATIVE — not clinical)"},
    {"gene": "BRAF",  "alteration": "V600E",         "drug": "dabrafenib",  "association": "sensitivity", "evidence_level": "1",  "tumor_type": "Melanoma",                     "source": "demo_kb (OncoKB/CIViC-style, ILLUSTRATIVE — not clinical)"},
    {"gene": "EGFR",  "alteration": "L858R",         "drug": "osimertinib", "association": "sensitivity", "evidence_level": "1",  "tumor_type": "Non-Small Cell Lung Cancer",   "source": "demo_kb (OncoKB/CIViC-style, ILLUSTRATIVE — not clinical)"},
    {"gene": "EGFR",  "alteration": "T790M",         "drug": "osimertinib", "association": "sensitivity", "evidence_level": "1",  "tumor_type": "Non-Small Cell Lung Cancer",   "source": "demo_kb (OncoKB/CIViC-style, ILLUSTRATIVE — not clinical)"},
    {"gene": "EGFR",  "alteration": "T790M",         "drug": "gefitinib",   "association": "resistance",  "evidence_level": "R1", "tumor_type": "Non-Small Cell Lung Cancer",   "source": "demo_kb (OncoKB/CIViC-style, ILLUSTRATIVE — not clinical)"},
    {"gene": "KRAS",  "alteration": "G12C",          "drug": "sotorasib",   "association": "sensitivity", "evidence_level": "1",  "tumor_type": "Non-Small Cell Lung Cancer",   "source": "demo_kb (OncoKB/CIViC-style, ILLUSTRATIVE — not clinical)"},
    {"gene": "ERBB2", "alteration": "AMPLIFICATION", "drug": "trastuzumab", "association": "sensitivity", "evidence_level": "1",  "tumor_type": "Breast Cancer",                "source": "demo_kb (OncoKB/CIViC-style, ILLUSTRATIVE — not clinical)"},
]

# three-letter -> one-letter, for best-effort HGVS.p (p.Val600Glu) normalisation
AA3 = {"Ala":"A","Arg":"R","Asn":"N","Asp":"D","Cys":"C","Gln":"Q","Glu":"E",
       "Gly":"G","His":"H","Ile":"I","Leu":"L","Lys":"K","Met":"M","Phe":"F",
       "Pro":"P","Ser":"S","Thr":"T","Trp":"W","Tyr":"Y","Val":"V","Ter":"*"}

def norm_alt(s):
    s = (s or "").strip()
    if s.lower().startswith("p."):
        s = s[2:]
    low = s.lower()
    if "amp" in low:
        return "AMPLIFICATION"
    if "del" in low and low in ("del", "deletion", "loss"):
        return "DELETION"
    for three, one in AA3.items():
        s = s.replace(three, one)
    return s.upper()

# ---- knowledge base: user TSV REPLACES the demo table when supplied ----
kb_source = "built-in demo table (ILLUSTRATIVE — not a clinical database)"
kb = DEMO_KB
TAB = chr(9)
if kb_tsv and os.path.exists(kb_tsv):
    loaded = []
    with open(kb_tsv, newline="") as fh:
        for r in csv.DictReader(fh, delimiter=TAB):
            if not r.get("gene"):
                continue
            loaded.append({
                "gene": (r.get("gene") or "").strip(),
                "alteration": (r.get("alteration") or "").strip(),
                "drug": (r.get("drug") or "").strip(),
                "association": (r.get("association") or "").strip() or "sensitivity",
                "evidence_level": (r.get("evidence_level") or "").strip(),
                "tumor_type": (r.get("tumor_type") or "").strip(),
                "source": (r.get("source") or "user_knowledge_tsv").strip(),
            })
    if loaded:
        kb = loaded
        kb_source = "user-supplied knowledge_tsv (%d rows)" % len(loaded)

# index KB by (gene, normalised alteration)
kb_index = {}
for row in kb:
    key = ((row.get("gene") or "").strip().upper(), norm_alt(row.get("alteration")))
    kb_index.setdefault(key, []).append(row)

# ---- collect input variants ----
try:
    variants = json.loads(variants_json)
except Exception as e:
    raise SystemExit("FATAL: could not parse params.variants JSON: %s" % e)
if not isinstance(variants, list):
    raise SystemExit("FATAL: params.variants must be a JSON list of variant objects")

norm_variants = []
for v in variants:
    if not isinstance(v, dict):
        continue
    gene = (v.get("gene") or v.get("Gene") or "").strip()
    pc   = (v.get("protein_change") or v.get("alteration") or v.get("hgvs_p") or "").strip()
    tt   = (v.get("tumor_type") or v.get("tumour_type") or default_tumor).strip()
    if gene:
        norm_variants.append({"gene": gene, "protein_change": pc, "tumor_type": tt})

# ---- optional annotated VCF: parse gene + HGVS.p from the SnpEff/VEP ANN field ----
# Standard SnpEff ANN sub-fields: Allele|Annotation|Impact|Gene_Name|Gene_ID|
# Feature_Type|Feature_ID|Transcript_BioType|Rank|HGVS.c|HGVS.p|... We read
# Gene_Name (index 3) and HGVS.p (index 10). Best-effort only; licensed feeds
# in production should pass a pre-normalised variant list.
if vcf_path and os.path.exists(vcf_path):
    with open(vcf_path) as fh:
        for line in fh:
            if not line or line.startswith("#"):
                continue
            cols = line.rstrip().split(TAB)
            if len(cols) < 8:
                continue
            info = cols[7]
            ann = ""
            for field in info.split(";"):
                if field.startswith("ANN="):
                    ann = field[4:]
                    break
            if not ann:
                continue
            first = ann.split(",")[0]
            parts = first.split("|")
            gene = parts[3].strip() if len(parts) > 3 else ""
            hgvs_p = parts[10].strip() if len(parts) > 10 else ""
            if gene:
                norm_variants.append({"gene": gene, "protein_change": hgvs_p, "tumor_type": default_tumor})

if not norm_variants:
    raise SystemExit("FATAL: no usable variants found in params.variants or params.vcf")

# ---- match each variant against the knowledge base ----
cols = ["gene", "protein_change", "drug", "association", "evidence_level", "tumor_type", "source"]
out_rows = []
n_actionable = 0
for v in norm_variants:
    key = (v["gene"].upper(), norm_alt(v["protein_change"]))
    hits = kb_index.get(key, [])
    if hits:
        n_actionable += 1
        for h in hits:
            out_rows.append({
                "gene": v["gene"],
                "protein_change": v["protein_change"],
                "drug": h.get("drug", ""),
                "association": h.get("association", ""),
                "evidence_level": h.get("evidence_level", ""),
                "tumor_type": h.get("tumor_type", ""),
                "source": h.get("source", ""),
            })
    else:
        out_rows.append({
            "gene": v["gene"],
            "protein_change": v["protein_change"],
            "drug": "",
            "association": "no_actionable_match",
            "evidence_level": "",
            "tumor_type": v["tumor_type"],
            "source": kb_source,
        })

with open("actionable_variants.csv", "w", newline="") as fh:
    w = csv.DictWriter(fh, fieldnames=cols)
    w.writeheader()
    for r in out_rows:
        w.writerow(r)

print("annotated %d variants (%d actionable) against %s -> %d rows" % (
    len(norm_variants), n_actionable, kb_source, len(out_rows)))
PYEOF

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        python: \$(python3 --version | cut -d' ' -f2)
        knowledge_base: "built-in demo table (illustrative) or user knowledge_tsv override"
    END_VERSIONS
    """
}

process SUMMARISE_ACTIONABILITY {
    tag "variant_therapy"
    label 'process_low'
    publishDir { "${params.outdir}/variant_therapy_annotation" }, mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/variant-annot:x86' : 'biomate/variant-annot:latest'

    input:
    path "actionable_variants.csv"

    output:
    path "actionability_summary.json", emit: summary
    path "qc_metrics.json",            emit: qc

    script:
    """
    python3 << 'PYEOF'
import json, csv, os

path = "actionable_variants.csv"
rows = []
if os.path.exists(path):
    with open(path, newline="") as fh:
        for r in csv.DictReader(fh):
            rows.append(r)

# LOUD-FAIL when no output was produced upstream.
if not rows:
    raise SystemExit("FATAL: actionable_variants.csv is empty or missing — the "
                     "annotation stage produced no output; refusing to emit an "
                     "empty actionability report.")

# OncoKB-style tier ordering: smaller = stronger evidence. R1 is standard-care
# resistance (high confidence), ranked alongside level 1.
ORDER = {"1": 1, "R1": 1, "2": 2, "3": 3, "3A": 3, "3B": 3, "R2": 3, "4": 4}

def is_actionable(r):
    return bool((r.get("drug") or "").strip()) and r.get("association") != "no_actionable_match"

actionable = [r for r in rows if is_actionable(r)]
no_match   = [r for r in rows if not is_actionable(r)]

# a "variant" is a unique (gene, protein_change) pair
all_variants = sorted({(r.get("gene"), r.get("protein_change")) for r in rows})
actionable_variants = sorted({(r.get("gene"), r.get("protein_change")) for r in actionable})

drugs_matched = sorted({(r.get("drug") or "").strip() for r in actionable if (r.get("drug") or "").strip()})

# highest (strongest) evidence level present among actionable rows
highest_level = None
if actionable:
    best = min(actionable, key=lambda r: ORDER.get((r.get("evidence_level") or "").strip(), 99))
    highest_level = (best.get("evidence_level") or "").strip() or None

# per-association rollup
assoc_rollup = {}
for r in actionable:
    a = (r.get("association") or "unknown").strip()
    assoc_rollup[a] = assoc_rollup.get(a, 0) + 1

n_variants = len(all_variants)
n_actionable = len(actionable_variants)

summary = {
    "workflow": "variant_therapy_annotation",
    "knowledge_base": "built-in demo table (ILLUSTRATIVE — not a clinical database) "
                      "unless a user knowledge_tsv override was supplied",
    "n_variants": n_variants,
    "n_actionable_variants": n_actionable,
    "n_no_actionable_match": n_variants - n_actionable,
    "n_therapy_associations": len(actionable),
    "highest_evidence_level": highest_level,
    "drugs_matched": drugs_matched,
    "association_rollup": assoc_rollup,
    "actionable_calls": [
        {"gene": r.get("gene"), "protein_change": r.get("protein_change"),
         "drug": r.get("drug"), "association": r.get("association"),
         "evidence_level": r.get("evidence_level"), "tumor_type": r.get("tumor_type")}
        for r in sorted(actionable, key=lambda r: ORDER.get((r.get("evidence_level") or "").strip(), 99))
    ],
    "no_match_variants": [
        {"gene": r.get("gene"), "protein_change": r.get("protein_change"),
         "tumor_type": r.get("tumor_type")}
        for r in no_match
    ],
    "status": "ok",
    "note": "Precision-oncology variant->therapy matching. Evidence levels and "
            "drug associations are LOOKED UP from the knowledge table, never "
            "fabricated. The built-in table is illustrative; wire a licensed "
            "OncoKB/CIViC feed for clinical use.",
}
with open("actionability_summary.json", "w") as fh:
    json.dump(summary, fh, indent=2)

qc = {
    "n_input_rows": len(rows),
    "n_variants": n_variants,
    "n_actionable_variants": n_actionable,
    "n_no_actionable_match": n_variants - n_actionable,
    "actionable_fraction": round(n_actionable / n_variants, 4) if n_variants else 0.0,
    "n_drugs_matched": len(drugs_matched),
    "highest_evidence_level": highest_level,
    "produced_output": True,
    "status": "pass",
}
with open("qc_metrics.json", "w") as fh:
    json.dump(qc, fh, indent=2)

print(json.dumps({k: summary[k] for k in
      ("n_variants", "n_actionable_variants", "highest_evidence_level", "drugs_matched")}, indent=2))
PYEOF
    """
}

workflow VARIANT_THERAPY_ANNOTATION {
    take:
    ch_variants   // channel: val(variants_json) — the somatic variant set as JSON

    main:
    ANNOTATE_VARIANTS(ch_variants)
    SUMMARISE_ACTIONABILITY(ANNOTATE_VARIANTS.out.actionable)

    emit:
    actionable = ANNOTATE_VARIANTS.out.actionable
    summary    = SUMMARISE_ACTIONABILITY.out.summary
    qc         = SUMMARISE_ACTIONABILITY.out.qc
    versions   = ANNOTATE_VARIANTS.out.versions
}

// Entry workflow for standalone execution.
workflow {
    def variants_json = params.variants instanceof String
        ? params.variants
        : groovy.json.JsonOutput.toJson(params.variants)

    ch_variants = Channel.of(variants_json as String)

    VARIANT_THERAPY_ANNOTATION(ch_variants)

    VARIANT_THERAPY_ANNOTATION.out.qc.view { f -> "variant therapy annotation done: ${f}" }
}
