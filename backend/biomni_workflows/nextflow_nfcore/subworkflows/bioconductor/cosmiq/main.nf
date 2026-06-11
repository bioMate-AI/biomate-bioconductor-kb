#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: cosmiq — cosmiq_wrapper
// Preprocess LCMS/GCMS raw data files in a single step using the cosmiq wrapper function.
// Input: my.input.files
// Container: quay.io/biocontainers/bioconductor-cosmiq:1.44.0--r45ha27e39d_0
// R packages: cosmiq
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_COSMIQ_COSMIQ_WRAPPER {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-cosmiq:1.44.0--r45ha27e39d_0"

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
    .bm_deps <- c("cosmiq")
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
    
    # Stage 1: Identify input file paths
    # The pipeline reads raw LCMS/GCMS files (CDF, mzXML, mzML) from the working directory.
    my.input.files <- list.files(
      path = ".", 
      pattern = "\\\\.(CDF|mzXML|mzML|cdf|mzxml|mzml)\$", 
      full.names = TRUE
    )
    
    if (length(my.input.files) == 0) {
      stop("Error: No raw LCMS/GCMS files (CDF, mzXML, mzML) found in the working directory.")
    }
    
    # Load the required package
    library(cosmiq)
    
    # Stage 2: Run the cosmiq wrapper function to combine spectra, detect peaks, 
    # correct retention times, and quantify features.
    message("Running cosmiq wrapper function on ", length(my.input.files), " files...")
    x <- cosmiq(files=my.input.files, mzbin=0.25, SNR.Th=0, linear=TRUE)
    
    # Stage 3: Visualize the resulting m/z versus RT map and inspect peak data.
    # Save the visualization to a PDF file
    pdf_file <- "mz_vs_rt_map.pdf"
    pdf(pdf_file, width = 8, height = 6)
    image(t(x\$eicmatrix), main='mz versus RT map')
    invisible(dev.off())
    message("Saved visualization to ", pdf_file)
    
    # Inspect and save peak data
    peaks_df <- as.data.frame(x\$xs@peaks)
    print(head(peaks_df))
    
    csv_file <- "detected_peaks.csv"
    write.csv(peaks_df, file = csv_file, row.names = FALSE)
    message("Saved peak table to ", csv_file)
    
    # Save the complete cosmiq result object
    rds_file <- "cosmiq_result.rds"
    saveRDS(x, file = rds_file)
    message("Saved cosmiq result object to ", rds_file)

    writeLines(c(
        '"BIOC_COSMIQ_COSMIQ_WRAPPER":',
        paste0('        cosmiq: ', as.character(packageVersion("cosmiq")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cosmiq_wrapper.csv versions.yml
    """
}

workflow BIOC_COSMIQ_COSMIQ_WRAPPER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ my.input.files ] ]

    main:
    BIOC_COSMIQ_COSMIQ_WRAPPER(ch_input)

    emit:
    tables   = BIOC_COSMIQ_COSMIQ_WRAPPER.out.tables
    plots    = BIOC_COSMIQ_COSMIQ_WRAPPER.out.plots
    objects  = BIOC_COSMIQ_COSMIQ_WRAPPER.out.objects
    versions = BIOC_COSMIQ_COSMIQ_WRAPPER.out.versions
}
