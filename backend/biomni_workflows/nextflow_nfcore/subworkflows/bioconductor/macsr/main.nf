#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: macsr — narrow_and_broad_peak_calling
// Call narrow and broad peaks from ChIP-seq treatment and control alignment files.
// Input: CHIP, CTRL
// Container: quay.io/biocontainers/bioconductor-macsr:1.18.0--r45hdfd78af_0
// R packages: MACSr
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MACSR_NARROW_AND_BROAD_PEAK_CALLING {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-macsr:1.18.0--r45hdfd78af_0"

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
    .bm_deps <- c("MACSr")
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
    
    # 1. Load the MACSr package
    library(MACSr)
    
    # 2. Identify user input files from the working directory
    CHIP <- "CHIP"
    CTRL <- "CTRL"
    
    if (!file.exists(CHIP)) {
      files <- list.files(pattern = "^CHIP")
      if (length(files) > 0) {
        CHIP <- files[1]
      } else {
        stop("Error: CHIP input file not found in the working directory.")
      }
    }
    
    if (!file.exists(CTRL)) {
      files <- list.files(pattern = "^CTRL")
      if (length(files) > 0) {
        CTRL <- files[1]
      } else {
        stop("Error: CTRL input file not found in the working directory.")
      }
    }
    
    # Create output directory for results
    out_dir <- "macsr_results"
    dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
    
    # 3. Call narrow peaks using callpeak with cutoff analysis
    message("Running narrow peak calling...")
    cp1 <- callpeak(CHIP, CTRL, gsize = 5.2e7, store_bdg = TRUE,
                    name = "run_callpeak_narrow0", outdir = out_dir,
                    cutoff_analysis = TRUE)
    
    # 4. Call broad peaks using callpeak with broad=TRUE
    message("Running broad peak calling...")
    cp2 <- callpeak(CHIP, CTRL, gsize = 5.2e7, store_bdg = TRUE,
                    name = "run_callpeak_broad", outdir = out_dir,
                    broad = TRUE)
    
    # 5. Inspect the resulting macsList objects, including arguments, outputs, and logs
    message("Inspecting results...")
    print(cp1)
    print(cp2)
    
    message("Inspecting cp1 arguments:")
    print(cp1\$arguments)
    
    message("Inspecting cp1 outputs:")
    print(cp1\$outputs)
    
    message("Printing cp1 log:")
    cat(paste(cp1\$log, collapse="\n"))
    cat("\n")
    
    # Write named output files for the meaningful results
    saveRDS(cp1, file.path(out_dir, "cp1_narrow_peaks.rds"))
    saveRDS(cp2, file.path(out_dir, "cp2_broad_peaks.rds"))
    
    writeLines(cp1\$log, file.path(out_dir, "cp1_narrow_log.txt"))
    writeLines(cp2\$log, file.path(out_dir, "cp2_broad_log.txt"))
    
    message("Pipeline completed successfully. Outputs saved in: ", out_dir)

    writeLines(c(
        '"BIOC_MACSR_NARROW_AND_BROAD_PEAK_CALLING":',
        paste0('        macsr: ', as.character(packageVersion("macsr")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_narrow_and_broad_peak_calling.csv versions.yml
    """
}

workflow BIOC_MACSR_NARROW_AND_BROAD_PEAK_CALLING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ CHIP, CTRL ] ]

    main:
    BIOC_MACSR_NARROW_AND_BROAD_PEAK_CALLING(ch_input)

    emit:
    tables   = BIOC_MACSR_NARROW_AND_BROAD_PEAK_CALLING.out.tables
    plots    = BIOC_MACSR_NARROW_AND_BROAD_PEAK_CALLING.out.plots
    objects  = BIOC_MACSR_NARROW_AND_BROAD_PEAK_CALLING.out.objects
    versions = BIOC_MACSR_NARROW_AND_BROAD_PEAK_CALLING.out.versions
}
