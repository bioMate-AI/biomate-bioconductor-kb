#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: lea — gea_mcmc_lfmm
// Perform genotype-environment association (GEA) testing using the Bayesian MCMC algorithm in LFMM.
// Input: genotypes.lfmm, gradients.env
// Container: quay.io/biocontainers/bioconductor-lea:3.22.0--r45h01b2380_0
// R packages: LEA
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_LEA_GEA_MCMC_LFMM {
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
    if (!requireNamespace("LEA", quietly = TRUE)) {
      stop("Package 'LEA' is required but not installed.")
    }
    library(LEA)
    
    # Check for required user input files in the working directory
    input_geno <- "genotypes.lfmm"
    input_env <- "gradients.env"
    
    if (!file.exists(input_geno)) {
      stop(paste("Required input file missing:", input_geno))
    }
    if (!file.exists(input_env)) {
      stop(paste("Required input file missing:", input_env))
    }
    
    # 1. Fit Latent Factor Mixed Models (LFMM) using MCMC via the lfmm() function
    message("Fitting LFMM model using MCMC...")
    project = lfmm("genotypes.lfmm", "gradients.env", K = 6, repetitions = 5, project = "new")
    
    # 2. Combine z-scores from multiple runs and compute adjusted p-values using lfmm.pvalues()
    message("Combining z-scores and computing adjusted p-values...")
    p = lfmm.pvalues(project, K = 6)
    pvalues = p\$pvalues
    
    # 3. Visualize significance values using a histogram and Manhattan plot
    message("Generating diagnostic plots...")
    pdf("lfmm_diagnostic_plots.pdf", width = 8, height = 10)
    par(mfrow = c(2, 1))
    hist(pvalues, col = "lightblue")
    plot(-log10(pvalues), pch = 19, col = "blue", cex = .7)
    dev.off()
    
    # 4. Control False Discovery Rate (FDR) using the Benjamini-Hochberg procedure to identify candidate loci
    message("Identifying candidate loci using Benjamini-Hochberg procedure...")
    alpha = 0.05
    L = length(pvalues)
    w = which(sort(pvalues) < alpha * (1:L) / L)
    candidates = order(pvalues)[w]
    
    # Save meaningful results to files
    message("Saving results to output files...")
    
    # Save the project object
    saveRDS(project, "lfmm_project.rds")
    
    # Save all p-values
    pvalues_df <- data.frame(
      Locus = 1:L,
      Pvalue = pvalues
    )
    write.csv(pvalues_df, "lfmm_pvalues.csv", row.names = FALSE)
    
    # Save candidate loci
    candidates_df <- data.frame(
      Candidate_Locus = candidates,
      Pvalue = pvalues[candidates]
    )
    write.csv(candidates_df, "lfmm_candidates.csv", row.names = FALSE)
    
    message("Workflow completed successfully.")
    message("Outputs written:")
    message("- 'lfmm_diagnostic_plots.pdf' (Plots)")
    message("- 'lfmm_project.rds' (LFMM Project Object)")
    message("- 'lfmm_pvalues.csv' (Table of all P-values)")
    message("- 'lfmm_candidates.csv' (Table of candidate loci)")

    writeLines(c(
        '"BIOC_LEA_GEA_MCMC_LFMM":',
        paste0('        lea: ', as.character(packageVersion("lea")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gea_mcmc_lfmm.csv versions.yml
    """
}

workflow BIOC_LEA_GEA_MCMC_LFMM_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ genotypes.lfmm, gradients.env ] ]

    main:
    BIOC_LEA_GEA_MCMC_LFMM(ch_input)

    emit:
    tables   = BIOC_LEA_GEA_MCMC_LFMM.out.tables
    plots    = BIOC_LEA_GEA_MCMC_LFMM.out.plots
    objects  = BIOC_LEA_GEA_MCMC_LFMM.out.objects
    versions = BIOC_LEA_GEA_MCMC_LFMM.out.versions
}
