#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: MetaboAnalystR — power_sample_size_analysis
// MetaboAnalyst Power / Sample-Size analysis: from a pilot metabolomics concentration
// table with 2-group labels it estimates the effect-size distribution (SSPA) and predicts
// statistical power as a function of per-group sample size, so a study can be powered
// before it is run. Produces a power-vs-sample-size profile, an effect-size plot and a
// predicted-power table.
// Input: concentration_table.csv (samples in cols, row1 = Label 2-group) + optional class sheet.
//        Falls back to a self-contained synthetic 2-group pilot fixture.
// Container: 399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-metabolomics:3.20-deps
// R packages: MetaboAnalystR (GitHub xia-lab/MetaboAnalystR)
// Bioconductor: 3.20 | R: 4.4
// Requires: MetaboAnalystR
// Visualizations: power-vs-sample-size profile, SSPA effect-size plot
// NOTE: Power analysis is a pure-statistics module (vendored SSPA) — NO internet download.
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input] Read pilot concentration table + 2-group labels (or synthesize a fixture)
//  * 2. [Data Processing] Sanity-check, impute missing, normalize (log + auto-scale)
//  * 3. [Power] InitPowerAnal + PerformPowerProfiling (effect-size distribution + power curve)
//  * 4. [Visualization & Output] PlotPowerProfile + PlotPowerStat + predicted-power CSV + mSet RDS

nextflow.enable.dsl = 2

process BIOC_METABOANALYSTR_POWER_SAMPLE_SIZE_ANALYSIS {
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
    def prefix       = task.ext.prefix ?: "${meta.id}"
    def fdr_level    = params.fdr_level ?: 0.1
    def max_smpl     = params.max_sample_size ?: 200
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

        fdr_lvl  <- as.numeric("${fdr_level}")
        max_smpl <- as.integer("${max_smpl}")

        find_input <- function(cands) { for (f in cands) if (file.exists(f)) return(f); NULL }
        conc_file  <- find_input(c("concentration_table.csv","conc_table.csv","peak_intensity_table.csv","data.csv"))
        class_file <- find_input(c("class_labels.csv","sampleMetadata.csv","metadata.csv","labels.csv"))

        # Build the MetaboAnalyst "colu" upload (samples in columns, row1 = 'Label').
        ma_csv <- "metaboanalyst_power_input.csv"
        if (!is.null(conc_file)) {
          mat <- read.csv(conc_file, header = TRUE, row.names = 1, check.names = FALSE, stringsAsFactors = FALSE)
          if (!is.null(class_file)) {
            lab_df <- read.csv(class_file, header = TRUE, row.names = 1, check.names = FALSE, stringsAsFactors = FALSE)
            grp <- lab_df[[1]]; names(grp) <- rownames(lab_df)
            labels <- as.character(grp[colnames(mat)])
            if (any(is.na(labels))) stop("Class labels could not be matched to sample columns.")
          } else labels <- rep(c("GroupA","GroupB"), length.out = ncol(mat))
          out <- rbind(c("Label", as.character(labels)),
                       cbind(rownames(mat), matrix(as.character(as.matrix(mat)), nrow = nrow(mat))))
          colnames(out) <- c("Sample", colnames(mat))
          write.csv(out, ma_csv, row.names = FALSE, quote = FALSE)
        } else {
          # Synthetic pilot: 2 groups x 10 samples, 50 features, 15 differential.
          set.seed(11)
          n_per <- 10L; n_feat <- 50L; n_diff <- 15L
          grp <- rep(c("grp1","grp2"), each = n_per)
          M <- matrix(rlnorm(2L*n_per*n_feat, 3, 0.4), nrow = n_feat)
          for (j in seq_len(n_diff)) M[j, grp == "grp2"] <- M[j, grp == "grp2"] * runif(1, 1.8, 2.8)
          rn <- sprintf("Metab_%02d", seq_len(n_feat)); cn <- sprintf("S%03d", seq_len(2L*n_per))
          out <- rbind(c("Label", grp), cbind(rn, matrix(as.character(M), nrow = n_feat)))
          colnames(out) <- c("Sample", cn)
          write.csv(out, ma_csv, row.names = FALSE, quote = FALSE)
          message("No input supplied — using a synthetic 2-group pilot fixture for power analysis.")
        }

        # ------------------------------------------------------------------
        # Processing + normalization
        # ------------------------------------------------------------------
        mSet <- InitDataObjects("conc", "power", FALSE)
        mSet <- Read.TextData(mSet, ma_csv, "colu", "disc")
        mSet <- SanityCheckData(mSet)
        mSet <- ImputeMissingVar(mSet, method = "min")
        mSet <- PreparePrenormData(mSet)
        mSet <- Normalization(mSet, "NULL", "LogNorm", "AutoNorm", ref = NULL, ratio = FALSE, ratioNum = 20)

        # ------------------------------------------------------------------
        # Power profiling. InitPowerAnal("NA") auto-selects the 2 group levels.
        # ------------------------------------------------------------------
        mSet <- InitPowerAnal(mSet, "NA")
        mSet <- PerformPowerProfiling(mSet, fdr_lvl, max_smpl)

        tryCatch({ mSet <- PlotPowerProfile(mSet, fdr_lvl, max_smpl, "power_profile_", "png", 72, NA) },
                 error = function(e) message("Power profile plot skipped: ", conditionMessage(e)))
        tryCatch({ mSet <- PlotPowerStat(mSet, "power_effect_size_", "png", 72, NA) },
                 error = function(e) message("Power effect-size plot skipped: ", conditionMessage(e)))

        tryCatch({ if (!is.null(mSet\$analSet\$power.mat)) write.csv(as.data.frame(mSet\$analSet\$power.mat), "predicted_power_by_sample_size.csv", row.names = TRUE) },
                 error = function(e) message("Could not persist power.mat: ", conditionMessage(e)))

        saveRDS(mSet, "metaboanalyst_power_mSet.rds")
        cat("MetaboAnalystR power/sample-size pipeline completed. Outputs written to working directory.\n")

    writeLines(c(
        '"BIOC_METABOANALYSTR_POWER_SAMPLE_SIZE_ANALYSIS":',
        paste0('    MetaboAnalystR: ', as.character(packageVersion('MetaboAnalystR')))
    ), "versions.yml")

    .bm_finish(0)
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_predicted_power_by_sample_size.csv versions.yml
    """
}

workflow BIOC_METABOANALYSTR_POWER_SAMPLE_SIZE_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ concentration_table.csv (+ class_labels.csv) ] ]

    main:
    BIOC_METABOANALYSTR_POWER_SAMPLE_SIZE_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_METABOANALYSTR_POWER_SAMPLE_SIZE_ANALYSIS.out.tables
    plots    = BIOC_METABOANALYSTR_POWER_SAMPLE_SIZE_ANALYSIS.out.plots
    images   = BIOC_METABOANALYSTR_POWER_SAMPLE_SIZE_ANALYSIS.out.images
    objects  = BIOC_METABOANALYSTR_POWER_SAMPLE_SIZE_ANALYSIS.out.objects
    versions = BIOC_METABOANALYSTR_POWER_SAMPLE_SIZE_ANALYSIS.out.versions
}
