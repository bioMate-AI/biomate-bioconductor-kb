#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: eiR — similarity_search_and_indexing
// Initialize a chemical compound database, embed it into a lower-dimensional space, perform fast similarity queries, add new compounds, and evaluate search perfor
// Input: sdfsample
// Container: quay.io/biocontainers/bioconductor-eir:1.50.0--r45ha27e39d_0
// R packages: ChemmineR, eiR
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_EIR_SIMILARITY_SEARCH_AND_INDEXING {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-eir:1.50.0--r45ha27e39d_0"

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
    .bm_deps <- c("ChemmineR", "eiR")
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
    library(eiR)
    library(ChemmineR)
    
    # ----------------------------------------------------------------------
    # Stage 0: Read User Input
    # ----------------------------------------------------------------------
    # Read the user-provided 'sdfsample' file from the working directory.
    # We support both raw SDF format and RDS-serialized SDFset objects.
    if (!file.exists("sdfsample")) {
      stop("Required input file 'sdfsample' not found in the working directory.")
    }
    
    sdfsample <- tryCatch({
      # Try reading as a standard SDF file first
      ChemmineR::read.SDFset("sdfsample")
    }, error = function(e) {
      # Fallback to reading as an RDS object
      readRDS("sdfsample")
    })
    
    # ----------------------------------------------------------------------
    # Stage 1: Initialize the database and compute descriptors
    # ----------------------------------------------------------------------
    eiInit(sdfsample[1:99], priorityFn=randomPriorities)
    
    # ----------------------------------------------------------------------
    # Stage 2: Create the searchable embedded database
    # ----------------------------------------------------------------------
    r <- 60 
    d <- 40 
    runId <- eiMakeDb(r, d)
    
    # ----------------------------------------------------------------------
    # Stage 3: Query the database for similar compounds
    # ----------------------------------------------------------------------
    result = eiQuery(runId, sdfsample[45], K=10, asSimilarity=TRUE)
    print(result)
    
    # Save query results to a CSV file
    write.csv(result, "query_results.csv", row.names = FALSE)
    
    # Generate and save a plot of the top query results
    pdf("query_compounds_plot.pdf")
    cid(sdfsample) <- sdfid(sdfsample)
    num_targets <- min(4, length(result\$target))
    if (num_targets > 0) {
      plot(sdfsample[result\$target[1:num_targets]], regenCoords = TRUE, print = FALSE)
    }
    dev.off()
    
    # ----------------------------------------------------------------------
    # Stage 4: Add new compounds to the database
    # ----------------------------------------------------------------------
    eiAdd(runId, sdfsample[100])
    
    # Short delay to ensure file handles are released (especially on Windows)
    Sys.sleep(1)
    
    # ----------------------------------------------------------------------
    # Stage 5: Evaluate embedding and LSH performance
    # ----------------------------------------------------------------------
    perf_test <- eiPerformanceTest(runId, K=22)
    
    # Save performance test results
    saveRDS(perf_test, "performance_results.rds")

    writeLines(c(
        '"BIOC_EIR_SIMILARITY_SEARCH_AND_INDEXING":',
        paste0('        eiR: ', as.character(packageVersion("eiR")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_similarity_search_and_indexing.csv versions.yml
    """
}

workflow BIOC_EIR_SIMILARITY_SEARCH_AND_INDEXING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sdfsample ] ]

    main:
    BIOC_EIR_SIMILARITY_SEARCH_AND_INDEXING(ch_input)

    emit:
    tables   = BIOC_EIR_SIMILARITY_SEARCH_AND_INDEXING.out.tables
    plots    = BIOC_EIR_SIMILARITY_SEARCH_AND_INDEXING.out.plots
    objects  = BIOC_EIR_SIMILARITY_SEARCH_AND_INDEXING.out.objects
    versions = BIOC_EIR_SIMILARITY_SEARCH_AND_INDEXING.out.versions
}
