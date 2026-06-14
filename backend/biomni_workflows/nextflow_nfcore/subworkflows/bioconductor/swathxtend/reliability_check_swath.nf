#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: swathxtend — reliability_check_swath
// Compare SWATH results extracted using the seed library versus the extended library to check coverage and quantification consistency.
// Input: seed_library.txt, extended_library.txt, swath_result_seed.xlsx, swath_result_ext.xlsx
// Container: quay.io/biocontainers/bioconductor-swathxtend:2.32.0--r45hdfd78af_0
// R packages: SwathXtend, openxlsx
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Visualizations: plot (ggplot/base)

nextflow.enable.dsl = 2

process BIOC_SWATHXTEND_RELIABILITY_CHECK_SWATH {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-swathxtend:2.32.0--r45hdfd78af_0"

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
    .bm_deps <- c("SwathXtend", "openxlsx")
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
    library(SwathXtend)
    library(openxlsx)
    
    # Define input file paths from the working directory
    seed_lib_file <- "seed_library.txt"
    ext_lib_file <- "extended_library.txt"
    swath_seed_file <- "swath_result_seed.xlsx"
    swath_ext_file <- "swath_result_ext.xlsx"
    
    # Verify that all required input files exist
    input_files <- c(seed_lib_file, ext_lib_file, swath_seed_file, swath_ext_file)
    for (f in input_files) {
      if (!file.exists(f)) {
        stop(paste("Required input file missing:", f))
      }
    }
    
    # --- Check library coverage using reliabilityCheckLibrary ---
    message("Running reliabilityCheckLibrary...")
    res_lib <- reliabilityCheckLibrary(seed_lib_file, ext_lib_file)
    write.csv(res_lib, "reliability_check_library_results.csv", row.names = FALSE)
    
    # --- Run comprehensive SWATH results check using ---
    # This function generates plots, so we wrap it in a PDF device to capture them.
    message("Running reliabilityCheckSwath...")
    pdf("reliability_check_swath_plots.pdf", width = 8, height = 8)
    res_swath <- reliabilityCheckSwath(swath_seed_file, swath_ext_file, max.fdrpass=8, max.peptide=2)
    dev.off()
    saveRDS(res_swath, "reliability_check_swath_results.rds")
    
    # --- Read FDR worksheets using readWorkbook ---
    message("Reading FDR worksheets...")
    fdr.seed = readWorkbook(swath_seed_file, sheet='FDR')
    fdr.ext = readWorkbook(swath_ext_file, sheet='FDR')
    
    # --- Calculate FDR pass statistics using fdr.crit ---
    message("Calculating FDR pass statistics...")
    fdr.seed = fdr.crit(fdr.seed)
    fdr.ext = fdr.crit(fdr.ext)
    
    # Save intermediate FDR statistics
    write.csv(fdr.seed, "fdr_seed_statistics.csv", row.names = FALSE)
    write.csv(fdr.ext, "fdr_ext_statistics.csv", row.names = FALSE)
    
    # Print head of extended FDR statistics to console
    print("Head of extended FDR statistics:")
    print(head(fdr.ext[, c(1:2, ncol(fdr.ext))]))
    
    # --- Read Peptide worksheets using readWorkbook ---
    message("Reading Peptide worksheets...")
    swa.seed = readWorkbook(swath_seed_file, 2)
    swa.ext = readWorkbook(swath_ext_file, 2)
    
    # Filter FDR data frames to keep only those passing FDR threshold in at least one sample
    fdr.seed = fdr.seed[fdr.seed\$nfdr.pass > 0,]
    fdr.ext = fdr.ext[fdr.ext\$nfdr.pass > 0,]
    
    # --- Calculate quantification accuracy/consistency using ---
    message("Calculating quantification accuracy...")
    res_quant = quantification.accuracy(swa.seed[fdr.seed\$nfdr.pass >= 1,], 
                                        swa.ext[fdr.ext\$nfdr.pass >= 1,], 
                                        method="cv")[[1]]
    
    # Save quantification accuracy results
    write.csv(data.frame(CV = res_quant), "quantification_accuracy_cv.csv", row.names = FALSE)
    
    message("Pipeline completed successfully. Outputs written to working directory.")

    writeLines(c(
        '"BIOC_SWATHXTEND_RELIABILITY_CHECK_SWATH":',
        paste0('        swathxtend: ', as.character(packageVersion("swathxtend")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_reliability_check_swath.csv versions.yml
    """
}

workflow BIOC_SWATHXTEND_RELIABILITY_CHECK_SWATH_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ seed_library.txt, extended_library.txt, swath_result_seed.xlsx, swath_result_ext.xlsx ] ]

    main:
    BIOC_SWATHXTEND_RELIABILITY_CHECK_SWATH(ch_input)

    emit:
    tables   = BIOC_SWATHXTEND_RELIABILITY_CHECK_SWATH.out.tables
    plots    = BIOC_SWATHXTEND_RELIABILITY_CHECK_SWATH.out.plots
    objects  = BIOC_SWATHXTEND_RELIABILITY_CHECK_SWATH.out.objects
    versions = BIOC_SWATHXTEND_RELIABILITY_CHECK_SWATH.out.versions
}
