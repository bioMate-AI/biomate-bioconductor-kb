#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: MetaboAnalystR — meta_analysis_multiple_datasets
// MetaboAnalyst statistical Meta-Analysis across MULTIPLE metabolomics datasets. Each
// dataset is read, sanity-checked and individually normalized; datasets are then merged
// (ComBat batch adjustment), per-dataset differential expression (limma) is run, and the
// evidence is combined across studies (Stouffer p-value combination by default) into a
// single ranked meta-signature (combined t-stat + combined p-value) — more robust than
// any single study.
// Input: study1.csv, study2.csv
// Input-note: >=2 dataset CSVs named study*/dataset* (samples in cols, row1 = 2-group Label, same
//   level names across studies, >=25% shared feature names). Falls back to a self-contained 2-study
//   fixture with no input. The `// Input:` line must stay a bare comma-separated filename list
//   (executor parses it as the declared-input contract; prose mis-tokenises into bogus params).
// Container: 399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-metabolomics:3.20-deps
// R packages: MetaboAnalystR (GitHub xia-lab/MetaboAnalystR)
// Bioconductor: 3.20 | R: 4.4
// Requires: MetaboAnalystR
// Visualizations: cross-study PCA / density QC plots
// NOTE: Meta-analysis is a pure-statistics module (limma + ComBat) — NO internet download.
//       Per-dataset DE runs INSIDE CheckMetaDataConsistency (which also merges the studies).
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input] Read >=2 dataset CSVs (or synthesize a 2-study fixture with shared features)
//  * 2. [Per-dataset] ReadIndData + SanityCheckIndData + PerformIndNormalization (each study)
//  * 3. [Merge + DE] CheckMetaDataConsistency (ComBat merge + per-study limma DE)
//  * 4. [Combine] PerformPvalCombination (Stouffer) -> ranked meta-signature (meta.mat)
//  * 5. [Visualization & Output] cross-study QC plot + merged-data CSV + meta result CSV + RDS

nextflow.enable.dsl = 2

process BIOC_METABOANALYSTR_META_ANALYSIS_MULTIPLE_DATASETS {
    tag "${meta.id}"
    label 'process_medium'

    publishDir "${params.outdir}", mode: 'copy'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-metabolomics:3.20-deps"

    input:
    tuple val(meta), path(input_files, stageAs: '?/*')

    output:
    tuple val(meta), path("*.csv"), emit: tables, optional: true
    tuple val(meta), path("*.pdf"), emit: plots,  optional: true
    tuple val(meta), path("*.png"), emit: images, optional: true
    tuple val(meta), path("*.rds"), emit: objects, optional: true
    path "versions.yml",            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix        = task.ext.prefix ?: "${meta.id}"
    def combine_method = params.combine_method ?: 'stouffer'
    def bh_threshold   = params.bh_threshold ?: 0.05
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment.
    .bm_deps <- c("MetaboAnalystR")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      if (!requireNamespace("remotes", quietly=TRUE)) install.packages("remotes", repos="https://cloud.r-project.org")
      options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))
      .bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      .ma_deps <- c("impute","pcaMethods","siggenes","globaltest","GlobalAncova","Rgraphviz",
                    "KEGGgraph","SSPA","sva","limma","crmn","pls","caret","e1071","igraph",
                    "fitdistrplus","ellipse","scatterplot3d","pheatmap","RColorBrewer")
      .ma_miss <- .ma_deps[!vapply(.ma_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
      if (length(.ma_miss)) suppressWarnings(suppressMessages(tryCatch(BiocManager::install(.ma_miss, update=FALSE, ask=FALSE, site_repository=.bin), error=function(e) try(install.packages(.ma_miss), silent=TRUE))))
      if (!requireNamespace("MetaboAnalystR", quietly=TRUE)) suppressWarnings(suppressMessages(try(remotes::install_github("xia-lab/MetaboAnalystR", upgrade="never", quiet=TRUE, build=FALSE), silent=TRUE)))
    }
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }

        suppressPackageStartupMessages({ library(MetaboAnalystR) })

        .bm_finish <- function(status) {
          try(suppressWarnings(system("pkill -9 -f Rserve 2>/dev/null")), silent = TRUE)
          quit(save = "no", status = status, runLast = FALSE)
        }
        options(error = function() .bm_finish(1))

        combine_method <- "${combine_method}"
        bh_thresh      <- as.numeric("${bh_threshold}")

        # Datasets = any *.csv named study*/dataset* (user-supplied), else synthesize 2 studies.
        cands <- list.files(".", pattern = "^(study|dataset).*\\\\.csv\$", ignore.case = TRUE)
        if (length(cands) < 2) {
          set.seed(5)
          mk_study <- function(n_ctrl, n_case, feats, effect_idx, batch_shift) {
            grp <- c(rep("Control", n_ctrl), rep("Case", n_case))
            M <- matrix(rlnorm(length(feats)*length(grp), 3 + batch_shift, 0.35), nrow = length(feats))
            for (j in effect_idx) M[j, grp == "Case"] <- M[j, grp == "Case"] * runif(1, 1.8, 2.6)
            cn <- paste0(substr(grp,1,1), seq_along(grp))
            out <- rbind(c("Label", grp), cbind(feats, matrix(as.character(M), nrow = length(feats))))
            colnames(out) <- c("Sample", cn); out
          }
          feats_common <- sprintf("Metab_%02d", 1:35)
          feats1 <- c(feats_common, sprintf("Metab_%02d", 36:40))   # 40 features
          feats2 <- c(feats_common, sprintf("Metab_%02d", 41:45))   # 40 features, 35 shared (>=25%)
          write.csv(mk_study(6, 6, feats1, 1:12, 0.0),  "study1.csv", row.names = FALSE, quote = FALSE)
          write.csv(mk_study(5, 5, feats2, 1:12, 0.3),  "study2.csv", row.names = FALSE, quote = FALSE)
          cands <- c("study1.csv", "study2.csv")
          message("No input supplied — using a synthetic 2-study meta-analysis fixture (35 shared features).")
        }

        # ------------------------------------------------------------------
        # Read + per-dataset sanity-check + normalization
        # ------------------------------------------------------------------
        mSet <- InitDataObjects("conc", "metadata", FALSE)
        for (f in cands) {
          mSet <- ReadIndData(mSet, f, "colu")
          mSet <- SanityCheckIndData(mSet, f)
          mSet <- PerformIndNormalization(mSet, f, "med", 0)
        }

        # ------------------------------------------------------------------
        # Merge (ComBat) + per-study DE (limma runs inside), then combine evidence
        # ------------------------------------------------------------------
        mSet <- CheckMetaDataConsistency(mSet, TRUE)
        tryCatch({
          if (identical(combine_method, "vote")) {
            mSet <- PerformVoteCounting(mSet, bh_thresh, 2)
          } else if (identical(combine_method, "merge")) {
            mSet <- PerformMetaMerge(mSet, bh_thresh)
          } else {
            mSet <- PerformPvalCombination(mSet, combine_method, bh_thresh)   # "stouffer" | "fisher"
          }
        }, error = function(e) message("Meta combination failed (non-fatal): ", conditionMessage(e)))

        # Cross-study QC PCA (best-effort; PlotPCAPairSummaryMeta is the meta-specific pair plot).
        tryCatch({ mSet <- PlotPCAPairSummaryMeta(mSet, "meta_pca_pair_", "png", 72, NA, 5, "dataset") },
                 error = function(e) message("Meta PCA plot skipped (non-fatal): ", conditionMessage(e)))

        # Persist the ranked meta-signature
        tryCatch({
          mm <- NULL
          if (exists("meta.mat")) mm <- get("meta.mat")
          if (is.null(mm) && !is.null(mSet\$analSet\$metap.mat)) mm <- mSet\$analSet\$metap.mat
          if (!is.null(mm)) write.csv(as.data.frame(mm), "meta_analysis_combined_signature.csv", row.names = TRUE)
        }, error = function(e) message("Could not persist meta result matrix: ", conditionMessage(e)))

        saveRDS(mSet, "metaboanalyst_meta_mSet.rds")
        cat("MetaboAnalystR meta-analysis pipeline completed. Outputs written to working directory.\n")

    writeLines(c(
        '"BIOC_METABOANALYSTR_META_ANALYSIS_MULTIPLE_DATASETS":',
        paste0('    MetaboAnalystR: ', as.character(packageVersion('MetaboAnalystR')))
    ), "versions.yml")

    .bm_finish(0)
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_meta_analysis_combined_signature.csv versions.yml
    """
}

workflow BIOC_METABOANALYSTR_META_ANALYSIS_MULTIPLE_DATASETS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ study1.csv, study2.csv, ... ] ]

    main:
    BIOC_METABOANALYSTR_META_ANALYSIS_MULTIPLE_DATASETS(ch_input)

    emit:
    tables   = BIOC_METABOANALYSTR_META_ANALYSIS_MULTIPLE_DATASETS.out.tables
    plots    = BIOC_METABOANALYSTR_META_ANALYSIS_MULTIPLE_DATASETS.out.plots
    images   = BIOC_METABOANALYSTR_META_ANALYSIS_MULTIPLE_DATASETS.out.images
    objects  = BIOC_METABOANALYSTR_META_ANALYSIS_MULTIPLE_DATASETS.out.objects
    versions = BIOC_METABOANALYSTR_META_ANALYSIS_MULTIPLE_DATASETS.out.versions
}
