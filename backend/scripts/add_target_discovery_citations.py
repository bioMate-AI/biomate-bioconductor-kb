#!/usr/bin/env python3
"""Register the target-discovery workflows and attach peer-reviewed citations.

Adds a `citations` TEXT (JSON) column to `workflows` if absent, then registers /
updates:
  - target_scorecard_ranker              (drug_discovery)
  - query_opentarget                     (database / data_source)
  - autoantibody_isotype_stratification  (immunology)

Each row's `citations` is a JSON list of {ref, doi, supports} so the platform can
surface the scientific provenance of every scoring choice (the reason to use the
Open Targets methodology over hand-tuned heuristics: it is fully citable).

Idempotent: safe to re-run (ADD COLUMN guarded; check-before-insert; citations
always refreshed).
"""
from __future__ import annotations
import json, os, sqlite3, sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
DB_PATH = os.environ.get(
    "BIOMATE_DB", os.path.join(ROOT, "backend", "database", "galaxy_ai_tools.db"))

# --- peer-reviewed reference library ---------------------------------------
OT_PLATFORM = [
    {"ref": "Ochoa et al. 2021, Open Targets Platform: supporting systematic "
            "drug–target identification and prioritisation, Nucleic Acids Research "
            "49(D1):D1302", "doi": "10.1093/nar/gkaa1027",
     "supports": "association-score harmonic-sum aggregation"},
    {"ref": "Ochoa et al. 2023, The next-generation Open Targets Platform, "
            "Nucleic Acids Research 51(D1):D1353", "doi": "10.1093/nar/gkac1046",
     "supports": "platform data model + scoring"},
    {"ref": "Buniello et al. 2025, Open Targets Platform: facilitating therapeutic "
            "hypotheses building in drug discovery, Nucleic Acids Research "
            "53(D1):D1467", "doi": "10.1093/nar/gkae1080",
     "supports": "Precedence/Tractability/Doability/Safety prioritisation framework"},
]
GENETIC_SUPPORT = [
    {"ref": "Nelson et al. 2015, The support of human genetic evidence for approved "
            "drug indications, Nature Genetics 47:856", "doi": "10.1038/ng.3314",
     "supports": "genetic support raises approval odds (2.0%→8.2%)"},
    {"ref": "Minikel et al. 2024, Refining the impact of genetic evidence on clinical "
            "success, Nature 629:624", "doi": "10.1038/s41586-024-07316-0",
     "supports": "2.6× higher clinical success with genetic support"},
]
TRACTABILITY = [
    {"ref": "Oprea et al. 2018, Unexplored therapeutic opportunities in the human "
            "genome, Nature Reviews Drug Discovery 17:317", "doi": "10.1038/nrd.2018.14",
     "supports": "Target Development Level / tractability"},
]
CONSTRAINT = [
    {"ref": "Karczewski et al. 2020, The mutational constraint spectrum quantified "
            "from variation in 141,456 humans (gnomAD), Nature 581:434",
     "doi": "10.1038/s41586-020-2308-7",
     "supports": "LOEUF genetic-constraint safety metric"},
]
FCRN_ISOTYPE = [
    {"ref": "Howard et al. 2021, Safety, efficacy, and tolerability of efgartigimod "
            "in generalised myasthenia gravis (ADAPT), Lancet Neurology 20:526",
     "doi": "10.1016/S1474-4422(21)00159-9",
     "supports": "FcRn inhibition is IgG-selective (no effect on IgA/IgM)"},
    {"ref": "Vincent et al., AChR autoantibody isotype/subclass heterogeneity in "
            "myasthenia gravis, Neurology: Neuroimmunology & Neuroinflammation",
     "doi": "", "supports": "isotype/subclass heterogeneity of AChR autoantibodies"},
    {"ref": "RemeGen/Vor Bio, Telitacicept (dual BAFF/APRIL) Phase 3 in generalised "
            "myasthenia gravis, 2026", "doi": "",
     "supports": "BAFF/APRIL depletion lowers all isotypes incl. IgA/IgM"},
]

GATE3 = [
    {"ref": "FDA-NIH Biomarker Working Group, BEST (Biomarkers, EndpointS, and other "
            "Tools) Resource, 2016", "doi": "",
     "supports": "predictive vs prognostic biomarker definitions; interaction testing"},
    {"ref": "Parkes et al. 2024, PROFILE trial — biomarker-stratified RCT in Crohn's "
            "disease, Lancet Gastroenterology & Hepatology 9:? (interaction 1%, p=0.944)",
     "doi": "10.1016/S2468-1253(24)00034-7",
     "supports": "canonical predictive-biomarker failure (prognostic but not predictive)"},
    {"ref": "McShane et al. 2005, REMARK reporting recommendations for tumour marker "
            "prognostic studies, JNCI 97:1180", "doi": "10.1093/jnci/dji237",
     "supports": "prognostic/predictive marker reporting standards"},
]

REPURPOSING = [
    {"ref": "Lamb et al. 2006, The Connectivity Map: using gene-expression signatures "
            "to connect small molecules, genes, and disease, Science 313:1929",
     "doi": "10.1126/science.1132939",
     "supports": "signature-reversal connectivity scoring (KS enrichment)"},
    {"ref": "Subramanian et al. 2017, A Next Generation Connectivity Map: L1000 platform "
            "and the first 1,000,000 profiles, Cell 171:1437",
     "doi": "10.1016/j.cell.2017.10.049",
     "supports": "next-gen L1000/CMap perturbation reference + connectivity"},
]

INTEGRATION_BENCH = [
    {"ref": "Luecken et al. 2022, Benchmarking atlas-level data integration in single-cell "
            "genomics (scIB), Nature Methods 19:41", "doi": "10.1038/s41592-021-01336-8",
     "supports": "two-objective integration metrics; no universal-best method"},
    {"ref": "Korsunsky et al. 2019, Fast, sensitive and accurate integration of single-cell "
            "data with Harmony, Nature Methods 16:1289", "doi": "10.1038/s41592-019-0619-0",
     "supports": "LISI (iLISI/cLISI) diversity metric"},
    {"ref": "Tran et al. 2020, A benchmark of batch-effect correction methods for single-cell "
            "RNA sequencing data, Genome Biology 21:12", "doi": "10.1186/s13059-019-1850-9",
     "supports": "condition-dependent method selection"},
]

METADATA_HARMONIZER = [
    {"ref": "Kamdar et al. 2023, text2term: mapping free-text descriptions to ontology terms, "
            "Journal of Biomedical Semantics", "doi": "",
     "supports": "deterministic term-to-ontology mapping with confidence + human review"},
    {"ref": "Malone et al. 2010, Modeling sample variables with an Experimental Factor "
            "Ontology (EFO), Bioinformatics 26:1112", "doi": "10.1093/bioinformatics/btq099",
     "supports": "controlled-vocabulary grounding (EFO)"},
]

QC_TRIAGE = [
    {"ref": "Moore et al. 2011, Biospecimen Reporting for Improved Study Quality (BRISQ), "
            "Biopreservation and Biobanking 9:57", "doi": "10.1089/bio.2010.0036",
     "supports": "specimen provenance completeness"},
    {"ref": "Yilmaz et al. 2011, Minimum information about a marker gene sequence (MIxS), "
            "Nature Biotechnology 29:415", "doi": "10.1038/nbt.1823",
     "supports": "minimum-information provenance fields"},
    {"ref": "Leek et al. 2010, Tackling the widespread and critical impact of batch effects "
            "in high-throughput data, Nature Reviews Genetics 11:733", "doi": "10.1038/nrg2825",
     "supports": "batch-effect / batch-biology confounding"},
]

ANTIGEN = [
    {"ref": "Reynisson et al. 2020, NetMHCpan-4.1 and NetMHCIIpan-4.0: improved MHC antigen "
            "presentation predictions, Nucleic Acids Research 48:W449",
     "doi": "10.1093/nar/gkaa379",
     "supports": "peptide:MHC-I/II binding (%rank) prediction"},
    {"ref": "Racle et al. 2023, Machine learning predictions of MHC-II specificities reveal "
            "alternative binding mode of class II epitopes, Immunity 56:1359",
     "doi": "10.1016/j.immuni.2023.03.009",
     "supports": "MHC-II epitope specificity / T-cell antigen prioritisation"},
    {"ref": "Abelin et al. 2019, Defining HLA-II ligand processing and binding rules with "
            "mass spectrometry enhances cancer epitope prediction, Immunity 51:766",
     "doi": "10.1016/j.immuni.2019.08.012",
     "supports": "HLA-II immunopeptidome; under-served DP/DQ presentation"},
]

VIRTUAL_TRIAL = [
    {"ref": "FDA-NIH Biomarker Working Group, BEST Resource, 2016", "doi": "",
     "supports": "predictive vs prognostic; interaction test target"},
    {"ref": "Wang et al. 2019, Model-Informed Drug Development: Current US Regulatory "
            "Practice and Future Considerations, Clin Pharmacol Ther 105:899",
     "doi": "10.1002/cpt.1363",
     "supports": "in-silico trial / MIDD framework for design de-risking"},
    {"ref": "Brookes et al. 2001, Subgroup analyses in RCTs: quantifying false-positive/"
            "false-negative risk, Health Technol Assess 5(33)", "doi": "10.3310/hta5330",
     "supports": "interaction-test power methodology"},
]

WORKFLOWS = [
    {
        "name": "target_scorecard_ranker",
        "filename": "nextflow_nfcore/subworkflows/drug_discovery/"
                    "target_scorecard_ranker/main.nf",
        "domain": "drug_discovery",
        "description": ("Fuse multi-omic, per-target evidence into a ranked, "
                        "provenance-backed target scorecard. Open Targets association "
                        "aggregation + genetic-support weighting + tractability/safety "
                        "prioritisation; coverage-aware; human-in-the-loop; advisory "
                        "network-propagation / harmonic-sum second opinion."),
        "citations": OT_PLATFORM + GENETIC_SUPPORT + TRACTABILITY + CONSTRAINT,
        "step_count": 1,
        "tags": ["target_discovery", "prioritisation", "open_targets", "scorecard"],
    },
    {
        "name": "query_opentarget",
        "filename": "nextflow/subworkflows/database/query_opentarget.nf",
        "domain": "database",
        "description": ("Query the Open Targets Platform GraphQL API for a disease's "
                        "associated targets; emit a per-target evidence table "
                        "(genetic / biological / tractability / safety) in the "
                        "target-scorecard schema."),
        "citations": OT_PLATFORM,
        "step_count": 1,
        "tags": ["open_targets", "data_source", "evidence", "target_discovery"],
    },
    {
        "name": "autoantibody_isotype_stratification",
        "filename": "nextflow_nfcore/subworkflows/immunology/"
                    "autoantibody_isotype_stratification/main.nf",
        "domain": "immunology",
        "description": ("Stratify autoantibody-driven autoimmune patients (MG/SLE/"
                        "Sjögren's) by autoantibody isotype (IgG vs IgA/IgM) to predict "
                        "FcRn-inhibitor non-response and flag BAFF/APRIL (telitacicept) "
                        "candidates."),
        "citations": FCRN_ISOTYPE,
        "step_count": 1,
        "tags": ["immunology", "myasthenia_gravis", "stratification",
                 "autoantibody", "fcrn", "baff_april"],
    },
    {
        "name": "gate3_interaction_test",
        "filename": "nextflow_nfcore/subworkflows/biostatistics/"
                    "gate3_interaction_test/main.nf",
        "domain": "biostatistics",
        "description": ("Gate-3 test: is a biomarker PREDICTIVE (changes which treatment "
                        "is better) or merely PROGNOSTIC? Computes the biomarker x treatment "
                        "interaction (estimate/CI/p) on a stratified-trial dataset, plus the "
                        "fraction of treatment decisions changed vs the marker-blind choice, "
                        "and a gate-3 verdict. Binary + continuous outcomes."),
        "citations": GATE3,
        "step_count": 1,
        "tags": ["biostatistics", "biomarker", "predictive", "interaction_test",
                 "clinical_trial", "stratification", "gate3"],
    },
    {
        "name": "repurposing_signature_reversal",
        "filename": "nextflow_nfcore/subworkflows/drug_discovery/"
                    "repurposing_signature_reversal/main.nf",
        "domain": "drug_discovery",
        "description": ("Repurposing hypotheses via Connectivity-Map signature reversal: "
                        "given a disease up/down signature and a perturbation-signature "
                        "reference (LINCS/CMap), rank perturbagens by how strongly they "
                        "REVERSE the disease signature (negative connectivity = candidate). "
                        "KS enrichment (Lamb 2006 / Subramanian 2017)."),
        "citations": REPURPOSING,
        "step_count": 1,
        "tags": ["drug_discovery", "repurposing", "connectivity_map", "lincs",
                 "signature_reversal", "target_discovery"],
    },
    {
        "name": "integration_benchmark",
        "filename": "nextflow_nfcore/subworkflows/single_cell/integration_benchmark/main.nf",
        "domain": "single_cell",
        "description": ("Harmonization select-and-evaluate scorer: score an integrated "
                        "embedding on BOTH objectives (iLISI/cLISI + ASW batch/celltype, "
                        "scIB) and detect OVER-CORRECTION, so the right integration method "
                        "is selected rather than defaulting to one tool."),
        "citations": INTEGRATION_BENCH,
        "step_count": 1,
        "tags": ["single_cell", "integration", "batch_correction", "harmonization",
                 "scib", "lisi", "benchmark"],
    },
    {
        "name": "metadata_harmonizer",
        "filename": "nextflow_nfcore/subworkflows/database/metadata_harmonizer/main.nf",
        "domain": "database",
        "description": ("Deterministic, ontology-grounded metadata harmonizer: maps free-text "
                        "clinical/sample values to a controlled vocabulary via a stdlib match "
                        "cascade (exact/synonym/Jaccard/edit-distance) with confidence + "
                        "needs_review flags. Never invents a term or ontology ID; flags "
                        "out-of-dictionary values for human curation."),
        "citations": METADATA_HARMONIZER,
        "step_count": 1,
        "tags": ["database", "metadata_harmonization", "ontology_mapping", "efo", "hpo",
                 "human_in_the_loop", "data_curation"],
    },
    {
        "name": "cohort_qc_triage",
        "filename": "nextflow_nfcore/subworkflows/biostatistics/cohort_qc_triage/main.nf",
        "domain": "biostatistics",
        "description": ("Pre-harmonization QC-triage gate: metadata completeness, batch-vs-"
                        "biology confounding (chi-square + Cramer's V), BRISQ/MIxS provenance, "
                        "and per-sample QC-metric outliers -> INTEGRATE / TRIAGE / REJECT "
                        "verdict. Detects un-integratable confounded cohorts."),
        "citations": QC_TRIAGE,
        "step_count": 1,
        "tags": ["biostatistics", "quality_control", "cohort", "confounding", "provenance",
                 "harmonization", "triage"],
    },
    {
        "name": "antigen_resolution",
        "filename": "nextflow_nfcore/subworkflows/immunology/antigen_resolution/main.nf",
        "domain": "immunology",
        "description": ("TCR<->HLA<->peptide antigen-resolution integration: fuses airrflow "
                        "(TCR/BCR repertoire support), hlatyping (patient HLA), and "
                        "epitopeprediction (peptide:MHC %rank) into a ranked candidate "
                        "antigen/epitope list, emphasising the under-served HLA-DP/DQ "
                        "class-II space. Ingests upstream outputs; serves TCR-T programs."),
        "citations": ANTIGEN,
        "step_count": 1,
        "tags": ["immunology", "antigen_resolution", "tcr", "hla", "epitope",
                 "immunopeptidome", "class_ii", "hla_dp_dq", "tcr_t"],
    },
    {
        "name": "virtual_trial_gate3",
        "filename": "nextflow_nfcore/subworkflows/biostatistics/virtual_trial_gate3/main.nf",
        "domain": "biostatistics",
        "description": ("Trial-design power simulation for the gate-3 predictive-biomarker "
                        "test: from a design-assumption spec (biomarker prevalence, N, "
                        "per-stratum arm outcomes), deterministically simulate n_sim virtual "
                        "trials, run the biomarker x treatment interaction on each, and report "
                        "POWER, expected % decisions changed, a sample-size suggestion, and a "
                        "pass/under-powered verdict. De-risks/sizes the real RCT. Outputs "
                        "labelled SIMULATED — a design tool, not clinical evidence."),
        "citations": VIRTUAL_TRIAL,
        "step_count": 1,
        "tags": ["biostatistics", "virtual_trial", "in_silico_trial", "power",
                 "sample_size", "gate3", "predictive_biomarker", "trial_design", "midd"],
    },
]


def main():
    if not os.path.exists(DB_PATH):
        print(f"DB not found: {DB_PATH}", file=sys.stderr)
        return 1
    with sqlite3.connect(DB_PATH) as conn:
        cur = conn.cursor()
        cols = {c[1] for c in cur.execute("PRAGMA table_info(workflows)").fetchall()}
        if "citations" not in cols:
            cur.execute("ALTER TABLE workflows ADD COLUMN citations TEXT")
            print("  + added column workflows.citations")
            cols.add("citations")

        for w in WORKFLOWS:
            cites = json.dumps(w["citations"])
            exists = cur.execute("SELECT 1 FROM workflows WHERE name=?",
                                 (w["name"],)).fetchone()
            if exists:
                cur.execute("UPDATE workflows SET citations=? WHERE name=?",
                            (cites, w["name"]))
                print(f"  ~ updated citations: {w['name']} ({len(w['citations'])} refs)")
                continue
            row = {
                "name": w["name"],
                "filename": w["filename"],
                "domain": w["domain"],
                "description": w["description"],
                "workflow_json": json.dumps({"name": w["name"], "steps": {},
                                             "tags": w["tags"],
                                             "annotation": w["description"]}),
                "format": "nextflow",
                "source": "biomate_target_discovery",
                "category": "target_discovery",
                "step_count": w["step_count"],
                "tags": json.dumps(w["tags"]),
                "citations": cites,
                "executable": 1,
            }
            fields = [f for f in row if f in cols]
            cur.execute(
                f"INSERT INTO workflows ({','.join(fields)}) "
                f"VALUES ({','.join('?'*len(fields))})",
                [row[f] for f in fields],
            )
            print(f"  + registered: {w['name']} (+{len(w['citations'])} citations)")
        conn.commit()
    print("done.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
