#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: miaViz — serial_data_and_trajectories
// Visualize longitudinal/serial abundance data and plot subject trajectories on ordination space.
// Input: SilvermanAGutData, hitchip1006
// Container: quay.io/biocontainers/bioconductor-miaviz:1.18.0--r45hdfd78af_0
// R packages: dplyr, ggplot2, mia, miaTime, miaViz, scater
// Bioconductor: 3.20 | R: 4.4
// Requires: dplyr, ggplot2, mia, miaTime, miaViz, scater
// Visualizations: ordination plot, trajectory plot
// QC: cell QC metrics
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Transform assay to relative abundance
//  * 2. [Visualization & Output] Plot abundance series over time faceted by metadata
//  * 3. [Core Analysis] Run MDS ordination
//  * 4. [Visualization & Output] Plot subject trajectories on ordination space
//  * 5. [Visualization & Output] Calculate stepwise divergence and plot top divergent trajectories

nextflow.enable.dsl = 2

process BIOC_MIAVIZ_SERIAL_DATA_AND_TRAJECTORIES {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-metagenomics:3.20-deps"

    input:
    tuple val(meta), path(input_files, stageAs: '?/*')

    output:
    tuple val(meta), path("*.csv"), emit: tables, optional: true
    tuple val(meta), path("*.pdf"), emit: plots,  optional: true
    tuple val(meta), path("*.rds"), emit: objects, optional: true
    tuple val(meta), path("qc_metrics.json"), emit: qc_metrics
    path "versions.yml",            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("dplyr", "ggplot2", "mia", "miaTime", "miaViz", "scater", "SummarizedExperiment")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
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
        library(SummarizedExperiment)
        library(miaViz)
        library(scater)
        library(miaTime)
        library(mia)
        library(dplyr)
        library(ggplot2)
        
        # Robust helper function to read the input files from the working directory
        read_input_tse <- function(base_name) {
          exts <- c(".rds", "", ".RData", ".Rdata")
          for (ext in exts) {
            file_path <- paste0(base_name, ext)
            if (file.exists(file_path)) {
              if (grepl("\\\\.rds\$", file_path, ignore.case = TRUE) || ext == "") {
                try_res <- try(readRDS(file_path), silent = TRUE)
                if (!inherits(try_res, "try-error")) return(try_res)
              }
              env <- new.env()
              try_res <- try(load(file_path, envir = env), silent = TRUE)
              if (!inherits(try_res, "try-error")) {
                objs <- ls(env)
                if (length(objs) > 0) {
                  return(env[[objs[1]]])
                }
              }
            }
          }
          stop(paste("Error: Could not find or read input file for:", base_name))
        }
        
        # ==========================================
        # 1. Process SilvermanAGutData
        # ==========================================
        
        # Read SilvermanAGutData from working directory
        tse_silverman <- read_input_tse("SilvermanAGutData")
        
        # Transform assay to relative abundance
        tse_silverman <- transformAssay(tse_silverman, method = "relabundance")
        
        # Get top 2 taxa
        taxa <- getTop(tse_silverman, 2)
        
        # Generate series plots
        p1 <- plotSeries(
            tse_silverman,
            assay.type = "relabundance",
            time.col = "DAY_ORDER",
            features = taxa,
            colour.by = "Family",
            facet.by = "Vessel"
        )
        
        p2 <- plotSeries(
            tse_silverman[taxa,],
            time.col = "DAY_ORDER",
            colour.by = "Family",
            linetype.by = "Phylum",
            assay.type = "relabundance"
        )
        
        p3 <- plotSeries(
            tse_silverman,
            time.col = "DAY_ORDER",
            features = getTop(tse_silverman, 5),
            colour.by = "Family",
            linetype.by = "Phylum",
            assay.type = "counts"
        )
        
        # Save Silverman series plots
        pdf("silverman_series_plots.pdf", width = 10, height = 8)
        print(p1)
        print(p2)
        print(p3)
        dev.off()
        
        # Save processed Silverman TSE
        saveRDS(tse_silverman, "SilvermanAGutData_processed.rds")
        
        
        # ==========================================
        # 2. Process hitchip1006
        # ==========================================
        
        # Read hitchip1006 from working directory
        tse_hitchip <- read_input_tse("hitchip1006")
        
        # Transform assay to relative abundance
        tse_hitchip <- transformAssay(tse_hitchip, method = "relabundance")
        
        # Run MDS ordination with PCoA using Bray-Curtis dissimilarity
        tse_hitchip <- runMDS(
            tse_hitchip, FUN = getDissimilarity, method = "bray", name = "PCoA_BC",
            assay.type = "relabundance", na.rm = TRUE
        )
        
        # Plot reduced dimensions
        p <- plotReducedDim(tse_hitchip, dimred = "PCoA_BC")
        
        # Retrieve information about available trajectories
        selected.subjects <- names(which(table(tse_hitchip\$subject) == 2))
        
        tb_timepoints <- table(table(tse_hitchip\$subject)) %>% 
            as.data.frame() %>%
            rename(Timepoints = Var1, Subjects = Freq)
        
        # Save the timepoints table to CSV
        write.csv(tb_timepoints, "hitchip_subject_timepoints.csv", row.names = FALSE)
        
        # Plot all trajectories with two time points
        p4 <- p + geom_path(
            aes(x = X1, y = X2, group = subject),
            arrow = arrow(length = unit(0.1, "inches")),
            data = subset(
                data.frame(reducedDim(tse_hitchip), colData(tse_hitchip)),
                subject %in% selected.subjects
            ) %>% arrange(time)
        ) +
            labs(title = "All trajectories with two time points") +
            theme(plot.title = element_text(hjust = 0.5))
        
        # Calculate stepwise divergence based on microbial profiles
        tse_hitchip <- getStepwiseDivergence(tse_hitchip, group = "subject", time_field = "time")
        
        # Retrieve top 10% divergent subjects having two time points
        top.selected.subjects <- subset(
            data.frame(reducedDim(tse_hitchip), colData(tse_hitchip)),
            subject %in% selected.subjects
        ) %>%
            top_frac(0.1, time_divergence) %>% 
            select(subject) %>% 
            .[[1]]
        
        # Plot top 10% divergent trajectories
        p5 <- p + geom_path(
            aes(x = X1, y = X2, color = time_divergence, group = subject),
            data = subset(
                data.frame(reducedDim(tse_hitchip), colData(tse_hitchip)),
                subject %in% top.selected.subjects
            ) %>% arrange(desc(time)),
            arrow = arrow(length = unit(0.1, "inches"), ends = "first")
        ) +
            labs(title = "Top 10%  divergent trajectories from time point one to two") +
            scale_color_gradient2(low = "white", high = "red") +
            theme(plot.title = element_text(hjust = 0.5))
        
        # Get subject with the maximum total divergence
        selected.subject <- data.frame(reducedDim(tse_hitchip), colData(tse_hitchip)) %>%
            group_by(subject) %>%
            summarise(total_divergence = sum(time_divergence, na.rm = TRUE)) %>%
            filter(total_divergence == max(total_divergence)) %>% 
            select(subject) %>%
            .[[1]]
        
        # Plot the longest trajectory by divergence
        p6 <- p + geom_path(
            aes(x = X1, y = X2, group = subject),
            data = subset(
                data.frame(reducedDim(tse_hitchip), colData(tse_hitchip)),
                subject %in% selected.subject
            ) %>% arrange(time),
            arrow = arrow(length = unit(0.1, "inches"))
        ) +
            labs(title = "Longest trajectory by divergence") +
            theme(plot.title = element_text(hjust = 0.5))
        
        # Save hitchip trajectory plots
        pdf("hitchip_trajectory_plots.pdf", width = 10, height = 8)
        print(p)
        print(p4)
        print(p5)
        print(p6)
        dev.off()
        
        # Save processed hitchip TSE
        saveRDS(tse_hitchip, "hitchip1006_processed.rds")
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

    # cell QC metrics — defensive cell-count + per-cell summary from any
    # matrix artifact. Pass when columns (cells) ≥ 50 and rows (features) ≥ 200
    # (Luecken & Theis 2019 single-cell QC floor).
    .cqc_ncells <- NA_real_; .cqc_nfeats <- NA_real_; .cqc_files <- character(0)
    for (.cqc_rds in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
      .cqc_obj <- tryCatch(readRDS(.cqc_rds), error = function(e) NULL)
      .cqc_mat <- if (is.matrix(.cqc_obj) || is.data.frame(.cqc_obj)) .cqc_obj else NULL
      if (!is.null(.cqc_mat) && nrow(.cqc_mat) > 100) {
        .cqc_ncells <- ncol(.cqc_mat); .cqc_nfeats <- nrow(.cqc_mat)
        .cqc_files <- c(.cqc_files, .cqc_rds); break
      }
    }
    .gates_by_label[["cell QC metrics"]] <- list(
      gate_row = "bioc_cell_qc_metrics",
      metric_name = "n_cells",
      metric_value = .cqc_ncells,
      passes = isTRUE(is.finite(.cqc_ncells) && .cqc_ncells >= 50 && .cqc_nfeats >= 200),
      status = if (is.finite(.cqc_ncells)) paste0("computed (cells=", .cqc_ncells, ", features=", .cqc_nfeats, "; proxy gate)")
               else "not_computed (no scRNA matrix .rds artifact present)"
    )

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_MIAVIZ_SERIAL_DATA_AND_TRAJECTORIES",
      domain  = "bioconductor",
      declared_qc_steps = c("cell QC metrics"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_MIAVIZ_SERIAL_DATA_AND_TRAJECTORIES":',
        paste0('    miaViz: ', as.character(packageVersion('miaViz')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_serial_data_and_trajectories.csv versions.yml
    """
}

workflow BIOC_MIAVIZ_SERIAL_DATA_AND_TRAJECTORIES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ SilvermanAGutData, hitchip1006 ] ]

    main:
    BIOC_MIAVIZ_SERIAL_DATA_AND_TRAJECTORIES(ch_input)

    emit:
    tables   = BIOC_MIAVIZ_SERIAL_DATA_AND_TRAJECTORIES.out.tables
    plots    = BIOC_MIAVIZ_SERIAL_DATA_AND_TRAJECTORIES.out.plots
    objects  = BIOC_MIAVIZ_SERIAL_DATA_AND_TRAJECTORIES.out.objects
    versions = BIOC_MIAVIZ_SERIAL_DATA_AND_TRAJECTORIES.out.versions
}
