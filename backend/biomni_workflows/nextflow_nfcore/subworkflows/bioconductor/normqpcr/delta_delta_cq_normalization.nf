#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: normqpcr — delta_delta_cq_normalization
// Normalize qPCR data and calculate relative gene expression between two groups using the 2^-ddCq method with single or multiple housekeeping genes.
// Input: example.txt
// Container: quay.io/biocontainers/bioconductor-normqpcr:1.56.0--r45h575d39b_0
// R packages: NormqPCR, ReadqPCR
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Visualizations: bar plot

nextflow.enable.dsl = 2

// Generic-path controls (used when a real user Ct table is provided; ignored by
// the no-input demo). Auto-detected when unset.
params.qpcr_hkg = null            // housekeeping gene(s), comma-separated (e.g. "GAPDH,ACTB")
params.qpcr_control_label = null  // substring identifying control samples in column names (default 'control')

process BIOC_NORMQPCR_DELTA_DELTA_CQ_NORMALIZATION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-normqpcr:1.56.0--r45h575d39b_0"

    input:
    tuple val(meta), path(input_files, stageAs: '?/*')

    output:
    tuple val(meta), path("*.csv"), emit: tables, optional: true
    tuple val(meta), path("*.pdf"), emit: plots,  optional: true
    tuple val(meta), path("*.rds"), emit: objects, optional: true
    path "versions.yml",            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("NormqPCR", "ReadqPCR")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))  # CRAN binaries (Posit PPM)
      .bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressWarnings(suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=.bin), error=function(e) try(install.packages(.bm_miss), silent=TRUE))))
    }

    # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
    for (.bm_d in list.files(".", full.names = TRUE)) {
      if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
        for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
          if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
        }
      }
    }
    
    # NB: ReadqPCR/NormqPCR are loaded only inside the demo branch below — the
    # generic path is pure base R, so it must not depend on those packages.

    # --- Input routing ---------------------------------------------------
    # A real user Ct table runs the GENERIC path (any gene x sample table ->
    # 2^-ddCt); NO input falls back to the NormqPCR bundled TaqMan example so
    # the workflow is one-click runnable ("try the platform"). Previously it
    # ONLY accepted the package example (hardcoded 8-sample matrix + rat probe
    # IDs), so real hospital qPCR data failed — this generalises it.
    .all_files <- setdiff(list.files("."), c("versions.yml"))
    .ext <- tolower(tools::file_ext(.all_files))
    .candidates <- .all_files[.ext %in% c("csv", "tsv", "txt")]
    .user_input <- if (length(.candidates)) .candidates[[1]] else NA_character_

    if (!is.na(.user_input)) {
      # ============ GENERIC PATH: any Ct table -> 2^-ddCt =================
      message(sprintf("[biomate] qPCR generic path on user input: %s", .user_input))
      df <- read.csv(.user_input, check.names = FALSE, stringsAsFactors = FALSE)
      if (ncol(df) < 2) df <- read.csv(.user_input, sep = "\t", check.names = FALSE, stringsAsFactors = FALSE)
      # First column = gene/target/detector; remaining columns = per-sample Ct.
      genes <- as.character(df[[1]])
      ct <- as.matrix(df[, -1, drop = FALSE])
      suppressWarnings(storage.mode(ct) <- "double")
      rownames(ct) <- genes
      samples <- colnames(ct)

      # Housekeeping gene(s): explicit param, else auto-detect common HKGs present.
      .hkg_param <- "${params.qpcr_hkg}"
      if (.hkg_param == "null" || !nchar(.hkg_param)) {
        .common <- c("GAPDH","ACTB","B2M","18S","RRN18S","HPRT1","HPRT","RPLP0","TBP","PPIA","YWHAZ")
        hkg <- genes[toupper(genes) %in% .common]
        if (!length(hkg)) stop("No housekeeping gene detected among targets; pass --qpcr_hkg (e.g. GAPDH).")
      } else {
        hkg <- trimws(strsplit(.hkg_param, ",")[[1]])
        hkg <- hkg[hkg %in% genes]
        if (!length(hkg)) stop("Requested housekeeping gene(s) not found among the targets.")
      }
      message(sprintf("[biomate] housekeeping gene(s): %s", paste(hkg, collapse = ", ")))

      # Control vs case grouping from column-name label (default 'control'),
      # with a first-half fallback so it still runs on uninformative names.
      .ctrl_label <- tolower("${params.qpcr_control_label}")
      if (.ctrl_label == "null" || !nchar(.ctrl_label)) .ctrl_label <- "control"
      is_control <- grepl(.ctrl_label, tolower(samples)) |
                    grepl("ctrl|ctl|untreat|vehicle|mock|dmso|wildtype", tolower(samples))
      if (!any(is_control) || all(is_control)) {
        is_control <- seq_along(samples) <= ceiling(length(samples) / 2)
        message("[biomate] control group not identifiable from names; using the first half as control.")
      }

      # deltaCt = Ct(target) - mean Ct(housekeeping) per sample
      hk_ct <- colMeans(ct[hkg, , drop = FALSE], na.rm = TRUE)
      dCt <- sweep(ct, 2, hk_ct, "-")
      # deltaDeltaCt = dCt - mean(dCt over control samples), per target
      ctrl_mean <- rowMeans(dCt[, is_control, drop = FALSE], na.rm = TRUE)
      ddCt <- sweep(dCt, 1, ctrl_mean, "-")
      rel <- 2 ^ (-ddCt)

      summary_tbl <- data.frame(
        gene = rownames(rel),
        mean_relExpr_case = rowMeans(rel[, !is_control, drop = FALSE], na.rm = TRUE),
        mean_relExpr_control = rowMeans(rel[, is_control, drop = FALSE], na.rm = TRUE),
        check.names = FALSE
      )
      summary_tbl[["log2_fold_change"]] <- log2(summary_tbl[["mean_relExpr_case"]] / summary_tbl[["mean_relExpr_control"]])
      write.csv(summary_tbl, "ddCq_relative_expression.csv", row.names = FALSE)
      write.csv(data.frame(gene = rownames(rel), rel, check.names = FALSE), "ddCq_per_sample_relative_expression.csv", row.names = FALSE)
      saveRDS(list(deltaCt = dCt, deltaDeltaCt = ddCt, relExpr = rel, summary = summary_tbl,
                   control_samples = samples[is_control]), "ddCq_result.rds")

      # Bar plot of top targets by |log2 fold-change| (housekeeping excluded).
      .plt <- summary_tbl[!(summary_tbl[["gene"]] %in% hkg), , drop = FALSE]
      .plt <- .plt[order(-abs(.plt[["log2_fold_change"]])), , drop = FALSE]
      .plt <- head(.plt, 20)
      pdf("relative_expression_plot.pdf", width = 10, height = 6)
      vals <- .plt[["log2_fold_change"]]; vals[is.na(vals)] <- 0
      barplot(vals, names.arg = .plt[["gene"]], las = 2, col = "skyblue",
              main = "qPCR relative expression (log2 fold-change, case vs control)",
              ylab = "log2 fold-change", cex.names = 0.8)
      dev.off()

      writeLines(c('"BIOC_NORMQPCR_DELTA_DELTA_CQ_NORMALIZATION":',
                   '        method: "2^-ddCt (generic Ct table, base R)"'), "versions.yml")

    } else {
      # ============ DEMO PATH: NormqPCR bundled TaqMan example ============
      library(ReadqPCR); library(NormqPCR)
      message("[biomate demo] No qPCR input provided — using the NormqPCR bundled example TaqMan dataset.")
      .pkg_example <- system.file("exData", "example.txt", package = "NormqPCR")
      if (!nchar(.pkg_example) || !file.exists(.pkg_example)) stop("No bundled demo dataset available.")
      qPCRBatch.taqman <- read.taqman(.pkg_example)
      contM <- cbind(c(0,0,1,1,0,0,1,1), c(1,1,0,0,1,1,0,0))
      colnames(contM) <- c("interestingPhenotype", "wildTypePhenotype")
      rownames(contM) <- sampleNames(qPCRBatch.taqman)
      hkg <- "Actb-Rn00667869_m1"
      ddCq.taqman <- deltaDeltaCq(qPCRBatch = qPCRBatch.taqman, maxNACase=1, maxNAControl=1,
                                  hkg=hkg, contrastM=contM, case="interestingPhenotype",
                                  control="wildTypePhenotype", statCalc="geom", hkgCalc="arith")
      hkgs <- c("Actb-Rn00667869_m1", "B2m-Rn00560865_m1", "Gapdh-Rn99999916_s1")
      ddCq.gM.taqman <- deltaDeltaCq(qPCRBatch = qPCRBatch.taqman, maxNACase=1, maxNAControl=1,
                                     hkgs=hkgs, contrastM=contM, case="interestingPhenotype",
                                     control="wildTypePhenotype", statCalc="arith", hkgCalc="arith")
      write.csv(ddCq.taqman, "ddCq_single_paired.csv", row.names = FALSE)
      write.csv(ddCq.gM.taqman, "ddCq_multiple.csv", row.names = FALSE)
      saveRDS(ddCq.gM.taqman, "ddCq_multiple.rds")
      pdf("relative_expression_plot.pdf", width = 10, height = 6)
      plot_data <- ddCq.gM.taqman[1:10, ]
      vals <- plot_data[["2^-ddCt"]]; vals[is.na(vals)] <- 0
      barplot(vals, names.arg = plot_data[["ID"]], las = 2,
              main = "Relative Expression (2^-ddCt) - Top 10 Genes (demo)",
              ylab = "Relative Expression", col = "skyblue", cex.names = 0.8)
      dev.off()
      writeLines(c('"BIOC_NORMQPCR_DELTA_DELTA_CQ_NORMALIZATION":',
                   paste0('        normqpcr: ', as.character(packageVersion("normqpcr")))), "versions.yml")
    }
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_delta_delta_cq_normalization.csv versions.yml
    """
}

workflow BIOC_NORMQPCR_DELTA_DELTA_CQ_NORMALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ example.txt ] ]

    main:
    BIOC_NORMQPCR_DELTA_DELTA_CQ_NORMALIZATION(ch_input)

    emit:
    tables   = BIOC_NORMQPCR_DELTA_DELTA_CQ_NORMALIZATION.out.tables
    plots    = BIOC_NORMQPCR_DELTA_DELTA_CQ_NORMALIZATION.out.plots
    objects  = BIOC_NORMQPCR_DELTA_DELTA_CQ_NORMALIZATION.out.objects
    versions = BIOC_NORMQPCR_DELTA_DELTA_CQ_NORMALIZATION.out.versions
}
