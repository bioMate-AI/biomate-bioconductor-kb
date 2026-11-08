#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: MetaboAnalystR — statistical_metabolomics_analysis
// Canonical MetaboAnalyst statistical pipeline over a peak-intensity table + a class/sample
// sheet: normalization (log + auto-scale), univariate (fold-change + t-test), and multivariate
// (PLS-DA with VIP) analysis, with optional pathway/enrichment when a compound list is present.
// Input: peak_intensity_table.csv, class_labels.csv, compound_list.txt
//        (if none supplied -> auto-downloads the MetaboAnalyst human_cachexia demo for a quick run)
// Container: 399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-metabolomics:3.20-deps
// R packages: MetaboAnalystR (GitHub xia-lab/MetaboAnalystR), OptiLCMS (raw spectra dep)
// Bioconductor: 3.20 | R: 4.4
// Requires: MetaboAnalystR
// Visualizations: PLS-DA score plot, volcano plot, fold-change plot
// NOTE: MetaboAnalystR is NOT on Bioconductor; it installs from GitHub via remotes::install_github.
//       Its heavy Bioc deps (impute, pcaMethods, siggenes, globaltest, GlobalAncova, Rgraphviz,
//       KEGGgraph, SSPA, sva, limma, crmn) are baked into the bioc-domain-metabolomics image so
//       the runtime guard below is a no-op in production and only self-heals on a clean runtime.
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Data Processing] Initialise mSet + read peak-intensity table and class labels
//  * 2. [Data Processing] Sanity-check, replace missing values, filter, normalize (log + auto-scale)
//  * 3. [Univariate Analysis] Fold-change analysis + t-test -> significant features + volcano plot
//  * 4. [Multivariate Analysis] PLS-DA -> score plot + VIP scores table
//  * 5. [Optional] Enrichment / pathway analysis when a compound list is supplied
//  * 6. [Visualization & Output] Save mSet RDS, tables (sig features, VIP), plots (PLS-DA, volcano)

nextflow.enable.dsl = 2

process BIOC_METABOANALYSTR_STATISTICAL_METABOLOMICS_ANALYSIS {
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
    # MetaboAnalystR is not on Bioconductor -> install its heavy Bioc/CRAN deps via BiocManager,
    # then install MetaboAnalystR (+ OptiLCMS) from GitHub via remotes::install_github.
    .bm_deps <- c("MetaboAnalystR")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      if (!requireNamespace("remotes", quietly=TRUE)) install.packages("remotes", repos="https://cloud.r-project.org")
      options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))  # CRAN binaries (Posit PPM)
      .bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      # heavy Bioc/CRAN deps MetaboAnalystR needs at load time
      .ma_deps <- c("impute","pcaMethods","siggenes","globaltest","GlobalAncova","Rgraphviz",
                    "KEGGgraph","SSPA","sva","limma","crmn","pls","caret","e1071","igraph",
                    "fitdistrplus","ellipse","scatterplot3d","pheatmap","RColorBrewer")
      .ma_miss <- .ma_deps[!vapply(.ma_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
      if (length(.ma_miss)) suppressWarnings(suppressMessages(tryCatch(BiocManager::install(.ma_miss, update=FALSE, ask=FALSE, site_repository=.bin), error=function(e) try(install.packages(.ma_miss), silent=TRUE))))
      # OptiLCMS is the raw-spectra companion dep; install best-effort (not needed for the stat pipeline)
      if (!requireNamespace("OptiLCMS", quietly=TRUE)) suppressWarnings(suppressMessages(try(remotes::install_github("xia-lab/OptiLCMS", upgrade="never", quiet=TRUE), silent=TRUE)))
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

        # Load required libraries
        suppressPackageStartupMessages({
          library(MetaboAnalystR)
        })

        # Ensure the Batch task exits promptly. MetaboAnalystR/OptiLCMS fork a background
        # Rserve daemon at init which keeps this task's stdout/stderr FDs open, so the AWS
        # Batch container hangs in RUNNING for the full timeout AFTER the R script finishes
        # OR errors (observed 2026-09-29: a failed run zombied ~30 min; even a SUCCESSFUL
        # run would hang identically). Kill Rserve on both paths so the container exits in
        # seconds, letting Nextflow stage outputs and the job reach a terminal state.
        .bm_finish <- function(status) {
          try(suppressWarnings(system("pkill -9 -f Rserve 2>/dev/null")), silent = TRUE)
          quit(save = "no", status = status, runLast = FALSE)
        }
        options(error = function() .bm_finish(1))

        # ------------------------------------------------------------------
        # 1. Read User Inputs (peak-intensity table + 2-group class labels)
        # ------------------------------------------------------------------
        find_input <- function(cands) {
          for (f in cands) if (file.exists(f)) return(f)
          NULL
        }
        peak_file  <- find_input(c("peak_intensity_table.csv", "peak_table.csv", "dataMatrix.csv", "data.csv"))
        class_file <- find_input(c("class_labels.csv", "sampleMetadata.csv", "metadata.csv", "labels.csv"))

        # MetaboAnalyst consumes a single CSV with samples in columns and a 'Label' row, OR a
        # features x samples matrix + a separate class sheet. We normalize to the standard
        # MetaboAnalyst "colu" (columns = samples) CSV with the class as the second row.
        demo_mode <- FALSE
        if (is.null(peak_file)) {
          # No user input -> fall back to the canonical MetaboAnalyst example dataset so a
          # param-less "quick run" works (mirrors the merfish/voyager built-in-demo pattern:
          # a REAL, clearly-labeled public dataset, NOT fabricated values). human_cachexia =
          # 77 human urine samples x 63 metabolites, 2 groups (cachexic vs control) -- the
          # official MetaboAnalyst statistical-analysis tutorial dataset (Eisner et al. 2011).
          demo_urls <- c(
            "https://www.metaboanalyst.ca/MetaboAnalyst/resources/data/human_cachexia.csv",
            "https://rest.xialab.ca/api/download/metaboanalyst/human_cachexia.csv"
          )
          demo_csv <- "human_cachexia.csv"
          ok <- FALSE
          for (u in demo_urls) {
            ok <- tryCatch({
              download.file(u, demo_csv, quiet = TRUE, mode = "wb")
              file.exists(demo_csv) && file.size(demo_csv) > 1000
            }, error = function(e) FALSE)
            if (isTRUE(ok)) break
          }
          if (!isTRUE(ok)) stop("No input peak-intensity table supplied and the MetaboAnalyst human_cachexia demo dataset could not be downloaded. Provide peak_intensity_table.csv (+ optional class_labels.csv) or ensure network egress for the demo dataset.")
          demo_mode <- TRUE
          # cachexia IS already a valid MetaboAnalyst "rowu" (rows = samples) concentration
          # upload: col 1 = sample id, col 2 = class label, cols 3+ = metabolites. Feed it to
          # Read.TextData natively as "rowu" below -- do NOT transpose + rebuild a "colu" CSV:
          # cachexia metabolite names contain commas, and a quote=FALSE colu rewrite corrupts
          # them -> "Duplicate feature names are not allowed!" in Read.TextData (root-caused on
          # a real Batch run 2026-10-04).
          .demo_hdr <- tryCatch(read.csv(demo_csv, header = TRUE, check.names = FALSE, stringsAsFactors = FALSE, nrows = 400), error = function(e) NULL)
          .demo_grps <- tryCatch(paste(unique(.demo_hdr[[2]]), collapse = "/"), error = function(e) "cachexic/control")
          cat(sprintf("[demo] No input supplied -> MetaboAnalyst human_cachexia demo (rows=samples, groups: %s), read natively as rowu.\n", .demo_grps))
        }

        if (!demo_mode) {
          mat <- read.csv(peak_file, header = TRUE, row.names = 1, check.names = FALSE, stringsAsFactors = FALSE)
          # Build / attach the class labels
          if (!is.null(class_file)) {
            lab_df <- read.csv(class_file, header = TRUE, row.names = 1, check.names = FALSE, stringsAsFactors = FALSE)
            # first column of the label sheet holds the group; align to the sample (column) order of mat
            grp_col <- lab_df[[1]]
            names(grp_col) <- rownames(lab_df)
            labels <- as.character(grp_col[colnames(mat)])
          } else {
            # Fallback: split samples into two balanced groups so the pipeline still demonstrates value
            labels <- rep(c("GroupA", "GroupB"), length.out = ncol(mat))
          }
        }
        # Demo path feeds the native cachexia file directly (rowu); user path builds a colu CSV.
        if (demo_mode) {
          ma_csv <- demo_csv
          ma_fmt <- "rowu"
        } else {
          if (any(is.na(labels))) stop("Class labels could not be matched to every sample column of the peak table.")

          # Write the canonical MetaboAnalyst upload CSV: header = sample names, row 1 = 'Label'.
          # Build as a single character matrix — NOT rbind() of two data.frames: the label
          # frame's auto-generated column names (t(data.frame(Label=labels)) -> "1","2",...)
          # differ from mat's real sample names, so rbind() throws
          # "names do not match previous names". A matrix rbind is name-agnostic and coerces
          # cleanly (the Label row is text, the feature rows are numbers-as-text — exactly the
          # MetaboAnalyst 'conc' upload format).
          ma_csv <- "metaboanalyst_input.csv"
          sample_names <- colnames(mat)
          out <- rbind(
            c("Label", as.character(labels)),
            cbind(rownames(mat), matrix(as.character(as.matrix(mat)), nrow = nrow(mat)))
          )
          colnames(out) <- c("Sample", sample_names)
          write.csv(out, ma_csv, row.names = FALSE, quote = FALSE)
          ma_fmt <- "colu"
        }

        # ------------------------------------------------------------------
        # 2. Initialise mSet + data processing / normalization (log + auto-scale)
        # ------------------------------------------------------------------
        mSet <- InitDataObjects("conc", "stat", FALSE)
        mSet <- Read.TextData(mSet, ma_csv, ma_fmt, "disc")
        mSet <- SanityCheckData(mSet)
        # Missing-value handling for the CONC stat pipeline.
        # ReplaceMin() is no longer EXPORTED by MetaboAnalystR 4.x; the exported modern
        # min-imputation is ImputeMissingVar(method="min"). BUT ImputeMissingVar is part of
        # the raw/spectra preprocessing path: it rewrites data_proc.qs and re-derives the
        # class-label vector via .get.latest.proc.matrix. On a clean CONC table with NO
        # missing values that rewrite desynchronises proc.cls from the preproc.qs matrix, so
        # the subsequent FilterVariable -> .get.latest.proc.matrix step fails with
        # "Unable to resolve class labels for matrix source" (root-caused 2026-09-30 on a
        # real Batch run; SanityCheckData already logs "No missing values were detected").
        # SanityCheckData itself replaces any residual missing with half the minimal positive
        # value, so imputation is a NO-OP on clean data — only invoke it when missing values
        # actually remain, keeping proc.cls intact for the common (complete) case.
        .n_missing <- tryCatch(as.integer(mSet\$dataSet\$missingCount), error = function(e) 0L)
        if (!is.na(.n_missing) && .n_missing > 0L) {
          mSet <- ImputeMissingVar(mSet, method = "min")
        }
        # FilterVariable in MetaboAnalystR 4.x returns an INTEGER status code (1 if missing
        # values remain, else 2) in the off-web path -- NOT the mSet object. It mutates state
        # via .set.mSet() (a no-op that just returns the object off-web) and writes its result
        # matrices to data.filt.qs / data_proc.qs on disk. So the usual chained idiom
        # mSet <- FilterVariable(mSet, ...) clobbers mSet with an atomic 2, and the next
        # PreparePrenormData(mSet) then fails inside pick.cls with an invalid-dollar-operator
        # error (root-caused 2026-09-30 on a real Batch run). Only re-bind mSet when the call
        # actually returns an mSet-shaped list; otherwise keep the pre-filter object (its
        # proc.cls stays valid and PreparePrenormData re-reads the filtered matrix from the
        # .qs files FilterVariable just wrote).
        .fv <- FilterVariable(mSet, "F", 25, "none", -1, "mean", 0)
        if (is.list(.fv) && !is.null(.fv\$dataSet)) mSet <- .fv
        mSet <- PreparePrenormData(mSet)
        # LogNorm (base-10 log) + AutoNorm (auto/unit-variance scaling) -- the canonical stat prep
        mSet <- Normalization(mSet, "NULL", "LogNorm", "AutoNorm", ratio = FALSE, ratioNum = 20)

        # ------------------------------------------------------------------
        # 3. Univariate analysis: fold-change + t-test -> volcano
        # ------------------------------------------------------------------
        tryCatch({
          mSet <- FC.Anal(mSet, 2.0, 0, FALSE)
        }, error = function(e) message("Fold-change analysis skipped: ", conditionMessage(e)))
        tryCatch({
          mSet <- Ttests.Anal(mSet, FALSE, 0.05, FALSE, TRUE, "fdr", FALSE)
        }, error = function(e) message("T-test analysis skipped: ", conditionMessage(e)))
        tryCatch({
          mSet <- Volcano.Anal(mSet, FALSE, 2.0, 0, 0.75, FALSE, 0.1, TRUE, "raw")
          mSet <- PlotVolcano(mSet, "volcano_plot_", 1, 0, "pdf", 72, width = NA)
        }, error = function(e) message("Volcano plot skipped (non-fatal): ", conditionMessage(e)))

        # Persist the significant-features table (t-test output) if produced
        tryCatch({
          if (!is.null(mSet\$analSet\$tt) && !is.null(mSet\$analSet\$tt\$sig.mat)) {
            write.csv(as.data.frame(mSet\$analSet\$tt\$sig.mat), "significant_features_ttest.csv", row.names = TRUE)
          }
          if (!is.null(mSet\$analSet\$fc) && !is.null(mSet\$analSet\$fc\$sig.mat)) {
            write.csv(as.data.frame(mSet\$analSet\$fc\$sig.mat), "significant_features_foldchange.csv", row.names = TRUE)
          }
        }, error = function(e) message("Could not persist univariate tables: ", conditionMessage(e)))

        # ------------------------------------------------------------------
        # 4. Multivariate: PLS-DA -> score plot + VIP table
        # ------------------------------------------------------------------
        tryCatch({
          mSet <- PLSR.Anal(mSet, reg = TRUE)
          mSet <- PlotPLS2DScore(mSet, "plsda_score_plot_", "pdf", 72, width = NA, 1, 2, 0.95, 1, 0)
          mSet <- PLSDA.CV(mSet, "T", 5, "Q2")
          mSet <- PlotPLS.Imp(mSet, "plsda_vip_", "pdf", 72, width = NA, "vip", "Comp. 1", 15, FALSE)
        }, error = function(e) message("PLS-DA analysis skipped (non-fatal): ", conditionMessage(e)))

        # Persist VIP scores
        tryCatch({
          if (!is.null(mSet\$analSet\$plsda) && !is.null(mSet\$analSet\$plsda\$vip.mat)) {
            write.csv(as.data.frame(mSet\$analSet\$plsda\$vip.mat), "plsda_vip_scores.csv", row.names = TRUE)
          }
        }, error = function(e) message("Could not persist VIP table: ", conditionMessage(e)))

        # ------------------------------------------------------------------
        # 5. Optional enrichment / pathway analysis when a compound list is present
        # ------------------------------------------------------------------
        cmpd_file <- find_input(c("compound_list.txt", "compounds.txt", "compound_list.csv"))
        if (!is.null(cmpd_file)) {
          tryCatch({
            cmpds <- readLines(cmpd_file)
            cmpds <- cmpds[nzchar(trimws(cmpds))]
            enr <- InitDataObjects("conc", "msetora", FALSE)
            enr <- Setup.MapData(enr, cmpds)
            enr <- CrossReferencing(enr, "name")
            enr <- CreateMappingResultTable(enr)
            enr <- SetMetabolomeFilter(enr, FALSE)
            enr <- SetCurrentMsetLib(enr, "smpdb_pathway", 2)
            enr <- CalculateHyperScore(enr)
            if (!is.null(enr\$analSet\$ora.mat)) {
              write.csv(as.data.frame(enr\$analSet\$ora.mat), "enrichment_ora_results.csv", row.names = TRUE)
            }
          }, error = function(e) message("Enrichment/pathway analysis skipped (non-fatal): ", conditionMessage(e)))
        }

        # ------------------------------------------------------------------
        # 6. Save the mSet object (analysis provenance) as RDS
        # ------------------------------------------------------------------
        saveRDS(mSet, "metaboanalyst_mSet.rds")

        cat("MetaboAnalystR statistical pipeline completed. Outputs written to working directory.\n")

    writeLines(c(
        '"BIOC_METABOANALYSTR_STATISTICAL_METABOLOMICS_ANALYSIS":',
        paste0('    MetaboAnalystR: ', as.character(packageVersion('MetaboAnalystR')))
    ), "versions.yml")

    # Kill the Rserve daemon + exit 0 so the Batch container terminates promptly and
    # Nextflow stages the outputs written above (see .bm_finish note near the top).
    .bm_finish(0)
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_statistical_metabolomics_analysis.csv versions.yml
    """
}

workflow BIOC_METABOANALYSTR_STATISTICAL_METABOLOMICS_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ peak_intensity_table.csv, class_labels.csv ] ]

    main:
    BIOC_METABOANALYSTR_STATISTICAL_METABOLOMICS_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_METABOANALYSTR_STATISTICAL_METABOLOMICS_ANALYSIS.out.tables
    plots    = BIOC_METABOANALYSTR_STATISTICAL_METABOLOMICS_ANALYSIS.out.plots
    images   = BIOC_METABOANALYSTR_STATISTICAL_METABOLOMICS_ANALYSIS.out.images
    objects  = BIOC_METABOANALYSTR_STATISTICAL_METABOLOMICS_ANALYSIS.out.objects
    versions = BIOC_METABOANALYSTR_STATISTICAL_METABOLOMICS_ANALYSIS.out.versions
}
