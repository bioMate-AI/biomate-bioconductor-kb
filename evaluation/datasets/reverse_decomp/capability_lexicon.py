#!/usr/bin/env python3
"""Build capability ACCEPT-SETS grounded in the BioMate catalog.

A "capability" is a functional role a scientist's biomedical NEED implies (e.g. "find the
differentially-expressed genes"). It is satisfied by ANY of several catalog tools/workflows
(DESeq2 OR edgeR OR limma all answer "find DE genes"). The accept-set is that set of
capability-equivalent realizations.

Design: docs/20260912_onprem_llm/20261008_REVERSE_DECOMP_DATASET.md

Every accept-set member is a REAL catalog identifier (tools.tool_id / tools.name or
workflows.name). Capabilities whose patterns resolve to an empty accept-set are DROPPED
(no fabrication). The accept-set is the grader's answer-key; it is NEVER shown in a query.

Sources of accept-sets (all grounded in backend/database/galaxy_ai_tools.db):
  (A) CURATED LEXICON  — ~40 well-known bioinformatics capabilities, each a (domain, role)
      with name/tool LIKE patterns; resolved against catalog -> the real members.
  (B) CHAIN ROLES      — workflow_chains[].steps[].role grouped to its workflow_names
      (free, real, author-curated equivalences, e.g. differential_expression ->
      {BIOC_DESEQ2, BIOC_LIMMA, deseq2, nf-core/differentialabundance}).
  (C) TOOL CATEGORIES  — a tool category subset = "all X tools" (e.g. peptide tools).

Usage:
    python capability_lexicon.py --db ../../../backend/database/galaxy_ai_tools.db \
        --out accept_sets.json
"""
from __future__ import annotations
import json, os, re, sqlite3, argparse
from collections import defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
_DEFAULT_DB = os.path.join(HERE, "..", "..", "..", "backend", "database", "galaxy_ai_tools.db")

_WORD = re.compile(r"[a-z0-9]+")


def toks(s):
    return set(_WORD.findall(str(s).lower()))


def canon(s):
    return re.sub(r"[^a-z0-9]+", " ", str(s).lower()).strip()


# ----------------------------------------------------------------------------------------
# (A) CURATED LEXICON — capability -> resolution patterns. Each pattern is an SQL LIKE run
# against tools(name, tool_id) and workflows(name, tools_used). Members verified at build.
# `role` is the capability key used in gold nodes; `deliverable` is the output KIND the need
# asks for (used for outcome grading); `domain` tags the unit.
# ----------------------------------------------------------------------------------------
LEXICON = [
    # --- transcriptomics ---
    dict(role="read_qc", domain="transcriptomics", deliverable="qc_report",
         patterns=["fastqc", "falco", "multiqc", "fastp", "trim galore", "trimmomatic", "cutadapt"]),
    dict(role="rnaseq_quantification", domain="transcriptomics", deliverable="counts_matrix",
         patterns=["rnaseq", "salmon", "star", "hisat2", "kallisto", "featurecounts", "htseq", "rsem"]),
    dict(role="differential_expression", domain="transcriptomics", deliverable="de_table",
         patterns=["deseq2", "deseq", "edger", "%limma%", "differentialabundance", "absseq", "noiseq", "ballgown"]),
    dict(role="pathway_enrichment", domain="transcriptomics", deliverable="enrichment_table",
         patterns=["clusterprofiler", "enrichgo", "fgsea", "gsea", "goseq", "gprofiler", "topgo", "reactomepa"]),
    dict(role="microarray_normalization", domain="transcriptomics", deliverable="normalized_matrix",
         patterns=["%affy%", "%vsn%", "%lumi%", "%oligo%", "rma", "limma"]),
    # --- variant calling / genomics ---
    dict(role="read_alignment", domain="genomics", deliverable="bam",
         patterns=["bwa", "bowtie", "minimap2", "hisat2", "%star%"]),
    dict(role="germline_variant_calling", domain="variant_calling", deliverable="vcf",
         patterns=["haplotypecaller", "deepvariant", "freebayes", "%gatk%", "bcftools call", "sarek"]),
    dict(role="somatic_variant_calling", domain="variant_calling", deliverable="vcf",
         patterns=["mutect", "strelka", "varscan", "lofreq", "muse", "somaticsniper"]),
    dict(role="variant_annotation", domain="variant_calling", deliverable="annotated_vcf",
         patterns=["%vep%", "snpeff", "annovar", "snpsift"]),
    dict(role="genome_assembly", domain="genomics", deliverable="assembly_fasta",
         patterns=["spades", "velvet", "%flye%", "unicycler", "megahit", "canu", "%abyss%"]),
    # --- epigenomics ---
    dict(role="peak_calling", domain="epigenomics", deliverable="peaks_bed",
         patterns=["macs2", "macs3", "%pepr%", "%genrich%", "epic2", "homer"]),
    dict(role="methylation_analysis", domain="epigenomics", deliverable="methylation_calls",
         patterns=["bismark", "%methyldackel%", "%methylkit%", "%dmr%", "%wgbs%"]),
    # --- single cell ---
    dict(role="single_cell_qc_norm", domain="single_cell", deliverable="h5ad_filtered",
         patterns=["%scanpy%", "%seurat%", "scrna", "cellranger", "%starsolo%", "%alevin%"]),
    dict(role="cell_type_annotation", domain="single_cell", deliverable="annotated_h5ad",
         patterns=["annotate_celltype", "singler", "celltypist", "%azimuth%"]),
    dict(role="batch_integration", domain="single_cell", deliverable="integrated_h5ad",
         patterns=["harmony", "%scvi%", "%bbknn%", "%mnn%", "%integration%"]),
    # --- proteomics ---
    dict(role="peptide_identification", domain="proteomics", deliverable="peptide_ids",
         patterns=["maxquant", "%msgf%", "comet", "%peptideshaker%", "%searchgui%", "%fragpipe%", "peptideprophet"]),
    dict(role="peptide_property", domain="proteomics", deliverable="peptide_properties",
         patterns=["peptidebuilder", "%peptideindexer%", "%pyprophet%", "%openms%", "peptide to gff",
                   "map peptides", "%pepnovo%"]),
    dict(role="protein_quantification", domain="proteomics", deliverable="protein_quant",
         patterns=["%proteinquant%", "flashlfq", "%msstats%", "maxlfq", "diann", "%diaproteomics%"]),
    # --- drug discovery ---
    dict(role="admet_prediction", domain="drug_discovery", deliverable="admet_table",
         patterns=["%admet%", "%herg%", "%ames%", "%cyp%", "%bioavailab%", "%toxicity%"]),
    dict(role="molecular_docking", domain="drug_discovery", deliverable="docking_poses",
         patterns=["%autodock%", "%vina%", "%smina%", "%glide%", "%rdock%", "%docking%"]),
    dict(role="qsar_modeling", domain="drug_discovery", deliverable="qsar_model",
         patterns=["%qsar%", "%descriptor%", "%rdkit%", "%mordred%", "%fingerprint%"]),
    # --- metagenomics ---
    dict(role="taxonomic_classification", domain="metagenomics", deliverable="taxonomy_profile",
         patterns=["kraken", "%bracken%", "%metaphlan%", "%centrifuge%", "%kaiju%"]),
    dict(role="metagenome_assembly", domain="metagenomics", deliverable="assembly_fasta",
         patterns=["metaspades", "megahit", "%concoct%", "%metabat%", "%maxbin%"]),
    # --- metabolomics ---
    dict(role="ms_feature_detection", domain="metabolomics", deliverable="feature_table",
         patterns=["%xcms%", "%mzmine%", "%openms%", "%asics%", "%camera%"]),
    # --- structural / cryo-em ---
    dict(role="protein_structure_prediction", domain="structural_biology", deliverable="structure_pdb",
         patterns=["%alphafold%", "%colabfold%", "%esmfold%", "%rosetta%"]),
    dict(role="molecular_dynamics", domain="structural_biology", deliverable="md_trajectory",
         patterns=["%gromacs%", "%namd%", "%openmm%", "%amber%"]),
    # --- systems biology ---
    dict(role="network_analysis", domain="systems_biology", deliverable="network",
         patterns=["%wgcna%", "%cytoscape%", "%stringdb%", "%igraph%"]),
    # --- phylogenetics ---
    dict(role="phylogenetic_tree", domain="genomics", deliverable="tree",
         patterns=["%raxml%", "%iqtree%", "%fasttree%", "%mrbayes%", "%phyml%"]),
    dict(role="multiple_sequence_alignment", domain="genomics", deliverable="alignment",
         patterns=["%mafft%", "%muscle%", "%clustal%", "%t-coffee%", "%tcoffee%"]),
]


def _resolve_patterns(db, patterns):
    """Return the real catalog members matching any LIKE pattern, across tools + workflows."""
    members = {}  # canon-id -> {"id","name","kind","category"}
    for p in patterns:
        like = p if "%" in p else f"%{p}%"
        for r in db.execute(
                "SELECT tool_id, name, category FROM tools WHERE lower(name) LIKE ? OR lower(tool_id) LIKE ?",
                (like, like)):
            key = canon(r["tool_id"] or r["name"])
            members[key] = {"id": r["tool_id"] or r["name"], "name": r["name"],
                            "kind": "tool", "category": r["category"] or ""}
        for r in db.execute(
                "SELECT name, domain, tools_used FROM workflows WHERE lower(name) LIKE ?", (like,)):
            key = canon(r["name"])
            members[key] = {"id": r["name"], "name": r["name"], "kind": "workflow",
                            "category": r["domain"] or ""}
    return members


def _chain_role_accept_sets(db):
    """(B) workflow_chains role -> its workflow_names (author-curated equivalence)."""
    role2wf = defaultdict(dict)
    for r in db.execute("SELECT domain, steps FROM workflow_chains"):
        try:
            steps = json.loads(r["steps"] or "[]")
        except Exception:
            steps = []
        for s in steps:
            role, wf = s.get("role"), s.get("workflow_name")
            if role and wf:
                role2wf[(r["domain"] or "", role)][canon(wf)] = {
                    "id": wf, "name": wf, "kind": "workflow", "category": r["domain"] or ""}
    return role2wf


def build(db_path=_DEFAULT_DB):
    db = sqlite3.connect(f"file:{os.path.abspath(db_path)}?mode=ro", uri=True)
    db.row_factory = sqlite3.Row
    caps = {}

    # (A) curated lexicon
    for spec in LEXICON:
        members = _resolve_patterns(db, spec["patterns"])
        if not members:
            continue  # drop capabilities with no real catalog realization
        cap_id = f"{spec['domain']}:{spec['role']}"
        caps[cap_id] = {
            "capability": spec["role"], "domain": spec["domain"],
            "deliverable": spec["deliverable"], "provenance": "curated_lexicon",
            "accept_set": sorted(m["id"] for m in members.values()),
            "accept_canon": sorted(members.keys()),
            "n_members": len(members),
        }

    # (B) chain roles (merge into existing cap or add new)
    for (dom, role), mem in _chain_role_accept_sets(db).items():
        cap_id = f"{dom}:{role}"
        ids = sorted(m["id"] for m in mem.values())
        if cap_id in caps:
            merged = sorted(set(caps[cap_id]["accept_set"]) | set(ids))
            merged_canon = sorted(set(caps[cap_id]["accept_canon"]) | set(mem.keys()))
            caps[cap_id]["accept_set"] = merged
            caps[cap_id]["accept_canon"] = merged_canon
            caps[cap_id]["n_members"] = len(merged)
            caps[cap_id]["provenance"] = "curated_lexicon+chain_role"
        else:
            caps[cap_id] = {"capability": role, "domain": dom, "deliverable": role,
                            "provenance": "chain_role", "accept_set": ids,
                            "accept_canon": sorted(mem.keys()), "n_members": len(ids)}

    # (C) tool-category "all X tools" accept-sets (for category-type capability units)
    CATEGORY_CAPS = {
        "proteomics:peptide_toolset": ("Proteomics", "peptide"),
        "drug_discovery:cheminformatics_toolset": ("Computational chemistry", None),
    }
    for cap_id, (cat, namefilter) in CATEGORY_CAPS.items():
        rows = db.execute("SELECT tool_id, name FROM tools WHERE category = ?", (cat,)).fetchall()
        mem = {}
        for r in rows:
            if namefilter and namefilter not in (r["name"] or "").lower():
                continue
            mem[canon(r["tool_id"] or r["name"])] = r["tool_id"] or r["name"]
        if len(mem) >= 2:
            dom = cap_id.split(":")[0]
            caps[cap_id] = {"capability": cap_id.split(":")[1], "domain": dom,
                            "deliverable": "tool_category_outputs", "provenance": "tool_category",
                            "accept_set": sorted(mem.values()), "accept_canon": sorted(mem.keys()),
                            "n_members": len(mem), "is_category_set": True}
    db.close()
    return caps


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--db", default=_DEFAULT_DB)
    ap.add_argument("--out", default=os.path.join(HERE, "accept_sets.json"))
    a = ap.parse_args()
    caps = build(a.db)
    with open(a.out, "w") as f:
        json.dump(caps, f, indent=2)
    print(f"capabilities: {len(caps)}  (members total: {sum(c['n_members'] for c in caps.values())})")
    for cid, c in sorted(caps.items()):
        print(f"  {cid:48s} n={c['n_members']:4d}  [{c['provenance']}]")
