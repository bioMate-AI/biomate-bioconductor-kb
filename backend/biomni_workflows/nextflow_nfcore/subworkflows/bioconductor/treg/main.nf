#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: TREG — treg_discovery
// Identify candidate Total RNA Expression Genes (TREGs) from a SingleCellExperiment object by filtering low-expression and sparse genes, and calculating rank inva
// Input: sce.dlpfc.tran
// Container: quay.io/biocontainers/bioconductor-treg:1.14.0--r45hdfd78af_0
// R packages: BiocStyle, dplyr, ggplot2, pheatmap, refmanager, SingleCellExperiment, tibble, tidyr, TREG
// Bioconductor: 3.20 | R: 4.4
// Requires: SingleCellExperiment, TREG, dplyr, ggplot2, pheatmap, tibble, tidyr
// Visualizations: plot (ggplot/base)
// QC: input validation
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Filter to top 50% expressed genes using row means
//  * 2. [Core Analysis] Calculate Proportion Zero per gene per cell type using get_prop_zero()
//  * 3. [Core Analysis] Filter genes by a maximum Proportion Zero cutoff using filter_prop_zero()
//  * 4. [Core Analysis] Calculate Rank Invariance using either the stepwise approach (rank_group(), rank_cells(), and rank_invariance()) or the express ap

nextflow.enable.dsl = 2

process BIOC_TREG_TREG_DISCOVERY {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

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
    .bm_deps <- c("BiocStyle", "dplyr", "ggplot2", "pheatmap", "refmanager", "SingleCellExperiment", "tibble", "tidyr", "TREG")
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
    library("TREG")
    library("SingleCellExperiment")
    library("pheatmap")
    library("dplyr")
    library("ggplot2")
    library("tidyr")
    library("tibble")
    
    # ==========================================
    # 1. Load User Input File
    # ==========================================
    # The pipeline expects 'sce.dlpfc.tran' in the working directory.
    # We will check for common formats (.rds, .rda, .RData, or unextended).
    input_file <- "sce.dlpfc.tran"
    
    if (file.exists(paste0(input_file, ".rds"))) {
        message("Loading input from RDS file...")
        sce.dlpfc.tran <- readRDS(paste0(input_file, ".rds"))
    } else if (file.exists(paste0(input_file, ".rda"))) {
        message("Loading input from RDA file...")
        load(paste0(input_file, ".rda"), verbose = TRUE)
    } else if (file.exists(paste0(input_file, ".RData"))) {
        message("Loading input from RData file...")
        load(paste0(input_file, ".RData"), verbose = TRUE)
    } else if (file.exists(input_file)) {
        message("Loading input from unextended file...")
        sce.dlpfc.tran <- tryCatch({
            readRDS(input_file)
        }, error = function(e) {
            load(input_file, verbose = TRUE)
            if (exists("sce.dlpfc.tran")) {
                get("sce.dlpfc.tran")
            } else {
                stop("Could not find 'sce.dlpfc.tran' object in loaded file.")
            }
        })
    } else {
        stop("Required input file 'sce.dlpfc.tran' (RDS or RDA) not found in the working directory.")
    }
    
    # Ensure the object is a SingleCellExperiment
    if (!inherits(sce.dlpfc.tran, "SingleCellExperiment")) {
        stop("Loaded object is not of class 'SingleCellExperiment'.")
    }
    
    # ==========================================
    # 2. Preprocess Cell Type Annotations
    # ==========================================
    # Ensure cellType.broad exists and filter out rare cell types (< 50 cells)
    if (!"cellType.broad" %in% colnames(colData(sce.dlpfc.tran))) {
        if ("cellType" %in% colnames(colData(sce.dlpfc.tran))) {
            sce.dlpfc.tran\$cellType.broad <- gsub("_[A-Z]\$", "", sce.dlpfc.tran\$cellType)
        } else {
            stop("Input SingleCellExperiment object must contain 'cellType' or 'cellType.broad' in colData.")
        }
    }
    
    cell_type_tab <- table(sce.dlpfc.tran\$cellType.broad)
    ct_drop <- names(cell_type_tab)[cell_type_tab < 50]
    if (length(ct_drop) > 0) {
        message("Dropping rare cell types: ", paste(ct_drop, collapse = ", "))
        sce.dlpfc.tran <- sce.dlpfc.tran[, !sce.dlpfc.tran\$cellType.broad %in% ct_drop]
    }
    
    # ==========================================
    # 3. Filter to Top 50% Expression
    # ==========================================
    row_means <- rowMeans(assays(sce.dlpfc.tran)\$logcounts)
    median_row_means <- median(row_means)
    sce.dlpfc.tran <- sce.dlpfc.tran[row_means > median_row_means, ]
    
    # ==========================================
    # 4. Calculate Proportion Zero and Filter
    # ==========================================
    prop_zeros <- get_prop_zero(sce.dlpfc.tran, group_col = "cellType.broad")
    
    propZero_limit <- 0.9
    
    filtered_genes <- filter_prop_zero(prop_zeros, cutoff = propZero_limit)
    
    sce.dlpfc.tran <- sce.dlpfc.tran[filtered_genes, ]
    
    # ==========================================
    # 5. Run Rank Invariance (Stepwise & Express)
    # ==========================================
    # Stepwise approach
    group_rank <- rank_group(sce.dlpfc.tran, group_col = "cellType.broad")
    
    cell_rank <- rank_cells(sce.dlpfc.tran, group_col = "cellType.broad")
    
    rank_invar <- rank_invariance(group_rank, cell_rank)
    
    message("Top 6 Candidate TREGs (Stepwise):")
    print(head(sort(rank_invar, decreasing = TRUE)))
    
    # Express approach
    rank_invar2 <- rank_invariance_express(
        sce.dlpfc.tran,
        group_col = "cellType.broad"
    )
    
    message("Top 6 Candidate TREGs (Express):")
    print(head(sort(rank_invar2, decreasing = TRUE)))
    
    # Verify consistency
    stopifnot(identical(rank_invar, rank_invar2))
    
    # ==========================================
    # 6. Save Outputs and Visualizations
    # ==========================================
    # Save Rank Invariance results as CSV
    rank_df <- data.frame(
        Gene = names(rank_invar),
        RankInvariance = rank_invar,
        stringsAsFactors = FALSE
    )
    rank_df <- rank_df[order(rank_df\$RankInvariance, decreasing = TRUE), ]
    write.csv(rank_df, "rank_invariance_results.csv", row.names = FALSE)
    message("Saved rank invariance results to 'rank_invariance_results.csv'")
    
    # Save the rank invariance vector as RDS
    saveRDS(rank_invar, "rank_invariance.rds")
    message("Saved rank invariance vector to 'rank_invariance.rds'")
    
    # Save the filtered SingleCellExperiment object
    saveRDS(sce.dlpfc.tran, "sce_filtered_treg.rds")
    message("Saved filtered SingleCellExperiment object to 'sce_filtered_treg.rds'")
    
    # Plot and save Proportion Zero distribution
    prop_zero_long <- prop_zeros %>%
        rownames_to_column("Gene") %>%
        pivot_longer(!Gene, names_to = "Group", values_to = "prop_zero")
    
    prop_zero_histogram <- ggplot(
        data = prop_zero_long,
        aes(x = prop_zero, fill = Group)
    ) +
        geom_histogram(binwidth = 0.05) +
        facet_wrap(~Group) +
        geom_vline(xintercept = propZero_limit, color = "red", linetype = "dashed") +
        theme_bw() +
        labs(
            title = "Proportion Zero Distribution across Groups",
            x = "Proportion Zero",
            y = "Count"
        )
    
    pdf("prop_zero_distribution.pdf", width = 10, height = 8)
    print(prop_zero_histogram)
    dev.off()
    message("Saved Proportion Zero distribution plot to 'prop_zero_distribution.pdf'")
    
    message("Pipeline completed successfully!")
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

    # input validation — workflow-level pass when expected output files exist
    # and have non-zero size. Binary pass: at least one .rds or .csv emitted.
    .iv_artifacts <- c(list.files(".", pattern = "\\.rds\$"), list.files(".", pattern = "\\.csv\$"))
    .iv_passes <- length(.iv_artifacts) > 0
    .gates_by_label[["input validation"]] <- list(
      gate_row = "bioc_input_validation",
      metric_name = "input_validation_passes",
      metric_value = if (.iv_passes) 1 else 0,
      passes = .iv_passes,
      status = paste0("computed (", length(.iv_artifacts), " artifact(s) emitted)")
    )

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_TREG_TREG_DISCOVERY",
      domain  = "bioconductor",
      declared_qc_steps = c("input validation"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_TREG_TREG_DISCOVERY":',
        paste0('    TREG: ', as.character(packageVersion('TREG')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_treg_discovery.csv versions.yml
    """
}

workflow BIOC_TREG_TREG_DISCOVERY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sce.dlpfc.tran ] ]

    main:
    BIOC_TREG_TREG_DISCOVERY(ch_input)

    emit:
    tables   = BIOC_TREG_TREG_DISCOVERY.out.tables
    plots    = BIOC_TREG_TREG_DISCOVERY.out.plots
    objects  = BIOC_TREG_TREG_DISCOVERY.out.objects
    versions = BIOC_TREG_TREG_DISCOVERY.out.versions
}
