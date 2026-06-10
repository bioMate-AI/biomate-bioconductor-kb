#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: CAMERA — multiple_sample_diffreport
// Annotate a multi-sample LC-MS dataset and combine the results with an xcms differential report.
// Input: cdf/
// Container: quay.io/biocontainers/bioconductor-camera:1.66.0--r45h01b2380_0
// Requires: CAMERA, xcms
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Group and fill peaks using xcms
//  * 2. [Core Analysis] Run annotateDiffreport to perform CAMERA annotation and combine with xcms diffreport
//  * 3. [Visualization & Output] Save the combined differential report

nextflow.enable.dsl = 2

process BIOC_CAMERA_MULTIPLE_SAMPLE_DIFFREPORT {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-epigenomics:3.20"

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
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_f in list.files(".", recursive = TRUE, full.names = TRUE)) {
          .bm_bn <- basename(.bm_f)
          if (!file.exists(.bm_bn)) try(file.copy(.bm_f, .bm_bn), silent = TRUE)
        }
        
    # Load required libraries
    library(xcms)
    library(CAMERA)
    
    # Define input directory
    input_dir <- "cdf"
    
    # List raw LC-MS data files (CDF, mzXML, mzML, etc.)
    cdf_files <- list.files(input_dir, pattern = "\\\\.(cdf|mzXML|mzML|nc)\$", full.names = TRUE, ignore.case = TRUE, recursive = TRUE)
    if (length(cdf_files) == 0) {
      cdf_files <- list.files(input_dir, full.names = TRUE, recursive = TRUE)
    }
    
    if (length(cdf_files) == 0) {
      stop("No raw LC-MS data files found in 'cdf/' directory.")
    }
    
    # Step 1: Peak picking to construct the initial xcmsSet object
    # (Replacing the pre-packaged 'faahko' object)
    xs <- xcmsSet(cdf_files)
    
    # Step 2: Group and fill peaks using xcms
    xsg <- group(xs)
    xsg.fill <- fillPeaks(xsg)
    
    # Step 3: Run annotateDiffreport to perform CAMERA annotation and combine with xcms diffreport
    diffreport <- annotateDiffreport(xsg.fill)
    
    # Step 4: Save the combined differential report
    write.csv(diffreport, file="diffreport.csv")

    writeLines(c(
        '"BIOC_CAMERA_MULTIPLE_SAMPLE_DIFFREPORT":',
        paste0('    CAMERA: ', as.character(packageVersion('CAMERA')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_multiple_sample_diffreport.csv versions.yml
    """
}

workflow BIOC_CAMERA_MULTIPLE_SAMPLE_DIFFREPORT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ cdf/ ] ]

    main:
    BIOC_CAMERA_MULTIPLE_SAMPLE_DIFFREPORT(ch_input)

    emit:
    tables   = BIOC_CAMERA_MULTIPLE_SAMPLE_DIFFREPORT.out.tables
    plots    = BIOC_CAMERA_MULTIPLE_SAMPLE_DIFFREPORT.out.plots
    objects  = BIOC_CAMERA_MULTIPLE_SAMPLE_DIFFREPORT.out.objects
    versions = BIOC_CAMERA_MULTIPLE_SAMPLE_DIFFREPORT.out.versions
}
