#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: BUS — unsupervised_gene_association
// Compute similarity and predict interaction networks among genes (unsupervised analysis) using mutual information.
// Input: expression_matrix.csv
// Container: quay.io/biocontainers/bioconductor-bus:1.66.0--r45ha27e39d_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: BUS, minet
// Visualizations: heatmap (ComplexHeatmap), heatmap
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the expression data and format it as a matrix
//  * 2. [Core Analysis] Run the BUS wrapper function with nflag=1 (unsupervised), specifying the similarity measure, network trimming method, and signific
//  * 3. [Core Analysis] Extract the similarity matrix, single/multiple permutation p-values, and the predicted network

nextflow.enable.dsl = 2

process BIOC_BUS_UNSUPERVISED_GENE_ASSOCIATION {
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
    .bm_deps <- c("BUS", "minet")
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
    library(BUS)
    library(minet)
    
    # 1. Load the expression data and format it as a matrix
    # Read the user-provided expression_matrix.csv
    # We assume the first column contains gene names (row names)
    expr_data <- read.csv("expression_matrix.csv", row.names = 1, check.names = FALSE)
    mat <- as.matrix(expr_data)
    
    # 2. Run the BUS wrapper function with nflag=1 (unsupervised)
    # Keep every documented function call and its argument names EXACTLY as shown in the vignette
    res <- BUS(EXP=mat, measure="MI", n.replica=400, net.trim="aracne", thresh=0.05, nflag=1)
    
    # 3. Extract the similarity matrix, single/multiple permutation p-values, and the predicted network
    similarity_matrix <- res\$similarity
    single_p_val <- res\$single.perm.p.value
    multi_p_val <- res\$multi.perm.p.value
    predicted_net <- res\$net.pred.permut
    
    # 4. Write named output files
    write.csv(similarity_matrix, "similarity_matrix.csv", row.names = TRUE)
    write.csv(single_p_val, "single_permutation_p_values.csv", row.names = TRUE)
    write.csv(multi_p_val, "multiple_permutation_p_values.csv", row.names = TRUE)
    write.csv(predicted_net, "predicted_network.csv", row.names = TRUE)
    
    # Save the complete results object
    saveRDS(res, "bus_output.rds")
    
    # Generate a PDF plot of the similarity matrix heatmap
    pdf("similarity_heatmap.pdf", width = 7, height = 7)
    heatmap(similarity_matrix, 
            main = "Gene Similarity Heatmap (Mutual Information)", 
            col = heat.colors(256),
            margins = c(10, 10))
    dev.off()

    writeLines(c(
        '"BIOC_BUS_UNSUPERVISED_GENE_ASSOCIATION":',
        paste0('    BUS: ', as.character(packageVersion('BUS')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_unsupervised_gene_association.csv versions.yml
    """
}

workflow BIOC_BUS_UNSUPERVISED_GENE_ASSOCIATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ expression_matrix.csv ] ]

    main:
    BIOC_BUS_UNSUPERVISED_GENE_ASSOCIATION(ch_input)

    emit:
    tables   = BIOC_BUS_UNSUPERVISED_GENE_ASSOCIATION.out.tables
    plots    = BIOC_BUS_UNSUPERVISED_GENE_ASSOCIATION.out.plots
    objects  = BIOC_BUS_UNSUPERVISED_GENE_ASSOCIATION.out.objects
    versions = BIOC_BUS_UNSUPERVISED_GENE_ASSOCIATION.out.versions
}
