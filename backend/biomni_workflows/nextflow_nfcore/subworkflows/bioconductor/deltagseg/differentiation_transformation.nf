#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: deltagseg — differentiation_transformation
// Transform trend-like non-stationary time series using differentiation before segmentation and clustering.
// Input: simtraj.tr
// Container: quay.io/biocontainers/bioconductor-deltagseg:1.50.0--r45hdfd78af_0
// R packages: deltaGseg
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DELTAGSEG_DIFFERENTIATION_TRANSFORMATION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-deltagseg:1.50.0--r45hdfd78af_0"

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
    
    # Load the required Bioconductor package
    library(deltaGseg)
    
    # Read the input TransTrajectories object from the working directory
    if (!file.exists("simtraj.tr")) {
      stop("Required input file 'simtraj.tr' not found in the working directory.")
    }
    simtraj.tr <- readRDS("simtraj.tr")
    
    # 1. Apply differentiation transformation using transformSeries with method='differentiation'
    simtraj.tr2 <- transformSeries(object = simtraj.tr, method = 'differentiation')
    
    # Save the transformed TransTrajectories object
    saveRDS(simtraj.tr2, file = "simtraj.tr2.rds")
    
    # 2. Visualize the differentiated series and identified segments using plotDiff
    # We redirect the plot to a PDF file for pipeline output
    pdf("plotDiff_1_2.pdf", width = 8, height = 6)
    plotDiff(simtraj.tr2, name = "1_2")
    dev.off()
    
    # Print completion message
    cat("Pipeline completed successfully. Outputs saved: 'simtraj.tr2.rds' and 'plotDiff_1_2.pdf'\n")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_DELTAGSEG_DIFFERENTIATION_TRANSFORMATION":
        deltagseg: \$(Rscript -e 'cat(as.character(packageVersion("deltagseg")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_differentiation_transformation.csv versions.yml
    """
}

workflow BIOC_DELTAGSEG_DIFFERENTIATION_TRANSFORMATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ simtraj.tr ] ]

    main:
    BIOC_DELTAGSEG_DIFFERENTIATION_TRANSFORMATION(ch_input)

    emit:
    tables   = BIOC_DELTAGSEG_DIFFERENTIATION_TRANSFORMATION.out.tables
    plots    = BIOC_DELTAGSEG_DIFFERENTIATION_TRANSFORMATION.out.plots
    objects  = BIOC_DELTAGSEG_DIFFERENTIATION_TRANSFORMATION.out.objects
    versions = BIOC_DELTAGSEG_DIFFERENTIATION_TRANSFORMATION.out.versions
}
