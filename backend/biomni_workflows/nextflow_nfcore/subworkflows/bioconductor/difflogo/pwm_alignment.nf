#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: DiffLogo — pwm_alignment
// Align multiple PWMs of different lengths and visualize the aligned sequence logos.
// Input: pwm_long.pwm, pwm_short.pwm
// Container: quay.io/biocontainers/bioconductor-difflogo:2.34.0--r45hdfd78af_0
// R packages: DiffLogo
// Bioconductor: 3.20 | R: 4.4
// Requires: DiffLogo
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Group PWMs into a list
//  * 2. [Core Analysis] Perform multiple local PWM alignment
//  * 3. [Core Analysis] Extend the PWMs based on the alignment vector
//  * 4. [Visualization & Output] Plot the unaligned and aligned sequence logos side-by-side

nextflow.enable.dsl = 2

process BIOC_DIFFLOGO_PWM_ALIGNMENT {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20-slim"

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
    
    # Load required library
    library(DiffLogo)
    
    # 1. Read the declared user input files from the working directory
    # The vignette uses getPwmFromPwmFile to read .pwm files.
    pwm_long = getPwmFromPwmFile("pwm_long.pwm")
    pwm_short = getPwmFromPwmFile("pwm_short.pwm")
    
    # 2. Group PWMs into a list
    pwms = list(pwm_long, pwm_short)
    
    # 3. Perform multiple local PWM alignment
    multiple_pwms_alignment = multipleLocalPwmsAlignment(pwms)
    
    # 4. Extend the PWMs based on the alignment vector
    aligned_pwms = extendPwmsFromAlignmentVector(pwms, multiple_pwms_alignment\$alignment\$vector)
    
    # 5. Plot the unaligned and aligned sequence logos side-by-side and save to PDF
    pdf("pwm_alignment_plot.pdf", width = 10, height = 8)
    layout(mat = matrix(data = 1:4, nrow = 2, ncol = 2))
    DiffLogo::seqLogo(pwms[[1]], main = "Unaligned")
    DiffLogo::seqLogo(pwms[[2]])
    DiffLogo::seqLogo(aligned_pwms[[1]], main = "Aligned")
    DiffLogo::seqLogo(aligned_pwms[[2]])
    dev.off()
    
    # 6. Save meaningful results to RDS files
    saveRDS(aligned_pwms, "aligned_pwms.rds")
    saveRDS(multiple_pwms_alignment, "multiple_pwms_alignment.rds")

    writeLines(c(
        '"BIOC_DIFFLOGO_PWM_ALIGNMENT":',
        paste0('    DiffLogo: ', as.character(packageVersion('DiffLogo')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_pwm_alignment.csv versions.yml
    """
}

workflow BIOC_DIFFLOGO_PWM_ALIGNMENT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ pwm_long.pwm, pwm_short.pwm ] ]

    main:
    BIOC_DIFFLOGO_PWM_ALIGNMENT(ch_input)

    emit:
    tables   = BIOC_DIFFLOGO_PWM_ALIGNMENT.out.tables
    plots    = BIOC_DIFFLOGO_PWM_ALIGNMENT.out.plots
    objects  = BIOC_DIFFLOGO_PWM_ALIGNMENT.out.objects
    versions = BIOC_DIFFLOGO_PWM_ALIGNMENT.out.versions
}
