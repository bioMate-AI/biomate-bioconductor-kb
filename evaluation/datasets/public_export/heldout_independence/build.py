#!/usr/bin/env python3
"""Held-out INDEPENDENCE set (committee blocker #3). The semantic scorer, the organism->genome rule layer,
and the 3 workflow-description fixes were all changed AFTER examining errors on the original items, so their
gains are currently dev-set. These items were authored fresh to probe whether those fixes GENERALIZE to new
instances of the same classes — none of these exact queries/values were seen while tuning.

Two parts:
  * param_heldout  — new organisms/assembly-aliases/strandedness-kits/booleans/IO-traps. The organism->genome
    RULE LAYER and the SEMANTIC SCORER are DETERMINISTIC, so `check_independence.py` scores these with NO LLM
    (free) — a direct generalization test of the two post-hoc deterministic changes.
  * routing_heldout — new phrasings for the confusable pairs the description fix targeted (10x↔nanopore,
    DIA↔LFQ, Comet→mhcquant) + new underscore/custom names. LLM bare-vs-harness eval is the billable follow-up.

Run: python3 build.py
"""
import json, os
from collections import Counter

HERE = os.path.dirname(os.path.abspath(__file__))

# --- param held-out: (id, user_query, expected_params, must_not_fill, probes) ---
# "probes" = which post-hoc fix this item tests (for the independence report).
PARAM = [
    # organism->genome, NEW human/mouse PHRASINGS not in the original set (should generalize)
    ("ph_01", "RNA-seq of a patient lymphoblastoid cell line from a healthy donor", {"genome": "GRCh38"}, ["accession"], "rule:human-phrasing"),
    ("ph_02", "iPSC-derived cortical neurons, bulk RNA-seq", {"genome": "GRCh38"}, ["input"], "rule:human-phrasing"),
    ("ph_03", "ChIP-seq in BALB/c mouse splenocytes", {"genome": "GRCm39"}, ["input"], "rule:mouse-phrasing"),
    ("ph_04", "APP/PS1 transgenic mouse hippocampus RNA-seq", {"genome": "GRCm39"}, ["accession"], "rule:mouse-phrasing"),
    ("ph_05", "Sprague-Dawley rat liver RNA-seq", {"genome": "Rnor_6.0"}, ["input"], "rule:rat-phrasing"),
    # assembly aliases (hg19/mm10/hg38) -> canonical (semantic scorer + rule canon)
    ("ph_06", "Align these reads to hg19", {"genome": "GRCh37"}, [], "alias:hg19"),
    ("ph_07", "Map to the mm10 mouse assembly", {"genome": "GRCm38"}, [], "alias:mm10"),
    ("ph_08", "Use the hg38 human reference", {"genome": "GRCh38"}, [], "alias:hg38"),
    # strandedness from NEW library-kit mentions (rule kit-tables; not the original items)
    ("ph_09", "Library prepped with the TruSeq Stranded mRNA kit", {"strandedness": "reverse"}, [], "rule:kit-reverse"),
    ("ph_10", "NEBNext Ultra II Directional RNA library", {"strandedness": "reverse"}, [], "rule:kit-reverse"),
    ("ph_11", "SMART-seq2 full-length single-cell libraries", {"strandedness": "unstranded"}, [], "rule:kit-unstranded"),
    ("ph_12", "dUTP second-strand marking protocol", {"strandedness": "reverse"}, [], "rule:dutp"),
    # booleans / single-end (rule bool mapping)
    ("ph_13", "single-end 75 bp reads", {"single_end": "true"}, [], "rule:single-end"),
    ("ph_14", "paired-end 150 bp sequencing", {"single_end": "false"}, [], "rule:paired-end"),
    ("ph_15", "run on CPU only, no GPU available", {"gpu_acceleration": "false"}, [], "rule:gpu-off"),
    # IO must_not_fill traps (guardrail): assay named, NO file/accession given -> must not hallucinate input
    ("ph_16", "ATAC-seq on frozen tumor tissue", {"genome": "GRCh38"}, ["input", "accession"], "guardrail:io-trap"),
    ("ph_17", "bisulfite WGBS, human blood", {"genome": "GRCh38"}, ["input"], "guardrail:io-trap"),
    ("ph_18", "DIA proteomics of a FFPE cohort", {}, ["input", "fasta"], "guardrail:io-trap"),
    # HONEST BOUNDARY: organisms the rule layer does NOT cover -> rule should abstain (fall to LLM), not hallucinate
    ("ph_19", "Sscrofa pig liver RNA-seq", {"genome": "Sscrofa11.1"}, [], "boundary:uncovered-organism"),
    ("ph_20", "chicken embryo fibroblast RNA-seq", {"genome": "GRCg7b"}, [], "boundary:uncovered-organism"),
]

# --- routing held-out: (id, query, correct_workflow, acceptable_alts, probes, domain) ---
ROUTING = [
    # 10x short-read vs Nanopore long-read — NEW phrasings (tests the scnanoseq/scrnaseq description fix)
    ("rh_01", "Process Chromium 10x single-cell libraries with STARsolo", "nf-core/scrnaseq", [], "desc:10x-shortread", "single_cell"),
    ("rh_02", "Oxford Nanopore long-read single-cell RNA-seq (R10.4)", "nf-core/scnanoseq", [], "desc:nanopore", "single_cell"),
    ("rh_03", "10x 5-prime scRNA-seq quantified with alevin-fry", "nf-core/scrnaseq", [], "desc:10x-shortread", "single_cell"),
    # DIA vs LFQ proteomics (NEW phrasing)
    ("rh_04", "Data-independent acquisition proteomics, label-free", "nf-core/diaproteomics", [], "desc:dia", "proteomics"),
    ("rh_05", "DDA label-free quantification of whole-cell lysate", "nf-core/proteomicslfq", [], "desc:lfq", "proteomics"),
    # Comet immunopeptidomics (mhcquant description fix)
    ("rh_06", "Comet database search of eluted HLA class I peptides", "nf-core/mhcquant", ["nf-core/epitopeprediction"], "desc:comet", "drug_discovery"),
    # underscore / custom names (semantic scorer underscore=space)
    ("rh_07", "Doublet detection and empty-droplet filtering for scRNA-seq QC", "scrna_doublet_qc", ["nf-core/scdownstream"], "scorer:underscore", "single_cell"),
    ("rh_08", "Spatial domain clustering of Visium with BANKSY", "spatial_visium_banksy", [], "scorer:underscore", "spatial_omics"),
    # new drug-dev routing (breadth; not touched during tuning)
    ("rh_09", "Virtual screening of a 10k compound library by docking against a kinase", "Structure Prediction Docking", [], "breadth:dd", "drug_discovery"),
    ("rh_10", "De novo generative design of lead-like molecules with an RL policy", "REINVENT4 Generative Lead Design", [], "breadth:dd", "drug_discovery"),
    # new general-domain routing
    ("rh_11", "Germline short-variant calling from WGS with GATK HaplotypeCaller", "nf-core/sarek", ["nf-core/raredisease"], "breadth:variant", "variant_calling"),
    ("rh_12", "Taxonomic profiling of shotgun metagenomes with Kraken2", "nf-core/taxprofiler", ["nf-core/mag"], "breadth:meta", "metagenomics"),
    ("rh_13", "CUT&RUN for histone mark profiling", "nf-core/cutandrun", [], "breadth:epi", "epigenomics"),
    ("rh_14", "Bulk RNA-seq differential expression, human", "nf-core/rnaseq", ["nf-core/differentialabundance"], "breadth:rna", "transcriptomics"),
    ("rh_15", "AlphaFold-style protein structure prediction", "nf-core/proteinfold", [], "breadth:struct", "structural"),
]


def main():
    pr = [{"id": i, "user_query": q, "expected_params": ep, "must_not_fill": mnf, "probes": pb}
          for i, q, ep, mnf, pb in PARAM]
    rt = [{"id": i, "query": q, "correct_workflow": cw, "acceptable_alts": alts, "probes": pb, "domain": d}
          for i, q, cw, alts, pb, d in ROUTING]
    open(os.path.join(HERE, "param_heldout.jsonl"), "w").write("\n".join(json.dumps(r) for r in pr) + "\n")
    open(os.path.join(HERE, "routing_heldout.jsonl"), "w").write("\n".join(json.dumps(r) for r in rt) + "\n")
    print(f"param_heldout: {len(pr)} items  probes={Counter(p['probes'].split(':')[0] for p in pr)}")
    print(f"routing_heldout: {len(rt)} items  probes={Counter(r['probes'].split(':')[0] for r in rt)}")


if __name__ == "__main__":
    main()
