#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: adSplit — manual_split_and_null_distribution
// Manually cluster samples using divisive hierarchical 2-means on a custom gene subset and generate a null distribution of DLD-scores using random gene sets.
// Input: Matrix, Environment
// Container: quay.io/biocontainers/bioconductor-adsplit:1.80.0--r45ha27e39d_0
// R packages: Biobase, adSplit
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, adSplit
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Filter the expression matrix for highly variable genes
//  * 2. [Core Analysis] Run diana2means to cluster samples and retrieve the split classifications and DLD-score
//  * 3. [Input & Preparation] Create an Entrez ID to probe set environment using makeEID2PROBESenv
//  * 4. [Visualization & Output] Draw random probe sets using drawRandomPS
//  * 5. [Visualization & Output] Generate a null distribution of DLD-scores using randomDiana2means and plot the distributions

nextflow.enable.dsl = 2

process BIOC_ADSPLIT_MANUAL_SPLIT_AND_NULL_DISTRIBUTION {
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
    .bm_deps <- c("Biobase", "adSplit")
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
    
    # Load required libraries
    library(adSplit)
    library(Biobase)
    
    # ==========================================
    # 1. Read User Inputs from Working Directory
    # ==========================================
    if (!file.exists("expression_matrix.csv")) {
      stop("Error: 'expression_matrix.csv' not found in the working directory.")
    }
    if (!file.exists("entrez_id_mapping.rds")) {
      stop("Error: 'entrez_id_mapping.rds' not found in the working directory.")
    }
    
    # Load the expression matrix (genes as rows, samples as columns)
    e_raw <- as.matrix(read.csv("expression_matrix.csv", row.names = 1, check.names = FALSE))
    
    # Reconstruct Golub_Merge as an ExpressionSet to match the documented code exactly
    Golub_Merge <- ExpressionSet(assayData = e_raw)
    
    # Load the Entrez ID mapping object (e.g., hu6800ENTREZID)
    hu6800ENTREZID <- readRDS("entrez_id_mapping.rds")
    
    
    # ==========================================
    # 2. Documented Workflow Execution
    # ==========================================
    
    # Filter the expression matrix for highly variable genes
    e <- exprs(Golub_Merge)
    vars <- apply(e, 1, var)
    e <- e[vars > quantile(vars,0.9),]
    
    # Run diana2means to cluster samples and retrieve the split classifications and DLD-score
    diana2means(e)
    diana2means(e, return.cut=TRUE)
    x <- diana2means(e, return.cut=TRUE)
    x\$cut
    
    # Create an Entrez ID to probe set environment using makeEID2PROBESenv
    EID2PSenv <- makeEID2PROBESenv(hu6800ENTREZID)
    
    # Draw random probe sets using drawRandomPS
    drawRandomPS(10, EID2PSenv, ls(EID2PSenv))
    
    # Generate a null distribution of DLD-scores using randomDiana2means
    scores <- randomDiana2means(20, exprs(Golub_Merge), "hu6800", ndraws = 1000)
    scores2 <- randomDiana2means(20, exprs(Golub_Merge), "hu6800", ndraws = 1000, ignore.genes=5)
    
    
    # ==========================================
    # 3. Save Outputs and Plots
    # ==========================================
    
    # Save the histograms to a PDF file
    pdf("dld_scores_histograms.pdf", width = 10, height = 5)
    par(mfrow=c(1,2))
    hist(scores,  nclass=30, main="", col="grey")
    hist(scores2, nclass=30, main="", col="grey")
    dev.off()
    
    # Save the split classifications (cut) to a CSV file
    write.csv(as.data.frame(x\$cut), "diana2means_cut.csv", row.names = FALSE)
    
    # Save the filtered expression matrix
    write.csv(e, "filtered_expression_matrix.csv")
    
    # Save the generated scores and environment metadata to an RDS file
    saveRDS(list(
      scores = scores,
      scores2 = scores2,
      diana_split = x
    ), "null_distribution_results.rds")
    
    message("Pipeline completed successfully.")
    message("Outputs written to:")
    message("- 'dld_scores_histograms.pdf'")
    message("- 'diana2means_cut.csv'")
    message("- 'filtered_expression_matrix.csv'")
    message("- 'null_distribution_results.rds'")

    writeLines(c(
        '"BIOC_ADSPLIT_MANUAL_SPLIT_AND_NULL_DISTRIBUTION":',
        paste0('    adSplit: ', as.character(packageVersion('adSplit')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_manual_split_and_null_distribution.csv versions.yml
    """
}

workflow BIOC_ADSPLIT_MANUAL_SPLIT_AND_NULL_DISTRIBUTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ Matrix, Environment ] ]

    main:
    BIOC_ADSPLIT_MANUAL_SPLIT_AND_NULL_DISTRIBUTION(ch_input)

    emit:
    tables   = BIOC_ADSPLIT_MANUAL_SPLIT_AND_NULL_DISTRIBUTION.out.tables
    plots    = BIOC_ADSPLIT_MANUAL_SPLIT_AND_NULL_DISTRIBUTION.out.plots
    objects  = BIOC_ADSPLIT_MANUAL_SPLIT_AND_NULL_DISTRIBUTION.out.objects
    versions = BIOC_ADSPLIT_MANUAL_SPLIT_AND_NULL_DISTRIBUTION.out.versions
}
