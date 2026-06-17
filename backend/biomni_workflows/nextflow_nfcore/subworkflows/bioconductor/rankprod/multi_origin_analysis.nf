#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: RankProd — multi_origin_analysis
// Combine datasets from multiple laboratories or origins to perform an overall differential expression analysis.
// Input: multi_origin_expression_matrix.tsv, class_labels.txt, origin_labels.txt
// Container: quay.io/biocontainers/bioconductor-rankprod:3.36.0--r45hdfd78af_0
// R packages: RankProd
// Bioconductor: 3.20 | R: 4.4
// Requires: RankProd
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run RP.advance to perform multi-origin Rank Product analysis
//  * 2. [Visualization & Output] Plot the estimated pfp vs. number of identified genes using plotRP
//  * 3. [Core Analysis] Extract significant genes across all origins using topGene

nextflow.enable.dsl = 2

process BIOC_RANKPROD_MULTI_ORIGIN_ANALYSIS {
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
    .bm_deps <- c("RankProd")
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
    
    # Load required library
    library(RankProd)
    
    # 1. Read user input files from the working directory
    if (!file.exists("multi_origin_expression_matrix.tsv")) {
      stop("Error: 'multi_origin_expression_matrix.tsv' not found in the working directory.")
    }
    arab <- as.matrix(read.delim("multi_origin_expression_matrix.tsv", row.names = 1, check.names = FALSE))
    
    if (!file.exists("class_labels.txt")) {
      stop("Error: 'class_labels.txt' not found in the working directory.")
    }
    arab.cl <- scan("class_labels.txt", quiet = TRUE)
    
    if (!file.exists("origin_labels.txt")) {
      stop("Error: 'origin_labels.txt' not found in the working directory.")
    }
    arab.origin <- scan("origin_labels.txt", quiet = TRUE)
    
    # Extract gene names from the expression matrix
    arab.gnames <- rownames(arab)
    
    # 2. Run RP.advance to perform multi-origin Rank Product analysis
    # (Faithfully reproducing the documented function call and arguments)
    RP.adv.out <-  RP.advance(arab,arab.cl,arab.origin,
    logged=TRUE,gene.names=arab.gnames,rand=123)
    
    # Save the analysis object to an RDS file
    saveRDS(RP.adv.out, file = "RP_advance_output.rds")
    
    # 3. Plot the estimated pfp vs. number of identified genes using plotRP
    # (Faithfully reproducing the documented function call and arguments, outputting to PDF)
    pdf("pfp_vs_identified_genes_plot.pdf", width = 8, height = 10)
    plotRP(RP.adv.out, cutoff=0.05)
    dev.off()
    
    # 4. Extract significant genes across all origins using topGene
    # (Faithfully reproducing the documented function call and arguments)
    top_genes_out <- topGene(RP.adv.out,cutoff=0.05,method="pfp",logged=TRUE,logbase=2,
            gene.names=arab.gnames)
    
    # Write the resulting tables of significant genes to CSV files
    if (!is.null(top_genes_out\$Table1)) {
      write.csv(top_genes_out\$Table1, file = "significant_genes_class1_less_than_class2.csv", row.names = TRUE)
    }
    if (!is.null(top_genes_out\$Table2)) {
      write.csv(top_genes_out\$Table2, file = "significant_genes_class1_greater_than_class2.csv", row.names = TRUE)
    }

    writeLines(c(
        '"BIOC_RANKPROD_MULTI_ORIGIN_ANALYSIS":',
        paste0('    RankProd: ', as.character(packageVersion('RankProd')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_multi_origin_analysis.csv versions.yml
    """
}

workflow BIOC_RANKPROD_MULTI_ORIGIN_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ multi_origin_expression_matrix.tsv, class_labels.txt, origin_labels.txt ] ]

    main:
    BIOC_RANKPROD_MULTI_ORIGIN_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_RANKPROD_MULTI_ORIGIN_ANALYSIS.out.tables
    plots    = BIOC_RANKPROD_MULTI_ORIGIN_ANALYSIS.out.plots
    objects  = BIOC_RANKPROD_MULTI_ORIGIN_ANALYSIS.out.objects
    versions = BIOC_RANKPROD_MULTI_ORIGIN_ANALYSIS.out.versions
}
