#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: regutools — regutools_bacterial_regulation
// Integrate E. coli transcriptomic count data with RegulonDB to identify active transcription factors, construct local regulatory networks, and extract genomic co
// Input: counts.csv, coldata.csv
// Container: 1.22.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: BiocGenerics, GenomicRanges, IRanges, regutools
// QC: count normalization
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_REGUTOOLS_REGUTOOLS_BACTERIAL_REGULATION {
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
    .bm_deps <- c("regutools", "GenomicRanges", "BiocGenerics")
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
    library(regutools)
    library(GenomicRanges)
    library(BiocGenerics)
    
    # ==========================================
    # --- Load and Preprocess Input Data ---
    # ==========================================
    
    # Read expression counts and sample metadata
    counts <- read.csv("counts.csv", row.names = 1, check.names = FALSE)
    coldata <- read.csv("coldata.csv", stringsAsFactors = FALSE)
    
    # Perform basic normalization: log2(Counts Per Million + 1)
    cpm <- apply(counts, 2, function(x) {
        lib_size <- sum(x)
        if (lib_size == 0) return(x)
        (x / lib_size) * 1e6
    })
    log_cpm <- log2(cpm + 1)
    
    # Identify differentially expressed genes based on log2 fold change
    conds <- coldata\$condition
    unique_conds <- unique(conds)
    
    if (length(unique_conds) >= 2) {
        group1 <- which(conds == unique_conds[1])
        group2 <- which(conds == unique_conds[2])
        
        mean1 <- rowMeans(log_cpm[, group1, drop = FALSE])
        mean2 <- rowMeans(log_cpm[, group2, drop = FALSE])
        
        logFC <- mean2 - mean1
        # Sort genes by absolute log fold change
        de_genes <- names(logFC)[order(abs(logFC), decreasing = TRUE)]
    } else {
        # Fallback to high-variance genes if conditions are insufficient
        gene_vars <- apply(log_cpm, 1, var)
        de_genes <- names(gene_vars)[order(gene_vars, decreasing = TRUE)]
    }
    
    # Select top N genes for downstream RegulonDB query
    top_n <- 50
    selected_genes <- head(de_genes, top_n)
    
    # ==========================================
    # --- Connect to RegulonDB Database ---
    # ==========================================
    
    # Establish connection to the database
    regulondb_conn <- connect_database()
    
    # Build the regulondb object
    e_coli_db <- regulondb(
        database_conn = regulondb_conn,
        organism = "E.coli",
        database_version = "1",
        genome_version = "1"
    )
    
    # ==========================================
    # --- Query Gene Regulators & Networks ---
    # ==========================================
    
    # Retrieve transcription factors regulating the selected genes
    regulators_df <- tryCatch({
        get_gene_regulators(e_coli_db, selected_genes)
    }, error = function(e) {
        warning("Failed to retrieve gene regulators: ", e\$message)
        data.frame(genes = character(), regulators = character(), effect = character())
    })
    
    # Retrieve the full regulatory network and filter for our genes/regulators
    network_subset <- tryCatch({
        full_network <- get_regulatory_network(e_coli_db)
        # Filter network for interactions involving our selected genes or their regulators
        subset_idx <- full_network\$regulated %in% selected_genes | 
                      full_network\$regulator %in% regulators_df\$regulators
        full_network[subset_idx, ]
    }, error = function(e) {
        warning("Failed to retrieve regulatory network: ", e\$message)
        data.frame(regulator = character(), regulated = character(), effect = character())
    })
    
    # Generate a summary of the transcription factors regulating the genes
    regulatory_summary <- tryCatch({
        get_regulatory_summary(e_coli_db, gene_regulators = selected_genes)
    }, error = function(e) {
        warning("Failed to generate regulatory summary: ", e\$message)
        data.frame(TF = character(), Regulated_genes_per_TF = character(), Percent = character())
    })
    
    # ==========================================
    # --- Retrieve Genomic Coordinates ---
    # ==========================================
    
    # Query genomic coordinates for the selected genes
    gene_coords_df <- tryCatch({
        coords_res <- get_dataset(
            regulondb = e_coli_db,
            dataset = "GENE",
            attributes = c("posleft", "posright", "strand", "name"),
            filters = list("name" = selected_genes)
        )
        # Convert the result to a GRanges object
        gr <- convert_to_granges(coords_res)
        as.data.frame(gr)
    }, error = function(e) {
        warning("Failed to retrieve gene coordinates: ", e\$message)
        data.frame(seqnames = character(), start = integer(), end = integer(), strand = character(), name = character())
    })
    
    # ==========================================
    # --- Extract Transcription Factor Binding Sites ---
    # ==========================================
    
    # Identify the most prominent regulator from our dataset
    top_regulator <- "Crp" # Default fallback
    if (nrow(regulators_df) > 0) {
        reg_counts <- table(regulators_df\$regulators)
        if (length(reg_counts) > 0) {
            top_regulator <- names(reg_counts)[which.max(reg_counts)]
        }
    }
    
    # Retrieve binding sites for the top regulator
    binding_sites_df <- tryCatch({
        bs_gr <- get_binding_sites(e_coli_db, transcription_factor = top_regulator)
        as.data.frame(bs_gr)
    }, error = function(e) {
        warning("Failed to retrieve binding sites for ", top_regulator, ": ", e\$message)
        data.frame(seqnames = character(), start = integer(), end = integer(), strand = character(), sequence = character())
    })
    
    # ==========================================
    # --- Write Outputs to Disk ---
    # ==========================================
    
    write.csv(as.data.frame(network_subset), "regulatory_network.csv", row.names = FALSE)
    write.csv(as.data.frame(regulatory_summary), "regulatory_summary.csv", row.names = FALSE)
    write.csv(gene_coords_df, "gene_coordinates.csv", row.names = FALSE)
    write.csv(binding_sites_df, "binding_sites.csv", row.names = FALSE)
    
    cat("Analysis complete. Outputs written to working directory.\n")
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

    # count normalization — scan .rds matrix artifacts for library-size CV
    # ratio (post-norm / pre-norm); without raw input we report median lib CV
    # as a proxy diagnostic. Threshold = 0.7 (Bullard 2010 BMC Bioinf).
    .cn_lib_cvs <- numeric(0)
    .cn_scanned <- character(0)
    for (.cn_rds in list.files(".", pattern = "\\.rds\$", recursive = FALSE)) {
      .cn_obj <- tryCatch(readRDS(.cn_rds), error = function(e) NULL)
      .cn_mat <- if (is.matrix(.cn_obj) || is.data.frame(.cn_obj)) .cn_obj else NULL
      if (!is.null(.cn_mat) && ncol(.cn_mat) >= 2 && nrow(.cn_mat) >= 2) {
        .cn_lib <- tryCatch(colSums(as.matrix(.cn_mat), na.rm = TRUE), error = function(e) NULL)
        if (!is.null(.cn_lib) && all(is.finite(.cn_lib)) && mean(.cn_lib) > 0) {
          .cn_lib_cvs <- c(.cn_lib_cvs, sd(.cn_lib) / mean(.cn_lib))
          .cn_scanned <- c(.cn_scanned, .cn_rds)
        }
      }
    }
    .cn_med_cv <- if (length(.cn_lib_cvs) > 0) round(median(.cn_lib_cvs), 4) else NA_real_
    .gates_by_label[["count normalization"]] <- list(
      gate_row = "bioc_count_normalization",
      metric_name = "lib_size_cv_median",
      metric_value = .cn_med_cv,
      passes = isTRUE(is.finite(.cn_med_cv) && .cn_med_cv <= 0.3),
      status = if (is.finite(.cn_med_cv)) paste0("computed (proxy: median lib-size CV across ", length(.cn_scanned), " matrix .rds; raw-vs-norm ratio not measurable without paired input)")
               else "not_computed (no count matrix .rds artifact present)"
    )

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_REGUTOOLS_REGUTOOLS_BACTERIAL_REGULATION",
      domain  = "bioconductor",
      declared_qc_steps = c("count normalization"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_REGUTOOLS_REGUTOOLS_BACTERIAL_REGULATION":',
        paste0('    regutools: ', as.character(packageVersion('regutools')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_regutools_bacterial_regulation.csv versions.yml
    """
}

workflow BIOC_REGUTOOLS_REGUTOOLS_BACTERIAL_REGULATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_REGUTOOLS_REGUTOOLS_BACTERIAL_REGULATION(ch_input)

    emit:
    tables   = BIOC_REGUTOOLS_REGUTOOLS_BACTERIAL_REGULATION.out.tables
    plots    = BIOC_REGUTOOLS_REGUTOOLS_BACTERIAL_REGULATION.out.plots
    objects  = BIOC_REGUTOOLS_REGUTOOLS_BACTERIAL_REGULATION.out.objects
    versions = BIOC_REGUTOOLS_REGUTOOLS_BACTERIAL_REGULATION.out.versions
}
