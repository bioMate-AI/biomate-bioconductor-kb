#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: vsn — reference_normalization
// Normalize new test arrays against an existing reference dataset without changing the reference parameters.
// Input: lymphoma
// Container: quay.io/biocontainers/bioconductor-vsn:3.78.1--r45h01b2380_0
// Requires: Biobase, vsn
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Fit the VSN model on the reference arrays using vsn2. 2. Fit the VSN model on the new arrays using vsn2 with the reference paramet

nextflow.enable.dsl = 2

process BIOC_VSN_REFERENCE_NORMALIZATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-variant_calling:3.20"

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
    library("vsn")
    library("Biobase")
    
    # ------------------------------------------------------------------------------
    # 1. Read User Input
    # ------------------------------------------------------------------------------
    # The pipeline expects the 'lymphoma' ExpressionSet to be saved as an RDS file
    # in the working directory, named either 'lymphoma.rds' or 'lymphoma'.
    if (file.exists("lymphoma.rds")) {
      lymphoma <- readRDS("lymphoma.rds")
    } else if (file.exists("lymphoma")) {
      lymphoma <- readRDS("lymphoma")
    } else {
      stop("Required input file 'lymphoma.rds' or 'lymphoma' not found in the working directory.")
    }
    
    # Determine the number of samples in the user-provided ExpressionSet
    N <- ncol(lymphoma)
    
    # ------------------------------------------------------------------------------
    # 2. Run Documented Workflow: Reference Normalization
    # ------------------------------------------------------------------------------
    # Fit the VSN model on the reference arrays (first N-1 samples)
    ref = vsn2(lymphoma[, 1:(N-1)])
    
    # Fit the VSN model on the last array using the reference parameters
    f8 = vsn2(lymphoma[, N], reference = ref)
    
    # Fit the VSN model on all arrays jointly for comparison
    fall = vsn2(lymphoma)
    
    # ------------------------------------------------------------------------------
    # 3. Save Outputs
    # ------------------------------------------------------------------------------
    # Save the fitted VSN objects as RDS
    saveRDS(ref, "vsn_ref_fit.rds")
    saveRDS(f8, "vsn_f8_fit.rds")
    saveRDS(fall, "vsn_fall_fit.rds")
    
    # Extract and save the normalized expression values as CSV
    write.csv(exprs(f8), "normalized_intensities_f8.csv", row.names = TRUE)
    write.csv(exprs(fall), "normalized_intensities_fall.csv", row.names = TRUE)
    
    # Generate diagnostic plot comparing reference-normalized vs joint-normalized values
    pdf("reference_vs_joint_normalization_plot.pdf", width = 6, height = 6)
    plot(exprs(f8), exprs(fall)[, N], 
         pch = ".", 
         asp = 1,
         xlab = "Reference Normalization (f8)",
         ylab = paste0("Joint Normalization (fall[,", N, "])"),
         main = "Comparison of Normalization Methods")
    abline(a = 0, b = 1, col = "red")
    dev.off()

    writeLines(c(
        '"BIOC_VSN_REFERENCE_NORMALIZATION":',
        paste0('    vsn: ', as.character(packageVersion('vsn')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_reference_normalization.csv versions.yml
    """
}

workflow BIOC_VSN_REFERENCE_NORMALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ lymphoma ] ]

    main:
    BIOC_VSN_REFERENCE_NORMALIZATION(ch_input)

    emit:
    tables   = BIOC_VSN_REFERENCE_NORMALIZATION.out.tables
    plots    = BIOC_VSN_REFERENCE_NORMALIZATION.out.plots
    objects  = BIOC_VSN_REFERENCE_NORMALIZATION.out.objects
    versions = BIOC_VSN_REFERENCE_NORMALIZATION.out.versions
}
