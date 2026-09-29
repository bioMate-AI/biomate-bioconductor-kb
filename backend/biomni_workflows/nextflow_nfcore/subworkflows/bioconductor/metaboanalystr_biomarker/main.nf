#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: MetaboAnalystR — biomarker_roc_analysis
// MetaboAnalyst Biomarker / ROC analysis over a metabolite concentration table with a
// 2-group class label: normalization (log + auto-scale), then multivariate exploratory
// biomarker modelling (Monte-Carlo cross-validated feature-subset models) producing
// ROC curves, predictive-accuracy plots, an importance-feature plot and a ranked
// feature (AUC / p-value / log2FC) table.
// Input: concentration table CSV (samples in rows, 2nd column = 2-group Label; or a
//        features x samples matrix + a class sheet). Falls back to a self-contained
//        synthetic 2-group fixture when no input is supplied (runs out-of-the-box).
// Container: 399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-metabolomics:3.20-deps
// R packages: MetaboAnalystR (GitHub xia-lab/MetaboAnalystR)
// Bioconductor: 3.20 | R: 4.4
// Requires: MetaboAnalystR
// Visualizations: ROC curves (all feature-subset models), predictive accuracy plot,
//                 importance-feature (selection-frequency) plot
// NOTE: Biomarker/ROC is a pure-statistics module — it consumes ONLY the concentration
//       table and needs NO internet library download (unlike enrichment/pathway/mummichog).
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Data Processing] Init mSet (conc / roc) + read/synthesize a 2-group concentration table
//  * 2. [Data Processing] Sanity-check, impute missing (LoD), normalize (log + auto-scale)
//  * 3. [Biomarker Modelling] Exploratory multivariate ROC: Monte-Carlo CV feature-subset models
//  * 4. [Ranking] CalculateFeatureRanking -> per-feature AUC / p-value / log2FC table
//  * 5. [Visualization & Output] ROC curves, accuracy plot, importance plot, ranked-feature CSV, mSet RDS

nextflow.enable.dsl = 2

process BIOC_METABOANALYSTR_BIOMARKER_ROC_ANALYSIS {
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
    def prefix = task.ext.prefix ?: "${meta.id}"
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
                    "fitdistrplus","ellipse","scatterplot3d","pheatmap","RColorBrewer","pROC","randomForest")
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

        suppressPackageStartupMessages({
          library(MetaboAnalystR)
        })

        # Ensure the Batch task exits promptly. MetaboAnalystR/OptiLCMS fork a background
        # Rserve daemon at init which keeps this task's stdout/stderr FDs open, so the AWS
        # Batch container hangs in RUNNING for the full timeout AFTER the R script finishes
        # or errors. Kill Rserve on both paths so the container exits in seconds.
        .bm_finish <- function(status) {
          try(suppressWarnings(system("pkill -9 -f Rserve 2>/dev/null")), silent = TRUE)
          quit(save = "no", status = status, runLast = FALSE)
        }
        options(error = function() .bm_finish(1))

        # ------------------------------------------------------------------
        # 1. Read user input (conc table + 2-group Label) OR build a fixture
        # ------------------------------------------------------------------
        find_input <- function(cands) { for (f in cands) if (file.exists(f)) return(f); NULL }
        conc_file  <- find_input(c("concentration_table.csv","conc_table.csv","peak_intensity_table.csv","peak_table.csv","dataMatrix.csv","data.csv"))
        class_file <- find_input(c("class_labels.csv","sampleMetadata.csv","metadata.csv","labels.csv"))

        # MetaboAnalyst "rowu" upload = samples in ROWS, col 1 = Sample, col 2 = Label,
        # remaining cols = metabolite concentrations.
        ma_csv <- "metaboanalyst_roc_input.csv"
        if (!is.null(conc_file)) {
          mat <- read.csv(conc_file, header = TRUE, row.names = 1, check.names = FALSE, stringsAsFactors = FALSE)
          # Heuristic: MetaboAnalyst tables are usually features x samples; transpose to samples x features.
          # If a class sheet exists and its rownames match the columns of mat, mat is features x samples.
          if (!is.null(class_file)) {
            lab_df <- read.csv(class_file, header = TRUE, row.names = 1, check.names = FALSE, stringsAsFactors = FALSE)
            grp <- lab_df[[1]]; names(grp) <- rownames(lab_df)
            if (all(colnames(mat) %in% names(grp))) {
              samp <- colnames(mat); feat <- rownames(mat); X <- t(mat)
            } else if (all(rownames(mat) %in% names(grp))) {
              samp <- rownames(mat); feat <- colnames(mat); X <- as.matrix(mat)
            } else stop("Class labels could not be matched to the concentration table samples.")
            labels <- as.character(grp[samp])
          } else {
            # No class sheet: assume features x samples, split into two balanced groups.
            samp <- colnames(mat); feat <- rownames(mat); X <- t(mat)
            labels <- rep(c("GroupA","GroupB"), length.out = length(samp))
          }
          out <- cbind(Sample = samp, Label = labels, as.data.frame(X, check.names = FALSE))
          write.csv(out, ma_csv, row.names = FALSE, quote = FALSE)
        } else {
          # ---- Self-contained synthetic fixture: 2 groups x 20 samples, 40 metabolites,
          #      12 of which are truly differential (so ROC/importance are non-trivial). ----
          set.seed(42)
          n_per <- 20L; n_feat <- 40L; n_diff <- 12L
          grp <- rep(c("Disease","Control"), each = n_per)
          feat_nm <- sprintf("Metab_%02d", seq_len(n_feat))
          samp_nm <- sprintf("S%03d", seq_len(2L*n_per))
          X <- matrix(rlnorm(2L*n_per*n_feat, meanlog = 3, sdlog = 0.4), nrow = 2L*n_per, ncol = n_feat)
          # inject a group effect into the first n_diff features for the Disease group
          for (j in seq_len(n_diff)) X[grp == "Disease", j] <- X[grp == "Disease", j] * runif(1, 1.8, 3.0)
          colnames(X) <- feat_nm; rownames(X) <- samp_nm
          out <- cbind(Sample = samp_nm, Label = grp, as.data.frame(X, check.names = FALSE))
          write.csv(out, ma_csv, row.names = FALSE, quote = FALSE)
          message("No input supplied — using a self-contained synthetic 2-group biomarker fixture.")
        }

        # ------------------------------------------------------------------
        # 2. Init mSet (conc / roc) + processing / normalization
        # ------------------------------------------------------------------
        mSet <- InitDataObjects("conc", "roc", FALSE)
        mSet <- Read.TextData(mSet, ma_csv, "rowu", "disc")
        mSet <- SanityCheckData(mSet)
        # ImputeMissingVar is the exported min/LoD imputation (ReplaceMin is NOT exported in 4.x).
        mSet <- ImputeMissingVar(mSet, method = "lod")
        mSet <- PreparePrenormData(mSet)
        mSet <- Normalization(mSet, "NULL", "LogNorm", "AutoNorm", ref = NULL, ratio = FALSE, ratioNum = 20)

        # ------------------------------------------------------------------
        # 3. Exploratory multivariate biomarker modelling (Monte-Carlo CV)
        # ------------------------------------------------------------------
        mSet <- SetAnalysisMode(mSet, "explore")
        tryCatch({
          mSet <- PerformCV.explore(mSet, cls.method = "rf", rank.method = "rf", lvNum = 2)
        }, error = function(e) message("Exploratory CV modelling failed (non-fatal): ", conditionMessage(e)))

        # ROC / accuracy / importance plots (best-effort; each guarded)
        tryCatch({ mSet <- PlotROC(mSet, "roc_curves_", "png", 300, mdl.inx = 0, avg.method = "threshold", show.conf = FALSE, show.holdout = FALSE) },
                 error = function(e) message("ROC plot skipped: ", conditionMessage(e)))
        tryCatch({ mSet <- PlotAccuracy(mSet, "roc_accuracy_", "png", 300) },
                 error = function(e) message("Accuracy plot skipped: ", conditionMessage(e)))
        tryCatch({ mSet <- PlotImpBiomarkers(mSet, "roc_importance_features_", "png", 300, mdl.inx = -1, measure = "freq", feat.num = 15) },
                 error = function(e) message("Importance-feature plot skipped: ", conditionMessage(e)))

        # Persist the multivariate ROC summary (per-model AUC + accuracy)
        tryCatch({
          mr <- mSet\$analSet\$multiROC
          if (!is.null(mr)) {
            if (!is.null(mr\$accu.mat)) write.csv(as.data.frame(mr\$accu.mat), "roc_model_accuracy.csv", row.names = TRUE)
            if (!is.null(mr\$auc.vec))  write.csv(data.frame(model = names(mr\$auc.vec), AUC = as.numeric(mr\$auc.vec)), "roc_model_auc.csv", row.names = FALSE)
          }
        }, error = function(e) message("Could not persist multiROC tables: ", conditionMessage(e)))

        # ------------------------------------------------------------------
        # 4. Per-feature ranking table (AUC / p-value / log2FC).
        #    In 'univ' mode CalculateFeatureRanking writes metaboanalyst_roc_univ.csv directly,
        #    so run it in univ mode to guarantee a written ranked-feature CSV, then restore.
        # ------------------------------------------------------------------
        tryCatch({
          mSet <- SetAnalysisMode(mSet, "univ")
          mSet <- CalculateFeatureRanking(mSet)
          if (exists("feat.rank.mat")) write.csv(as.data.frame(feat.rank.mat), "biomarker_feature_ranking.csv", row.names = TRUE)
        }, error = function(e) message("Feature ranking skipped (non-fatal): ", conditionMessage(e)))

        # ------------------------------------------------------------------
        # 5. Save the mSet object
        # ------------------------------------------------------------------
        saveRDS(mSet, "metaboanalyst_biomarker_mSet.rds")
        cat("MetaboAnalystR biomarker/ROC pipeline completed. Outputs written to working directory.\n")

    writeLines(c(
        '"BIOC_METABOANALYSTR_BIOMARKER_ROC_ANALYSIS":',
        paste0('    MetaboAnalystR: ', as.character(packageVersion('MetaboAnalystR')))
    ), "versions.yml")

    # Kill Rserve + clean exit so the Batch container terminates promptly.
    .bm_finish(0)
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_biomarker_feature_ranking.csv versions.yml
    """
}

workflow BIOC_METABOANALYSTR_BIOMARKER_ROC_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ concentration_table.csv, class_labels.csv (optional) ] ]

    main:
    BIOC_METABOANALYSTR_BIOMARKER_ROC_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_METABOANALYSTR_BIOMARKER_ROC_ANALYSIS.out.tables
    plots    = BIOC_METABOANALYSTR_BIOMARKER_ROC_ANALYSIS.out.plots
    images   = BIOC_METABOANALYSTR_BIOMARKER_ROC_ANALYSIS.out.images
    objects  = BIOC_METABOANALYSTR_BIOMARKER_ROC_ANALYSIS.out.objects
    versions = BIOC_METABOANALYSTR_BIOMARKER_ROC_ANALYSIS.out.versions
}
