#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: EBSEA — ebsea_differential_expression
// Perform exon-level differential expression analysis and aggregate to gene-level using EBSEA.
// Input: counts.csv, coldata.csv
// Container: 1.38.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: EBSEA
// Visualizations: plot (ggplot/base)
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_EBSEA_EBSEA_DIFFERENTIAL_EXPRESSION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim"

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
    .bm_deps <- c("EBSEA")
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
    library(EBSEA)
    
    # --- Read and preprocess input data ---
    if (!file.exists("counts.csv") || !file.exists("coldata.csv")) {
        stop("Required input files 'counts.csv' and/or 'coldata.csv' are missing.")
    }
    
    # Read counts matrix
    counts_df <- read.csv("counts.csv", check.names = FALSE, stringsAsFactors = FALSE)
    if ("gene_id" %in% colnames(counts_df)) {
        rownames(counts_df) <- counts_df\$gene_id
        counts_df\$gene_id <- NULL
    } else {
        rownames(counts_df) <- counts_df[, 1]
        counts_df <- counts_df[, -1, drop = FALSE]
    }
    counts <- as.matrix(counts_df)
    
    # Read sample metadata
    coldata <- read.csv("coldata.csv", stringsAsFactors = FALSE)
    if (!all(c("sample", "condition") %in% colnames(coldata))) {
        stop("coldata.csv must contain 'sample' and 'condition' columns.")
    }
    
    # Align counts columns with coldata samples
    common_samples <- intersect(colnames(counts), coldata\$sample)
    if (length(common_samples) == 0) {
        stop("No matching samples found between counts.csv and coldata.csv.")
    }
    counts <- counts[, common_samples, drop = FALSE]
    coldata <- coldata[match(common_samples, coldata\$sample), ]
    
    # Format row names to "Gene:Exon" if not already formatted
    # EBSEA requires "GeneName:ExonNumber" format to correctly aggregate exons to genes
    if (!any(grepl(":", rownames(counts)))) {
        message("Row names do not contain ':'. Appending ':001' to simulate single-exon genes.")
        rownames(counts) <- paste0(rownames(counts), ":001")
    }
    
    # --- Prepare design and group data frame ---
    group <- data.frame(group = as.factor(coldata\$condition))
    rownames(group) <- coldata\$sample
    design <- ~ group
    
    # --- Filter lowly expressed exons ---
    message("Filtering lowly expressed exons...")
    filtCounts <- filterCounts(counts)
    
    # --- Run EBSEA analysis ---
    message("Running EBSEA statistical testing and gene-level aggregation...")
    ebsea.out <- EBSEA(filtCounts, group, design)
    
    # --- Export results ---
    message("Exporting results...")
    write.csv(ebsea.out\$ExonTable, "exon_results.csv", row.names = TRUE)
    write.csv(ebsea.out\$GeneTable, "gene_results.csv", row.names = FALSE)
    
    # --- Visualization of the top significant gene ---
    message("Generating visualization for the top significant gene...")
    gene_table <- ebsea.out\$GeneTable
    
    # Sort to find the most significant gene
    if (nrow(gene_table) > 0) {
        # Order by padj, then by P_test
        gene_table_sorted <- gene_table[order(gene_table\$padj, gene_table\$P_test, decreasing = FALSE), ]
        top_gene <- gene_table_sorted\$Gene[1]
        
        if (!is.null(top_gene) && !is.na(top_gene) && top_gene != "") {
            tryCatch({
                pdf("top_gene_expression.pdf", width = 8, height = 6)
                visualizeGenes(top_gene, ebsea.out)
                dev.off()
                message(paste("Successfully plotted top gene:", top_gene))
            }, error = function(e) {
                warning("Visualization failed: ", e\$message)
                if (dev.cur() > 1) dev.off()
            })
        } else {
            warning("No valid top gene found for visualization.")
        }
    } else {
        warning("Gene table is empty. Skipping visualization.")
    }
    
    message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_EBSEA_EBSEA_DIFFERENTIAL_EXPRESSION":',
        paste0('    EBSEA: ', as.character(packageVersion('EBSEA')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ebsea_differential_expression.csv versions.yml
    """
}

workflow BIOC_EBSEA_EBSEA_DIFFERENTIAL_EXPRESSION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_EBSEA_EBSEA_DIFFERENTIAL_EXPRESSION(ch_input)

    emit:
    tables   = BIOC_EBSEA_EBSEA_DIFFERENTIAL_EXPRESSION.out.tables
    plots    = BIOC_EBSEA_EBSEA_DIFFERENTIAL_EXPRESSION.out.plots
    objects  = BIOC_EBSEA_EBSEA_DIFFERENTIAL_EXPRESSION.out.objects
    versions = BIOC_EBSEA_EBSEA_DIFFERENTIAL_EXPRESSION.out.versions
}
