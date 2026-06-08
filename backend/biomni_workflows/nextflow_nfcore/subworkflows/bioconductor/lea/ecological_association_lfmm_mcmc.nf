#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: LEA — ecological_association_lfmm_mcmc
// Perform genotype-environment association (GEA) tests using the Bayesian MCMC LFMM algorithm to identify candidate loci under selection.
// Input: genotypes.lfmm, gradients.env
// Container: quay.io/biocontainers/bioconductor-lea:3.22.0--r45h01b2380_0
// Requires: LEA
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run latent factor mixed models (lfmm) with specified latent factors (K) and repetitions
//  * 2. [Core Analysis] Combine z-scores from multiple runs and compute adjusted p-values (lfmm.pvalues)
//  * 3. [Visualization & Output] Visualize p-values and identify candidate loci using the Benjamini-Hochberg FDR control procedure

nextflow.enable.dsl = 2

process BIOC_LEA_ECOLOGICAL_ASSOCIATION_LFMM_MCMC {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20"

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
    
    # Load required library
    library(LEA)
    
    # Define input file paths
    geno_file <- "genotypes.lfmm"
    env_file <- "gradients.env"
    
    # Verify input files exist in the working directory
    if (!file.exists(geno_file)) {
      stop(paste("Error: Input genotype file missing:", geno_file))
    }
    if (!file.exists(env_file)) {
      stop(paste("Error: Input environmental file missing:", env_file))
    }
    
    # 1. Run latent factor mixed models (lfmm) with specified latent factors (K) and repetitions
    project = lfmm("genotypes.lfmm", 
                   "gradients.env", 
                    K = 6, 
                    repetitions = 5, 
                    project = "new")
    
    # 2. Combine z-scores from multiple runs and compute adjusted p-values (lfmm.pvalues)
    p = lfmm.pvalues(project, K = 6)
    pvalues = p\$pvalues
    
    # 3. Visualize p-values and identify candidate loci using the Benjamini-Hochberg FDR control procedure
    # Save diagnostic plots to a PDF file
    pdf("lfmm_diagnostic_plots.pdf", width = 8, height = 8)
    par(mfrow = c(2, 1))
    hist(pvalues, col = "lightblue")
    plot(-log10(pvalues), pch = 19, col = "blue", cex = .7)
    dev.off()
    
    # Set FDR threshold (alpha) and total number of loci (L)
    alpha = 0.05
    L = length(pvalues)
    
    # Identify candidate loci using the Benjamini-Hochberg algorithm
    w = which(sort(pvalues) < alpha * (1:L) / L)
    candidates = order(pvalues)[w]
    
    # Write outputs to files
    write.csv(data.frame(Locus = 1:L, Pvalue = pvalues), "lfmm_pvalues.csv", row.names = FALSE)
    write.csv(data.frame(Candidate_Locus_Index = candidates), "lfmm_candidates.csv", row.names = FALSE)
    saveRDS(p, "lfmm_pvalues_object.rds")

    writeLines(c(
        '"BIOC_LEA_ECOLOGICAL_ASSOCIATION_LFMM_MCMC":',
        paste0('    LEA: ', as.character(packageVersion('LEA')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ecological_association_lfmm_mcmc.csv versions.yml
    """
}

workflow BIOC_LEA_ECOLOGICAL_ASSOCIATION_LFMM_MCMC_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ genotypes.lfmm, gradients.env ] ]

    main:
    BIOC_LEA_ECOLOGICAL_ASSOCIATION_LFMM_MCMC(ch_input)

    emit:
    tables   = BIOC_LEA_ECOLOGICAL_ASSOCIATION_LFMM_MCMC.out.tables
    plots    = BIOC_LEA_ECOLOGICAL_ASSOCIATION_LFMM_MCMC.out.plots
    objects  = BIOC_LEA_ECOLOGICAL_ASSOCIATION_LFMM_MCMC.out.objects
    versions = BIOC_LEA_ECOLOGICAL_ASSOCIATION_LFMM_MCMC.out.versions
}
