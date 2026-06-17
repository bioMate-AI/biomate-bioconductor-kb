#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: CAMERA — isotope_validation
// Perform targeted peak picking for isotopes and validate putative isotope clusters using database statistics.
// Input: file.mzML
// Container: quay.io/biocontainers/bioconductor-camera:1.66.0--r45h01b2380_0
// R packages: CAMERA, xcms
// Bioconductor: 3.20 | R: 4.4
// Requires: CAMERA, xcms
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Peak picking using centWave with predicted isotope ROIs
//  * 2. [Core Analysis] Initialize xsAnnotate object
//  * 3. [Core Analysis] Group peaks by retention time (groupFWHM)
//  * 4. [Core Analysis] Annotate and validate isotopes using database statistics (findIsotopesWithValidation)
//  * 5. [Core Analysis] Extract the annotated peak list (getPeaklist)

nextflow.enable.dsl = 2

process BIOC_CAMERA_ISOTOPE_VALIDATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-epigenomics:3.20-slim"

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
    .bm_deps <- c("CAMERA", "xcms")
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
    
    # Load required libraries
    library(xcms)
    library(CAMERA)
    
    # Define input file from the working directory
    file <- "file.mzML"
    
    # Verify input file existence
    if (!file.exists(file)) {
      stop(paste("Required input file 'file.mzML' not found in the working directory:", getwd()))
    }
    
    # 1. Peak picking using centWave with predicted isotope ROIs
    xs <- xcmsSet(
       files=file, method="centWaveWithPredictedIsotopeROIs",
       ppm=10, peakwidth=c(5,12), snthresh=25, prefilter=c(3,200)
    )
    
    # 2. Initialize xsAnnotate object
    an <- xsAnnotate(xs, polarity="positive")
    
    # 3. Group peaks by retention time (groupFWHM)
    an <- groupFWHM(an, perfwhm = 1)
    
    # 4. Annotate and validate isotopes using database statistics (findIsotopesWithValidation)
    an <- findIsotopesWithValidation(object = an, ppm = 10,
                                       mzabs = 0.01, intval="intb",
           maxcharge = 3)
    
    # 5. Extract the annotated peak list (getPeaklist)
    peakTable <- getPeaklist(an)
    
    # Write outputs
    write.csv(peakTable, file = "annotated_peak_list.csv", row.names = FALSE)
    saveRDS(an, file = "xsAnnotate_validated.rds")
    
    # Generate diagnostic plot of the first pseudospectrum
    pdf("pseudospectrum_plot.pdf")
    tryCatch({
      plotPsSpectrum(an, pspec = 1, maxlabel = 5)
    }, error = function(e) {
      message("Could not plot pseudospectrum: ", e\$message)
    })
    dev.off()

    writeLines(c(
        '"BIOC_CAMERA_ISOTOPE_VALIDATION":',
        paste0('    CAMERA: ', as.character(packageVersion('CAMERA')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_isotope_validation.csv versions.yml
    """
}

workflow BIOC_CAMERA_ISOTOPE_VALIDATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ file.mzML ] ]

    main:
    BIOC_CAMERA_ISOTOPE_VALIDATION(ch_input)

    emit:
    tables   = BIOC_CAMERA_ISOTOPE_VALIDATION.out.tables
    plots    = BIOC_CAMERA_ISOTOPE_VALIDATION.out.plots
    objects  = BIOC_CAMERA_ISOTOPE_VALIDATION.out.objects
    versions = BIOC_CAMERA_ISOTOPE_VALIDATION.out.versions
}
