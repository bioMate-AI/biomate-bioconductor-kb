#!/usr/bin/env python3
"""
register_metaboanalystr_suite.py

Registers the MetaboAnalystR workflow SUITE (one Nextflow subworkflow per MetaboAnalyst
analysis module) into the workflows DB, so each module is independently routable in
BioMate the same way the multi-workflow protein packages (#217 pattern) are.

Modules registered:
  * statistical  — Statistical Analysis (fold-change/t-test/PLS-DA)  [pre-existing .nf]
  * enrichment   — MSEA (ORA + QEA metabolite-set enrichment)
  * pathway      — MetPA (KEGG pathway analysis)
  * biomarker    — ROC / biomarker modelling
  * mummichog    — MS Peaks to Pathways (mummichog PSEA)

The .nf files live under backend/biomni_workflows/nextflow_nfcore/subworkflows/bioconductor/
and the DB `filename` is the logical path the executor resolves (nextflow_nfcore/...).

FTS: rebuilds workflows_fts (external-content FTS5) after inserting.

Usage:
    python3 scripts/register_metaboanalystr_suite.py [--db /path/to/galaxy_ai_tools.db]
"""
import argparse
import hashlib
import json
import sqlite3
from pathlib import Path

REPO_ROOT  = Path(__file__).parent.parent          # backend/
WF_ROOT    = REPO_ROOT / "biomni_workflows"         # where the .nf files physically live
DB_DEFAULT = REPO_ROOT / "database" / "galaxy_ai_tools.db"

IMG = "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-metabolomics:3.20-deps"

WORKFLOWS = [
    {
        "name":        "metaboanalystr_statistical",
        "filename":    "nextflow_nfcore/subworkflows/bioconductor/metaboanalystr/main.nf",
        "description": (
            "MetaboAnalystR Statistical Analysis: canonical one-factor targeted-metabolomics "
            "pipeline over a peak-intensity/concentration table + a 2-group class sheet. "
            "Normalises (log + auto-scale), runs univariate fold-change + t-test (volcano), "
            "and multivariate PLS-DA (score plot + VIP), with optional metabolite-set "
            "enrichment when a compound list is supplied. "
            "Input: peak_intensity_table.csv + class_labels.csv (+ optional compound_list.txt). "
            "Output: significant-feature tables, volcano/PLS-DA/VIP plots, mSet RDS."
        ),
        "annotation":  "Conc/peak table + 2-group labels -> fold-change + t-test + PLS-DA/VIP (MetaboAnalystR stat)",
        "tags":        "metaboanalyst,metaboanalystr,metabolomics,statistical analysis,fold change,t-test,volcano,pls-da,vip,normalization,univariate,multivariate,targeted metabolomics",
        "category":    "Metabolomics Statistical Analysis",
        "input_types": ["peak_intensity_table.csv (features x samples peak/concentration table)",
                        "class_labels.csv (sample -> 2-group class)", "compound_list.txt (optional, for enrichment)"],
        "output_types":["csv (significant features, VIP scores)", "pdf (volcano, PLS-DA score, VIP)", "rds (mSet)"],
        "step_count":  6,
    },
    {
        "name":        "metaboanalystr_enrichment",
        "filename":    "nextflow_nfcore/subworkflows/bioconductor/metaboanalystr_enrichment/main.nf",
        "description": (
            "MetaboAnalystR MSEA (Metabolite Set Enrichment Analysis). Over-Representation "
            "Analysis (ORA) from a compound-name list, or Quantitative Enrichment Analysis "
            "(QEA) from a concentration table + 2-group labels. Standardises compound names, "
            "selects a metabolite-set library (SMPDB pathway-associated sets) and scores "
            "enrichment (hypergeometric for ORA, globaltest for QEA). Ships a built-in "
            "HMDB-mappable compound-list fixture so it runs with no user input. "
            "Input: compound_list.txt (ORA) OR concentration_table.csv + class_labels.csv (QEA). "
            "Output: enrichment result table (p/FDR/hits), summary plot, name-map CSV, mSet RDS."
        ),
        "annotation":  "Compound list (ORA) or conc table (QEA) -> metabolite-set enrichment (MSEA, MetaboAnalystR)",
        "tags":        "metaboanalyst,metaboanalystr,metabolomics,msea,metabolite set enrichment,ora,qea,over-representation,quantitative enrichment,smpdb,hypergeometric,globaltest,enrichment analysis",
        "category":    "Metabolomics Enrichment (MSEA)",
        "input_types": ["compound_list.txt (one compound name per line, ORA)",
                        "concentration_table.csv + class_labels.csv (QEA)"],
        "output_types":["csv (msea_ora_result / msea_qea_result, name_map)", "png (enrichment summary)", "rds (mSet)"],
        "step_count":  4,
    },
    {
        "name":        "metaboanalystr_pathway",
        "filename":    "nextflow_nfcore/subworkflows/bioconductor/metaboanalystr_pathway/main.nf",
        "description": (
            "MetaboAnalystR MetPA pathway analysis: maps a compound-name list onto KEGG "
            "metabolic pathways for a chosen organism and scores pathway over-representation "
            "(Fisher exact) combined with topology impact (relative-betweenness-centrality "
            "node importance), giving a ranked pathway table (p, FDR, Impact) and a "
            "pathway-summary scatter. Organism via params.kegg_org (default hsa). Ships a "
            "built-in HMDB-mappable compound-list fixture. "
            "Input: compound_list.txt (+ optional KEGG organism code). "
            "Output: pathway_results.csv (p/FDR/Impact), pathway-summary plot, name-map, mSet RDS."
        ),
        "annotation":  "Compound list + organism -> KEGG pathway over-representation + topology impact (MetPA, MetaboAnalystR)",
        "tags":        "metaboanalyst,metaboanalystr,metabolomics,metpa,pathway analysis,kegg,pathway enrichment,topology,impact,betweenness centrality,fisher exact,pathway topology",
        "category":    "Metabolomics Pathway Analysis (MetPA)",
        "input_types": ["compound_list.txt (one compound name per line)", "kegg_org (organism KEGG code, param, default hsa)"],
        "output_types":["csv (pathway_results with p/FDR/Impact, name_map)", "png (pathway summary scatter)", "rds (mSet)"],
        "step_count":  5,
    },
    {
        "name":        "metaboanalystr_biomarker",
        "filename":    "nextflow_nfcore/subworkflows/bioconductor/metaboanalystr_biomarker/main.nf",
        "description": (
            "MetaboAnalystR Biomarker / ROC analysis over a metabolite concentration table "
            "with a 2-group class label. Normalises (log + auto-scale) then builds "
            "Monte-Carlo cross-validated multivariate biomarker models (random forest) "
            "producing ROC curves, predictive-accuracy plots, an importance-feature plot and "
            "a ranked feature table (AUC / p-value / log2FC). Pure-statistics module, needs "
            "no internet. Ships a self-contained synthetic 2-group fixture. "
            "Input: concentration_table.csv (+ optional class_labels.csv). "
            "Output: feature-ranking CSV, per-model AUC/accuracy CSV, ROC/accuracy/importance plots, mSet RDS."
        ),
        "annotation":  "Conc table + 2-group labels -> multivariate ROC biomarker models + ranked features (MetaboAnalystR)",
        "tags":        "metaboanalyst,metaboanalystr,metabolomics,biomarker,roc,auc,classification,cross-validation,random forest,feature ranking,predictive model,diagnostic",
        "category":    "Metabolomics Biomarker (ROC)",
        "input_types": ["concentration_table.csv (samples x metabolites)", "class_labels.csv (sample -> 2-group class, optional)"],
        "output_types":["csv (feature ranking, model AUC/accuracy)", "png (ROC curves, accuracy, importance)", "rds (mSet)"],
        "step_count":  5,
    },
    {
        "name":        "metaboanalystr_mummichog",
        "filename":    "nextflow_nfcore/subworkflows/bioconductor/metaboanalystr_mummichog/main.nf",
        "description": (
            "MetaboAnalystR MS Peaks to Pathways (mummichog). Takes an untargeted LC-MS peak "
            "list (m/z, p-value, t-score) with instrument mass-accuracy + ionisation mode, "
            "tentatively annotates m/z to compounds and runs pathway-set enrichment analysis "
            "(PSEA) against a KEGG/BioCyc metabolic model, giving a ranked pathway table "
            "(Fisher/EASE p, hits) + an enrichment scatter — no prior compound identification "
            "required. Params: ms_mode (positive/negative/mixed), instrument_ppm, mummichog_lib. "
            "Ships a synthetic peak-list fixture. "
            "Input: peaklist.txt (columns m.z, p.value, t.score). "
            "Output: mummichog_pathway_enrichment.csv, matched-compound CSV, peaks-to-paths scatter, mSet RDS."
        ),
        "annotation":  "LC-MS peak list (m/z, p) -> mummichog peaks-to-pathways PSEA (MetaboAnalystR)",
        "tags":        "metaboanalyst,metaboanalystr,metabolomics,mummichog,ms peaks to pathways,psea,untargeted,lc-ms,peak list,mz,pathway enrichment,functional analysis,annotation-free",
        "category":    "Metabolomics MS Peaks to Pathways (mummichog)",
        "input_types": ["peaklist.txt (columns m.z, p.value, t.score)", "ms_mode/instrument_ppm/mummichog_lib (params)"],
        "output_types":["csv (mummichog pathway enrichment, matched compounds)", "png (peaks-to-paths scatter)", "rds (mSet)"],
        "step_count":  5,
    },
    {
        "name":        "metaboanalystr_power",
        "filename":    "nextflow_nfcore/subworkflows/bioconductor/metaboanalystr_power/main.nf",
        "description": (
            "MetaboAnalystR Power / Sample-Size analysis: from a pilot metabolomics "
            "concentration table with 2-group labels it estimates the effect-size "
            "distribution (SSPA) and predicts statistical power as a function of per-group "
            "sample size, so a metabolomics study can be powered before it is run. Pure "
            "statistics, needs no internet. Ships a synthetic 2-group pilot fixture. "
            "Input: concentration_table.csv (+ optional class_labels.csv). "
            "Output: predicted power-by-sample-size table, power-profile + effect-size plots, mSet RDS."
        ),
        "annotation":  "Pilot conc table + 2-group labels -> predicted power vs sample size (SSPA, MetaboAnalystR)",
        "tags":        "metaboanalyst,metaboanalystr,metabolomics,power analysis,sample size,statistical power,sspa,effect size,study design,pilot study,power calculation",
        "category":    "Metabolomics Power Analysis",
        "input_types": ["concentration_table.csv (samples x metabolites, 2-group)", "class_labels.csv (optional)"],
        "output_types":["csv (predicted power by sample size)", "png (power profile, effect-size)", "rds (mSet)"],
        "step_count":  4,
    },
    {
        "name":        "metaboanalystr_timeseries",
        "filename":    "nextflow_nfcore/subworkflows/bioconductor/metaboanalystr_timeseries/main.nf",
        "description": (
            "MetaboAnalystR Time-Series / Two-Factor analysis via ASCA (ANOVA-Simultaneous "
            "Component Analysis). Decomposes a longitudinal metabolomics matrix into the "
            "variation from each experimental factor (time and phenotype) and their "
            "interaction, flags well-modelled / outlying metabolites per factor "
            "(leverage + SPE), and permutation-tests model significance. Pure statistics, "
            "needs no internet. Ships a synthetic 3-subject x 2-phenotype x 4-timepoint fixture. "
            "Input: data.csv (samples x metabolites) + metadata.csv (Sample, Time, Phenotype, Subject). "
            "Output: per-factor significant-feature tables, ASCA score/interaction/permutation plots, mSet RDS."
        ),
        "annotation":  "Longitudinal conc matrix + 2-factor metadata -> ASCA time/phenotype decomposition (MetaboAnalystR)",
        "tags":        "metaboanalyst,metaboanalystr,metabolomics,time series,two-factor,asca,anova,longitudinal,repeated measures,multifactor,temporal,interaction",
        "category":    "Metabolomics Time-Series (ASCA)",
        "input_types": ["data.csv (samples x metabolites)", "metadata.csv (Sample, Time, Phenotype, Subject)"],
        "output_types":["csv (significant features per factor)", "png (ASCA score/interaction/permutation)", "rds (mSet)"],
        "step_count":  5,
    },
    {
        "name":        "metaboanalystr_meta",
        "filename":    "nextflow_nfcore/subworkflows/bioconductor/metaboanalystr_meta/main.nf",
        "description": (
            "MetaboAnalystR statistical Meta-Analysis across MULTIPLE metabolomics datasets. "
            "Each dataset is read, sanity-checked and individually normalized; datasets are "
            "merged (ComBat batch adjustment), per-dataset differential expression (limma) is "
            "run, and evidence is combined across studies (Stouffer p-value combination by "
            "default; Fisher / vote-counting / effect-size merge alternatives) into a single "
            "ranked meta-signature. Pure statistics, needs no internet. Ships a synthetic "
            "2-study fixture with shared features. "
            "Input: >=2 dataset CSVs (samples in cols, row1 = 2-group Label, >=25% shared features). "
            "Output: combined meta-signature table, merged-data CSV, cross-study PCA QC plot, mSet RDS."
        ),
        "annotation":  "Multiple metabolomics datasets -> ComBat merge + limma DE + cross-study p-value combination (MetaboAnalystR)",
        "tags":        "metaboanalyst,metaboanalystr,metabolomics,meta-analysis,multiple datasets,combat,batch effect,limma,p-value combination,stouffer,fisher,vote counting,cross-study,integration",
        "category":    "Metabolomics Meta-Analysis",
        "input_types": ["study1.csv, study2.csv, ... (>=2 datasets, samples in cols, row1 = 2-group Label)"],
        "output_types":["csv (combined meta-signature, merged data)", "png (cross-study PCA)", "rds (mSet)"],
        "step_count":  5,
    },
]

TOOLS_USED = "MetaboAnalystR"
DOMAIN     = "metabolomics"


def workflow_hash(entry: dict) -> str:
    h = hashlib.sha256()
    h.update((entry["name"] + entry["filename"] + entry["description"]).encode("utf-8"))
    return h.hexdigest()


def rebuild_fts(conn: sqlite3.Connection) -> None:
    print("  Rebuilding workflows_fts …", end=" ")
    conn.execute("DELETE FROM workflows_fts")
    conn.execute("""
        INSERT INTO workflows_fts(rowid, name, description, annotation, tags, domain, tools_used)
        SELECT id, name, description, annotation, tags, domain, tools_used
        FROM workflows
    """)
    print("done.")


def register(db_path: Path) -> None:
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    inserted = updated = skipped = 0

    for entry in WORKFLOWS:
        # physical path check (logical filename -> biomni_workflows/<filename>)
        nf_path = WF_ROOT / entry["filename"]
        if not nf_path.exists():
            print(f"  WARN  {entry['name']} — .nf not found at {nf_path}; skipping")
            skipped += 1
            continue
        nf_content = nf_path.read_text(encoding="utf-8")
        h = workflow_hash(entry)

        row = conn.execute(
            "SELECT id FROM workflows WHERE name = ? OR filename = ?",
            (entry["name"], entry["filename"]),
        ).fetchone()

        cols_vals = {
            "name":         entry["name"],
            "filename":     entry["filename"],
            "description":  entry["description"],
            "annotation":   entry["annotation"],
            "tags":         entry["tags"],
            "domain":       DOMAIN,
            "category":     entry["category"],
            "docker_image": IMG,
            "input_types":  json.dumps(entry["input_types"]),
            "output_types": json.dumps(entry["output_types"]),
            "step_count":   entry["step_count"],
            "tools_used":   TOOLS_USED,
            "format":       "nextflow",
            "executable":   1,
            "source":       "metaboanalystr-suite",
            "workflow_hash": h,
            "workflow_json": nf_content,
        }

        if row:
            set_clause = ", ".join(f"{k} = ?" for k in cols_vals)
            conn.execute(
                f"UPDATE workflows SET {set_clause} WHERE id = ?",
                (*cols_vals.values(), row["id"]),
            )
            print(f"  UPD   {entry['name']} (id={row['id']})")
            updated += 1
        else:
            keys = ",".join(cols_vals.keys())
            qs   = ",".join("?" * len(cols_vals))
            conn.execute(
                f"INSERT INTO workflows ({keys}) VALUES ({qs})",
                tuple(cols_vals.values()),
            )
            print(f"  ADD   {entry['name']}")
            inserted += 1

    conn.commit()
    rebuild_fts(conn)
    conn.commit()
    conn.close()
    print(f"\nDone: {inserted} inserted, {updated} updated, {skipped} skipped.")


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--db", type=Path, default=DB_DEFAULT)
    args = ap.parse_args()
    print(f"DB: {args.db}")
    register(args.db)
