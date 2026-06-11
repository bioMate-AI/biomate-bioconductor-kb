#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: difflogo — multiple_pwm_alignment
// Align multiple PWMs of different lengths and visualize the unaligned vs. aligned sequence logos.
// Input: pwm_long.pwm, pwm_short.pwm
// Container: quay.io/biocontainers/bioconductor-difflogo:2.34.0--r45hdfd78af_0
// R packages: DiffLogo
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DIFFLOGO_MULTIPLE_PWM_ALIGNMENT {
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
    .bm_deps <- c("DiffLogo")
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
    
    # Load required libraries
    library(DiffLogo)
    
    # Verify that the required input files exist in the working directory
    if (!file.exists("pwm_long.pwm") || !file.exists("pwm_short.pwm")) {
      stop("Error: Required input files 'pwm_long.pwm' and/or 'pwm_short.pwm' are missing from the working directory.")
    }
    
    # Read the input PWM files using DiffLogo's built-in parser
    pwm_long = getPwmFromPwmFile("pwm_long.pwm")
    pwm_short = getPwmFromPwmFile("pwm_short.pwm")
    
    # 1. Perform multiple local alignment of PWMs
    # 2. Extend the PWMs based on the alignment vector
    pwms = list(pwm_long, pwm_short)
    multiple_pwms_alignment = multipleLocalPwmsAlignment(pwms)
    aligned_pwms = extendPwmsFromAlignmentVector(pwms, multiple_pwms_alignment\$alignment\$vector)
    
    # Save the alignment results and extended PWMs as RDS objects
    saveRDS(multiple_pwms_alignment, "multiple_pwms_alignment.rds")
    saveRDS(aligned_pwms, "aligned_pwms.rds")
    
    # Save the alignment shift vector as a CSV table
    alignment_df <- data.frame(
      PWM_Index = seq_along(multiple_pwms_alignment\$alignment\$vector),
      Shift = multiple_pwms_alignment\$alignment\$vector
    )
    write.csv(alignment_df, "alignment_vector.csv", row.names = FALSE)
    
    # 3. Plot the unaligned and aligned sequence logos to a PDF file
    pdf("unaligned_vs_aligned_logos.pdf", width = 10, height = 8)
    
    layout(mat = matrix(data = 1:4, nrow = 2, ncol = 2))
    DiffLogo::seqLogo(pwms[[1]], main = "Unaligned")
    DiffLogo::seqLogo(pwms[[2]])
    DiffLogo::seqLogo(aligned_pwms[[1]], main = "Aligned")
    DiffLogo::seqLogo(aligned_pwms[[2]])
    
    dev.off()
    
    cat("Workflow completed successfully. Outputs written:\n")
    cat("- multiple_pwms_alignment.rds\n")
    cat("- aligned_pwms.rds\n")
    cat("- alignment_vector.csv\n")
    cat("- unaligned_vs_aligned_logos.pdf\n")

    writeLines(c(
        '"BIOC_DIFFLOGO_MULTIPLE_PWM_ALIGNMENT":',
        paste0('        difflogo: ', as.character(packageVersion("difflogo")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_multiple_pwm_alignment.csv versions.yml
    """
}

workflow BIOC_DIFFLOGO_MULTIPLE_PWM_ALIGNMENT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ pwm_long.pwm, pwm_short.pwm ] ]

    main:
    BIOC_DIFFLOGO_MULTIPLE_PWM_ALIGNMENT(ch_input)

    emit:
    tables   = BIOC_DIFFLOGO_MULTIPLE_PWM_ALIGNMENT.out.tables
    plots    = BIOC_DIFFLOGO_MULTIPLE_PWM_ALIGNMENT.out.plots
    objects  = BIOC_DIFFLOGO_MULTIPLE_PWM_ALIGNMENT.out.objects
    versions = BIOC_DIFFLOGO_MULTIPLE_PWM_ALIGNMENT.out.versions
}
