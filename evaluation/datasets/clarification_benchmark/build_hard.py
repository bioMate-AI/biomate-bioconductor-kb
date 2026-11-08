#!/usr/bin/env python3
"""Build the HARD tier of the clarification benchmark (v2), per the committee review.

Key fix: "slot not stated" != "must ask". Each item attaches AVAILABLE CONTEXT (file header, manifest, sample
sheet, prior turn, paper methods) that the agent should INSPECT. The gold turns on evidence + default policy,
not keyword presence. Covers the committee's priority scenarios: experimental contrast, conflicting provenance,
recoverable-from-context, conflicting tool/data, ambiguous entity, almost-specific boundary, multi-slot follow-up.
"""
import json, os
HERE = os.path.dirname(os.path.abspath(__file__))

# (id, scenario, slot_type, query, context, gold_action, gold_target, gold_value, accept_either)
# accept_either = a competent agent may EITHER clarify OR correctly interpret/default — both score correct,
# and the item is excluded from the over/under-clarify rates (it is not a one-right-action item).
ITEMS = [
 ("hd_contrast", "experimental_contrast", "design",
  "Run DESeq2 differential expression on counts.tsv comparing treated and control.",
  "samples.tsv lists 3 treated and 3 control; no reference/baseline level is set.",
  "clarify", "contrast", "", True),       # control-as-reference is a standard default; asking is also fine
 ("hd_prov_conflict", "conflicting_provenance", "param",
  "Call germline variants on GRCh38 from aligned.bam.",
  "aligned.bam sequence dictionary (@SQ) is GRCh37; the original FASTQs are also available.",
  "clarify", "genome_conflict", ""),
 ("hd_recover_strand", "recoverable_from_context", "param",
  "Quantify expression from these bulk RNA-seq reads; I don't know the strandedness.",
  "run_manifest.json records strandedness: reverse for these sample IDs.",
  "interpret", "strandedness", "reverse"),
 ("hd_tool_bulk_seurat", "conflicting_tool_data", "branch",
  "Run Seurat single-cell clustering on my RNA-seq counts.",
  "the counts matrix is 6 bulk samples (genes x 6 samples), not per-cell.",
  "clarify", "tool_data_conflict", ""),
 ("hd_tool_sniffles", "conflicting_tool_data", "branch",
  "Find structural variants in my short-read Illumina WGS using Sniffles.",
  "reads are 150 bp paired-end Illumina (Sniffles is a long-read SV caller).",
  "clarify", "tool_data_conflict", ""),
 ("hd_mouse_build", "ambiguous_entity", "param",
  "Align my mouse RNA-seq reads and quantify gene counts.",
  "",
  "clarify", "genome_build", "", True),    # a transparent current-default (mm39) is also acceptable
 ("hd_pdb_chain", "ambiguous_entity", "input",
  "Use PDB 4XYZ as the receptor and dock my ligand into the ATP site.",
  "4XYZ contains two distinct ATP-binding chains, A and B.",
  "clarify", "receptor_chain", ""),
 ("hd_10x_interp", "almost_specific", "param",
  "Run the scRNA-seq pipeline on my 10x Genomics Chromium 3' v3 FASTQs.",
  "",
  "interpret", "strandedness", ""),       # 10x 3' v3 determines strandedness -> should NOT ask
 ("hd_paired_not_strand", "almost_specific", "param",
  "Align my paired-end FASTQ files for human and count reads per gene.",
  "",
  "clarify", "strandedness", "", True),    # paired-end != strandedness; asking OR auto-inferring is valid
 ("hd_followup_normal", "multi_slot_followup", "branch",
  "Earlier you asked which BAM is tumor vs normal. Reply: A.bam is tumor; B.bam is a second tumor biopsy "
  "from the same patient. Proceed with somatic calling.",
  "no matched normal sample has been provided.",
  "clarify", "matched_normal", ""),
 ("hd_recover_header", "recoverable_from_context", "param",
  "Call variants from sample.bam for this human sample.",
  "sample.bam header @SQ shows GRCh38 contigs (chr1..chrY).",
  "interpret", "genome", "GRCh38"),
 ("hd_reproduce_default", "authorized_default", "param",
  "Reproduce the differential-expression results from the Smith 2023 paper using my counts.tsv.",
  "Smith 2023 methods state GRCh37 and edgeR were used.",
  "interpret", "genome", "GRCh37"),        # match the paper, not the product default GRCh38
 ("hd_tpm_matrix", "conflicting_tool_data", "input",
  "Run DESeq2 on matrix.csv.",
  "matrix.csv contains TPM-normalized values (decimals), not integer raw counts.",
  "clarify", "matrix_type", ""),
 ("hd_multi_matrix", "ambiguous_entity", "input",
  "Run differential expression analysis.",
  "the workspace has two files: raw_counts.tsv and normalized_tpm.tsv.",
  "interpret", "matrix_select", "raw_counts", True),   # DESeq2/DE needs raw counts -> raw_counts is correct
 ("hd_recover_layout", "recoverable_from_context", "param",
  "Align my FASTQ files to GRCh38.",
  "the folder contains sample1_R1.fastq.gz and sample1_R2.fastq.gz per sample.",
  "interpret", "read_layout", "paired"),   # R1/R2 -> paired-end, recoverable -> don't ask
]

def main():
    out = []
    for row in ITEMS:
        id_, sc, st, q, ctx, act, tgt, val = row[:8]
        ae = row[8] if len(row) > 8 else False
        it = dict(id=id_, tier="hard", scenario=sc, slot_type=st, query=q, gold_action=act, gold_target=tgt)
        if ctx: it["context"] = ctx
        if val: it["gold_value"] = val
        if ae: it["accept_either"] = True
        out.append(it)
    with open(os.path.join(HERE, "data_hard.jsonl"), "w") as f:
        for it in out: f.write(json.dumps(it) + "\n")
    n_cl = sum(1 for it in out if it["gold_action"] == "clarify")
    print(f"wrote {len(out)} hard items (interpret={len(out)-n_cl}, clarify={n_cl}); "
          f"{sum(1 for it in out if 'context' in it)} carry available context")

if __name__ == "__main__":
    main()
