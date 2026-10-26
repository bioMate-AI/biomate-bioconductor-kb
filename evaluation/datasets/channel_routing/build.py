#!/usr/bin/env python3
"""Build the channel_routing benchmark: the STAGE-1 routing decision BioMate makes before workflow
selection — "which resource/channel should this request go to?" (workflow vs tool-search vs live DB vs
literature vs ad-hoc code vs direct answer vs dataset discovery).

Grounded in BioMate's production router (frontend/server/galaxy-assistant.ts IntentType + ActionCategories):
the 7 channels map 1:1 to the real ActionCategories the router sets. Gold = the destination channel.
Drug-development use cases are deliberately the largest share (ADMET/docking/PBPK/QSAR/FEP/target-ID/CRO),
per the product's focus.

Purpose (per project policy): improve BioMate's actual channel routing + compare LLMs bare vs +harness.
`run_channel_routing.py` reports BOTH the raw LLM and LLM+harness for every model.

Run: python3 build.py   # writes data.jsonl (+ channels.json for the harness/README)
"""
import json, os
from collections import Counter

HERE = os.path.dirname(os.path.abspath(__file__))

# 7 channels — gold labels — each with the production ActionCategories mapping + the definition the
# +harness condition shows the model (lifted from the router's own intent descriptions).
CHANNELS = {
    "workflow": {
        "maps_to": "needsWorkflowGeneration",
        "def": "Run a multi-step analysis PIPELINE on data (nf-core or a custom BioMate workflow): "
               "ADMET screens, docking/virtual-screening, RBFE/FEP, PBPK simulation, QSAR training, "
               "RNA-seq, variant calling, scRNA-seq, proteomics, cryo-EM, etc."},
    "tool_search": {
        "maps_to": "needsToolSearch",
        "def": "Find, recommend, compare, or modify a specific TOOL/method to use (not run a full pipeline). "
               "e.g. 'what tool predicts hERG?', 'Vina vs Glide?', 'add an MM-GBSA rescoring step'."},
    "database_lookup": {
        "maps_to": "needsResearchAgent (structured DB)",
        "def": "Answer requires a LIVE query to a structured biological/chemical DATABASE: ChEMBL, DrugBank, "
               "Open Targets, PDB, UniProt, OMIM, ClinVar, Ensembl, GWAS Catalog, FAERS, mygene.info."},
    "literature_research": {
        "maps_to": "needsResearchAgent (literature)",
        "def": "Answer requires synthesizing published LITERATURE / evidence: state-of-the-art, mechanism, "
               "prior art, best-practice review, resistance mechanisms, method comparisons from papers."},
    "code_execution": {
        "maps_to": "run_code / ad-hoc compute",
        "def": "A short AD-HOC COMPUTATION on provided or small data, best done by running code directly "
               "(NOT a full pipeline): a similarity/property calc, a statistical test, a format conversion, "
               "a small fit, parsing a small file."},
    "knowledge_answer": {
        "maps_to": "needsLLMReasoning only",
        "def": "A direct FACTUAL/CONCEPTUAL answer from the model's own knowledge — a definition or "
               "explanation — needing NO tool, DB, literature, or data. e.g. 'what is Lipinski's rule of five?'."},
    "dataset_discovery": {
        "maps_to": "needsDatasetAccess",
        "def": "Find or FETCH an existing DATASET / accession: a public benchmark (PDBbind, TDC), a GEO/SRA/"
               "PRIDE accession, a reference dataset, or BioMate internal test data."},
}

# (id, query, gold_channel, domain, difficulty, acceptable_alts)
ITEMS = [
    # ---------------- workflow (run a pipeline) ----------------
    ("wf_01", "Run ADMET prediction (hERG, CYP3A4, oral bioavailability) on this list of 50 SMILES.", "workflow", "drug_discovery", "easy", []),
    ("wf_02", "Dock this 2,000-compound library against the EGFR kinase domain and rank by predicted affinity.", "workflow", "drug_discovery", "easy", []),
    ("wf_03", "Run an RBFE free-energy perturbation campaign for these 12 congeneric BRD4 inhibitors.", "workflow", "drug_discovery", "medium", []),
    ("wf_04", "Build a PBPK model for compound BMT-101 and simulate plasma concentration after a 50 mg oral dose.", "workflow", "drug_discovery", "medium", ["code_execution"]),
    ("wf_05", "Train a QSAR regression to predict aqueous solubility from these 1,200 molecules with measured logS.", "workflow", "drug_discovery", "medium", []),
    ("wf_06", "Generate 500 novel scaffolds with improved JAK1-over-JAK2 selectivity using a generative model.", "workflow", "drug_discovery", "medium", []),
    ("wf_07", "Run accelerated-stability degradation analysis on these HPLC time-course files.", "workflow", "drug_discovery", "hard", []),
    ("wf_08", "Process my paired-end bulk RNA-seq FASTQs from a mouse study into a counts matrix and DE table.", "workflow", "transcriptomics", "easy", []),
    ("wf_09", "Call somatic variants from these tumor–normal WGS BAMs with GATK Mutect2.", "workflow", "variant_calling", "easy", []),
    ("wf_10", "Run standard 10x scRNA-seq preprocessing and clustering on these Cell Ranger outputs.", "workflow", "single_cell", "easy", []),
    ("wf_11", "Analyze these DIA mass-spec runs for label-free protein quantification.", "workflow", "proteomics", "medium", []),
    ("wf_12", "Run single-particle 3D reconstruction on these motion-corrected cryo-EM micrographs.", "workflow", "cryo_em", "medium", []),

    # ---------------- tool_search (find/recommend/compare/modify a tool) ----------------
    ("ts_01", "What's the best open-source tool to predict hERG cardiotoxicity from structure?", "tool_search", "drug_discovery", "easy", []),
    ("ts_02", "Recommend a docking engine that handles covalent inhibitors.", "tool_search", "drug_discovery", "easy", []),
    ("ts_03", "Which tool should I use for retrosynthesis route planning?", "tool_search", "drug_discovery", "easy", []),
    ("ts_04", "Is there a tool to compute a synthetic-accessibility score for generated molecules?", "tool_search", "drug_discovery", "medium", []),
    ("ts_05", "Compare AutoDock Vina vs Glide for virtual screening — which should I pick?", "tool_search", "drug_discovery", "medium", ["literature_research"]),
    ("ts_06", "What method estimates protein–ligand binding free energy more accurately than MM-GBSA?", "tool_search", "drug_discovery", "medium", ["literature_research"]),
    ("ts_07", "What aligner do you recommend for spliced RNA-seq reads?", "tool_search", "transcriptomics", "easy", []),
    ("ts_08", "Recommend a tool for removing ambient RNA from droplet scRNA-seq.", "tool_search", "single_cell", "easy", []),
    ("ts_09", "Which caller is best for structural variants from long reads?", "tool_search", "variant_calling", "medium", []),
    ("ts_10", "What search engine do you recommend for immunopeptidomics DIA data?", "tool_search", "proteomics", "medium", []),
    ("ts_11", "Recommend a taxonomic profiler for shotgun metagenomes.", "tool_search", "metagenomics", "easy", []),
    ("ts_12", "Modify my docking workflow to add a post-docking MM-GBSA rescoring step.", "tool_search", "drug_discovery", "hard", ["workflow"]),

    # ---------------- database_lookup (live structured DB query) ----------------
    ("db_01", "What is the ChEMBL-reported IC50 of imatinib against ABL1?", "database_lookup", "drug_discovery", "easy", []),
    ("db_02", "Give me the Open Targets association score between JAK2 and rheumatoid arthritis.", "database_lookup", "drug_discovery", "easy", []),
    ("db_03", "What approved drugs in DrugBank target PCSK9?", "database_lookup", "drug_discovery", "easy", []),
    ("db_04", "Look up the DrugBank half-life and plasma protein binding of warfarin.", "database_lookup", "drug_discovery", "easy", []),
    ("db_05", "What is the PDB structure ID for the KRAS G12C covalent complex with sotorasib?", "database_lookup", "drug_discovery", "medium", []),
    ("db_06", "Fetch the UniProt sequence and domain annotation for human BTK.", "database_lookup", "drug_discovery", "easy", []),
    ("db_07", "What's the GWAS Catalog lead SNP for LDL cholesterol at the SORT1 locus?", "database_lookup", "genomics", "medium", []),
    ("db_08", "Which ClinVar variants in BRCA1 are classified pathogenic for breast cancer?", "database_lookup", "clinical_genomics", "medium", []),
    ("db_09", "What FAERS adverse events are most reported for semaglutide?", "database_lookup", "drug_discovery", "medium", []),
    ("db_10", "Get the Ensembl gene coordinates and transcripts for TP53 in GRCh38.", "database_lookup", "genomics", "easy", []),
    ("db_11", "What is the measured aqueous solubility of atorvastatin in the reference databases?", "database_lookup", "drug_discovery", "medium", []),
    ("db_12", "Map these HPO terms to candidate disease genes via OMIM/Monarch.", "database_lookup", "clinical_genomics", "medium", []),

    # ---------------- literature_research (evidence synthesis from papers) ----------------
    ("lit_01", "What's the current state of the art for predicting macrocycle membrane permeability?", "literature_research", "drug_discovery", "medium", []),
    ("lit_02", "Summarize the evidence for PROTAC ternary-complex cooperativity and how it's measured.", "literature_research", "drug_discovery", "medium", []),
    ("lit_03", "What is known about resistance mechanisms to KRAS G12C inhibitors?", "literature_research", "drug_discovery", "medium", []),
    ("lit_04", "Review the literature on PBPK model-validation standards for oral small molecules.", "literature_research", "drug_discovery", "hard", []),
    ("lit_05", "What published methods exist for de novo macrocyclic-peptide design against PPIs?", "literature_research", "drug_discovery", "hard", []),
    ("lit_06", "Find prior art on αvβ6 integrin antagonists for pulmonary fibrosis.", "literature_research", "drug_discovery", "medium", []),
    ("lit_07", "Summarize recent findings on TCR-repertoire changes in checkpoint-inhibitor responders.", "literature_research", "immunology", "medium", []),
    ("lit_08", "What are the recommended best practices for batch correction in large RNA-seq meta-analyses?", "literature_research", "transcriptomics", "medium", []),
    ("lit_09", "What does the literature say about hERG off-target liability of macrocyclic drugs?", "literature_research", "drug_discovery", "medium", []),
    ("lit_10", "Review the evidence linking SNCA expression to Parkinson's disease progression.", "literature_research", "clinical_genomics", "medium", []),
    ("lit_11", "Compare published FEP benchmark accuracies across the major software packages.", "literature_research", "drug_discovery", "hard", ["database_lookup"]),
    ("lit_12", "What's the consensus on the role of regulatory T cells in autoimmune disease flares?", "literature_research", "immunology", "medium", []),

    # ---------------- code_execution (short ad-hoc computation, run_code) ----------------
    ("ce_01", "Compute the Tanimoto similarity between these two SMILES: CCO and CCOC.", "code_execution", "drug_discovery", "easy", []),
    ("ce_02", "Calculate the molecular weight and cLogP for CC(=O)Oc1ccccc1C(=O)O.", "code_execution", "drug_discovery", "easy", []),
    ("ce_03", "I have these 20 IC50 values in two groups — run a Mann-Whitney U test and give me the p-value.", "code_execution", "drug_discovery", "medium", []),
    ("ce_04", "Convert this list of 8 InChI strings to canonical SMILES.", "code_execution", "drug_discovery", "easy", []),
    ("ce_05", "Given these dose and plasma-concentration arrays, fit a one-compartment PK model and report clearance.", "code_execution", "drug_discovery", "medium", ["workflow"]),
    ("ce_06", "Count how many of these 300 compounds pass Lipinski's rule of five.", "code_execution", "drug_discovery", "easy", []),
    ("ce_07", "Fit a 4-parameter logistic dose–response curve and report IC50 from these 8 points.", "code_execution", "drug_discovery", "medium", []),
    ("ce_08", "Here are 30 paired before/after measurements — run a paired t-test.", "code_execution", "statistics", "easy", []),
    ("ce_09", "Standardize and desalt these 50 SMILES and tell me how many are unique.", "code_execution", "drug_discovery", "medium", []),
    ("ce_10", "I have a small 12-gene × 6-sample counts table — compute CPM and a quick PCA.", "code_execution", "transcriptomics", "medium", ["workflow"]),
    ("ce_11", "Calculate ligand efficiency for these 15 hits given pIC50 and heavy-atom count.", "code_execution", "drug_discovery", "easy", []),
    ("ce_12", "Parse this VCF header and tell me how many samples and contigs it has.", "code_execution", "variant_calling", "easy", []),

    # ---------------- knowledge_answer (direct factual/conceptual, no tool) ----------------
    ("ka_01", "What is Lipinski's rule of five?", "knowledge_answer", "drug_discovery", "easy", []),
    ("ka_02", "Explain how MM-GBSA estimates binding free energy.", "knowledge_answer", "drug_discovery", "easy", []),
    ("ka_03", "What's the difference between IC50 and Ki?", "knowledge_answer", "drug_discovery", "easy", []),
    ("ka_04", "What does ADMET stand for and what does each property mean?", "knowledge_answer", "drug_discovery", "easy", []),
    ("ka_05", "Explain the hERG channel's role in cardiotoxicity.", "knowledge_answer", "drug_discovery", "easy", []),
    ("ka_06", "What is a PROTAC and how does it work mechanistically?", "knowledge_answer", "drug_discovery", "easy", []),
    ("ka_07", "What's the difference between pharmacokinetics and pharmacodynamics?", "knowledge_answer", "drug_discovery", "easy", []),
    ("ka_08", "What is the BOIN design for phase I dose escalation?", "knowledge_answer", "drug_discovery", "medium", []),
    ("ka_09", "What does 'stranded' library prep mean in RNA-seq?", "knowledge_answer", "transcriptomics", "easy", []),
    ("ka_10", "What is the difference between a competitive and an allosteric inhibitor?", "knowledge_answer", "drug_discovery", "easy", []),
    ("ka_11", "What is a GWAS and what does a Manhattan plot show?", "knowledge_answer", "genomics", "easy", []),
    ("ka_12", "What is the central dogma of molecular biology?", "knowledge_answer", "general_biology", "easy", []),

    # ---------------- dataset_discovery (find/fetch a dataset/accession) ----------------
    ("ds_01", "Find a public dataset of measured hERG inhibition to train an ADMET model.", "dataset_discovery", "drug_discovery", "medium", []),
    ("ds_02", "Is there a benchmark set of protein–ligand binding affinities I can download, like PDBbind?", "dataset_discovery", "drug_discovery", "easy", []),
    ("ds_03", "Get me a curated ADMET dataset from TDC (Therapeutics Data Commons).", "dataset_discovery", "drug_discovery", "easy", []),
    ("ds_04", "Download the RNA-seq counts for GEO accession GSE123456.", "dataset_discovery", "transcriptomics", "easy", []),
    ("ds_05", "Fetch the FASTQ files for SRA run SRR12345678.", "dataset_discovery", "genomics", "easy", []),
    ("ds_06", "Find a public kinase-inhibitor bioactivity dataset for benchmarking a QSAR model.", "dataset_discovery", "drug_discovery", "medium", []),
    ("ds_07", "Is there a PRIDE dataset of DIA immunopeptidomics I can use as a test set?", "dataset_discovery", "proteomics", "medium", []),
    ("ds_08", "Point me to a reference 10x PBMC scRNA-seq dataset for annotation.", "dataset_discovery", "single_cell", "easy", []),
    ("ds_09", "Where can I get a clean solubility dataset with measured logS values?", "dataset_discovery", "drug_discovery", "easy", []),
    ("ds_10", "Find a public cohort with matched genotype and drug-response phenotypes.", "dataset_discovery", "clinical_genomics", "hard", []),
    ("ds_11", "Do we have internal test data for the ADMET workflow I can run against?", "dataset_discovery", "drug_discovery", "medium", []),
    ("ds_12", "Find a mock-community metagenome dataset for benchmarking taxonomic profilers.", "dataset_discovery", "metagenomics", "medium", []),
]


def main():
    rows = []
    for i, q, gold, dom, diff, alts in ITEMS:
        assert gold in CHANNELS, f"bad channel {gold}"
        for a in alts:
            assert a in CHANNELS, f"bad alt {a}"
        rows.append({"id": i, "query": q, "correct_channel": gold, "acceptable_alts": alts,
                     "domain": dom, "difficulty": diff})
    open(os.path.join(HERE, "data.jsonl"), "w").write("\n".join(json.dumps(r) for r in rows) + "\n")
    json.dump(CHANNELS, open(os.path.join(HERE, "channels.json"), "w"), indent=2)
    dd = sum(1 for r in rows if r["domain"] == "drug_discovery")
    print(f"wrote {len(rows)} items -> data.jsonl")
    print(f"channels: {Counter(r['correct_channel'] for r in rows)}")
    print(f"drug_discovery: {dd}/{len(rows)} = {dd/len(rows):.0%}  | domains: {Counter(r['domain'] for r in rows)}")


if __name__ == "__main__":
    main()
