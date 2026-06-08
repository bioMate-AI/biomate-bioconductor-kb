#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: pcaMethods — expressionset_pca_imputation
// Perform PCA and impute missing values directly on a Bioconductor ExpressionSet object.
// Input: sample.ExpressionSet
// Container: quay.io/biocontainers/bioconductor-pcamethods:2.2.0--r45ha27e39d_0
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

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20"

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
