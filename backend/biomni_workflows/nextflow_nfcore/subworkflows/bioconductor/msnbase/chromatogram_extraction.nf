#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: MSnbase — chromatogram_extraction
// Import chromatographic data from SRM/MRM experiments or extract chromatograms (TIC/BPC) from raw MS experiments.
// Input: srm_data.mzML
// Container: quay.io/biocontainers/bioconductor-msnbase:2.36.0--r45ha27e39d_0
// R packages: MSnbase
// Bioconductor: 3.20 | R: 4.4
// Requires: MSnbase
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Import SRM/MRM chromatographic data using readSRMData
//  * 2. [Input & Preparation] Extract precursor and product m/z values using
//  * 3. [Input & Preparation] Extract total ion chromatograms (TIC) or base peak

nextflow.enable.dsl = 2

process BIOC_MSNBASE_CHROMATOGRAM_EXTRACTION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-proteomics:3.20"

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
    .bm_deps <- c("MSnbase")
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
    library(MSnbase)
    
    # Define input files from the working directory
    fl <- "srm_data.mzML"
    f <- "srm_data.mzML"
    
    # --- Import SRM/MRM chromatographic data using readSRMData ---
    message("Reading SRM data...")
    srm <- readSRMData(fl)
    
    # --- Extract precursor and product m/z values using ---
    message("Extracting precursor and product m/z values...")
    prec_mz <- precursorMz(srm)
    prod_mz <- productMz(srm)
    
    # Save SRM m/z metadata to a CSV file
    srm_mz_df <- data.frame(
      Precursor_mz = prec_mz,
      Product_mz = prod_mz
    )
    write.csv(srm_mz_df, "srm_mz_metadata.csv", row.names = FALSE)
    message("Saved SRM m/z metadata to 'srm_mz_metadata.csv'")
    
    # --- Extract total ion chromatograms (TIC) or base peak ---
    message("Reading MS data on-disk...")
    mtof <- readMSData(f, mode = "onDisk")
    
    message("Extracting Total Ion Chromatogram (TIC)...")
    mtof_tic <- chromatogram(mtof)
    
    message("Extracting Base Peak Chromatogram (BPC)...")
    mtof_bpc <- chromatogram(mtof, aggregationFun = "max")
    
    # Save chromatogram objects as RDS for downstream analysis
    saveRDS(mtof_tic, "mtof_tic.rds")
    saveRDS(mtof_bpc, "mtof_bpc.rds")
    message("Saved chromatogram RDS objects.")
    
    # Generate and save plots of the extracted chromatograms
    pdf("chromatograms_plot.pdf", width = 10, height = 8)
    par(mfrow = c(2, 1))
    plot(mtof_tic, main = "Total Ion Chromatogram (TIC)")
    plot(mtof_bpc, main = "Base Peak Chromatogram (BPC)")
    dev.off()
    message("Saved chromatogram plots to 'chromatograms_plot.pdf'")
    
    message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_MSNBASE_CHROMATOGRAM_EXTRACTION":',
        paste0('    MSnbase: ', as.character(packageVersion('MSnbase')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_chromatogram_extraction.csv versions.yml
    """
}

workflow BIOC_MSNBASE_CHROMATOGRAM_EXTRACTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ srm_data.mzML ] ]

    main:
    BIOC_MSNBASE_CHROMATOGRAM_EXTRACTION(ch_input)

    emit:
    tables   = BIOC_MSNBASE_CHROMATOGRAM_EXTRACTION.out.tables
    plots    = BIOC_MSNBASE_CHROMATOGRAM_EXTRACTION.out.plots
    objects  = BIOC_MSNBASE_CHROMATOGRAM_EXTRACTION.out.objects
    versions = BIOC_MSNBASE_CHROMATOGRAM_EXTRACTION.out.versions
}
