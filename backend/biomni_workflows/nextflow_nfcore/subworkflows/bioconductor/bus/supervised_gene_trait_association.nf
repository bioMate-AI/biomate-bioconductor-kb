#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: BUS — supervised_gene_trait_association
// Compute similarity and identify associations between genes and external traits (supervised analysis) using mutual information.
// Input: expression_matrix.csv, trait_matrix.csv
// Container: quay.io/biocontainers/bioconductor-bus:1.66.0--r45ha27e39d_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: BUS, minet
// Visualizations: heatmap (ComplexHeatmap), heatmap
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the gene expression data and external trait data, formatting both as matrices with matching columns (samples)
//  * 2. [Core Analysis] Run the BUS wrapper function with nflag=2 (supervised), specifying the similarity measure
//  * 3. [Core Analysis] Extract the similarity matrix and single/multiple permutation p-values

nextflow.enable.dsl = 2

process BIOC_BUS_SUPERVISED_GENE_TRAIT_ASSOCIATION {
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
    
    # 1. Load the gene expression data and external trait data
    if (!file.exists("expression_matrix.csv")) {
      stop("Error: expression_matrix.csv not found in the working directory.")
    }
    if (!file.exists("trait_matrix.csv")) {
      stop("Error: trait_matrix.csv not found in the working directory.")
    }
    
    # Read CSV files
    exp_df <- read.csv("expression_matrix.csv", row.names = 1, check.names = FALSE)
    trait_df <- read.csv("trait_matrix.csv", row.names = 1, check.names = FALSE)
    
    # Convert to matrices
    exp <- as.matrix(exp_df)
    trait <- as.matrix(trait_df)
    
    # Align columns (samples) to ensure they match exactly
    common_samples <- intersect(colnames(exp), colnames(trait))
    if (length(common_samples) == 0) {
      stop("Error: No matching sample columns found between expression_matrix.csv and trait_matrix.csv.")
    }
    
    exp <- exp[, common_samples, drop = FALSE]
    trait <- trait[, common_samples, drop = FALSE]
    
    # 2. Run the BUS wrapper function with nflag=2 (supervised)
    # Keeping the exact function call and argument names as documented
    res <- BUS(EXP=exp,trait=trait,measure="MI",nflag=2)
    
    # 3. Extract and save the results
    # Save the complete results list as an RDS object
    saveRDS(res, file = "bus_results.rds")
    
    # Save individual matrices to CSV files
    if (!is.null(res\$similarity)) {
      write.csv(res\$similarity, file = "similarity_matrix.csv", row.names = TRUE)
    }
    if (!is.null(res\$single.perm.p.value)) {
      write.csv(res\$single.perm.p.value, file = "single_perm_p_value.csv", row.names = TRUE)
    }
    if (!is.null(res\$multi.perm.p.value)) {
      write.csv(res\$multi.perm.p.value, file = "multi_perm_p_value.csv", row.names = TRUE)
    }
    
    # Generate a PDF plot of the similarity matrix
    pdf("similarity_heatmap.pdf", width = 8, height = 8)
    if (!is.null(res\$similarity) && nrow(res\$similarity) > 0 && ncol(res\$similarity) > 0) {
      heatmap(res\$similarity, 
              main = "Gene-Trait Similarity Heatmap (MI)",
              xlab = "Traits", 
              ylab = "Genes",
              col = heat.colors(256),
              margins = c(10, 10))
    } else {
      plot.new()
      text(0.5, 0.5, "No similarity data available to plot")
    }
    dev.off()

    writeLines(c(
        '"BIOC_BUS_SUPERVISED_GENE_TRAIT_ASSOCIATION":',
        paste0('    BUS: ', as.character(packageVersion('BUS')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_supervised_gene_trait_association.csv versions.yml
    """
}

workflow BIOC_BUS_SUPERVISED_GENE_TRAIT_ASSOCIATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ expression_matrix.csv, trait_matrix.csv ] ]

    main:
    BIOC_BUS_SUPERVISED_GENE_TRAIT_ASSOCIATION(ch_input)

    emit:
    tables   = BIOC_BUS_SUPERVISED_GENE_TRAIT_ASSOCIATION.out.tables
    plots    = BIOC_BUS_SUPERVISED_GENE_TRAIT_ASSOCIATION.out.plots
    objects  = BIOC_BUS_SUPERVISED_GENE_TRAIT_ASSOCIATION.out.objects
    versions = BIOC_BUS_SUPERVISED_GENE_TRAIT_ASSOCIATION.out.versions
}
