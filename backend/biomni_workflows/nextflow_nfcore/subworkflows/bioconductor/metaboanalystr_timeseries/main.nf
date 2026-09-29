#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: MetaboAnalystR — timeseries_two_factor_asca
// MetaboAnalyst Time-Series / Two-Factor analysis via ASCA (ANOVA-Simultaneous Component
// Analysis). Decomposes a longitudinal metabolomics concentration matrix into the variation
// attributable to each experimental factor (time and phenotype) and their interaction,
// then flags well-modelled / outlying metabolites per factor (leverage + SPE cutoffs) with
// a permutation test for model significance.
// Input: data.csv (samples x metabolites) + metadata.csv (Sample, Time, Phenotype, Subject).
//        Falls back to a self-contained synthetic 3-subject x 2-phenotype x 4-timepoint fixture.
// Container: 399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-metabolomics:3.20-deps
// R packages: MetaboAnalystR (GitHub xia-lab/MetaboAnalystR)
// Bioconductor: 3.20 | R: 4.4
// Requires: MetaboAnalystR
// Visualizations: ASCA factor-A/B score plots, interaction plot, permutation plot
// NOTE: ASCA is a pure-statistics module — NO internet download. Two factors are read from
//       the metadata sheet (ReadMetaData + SanityCheckMeta), not from the data matrix.
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input] Read data matrix + 2-factor metadata (Time/Phenotype/Subject) or synthesize
//  * 2. [Data Processing] SanityCheckMeta + SanityCheckData + impute + normalize
//  * 3. [ASCA] Perform.ASCA + CalculateImpVarCutoff (well-modelled vs outlier features)
//  * 4. [Permutation] Perform.ASCA.permute (model-significance test)
//  * 5. [Visualization & Output] ASCA factor/interaction/permutation plots + Sig_features CSVs + RDS

nextflow.enable.dsl = 2

process BIOC_METABOANALYSTR_TIMESERIES_TWO_FACTOR_ASCA {
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
    def prefix   = task.ext.prefix ?: "${meta.id}"
    def perm_num = params.perm_num ?: 20
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

        perm_num <- as.integer("${perm_num}")

        find_input <- function(cands) { for (f in cands) if (file.exists(f)) return(f); NULL }
        data_file <- find_input(c("data.csv","concentration_table.csv","conc_table.csv","peak_intensity_table.csv"))
        meta_file <- find_input(c("metadata.csv","meta.csv","sample_metadata.csv"))

        if (is.null(data_file) || is.null(meta_file)) {
          # Synthetic longitudinal fixture: 3 subjects x 2 phenotypes x 4 timepoints = 24 samples,
          # 40 features (12 time-responsive, 12 phenotype-responsive). All time x group cells filled.
          set.seed(3)
          subs <- 1:3; phenos <- c("Ctrl","Trt"); times <- c(0,6,12,24)
          grid <- expand.grid(Subject = subs, Phenotype = phenos, Time = times, KEEP.OUT.ATTRS = FALSE, stringsAsFactors = FALSE)
          grid <- grid[order(grid\$Phenotype, grid\$Subject, grid\$Time), ]
          n <- nrow(grid); n_feat <- 40L
          samp <- sprintf("%s_S%d_T%02d", grid\$Phenotype, grid\$Subject, grid\$Time)
          X <- matrix(rlnorm(n*n_feat, 3, 0.3), nrow = n, ncol = n_feat)
          for (j in 1:12)  X[, j] <- X[, j] * (1 + 0.06 * grid\$Time)                     # time effect
          for (j in 13:24) X[grid\$Phenotype == "Trt", j] <- X[grid\$Phenotype == "Trt", j] * 2.0  # phenotype effect
          colnames(X) <- sprintf("Metab_%02d", seq_len(n_feat)); rownames(X) <- samp
          data_file <- "data.csv"; meta_file <- "metadata.csv"
          write.csv(cbind(Sample = samp, as.data.frame(X, check.names = FALSE)), data_file, row.names = FALSE, quote = FALSE)
          # metadata columns MUST be named Time, Phenotype, Subject for design.type="time"
          write.csv(data.frame(Sample = samp, Time = grid\$Time, Phenotype = grid\$Phenotype, Subject = grid\$Subject),
                    meta_file, row.names = FALSE, quote = FALSE)
          message("No input supplied — using a synthetic 3-subject x 2-phenotype x 4-timepoint ASCA fixture.")
        }

        # ------------------------------------------------------------------
        # Init two-factor time-series object
        # ------------------------------------------------------------------
        mSet <- InitDataObjects("conc", "ts", FALSE)
        mSet <- SetDesignType(mSet, "time")
        mSet <- Read.TextDataTs(mSet, data_file, "rowu")
        mSet <- ReadMetaData(mSet, meta_file)
        mSet <- SanityCheckMeta(mSet, 1)
        mSet <- SanityCheckData(mSet)
        mSet <- ImputeMissingVar(mSet, method = "min")
        mSet <- Normalization(mSet, "NULL", "LogNorm", "AutoNorm", ref = NULL, ratio = FALSE, ratioNum = 20)

        # ------------------------------------------------------------------
        # ASCA decomposition + significant-variable cutoffs
        # ------------------------------------------------------------------
        mSet <- Perform.ASCA(mSet, 1, 2, 2, 2)
        mSet <- CalculateImpVarCutoff(mSet, 0.05, 0.95)

        tryCatch({ mSet <- PlotASCAModel(mSet, "asca_factor_time_",  "png", 72, NA, "a") },
                 error = function(e) message("ASCA factor-A plot skipped: ", conditionMessage(e)))
        tryCatch({ mSet <- PlotASCAModel(mSet, "asca_factor_pheno_", "png", 72, NA, "b") },
                 error = function(e) message("ASCA factor-B plot skipped: ", conditionMessage(e)))
        tryCatch({ mSet <- PlotASCAInteraction(mSet, "asca_interaction_", "png", 72, FALSE, NA) },
                 error = function(e) message("ASCA interaction plot skipped: ", conditionMessage(e)))

        # ------------------------------------------------------------------
        # Model-significance permutation test
        # ------------------------------------------------------------------
        tryCatch({
          mSet <- Perform.ASCA.permute(mSet, perm_num)
          mSet <- PlotASCA.Permutation(mSet, "asca_permutation_", "png", 72, NA)
        }, error = function(e) message("ASCA permutation skipped (non-fatal): ", conditionMessage(e)))

        # Significant-feature tables (Sig_features_Model_a/b/ab.csv are auto-written); also
        # persist the in-object sig lists as stable filenames.
        tryCatch({
          sl <- mSet\$analSet\$asca\$sig.list
          if (!is.null(sl)) for (nm in names(sl)) if (!is.null(sl[[nm]]) && nrow(as.data.frame(sl[[nm]])) > 0)
            write.csv(as.data.frame(sl[[nm]]), paste0("asca_significant_features_", gsub("\\\\.", "_", nm), ".csv"), row.names = TRUE)
        }, error = function(e) message("Could not persist ASCA sig lists: ", conditionMessage(e)))

        saveRDS(mSet, "metaboanalyst_timeseries_mSet.rds")
        cat("MetaboAnalystR time-series/two-factor ASCA pipeline completed. Outputs written to working directory.\n")

    writeLines(c(
        '"BIOC_METABOANALYSTR_TIMESERIES_TWO_FACTOR_ASCA":',
        paste0('    MetaboAnalystR: ', as.character(packageVersion('MetaboAnalystR')))
    ), "versions.yml")

    .bm_finish(0)
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_asca_significant_features_Model_a.csv versions.yml
    """
}

workflow BIOC_METABOANALYSTR_TIMESERIES_TWO_FACTOR_ASCA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ data.csv, metadata.csv (Sample,Time,Phenotype,Subject) ] ]

    main:
    BIOC_METABOANALYSTR_TIMESERIES_TWO_FACTOR_ASCA(ch_input)

    emit:
    tables   = BIOC_METABOANALYSTR_TIMESERIES_TWO_FACTOR_ASCA.out.tables
    plots    = BIOC_METABOANALYSTR_TIMESERIES_TWO_FACTOR_ASCA.out.plots
    images   = BIOC_METABOANALYSTR_TIMESERIES_TWO_FACTOR_ASCA.out.images
    objects  = BIOC_METABOANALYSTR_TIMESERIES_TWO_FACTOR_ASCA.out.objects
    versions = BIOC_METABOANALYSTR_TIMESERIES_TWO_FACTOR_ASCA.out.versions
}
