#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: difflogo — pairwise_motif_comparison
// Compare two PWMs (of the same or different lengths), optionally align them, calculate statistical significance of differences, and plot the pairwise difference 
// Input: pwm1.pwm, pwm2.pwm
// Container: quay.io/biocontainers/bioconductor-difflogo:2.34.0--r45hdfd78af_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DIFFLOGO_PAIRWISE_MOTIF_COMPARISON {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-difflogo:2.34.0--r45hdfd78af_0"

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
    .bm_deps <- c("difflogo", "motifdb", "seqlogo")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    # Load the required library
    library(DiffLogo)
    
    # 1. Load PWMs from the user-provided files in the working directory
    pwm1_file <- "pwm1.pwm"
    pwm2_file <- "pwm2.pwm"
    
    if (!file.exists(pwm1_file) || !file.exists(pwm2_file)) {
      stop("Error: Both 'pwm1.pwm' and 'pwm2.pwm' must exist in the working directory.")
    }
    
    pwm1 <- getPwmFromPwmFile(pwm1_file)
    pwm2 <- getPwmFromPwmFile(pwm2_file)
    
    # Define sample sizes (sequence counts) for p-value enrichment
    n1 <- 100
    n2 <- 100
    
    # Determine long and short PWMs for the alignment demonstration
    if (ncol(pwm1) >= ncol(pwm2)) {
      pwm_long <- pwm1
      pwm_short <- pwm2
    } else {
      pwm_long <- pwm2
      pwm_short <- pwm1
    }
    
    # 2. Generate and export the basic DiffLogo directly from PWMs
    pdf("diffLogo_from_pwm.pdf", width = 10, height = 6)
    diffLogoFromPwm(pwm1 = pwm1, pwm2 = pwm2)
    dev.off()
    
    # 3. Create a DiffLogo object and plot it
    diffLogoObj = createDiffLogoObject(pwm1 = pwm1, pwm2 = pwm2)
    
    pdf("diffLogo_from_object.pdf", width = 10, height = 6)
    diffLogo(diffLogoObj)
    dev.off()
    
    # 4. Enrich the DiffLogo object with p-values and plot
    diffLogoObj = enrichDiffLogoObjectWithPvalues(diffLogoObj, n1, n2)
    
    pdf("diffLogo_enriched.pdf", width = 10, height = 6)
    diffLogo(diffLogoObj)
    dev.off()
    
    # Save the enriched DiffLogo object as an RDS file
    saveRDS(diffLogoObj, file = "diffLogoObj.rds")
    
    # 5. Plot DiffLogo for PWMs with alignment (handles different lengths)
    pdf("diffLogo_aligned.pdf", width = 10, height = 6)
    diffLogoFromPwm(pwm1 = pwm_long, pwm2 = pwm_short, align_pwms=TRUE)
    dev.off()

    cat <<-END_VERSIONS > versions.yml
    "BIOC_DIFFLOGO_PAIRWISE_MOTIF_COMPARISON":
        difflogo: \$(Rscript -e 'cat(as.character(packageVersion("difflogo")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_pairwise_motif_comparison.csv versions.yml
    """
}

workflow BIOC_DIFFLOGO_PAIRWISE_MOTIF_COMPARISON_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ pwm1.pwm, pwm2.pwm ] ]

    main:
    BIOC_DIFFLOGO_PAIRWISE_MOTIF_COMPARISON(ch_input)

    emit:
    tables   = BIOC_DIFFLOGO_PAIRWISE_MOTIF_COMPARISON.out.tables
    plots    = BIOC_DIFFLOGO_PAIRWISE_MOTIF_COMPARISON.out.plots
    objects  = BIOC_DIFFLOGO_PAIRWISE_MOTIF_COMPARISON.out.objects
    versions = BIOC_DIFFLOGO_PAIRWISE_MOTIF_COMPARISON.out.versions
}
