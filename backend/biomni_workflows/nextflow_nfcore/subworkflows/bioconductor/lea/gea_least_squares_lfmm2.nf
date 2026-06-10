#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: lea — gea_least_squares_lfmm2
// Perform fast genotype-environment association (GEA) testing using the least-squares algorithm in LFMM2.
// Input: Y, X
// Container: quay.io/biocontainers/bioconductor-lea:3.22.0--r45h01b2380_0
// R packages: LEA
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_LEA_GEA_LEAST_SQUARES_LFMM2 {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-lea:3.22.0--r45h01b2380_0"

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
    .bm_deps <- c("LEA")
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
    
    # Load required library
    library(LEA)
    
    # -----------------------------------------------------------------------------
    # 1. Load User Inputs
    # -----------------------------------------------------------------------------
    # The pipeline expects 'Y' (genotype matrix) and 'X' (environmental variables)
    # to be present in the working directory as RDS or CSV files.
    
    if (file.exists("Y.rds")) {
      Y <- readRDS("Y.rds")
    } else if (file.exists("Y.csv")) {
      Y <- as.matrix(read.csv("Y.csv", row.names = 1))
    } else {
      stop("Error: Genotype matrix Y (Y.rds or Y.csv) not found in the working directory.")
    }
    
    if (file.exists("X.rds")) {
      X <- readRDS("X.rds")
    } else if (file.exists("X.csv")) {
      X <- as.matrix(read.csv("X.csv", row.names = 1))
    } else {
      stop("Error: Environmental matrix X (X.rds or X.csv) not found in the working directory.")
    }
    
    # -----------------------------------------------------------------------------
    # 2. Execution of the LFMM2 Workflow
    # -----------------------------------------------------------------------------
    # Open PDF device to save all visualization plots
    pdf("lfmm2_analysis_plots.pdf", width = 8, height = 6)
    
    # Fit LFMM2 with K = 2
    mod.lfmm2 <- lfmm2(input = Y, env = X, K = 2)
    
    # Plot the estimated latent factors to inspect population structure
    plot(mod.lfmm2@U, col = "grey", pch = 19, xlab = "Factor 1", ylab = "Factor 2")
    
    # Compute significance values using lfmm2.test (Fisher's test / full model)
    pv <- lfmm2.test(object = mod.lfmm2, input = Y, env = X, full = TRUE)
    
    # Save the full test p-values
    write.csv(data.frame(pvalue = pv\$pvalues), "pvalues_full_K2.csv", row.names = FALSE)
    
    # Visualize association significance using a Manhattan plot
    plot(-log10(pv\$pvalues), col = "grey", cex = .5, pch = 19)
    
    # Fit LFMM2 with K = 3
    mod <- lfmm2(input = Y, env = X, K = 3)
    
    # Compute significance values using lfmm2.test (linear model test)
    pv <- lfmm2.test(object = mod, input = Y, env = X, linear = TRUE)
    
    # Save the linear test p-values
    write.csv(data.frame(pvalue = pv\$pvalues), "pvalues_linear_K3.csv", row.names = FALSE)
    
    # Visualize association significance for K = 3
    plot(-log10(pv\$pvalues), col = "grey", cex = .6, pch = 19)
    
    # Handle target loci highlighting (read from file if available, otherwise fallback to top 10)
    if (file.exists("target.rds")) {
      target <- readRDS("target.rds")
    } else if (file.exists("target.csv")) {
      target <- as.vector(read.csv("target.csv")[[1]])
    } else {
      # Fallback: Highlight the top 10 most significant loci from the linear test
      target <- order(pv\$pvalues)[1:min(10, length(pv\$pvalues))]
    }
    
    # Highlight target loci on the Manhattan plot
    points(target, -log10(pv\$pvalues[target]), col = "red")
    
    # Close the PDF device
    dev.off()
    
    # -----------------------------------------------------------------------------
    # 3. Save Meaningful Results
    # -----------------------------------------------------------------------------
    saveRDS(mod.lfmm2, "mod_lfmm2_K2.rds")
    saveRDS(mod, "mod_lfmm2_K3.rds")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_LEA_GEA_LEAST_SQUARES_LFMM2":
        lea: \$(Rscript -e 'cat(as.character(packageVersion("lea")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gea_least_squares_lfmm2.csv versions.yml
    """
}

workflow BIOC_LEA_GEA_LEAST_SQUARES_LFMM2_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ Y, X ] ]

    main:
    BIOC_LEA_GEA_LEAST_SQUARES_LFMM2(ch_input)

    emit:
    tables   = BIOC_LEA_GEA_LEAST_SQUARES_LFMM2.out.tables
    plots    = BIOC_LEA_GEA_LEAST_SQUARES_LFMM2.out.plots
    objects  = BIOC_LEA_GEA_LEAST_SQUARES_LFMM2.out.objects
    versions = BIOC_LEA_GEA_LEAST_SQUARES_LFMM2.out.versions
}
