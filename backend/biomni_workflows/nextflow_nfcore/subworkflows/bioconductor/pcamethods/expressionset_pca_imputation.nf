#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: pcaMethods — expressionset_pca_imputation
// Perform PCA and impute missing values directly on a Bioconductor ExpressionSet object.
// Input: sample.ExpressionSet
// Container: quay.io/biocontainers/bioconductor-pcamethods:2.2.0--r45ha27e39d_0
// R packages: Biobase, pcaMethods
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, pcaMethods
// Visualizations: PCA plot
// QC: missing-value handling
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Introduce missing values to the ExpressionSet
//  * 2. [Core Analysis] Run PCA on the ExpressionSet
//  * 3. [Core Analysis] Convert the PCA result back to an imputed ExpressionSet using asExprSet

nextflow.enable.dsl = 2

process BIOC_PCAMETHODS_EXPRESSIONSET_PCA_IMPUTATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20-slim"

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
    .bm_deps <- c("Biobase", "pcaMethods")
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
    library(pcaMethods)
    library(Biobase)
    
    # 1. Read the user input file (ExpressionSet object)
    # The pipeline expects "sample.ExpressionSet" in the working directory.
    exSet <- readRDS("sample.ExpressionSet")
    
    # 2. Introduce missing values to the ExpressionSet
    exSetNa <- exSet
    total_elements <- length(exprs(exSetNa))
    # We dynamically determine the number of NAs to introduce based on the dataset size,
    # mimicking the vignette's introduction of missing values.
    num_to_na <- min(200, as.integer(total_elements * 0.05))
    set.seed(123) # Ensure reproducibility of the NA mask
    exprs(exSetNa)[sample(total_elements, num_to_na)] <- NA
    lost <- is.na(exprs(exSetNa))
    
    # 3. Run PCA on the ExpressionSet
    pc <- pca(exSetNa, nPcs=2, method="ppca")
    
    # 4. Convert the PCA result back to an imputed ExpressionSet using asExprSet
    impExSet <- asExprSet(pc, exSetNa)
    
    # 5. Write named output files
    # Save the imputed ExpressionSet object
    saveRDS(impExSet, "imputed_ExpressionSet.rds")
    
    # Save the PCA result object
    saveRDS(pc, "pca_result.rds")
    
    # Save the imputed expression matrix as a CSV
    write.csv(exprs(impExSet), "imputed_expression_matrix.csv", row.names = TRUE)
    
    # Save a PDF plot of the PCA scores
    pdf("pca_scores_plot.pdf")
    plotPcs(pc, pc=1:2, type="score")
    dev.off()

    writeLines(c(
        '"BIOC_PCAMETHODS_EXPRESSIONSET_PCA_IMPUTATION":',
        paste0('    pcaMethods: ', as.character(packageVersion('pcaMethods')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_expressionset_pca_imputation.csv versions.yml
    """
}

workflow BIOC_PCAMETHODS_EXPRESSIONSET_PCA_IMPUTATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sample.ExpressionSet ] ]

    main:
    BIOC_PCAMETHODS_EXPRESSIONSET_PCA_IMPUTATION(ch_input)

    emit:
    tables   = BIOC_PCAMETHODS_EXPRESSIONSET_PCA_IMPUTATION.out.tables
    plots    = BIOC_PCAMETHODS_EXPRESSIONSET_PCA_IMPUTATION.out.plots
    objects  = BIOC_PCAMETHODS_EXPRESSIONSET_PCA_IMPUTATION.out.objects
    versions = BIOC_PCAMETHODS_EXPRESSIONSET_PCA_IMPUTATION.out.versions
}
