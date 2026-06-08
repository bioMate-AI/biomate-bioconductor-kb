#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: DEGreport — expression_pattern_clustering
// Detect and cluster genes showing similar expression patterns across experimental groups or time points.
// Input: dds_object.rds, res_object.rds
// Container: quay.io/biocontainers/bioconductor-degreport:1.46.0--r45hdfd78af_0
// Requires: DEGreport, DESeq2
// Visualizations: plot (ggplot/base)
// QC: count normalization
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Prepare transformed expression matrix. 2. Detect expression patterns using degPatterns

nextflow.enable.dsl = 2

process BIOC_DEGREPORT_EXPRESSION_PATTERN_CLUSTERING {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

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
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_f in list.files(".", recursive = TRUE, full.names = TRUE)) {
          .bm_bn <- basename(.bm_f)
          if (!file.exists(.bm_bn)) try(file.copy(.bm_f, .bm_bn), silent = TRUE)
        }
            
    # Load required libraries
    library(DESeq2)
    library(DEGreport)
    
    # Check if input files exist
    if (!file.exists("dds_object.rds") || !file.exists("res_object.rds")) {
      stop("Required input files 'dds_object.rds' and/or 'res_object.rds' not found in the working directory.")
    }
    
    # Read user input files
    dds <- readRDS("dds_object.rds")
    res <- readRDS("res_object.rds")
    
    # Align res and dds to ensure matching genes
    common_genes <- intersect(rownames(res), rownames(dds))
    if (length(common_genes) == 0) {
      stop("No common genes found between dds_object and res_object.")
    }
    res <- res[common_genes, ]
    dds <- dds[common_genes, ]
    
    # Extract design from dds object
    design <- as.data.frame(colData(dds))
    
    # Ensure the 'group' column exists in design (since time = "group" is used in degPatterns)
    if (!"group" %in% colnames(design)) {
      possible_groups <- c("group", "condition", "treatment", "time", "status")
      found_col <- intersect(possible_groups, colnames(design))
      if (length(found_col) > 0) {
        design\$group <- design[[found_col[1]]]
        message(paste("Using column '", found_col[1], "' as 'group' for pattern clustering.", sep = ""))
      } else {
        design\$group <- design[[1]]
        message(paste("Using first column '", colnames(design)[1], "' as 'group' for pattern clustering.", sep = ""))
      }
    }
    
    # Filter for significantly differentially expressed genes
    sig_genes <- !is.na(res\$padj) & res\$padj < 0.05
    if (any(sig_genes)) {
      res <- res[sig_genes, ]
    } else {
      # Fallback if no genes are significant: use top genes by p-value
      res <- res[order(res\$pvalue)[1:min(100, nrow(res))], ]
    }
    
    # === DOCUMENTED CODE ===
    ma = assay(rlog(dds))[row.names(res),]
    res <- degPatterns(ma, design, time = "group")
    # === END DOCUMENTED CODE ===
    
    # Save meaningful results
    # 1. Save the full degPatterns output object
    saveRDS(res, "deg_patterns_results.rds")
    
    # 2. Save the gene-to-cluster mapping table
    if (!is.null(res\$df)) {
      write.csv(res\$df, "expression_patterns_cl_membership.csv", row.names = FALSE)
    }
    
    # 3. Save the plot
    if (!is.null(res\$plot)) {
      pdf("expression_patterns_plot.pdf", width = 10, height = 8)
      print(res\$plot)
      dev.off()
    }

    writeLines(c(
        '"BIOC_DEGREPORT_EXPRESSION_PATTERN_CLUSTERING":',
        paste0('    DEGreport: ', as.character(packageVersion('DEGreport')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_expression_pattern_clustering.csv versions.yml
    """
}

workflow BIOC_DEGREPORT_EXPRESSION_PATTERN_CLUSTERING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ dds_object.rds, res_object.rds ] ]

    main:
    BIOC_DEGREPORT_EXPRESSION_PATTERN_CLUSTERING(ch_input)

    emit:
    tables   = BIOC_DEGREPORT_EXPRESSION_PATTERN_CLUSTERING.out.tables
    plots    = BIOC_DEGREPORT_EXPRESSION_PATTERN_CLUSTERING.out.plots
    objects  = BIOC_DEGREPORT_EXPRESSION_PATTERN_CLUSTERING.out.objects
    versions = BIOC_DEGREPORT_EXPRESSION_PATTERN_CLUSTERING.out.versions
}
