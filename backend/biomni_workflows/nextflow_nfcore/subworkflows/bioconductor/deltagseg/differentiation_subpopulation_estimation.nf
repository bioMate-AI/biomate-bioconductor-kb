#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: deltaGseg — differentiation_subpopulation_estimation
// Analyze trend-like non-stationary time series by applying differentiation to achieve stationarity before segmentation and clustering.
// Input: y
// Container: quay.io/biocontainers/bioconductor-deltagseg:1.50.0--r45hdfd78af_0
// Requires: deltaGseg
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the trend-like series using parseTraj
//  * 2. [Core Analysis] Perform initial splitting using transformSeries with 'splitting'
//  * 3. [Core Analysis] Apply differentiation to non-stationary subseries using transformSeries with 'differentiation'
//  * 4. [Visualization & Output] Plot differentiated series using plotDiff

nextflow.enable.dsl = 2

process BIOC_DELTAGSEG_DIFFERENTIATION_SUBPOPULATION_ESTIMATION {
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
    .bm_deps <- c("deltaGseg")
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
    
    # Load required library
    library(deltaGseg)
    
    # 1. Load the trend-like series from the user-provided file 'y'
    if (file.exists("y")) {
      y <- tryCatch({
        readRDS("y")
      }, error = function(e) {
        # Fallback to reading as a table/matrix if not an RDS file
        as.matrix(read.table("y", header = FALSE))
      })
    } else {
      stop("Required input file 'y' not found in the working directory.")
    }
    
    # Parse the trajectory
    simtraj<-parseTraj(files=list(y),fromfile=FALSE)
    
    # 2. Perform initial splitting using transformSeries with 'splitting'
    simtraj.tr<-transformSeries(object=simtraj,method='splitting',breakpoints=1)
    
    # 3. Apply differentiation to non-stationary subseries using transformSeries with 'differentiation'
    simtraj.tr2<-transformSeries(object=simtraj.tr,method='differentiation')
    
    # Save the transformed trajectory objects to RDS files
    saveRDS(simtraj.tr, "simtraj_tr.rds")
    saveRDS(simtraj.tr2, "simtraj_tr2.rds")
    
    # 4. Plot differentiated series using plotDiff and save to PDF
    pdf("differentiation_plot.pdf")
    plotDiff(simtraj.tr2,name="1_2")
    dev.off()

    writeLines(c(
        '"BIOC_DELTAGSEG_DIFFERENTIATION_SUBPOPULATION_ESTIMATION":',
        paste0('    deltaGseg: ', as.character(packageVersion('deltaGseg')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_differentiation_subpopulation_estimation.csv versions.yml
    """
}

workflow BIOC_DELTAGSEG_DIFFERENTIATION_SUBPOPULATION_ESTIMATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ y ] ]

    main:
    BIOC_DELTAGSEG_DIFFERENTIATION_SUBPOPULATION_ESTIMATION(ch_input)

    emit:
    tables   = BIOC_DELTAGSEG_DIFFERENTIATION_SUBPOPULATION_ESTIMATION.out.tables
    plots    = BIOC_DELTAGSEG_DIFFERENTIATION_SUBPOPULATION_ESTIMATION.out.plots
    objects  = BIOC_DELTAGSEG_DIFFERENTIATION_SUBPOPULATION_ESTIMATION.out.objects
    versions = BIOC_DELTAGSEG_DIFFERENTIATION_SUBPOPULATION_ESTIMATION.out.versions
}
