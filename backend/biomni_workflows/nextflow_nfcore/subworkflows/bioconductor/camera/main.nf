#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: camera — single_sample_lcms_annotation
// Group peaks and annotate isotopes and adducts for a single LC-MS sample.
// Input: MM14.mzML
// Container: quay.io/biocontainers/bioconductor-camera:1.66.0--r45h01b2380_0
// R packages: CAMERA, xcms
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Visualizations: plot (ggplot/base)

nextflow.enable.dsl = 2

process BIOC_CAMERA_SINGLE_SAMPLE_LCMS_ANNOTATION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-camera:1.66.0--r45h01b2380_0"

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
    file <- "MM14.mzML"
    
    # Verify input file existence
    if (!file.exists(file)) {
      stop(paste("Required input file missing:", file))
    }
    
    # --- Preprocess raw data with xcms peak picking ---
    xs <- xcmsSet(file, method="centWave", ppm=30, peakwidth=c(5,10))
    
    # --- Initialize CAMERA annotation object ---
    an <- xsAnnotate(xs)
    
    # --- Group peaks by retention time ---
    anF <- groupFWHM(an, perfwhm = 0.6)
    
    # --- Annotate isotopes ---
    anI <- findIsotopes(anF, mzabs = 0.01)
    
    # --- Verify grouping with peak shape correlation ---
    anIC <- groupCorr(anI, cor_eic_th = 0.75)
    
    # --- Annotate adducts ---
    anFA <- findAdducts(anIC, polarity="positive")
    
    # --- Export annotated peak list ---
    peaklist <- getPeaklist(anFA)
    write.csv(peaklist, file='xsannotated.csv', row.names=FALSE)
    
    # Save the final CAMERA object as an RDS file
    saveRDS(anFA, file='xsannotated.rds')
    
    # Generate diagnostic plots for the annotated pseudospectra
    pdf("camera_plots.pdf", width=8, height=6)
    tryCatch({
      # Plot EICs and Spectrum for pseudospectrum 2 if available
      plotEICs(anFA, pspec=2, maxlabel=5)
      plotPsSpectrum(anFA, pspec=2, maxlabel=5)
    }, error = function(e) {
      message("Could not generate plots for pseudospectrum 2: ", e\$message)
    })
    dev.off()

    writeLines(c(
        '"BIOC_CAMERA_SINGLE_SAMPLE_LCMS_ANNOTATION":',
        paste0('        camera: ', as.character(packageVersion("camera")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_single_sample_lcms_annotation.csv versions.yml
    """
}

workflow BIOC_CAMERA_SINGLE_SAMPLE_LCMS_ANNOTATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ MM14.mzML ] ]

    main:
    BIOC_CAMERA_SINGLE_SAMPLE_LCMS_ANNOTATION(ch_input)

    emit:
    tables   = BIOC_CAMERA_SINGLE_SAMPLE_LCMS_ANNOTATION.out.tables
    plots    = BIOC_CAMERA_SINGLE_SAMPLE_LCMS_ANNOTATION.out.plots
    objects  = BIOC_CAMERA_SINGLE_SAMPLE_LCMS_ANNOTATION.out.objects
    versions = BIOC_CAMERA_SINGLE_SAMPLE_LCMS_ANNOTATION.out.versions
}
