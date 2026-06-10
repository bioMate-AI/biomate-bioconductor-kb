#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: camera — multi_sample_lcms_diffreport
// Annotate isotopes and adducts across multiple samples and integrate results with an xcms differential report.
// Input: faahko
// Container: quay.io/biocontainers/bioconductor-camera:1.66.0--r45h01b2380_0
// R packages: CAMERA, xcms
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CAMERA_MULTI_SAMPLE_LCMS_DIFFREPORT {
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
    library(xcms)
    library(CAMERA)
    
    # ---------------------------------------------------------
    # Stage 0: Read User Input (faahko as RDS or raw CDF files)
    # ---------------------------------------------------------
    if (file.exists("faahko.rds")) {
      faahko <- readRDS("faahko.rds")
    } else {
      # Search for CDF files in the working directory
      cdf_files <- list.files(pattern = "\\\\.(cdf|CDF)\$", recursive = TRUE, full.names = TRUE)
      if (length(cdf_files) == 0) {
        stop("Error: No CDF files or 'faahko.rds' found in the working directory.")
      }
      # Construct the xcmsSet object from the raw CDF files
      faahko <- xcmsSet(cdf_files, method = "matchedFilter")
    }
    
    # Save the initial xcmsSet object for reproducibility
    saveRDS(faahko, file = "faahko_init.rds")
    
    # ---------------------------------------------------------
    # Stage 1: Preprocess multiple samples with xcms grouping and peak filling
    # ---------------------------------------------------------
    xsg <- group(faahko)
    xsg <- fillPeaks(xsg)
    
    # ---------------------------------------------------------
    # Stage 2: Initialize CAMERA annotation object
    # ---------------------------------------------------------
    xsa <- xsAnnotate(xsg)
    
    # ---------------------------------------------------------
    # Stage 3: Group peaks by retention time
    # ---------------------------------------------------------
    xsaF <- groupFWHM(xsa, perfwhm=0.6)
    
    # ---------------------------------------------------------
    # Stage 4: Verify grouping with peak shape correlation
    # ---------------------------------------------------------
    xsaC <- groupCorr(xsaF)
    
    # ---------------------------------------------------------
    # Stage 5: Annotate isotopes
    # ---------------------------------------------------------
    xsaFI <- findIsotopes(xsaC)
    
    # ---------------------------------------------------------
    # Stage 6: Annotate adducts
    # ---------------------------------------------------------
    xsaFA <- findAdducts(xsaFI, polarity="positive")
    write.csv(getPeaklist(xsaFA), file="result_CAMERA.csv")
    saveRDS(xsaFA, file="xsaFA.rds")
    
    # ---------------------------------------------------------
    # Stage 7: Generate and export combined differential report
    # ---------------------------------------------------------
    xsg.fill <- fillPeaks(xsg)
    diffreport <- annotateDiffreport(xsg.fill)
    write.csv(diffreport, file="diffreport.csv")
    saveRDS(diffreport, file="diffreport.rds")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_CAMERA_MULTI_SAMPLE_LCMS_DIFFREPORT":
        camera: \$(Rscript -e 'cat(as.character(packageVersion("camera")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_multi_sample_lcms_diffreport.csv versions.yml
    """
}

workflow BIOC_CAMERA_MULTI_SAMPLE_LCMS_DIFFREPORT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ faahko ] ]

    main:
    BIOC_CAMERA_MULTI_SAMPLE_LCMS_DIFFREPORT(ch_input)

    emit:
    tables   = BIOC_CAMERA_MULTI_SAMPLE_LCMS_DIFFREPORT.out.tables
    plots    = BIOC_CAMERA_MULTI_SAMPLE_LCMS_DIFFREPORT.out.plots
    objects  = BIOC_CAMERA_MULTI_SAMPLE_LCMS_DIFFREPORT.out.objects
    versions = BIOC_CAMERA_MULTI_SAMPLE_LCMS_DIFFREPORT.out.versions
}
