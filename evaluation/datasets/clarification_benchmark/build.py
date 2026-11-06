#!/usr/bin/env python3
"""Build the clarification benchmark — interpret-or-clarify across params, input files, and workflow branches.

Design (from the product's real clarification surface): for every parameter, input file, and context-dependent
workflow BRANCH, the agent must do exactly one of two things correctly:
  - INTERPRET it, when the request/context determines it; or
  - CLARIFY it, when it is genuinely ambiguous or a required value is missing.
and must be penalized for BOTH silently guessing wrong (under-clarify) AND over-asking when it is clear
(over-clarify). Branch items are grounded in the deployed clarification fork-points and their resolver regexes,
so the gold matches what the product actually does.

Each item: {id, slot_type (branch|param|input), query, gold_action (interpret|clarify), gold_target, gold_value?}
"""
import json, os, re

HERE = os.path.dirname(os.path.abspath(__file__))

# Resolver regexes mirrored from the deployed clarification gate (AMBIGUITY_RESOLVERS). A query that matches
# the resolver for its fork is already disambiguated -> gold = interpret; otherwise -> gold = clarify.
RESOLVERS = {
    "variant_type": r"\bgermline\b|\bsomatic\b|\bHaplotypeCaller\b|\bMutect2?\b",
    "assembly_type": r"\bde\s+novo\b|\breference[- ]guided\b|\breference[- ]based\b|\bSPAdes\b|\bFlye\b|\bHifiasm\b",
    "rnaseq_type": r"\bbulk\s+rna|\bsingle[- ]cell\b|\bscRNA\b|\bDESeq2\b|\bedgeR\b|\bSeurat\b|\bScanpy\b",
    "peak_calling_type": r"\bChIP[- ]seq\b|\bATAC[- ]seq\b|\btransposase\b",
    "chip_target": r"\btranscription\s+factor\b|\bhistone\b|\bH3K\w{1,6}\b|\bnarrow\s+peak|\bbroad\s+peak",
    "proteomics_type": r"\bDDA\b|\bDIA\b|\bMaxQuant\b|\bDIA-NN\b|\bSpectronaut\b|\bdata[- ]independent\b|\bdata[- ]dependent\b",
    "cryoem_type": r"\bSPA\b|\bsingle[- ]particle\b|\btomograph|\bcryo[- ]ET\b|\bin[- ]situ\b",
    "metagenomics_type": r"\b16S\b|\bamplicon\b|\bQIIME\b|\bDADA2\b|\bshotgun\b|\bKraken\b|\bMetaPhlAn\b",
    "docking_type": r"\bblind\s+dock|\bsite[- ]directed\b|\bDiffDock\b|\bVina\b|\bknown\s+(binding\s+)?pocket\b",
    "rnaseq_focus": r"\bmRNA\b|\bdifferential\s+expression\b|\bmiRNA\b|\bsmall\s+RNA\b|\bmiRDeep\b",
}

# BRANCH items: (fork, ambiguous_query, resolved_query)
BRANCH = [
    ("variant_type",
     "Call variants from my whole-genome sequencing BAM files.",
     "Run germline variant calling with GATK HaplotypeCaller on my WGS BAMs."),
    ("assembly_type",
     "Assemble a genome from my long-read sequencing data.",
     "Run de novo genome assembly with Flye on my Nanopore reads."),
    ("rnaseq_type",
     "Analyze my RNA-seq data for gene expression.",
     "Run single-cell RNA-seq clustering with Seurat on my 10x data."),
    ("peak_calling_type",
     "Call peaks from my chromatin sequencing experiment.",
     "Run ATAC-seq open-chromatin peak calling (transposase-accessible)."),
    ("chip_target",
     "Run a ChIP-seq peak-calling pipeline on my samples.",
     "ChIP-seq for the histone mark H3K27me3 (broad peaks)."),
    ("proteomics_type",
     "Quantify proteins from my mass-spectrometry raw files.",
     "Run DIA proteomics quantification with DIA-NN."),
    ("cryoem_type",
     "Process my cryo-EM dataset to get a structure.",
     "Run single-particle analysis (SPA) 3D reconstruction from my purified-protein micrographs."),
    ("metagenomics_type",
     "Profile the microbiome composition of my sequencing samples.",
     "Run 16S amplicon taxonomic profiling with QIIME2 / DADA2."),
    ("docking_type",
     "Dock this ligand library against my target protein.",
     "Run site-directed docking with AutoDock Vina into the known ATP pocket."),
    ("rnaseq_focus",
     "Study the RNA in my sequencing samples.",
     "Run bulk mRNA differential expression (DESeq2) on tumor vs normal."),
]

# PARAM items: (query, gold_action, target, value?) — interpret stated/inferable, clarify missing-required
PARAM = [
    ("Align my human tumor RNA-seq reads.", "interpret", "genome", "GRCh38"),
    ("Run RNA-seq on Saccharomyces cerevisiae heat-stress samples.", "interpret", "genome", "R64-1-1"),
    ("Align my sequencing reads to a reference and quantify expression.", "clarify", "genome", None),   # no organism
    ("Run variant calling on my samples.", "clarify", "genome", None),                                  # no organism
    ("Standard polyA stranded (reverse) library, run the RNA-seq pipeline for human.", "interpret", "strandedness", "reverse"),
    ("Run the RNA-seq pipeline — I'm not sure about the library strandedness.", "clarify", "strandedness", None),
]

# INPUT-FILE items: interpret when provided, clarify when a required input is missing
INPUT = [
    ("Run an ADMET safety screen on CC(=O)Oc1ccccc1C(=O)O.", "interpret", "smiles", "provided"),
    ("Run an ADMET safety screen for my compound.", "clarify", "smiles", None),                         # no SMILES/SDF
    ("Dock my ligands into the receptor at s3://bucket/receptor.pdb.", "interpret", "receptor_pdb", "provided"),
    ("Run molecular docking of my compound library.", "clarify", "receptor_pdb", None),                 # no receptor
    ("Run DESeq2 on my counts matrix counts.tsv (genes x samples).", "interpret", "matrix", "provided"),
    ("Run differential expression analysis.", "clarify", "matrix", None),                               # no matrix/fastq
]


def main():
    items = []
    for fork, amb, res in BRANCH:
        pat = RESOLVERS.get(fork, "")
        # self-check: resolved query MUST match the resolver; ambiguous MUST NOT
        assert not pat or re.search(pat, amb, re.I) is None, f"ambiguous matched resolver: {fork} / {amb}"
        assert not pat or re.search(pat, res, re.I) is not None, f"resolved did NOT match resolver: {fork} / {res}"
        items.append(dict(id=f"br_{fork}_clarify", slot_type="branch", query=amb, gold_action="clarify", gold_target=fork))
        items.append(dict(id=f"br_{fork}_interp", slot_type="branch", query=res, gold_action="interpret", gold_target=fork))
    for i, (q, act, tgt, val) in enumerate(PARAM):
        items.append(dict(id=f"pa_{i:02d}", slot_type="param", query=q, gold_action=act, gold_target=tgt,
                          **({"gold_value": val} if val else {})))
    for i, (q, act, tgt, val) in enumerate(INPUT):
        items.append(dict(id=f"in_{i:02d}", slot_type="input", query=q, gold_action=act, gold_target=tgt,
                          **({"gold_value": val} if val and val != "provided" else {})))
    with open(os.path.join(HERE, "data.jsonl"), "w") as f:
        for it in items:
            f.write(json.dumps(it) + "\n")
    n_cl = sum(1 for it in items if it["gold_action"] == "clarify")
    print(f"wrote {len(items)} items  (interpret={len(items)-n_cl}, clarify={n_cl}) across "
          f"branch/param/input; all branch items self-checked against the deployed resolvers")


if __name__ == "__main__":
    main()
