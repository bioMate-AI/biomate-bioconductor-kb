#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: RankProd — single_origin_analysis
// Identify differentially expressed genes from a single-origin dataset using the Rank Product method.
// Input: normalized_expression_matrix.tsv, class_labels.txt
// Container: quay.io/biocontainers/bioconductor-rankprod:3.36.0--r45hdfd78af_0
// R packages: RankProd
// Bioconductor: 3.20 | R: 4.4
// Requires: RankProd
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run RankProducts to perform the Rank Product analysis
//  * 2. [Visualization & Output] Plot the estimated pfp vs. number of identified genes using plotRP
//  * 3. [Core Analysis] Extract significant up- and down-regulated genes using topGene

nextflow.enable.dsl = 2

process BIOC_RANKPROD_SINGLE_ORIGIN_ANALYSIS {
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
    
    # Load the required Bioconductor package
    library(RankProd)
    
    # -----------------------------------------------------------------------------
    # 1. Read User Input Files
    # -----------------------------------------------------------------------------
    # Read the normalized expression matrix (TSV format, genes as rows, samples as columns)
    expression_data <- read.delim("normalized_expression_matrix.tsv", row.names = 1, header = TRUE, check.names = FALSE)
    arab.sub <- as.matrix(expression_data)
    
    # Extract gene names from the row names of the expression matrix
    arab.gnames <- rownames(arab.sub)
    
    # Read the class labels vector (e.g., 0 for control, 1 for treatment)
    arab.cl.sub <- scan("class_labels.txt", quiet = TRUE)
    
    # -----------------------------------------------------------------------------
    # 2. Perform Rank Product Analysis
    # -----------------------------------------------------------------------------
    # Run RankProducts exactly as documented
    RP.out <- RankProducts(arab.sub,arab.cl.sub, logged=TRUE,
    na.rm=FALSE,plot=FALSE,  rand=123)
    
    # Save the complete RankProducts output object as an RDS file
    saveRDS(RP.out, file = "RankProducts_output.rds")
    
    # -----------------------------------------------------------------------------
    # 3. Plot Estimated PFP vs. Number of Identified Genes
    # -----------------------------------------------------------------------------
    # Save the plot to a PDF file
    pdf("pfp_vs_identified_genes_plot.pdf", width = 7, height = 10)
    plotRP(RP.out, cutoff=0.05)
    dev.off()
    
    # -----------------------------------------------------------------------------
    # 4. Extract Significant Up- and Down-Regulated Genes
    # -----------------------------------------------------------------------------
    # Run topGene exactly as documented
    significant_genes <- topGene(RP.out,cutoff=0.05,method="pfp",
    logged=TRUE,logbase=2,gene.names=arab.gnames)
    
    # Save the resulting tables to CSV files
    if (!is.null(significant_genes\$Table1)) {
      write.csv(significant_genes\$Table1, file = "significant_up_regulated_genes.csv", row.names = TRUE)
    }
    
    if (!is.null(significant_genes\$Table2)) {
      write.csv(significant_genes\$Table2, file = "significant_down_regulated_genes.csv", row.names = TRUE)
    }

    writeLines(c(
        '"BIOC_RANKPROD_SINGLE_ORIGIN_ANALYSIS":',
        paste0('    RankProd: ', as.character(packageVersion('RankProd')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_single_origin_analysis.csv versions.yml
    """
}

workflow BIOC_RANKPROD_SINGLE_ORIGIN_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ normalized_expression_matrix.tsv, class_labels.txt ] ]

    main:
    BIOC_RANKPROD_SINGLE_ORIGIN_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_RANKPROD_SINGLE_ORIGIN_ANALYSIS.out.tables
    plots    = BIOC_RANKPROD_SINGLE_ORIGIN_ANALYSIS.out.plots
    objects  = BIOC_RANKPROD_SINGLE_ORIGIN_ANALYSIS.out.objects
    versions = BIOC_RANKPROD_SINGLE_ORIGIN_ANALYSIS.out.versions
}
