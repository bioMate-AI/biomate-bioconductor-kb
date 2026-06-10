#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: seqgsea — one_step_seqgsea
// Run the entire SeqGSEA pipeline (including DE, DS, score integration, and GSEA) in a single step using the all-in-one wrapper function.
// Input: data.dir, geneset.file
// Container: quay.io/biocontainers/bioconductor-seqgsea:1.50.0--r45hdfd78af_0
// R packages: SeqGSEA, doParallel
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SEQGSEA_ONE_STEP_SEQGSEA {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-seqgsea:1.50.0--r45hdfd78af_0"

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
    .bm_deps <- c("SeqGSEA", "doParallel")
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
    library(SeqGSEA)
    library(doParallel)
    
    # 1. Define input file patterns, gene set file, and analysis parameters
    data.dir <- "data.dir"
    geneset.file <- "geneset.file"
    
    # Validate that the required user inputs exist in the working directory
    if (!dir.exists(data.dir)) {
      stop("Error: 'data.dir' directory not found in the working directory.")
    }
    if (!file.exists(geneset.file)) {
      stop("Error: 'geneset.file' not found in the working directory.")
    }
    
    # Define file patterns for case and control samples
    # Defaulting to "^SC" and "^SN" as per vignette, with fallback auto-detection
    case.pattern <- "^SC"
    ctrl.pattern <- "^SN"
    
    case.files <- list.files(data.dir, pattern=case.pattern)
    ctrl.files <- list.files(data.dir, pattern=ctrl.pattern)
    
    if (length(case.files) == 0 || length(ctrl.files) == 0) {
      # Fallback to alternative common patterns if default ones are not found
      case.pattern <- "^case"
      ctrl.pattern <- "^ctrl"
      case.files <- list.files(data.dir, pattern=case.pattern, ignore.case=TRUE)
      ctrl.files <- list.files(data.dir, pattern=ctrl.pattern, ignore.case=TRUE)
      
      if (length(case.files) == 0 || length(ctrl.files) == 0) {
        warning("Could not find files matching default patterns. Reverting to '^SC' and '^SN'.")
        case.pattern <- "^SC"
        ctrl.pattern <- "^SN"
      }
    }
    
    # Analysis parameters
    geneID.type <- "ensembl"
    output.prefix <- "SeqGSEA.output"
    perm.times <- 1000  # Recommended >= 1000 for real analyses
    DEonly <- FALSE
    DEweight <- c(0.2, 0.5, 0.8)  # Vector of weights for integrating DE and DS scores
    integrationMethod <- "linear"
    
    # Setup parallel backend
    nCores <- min(8, parallel::detectCores() - 1)
    if (is.na(nCores) || nCores < 1) {
      nCores <- 1
    }
    cl <- makeCluster(nCores)
    registerDoParallel(cl)
    
    # 2. Run the complete analysis using runSeqGSEA
    message("Running SeqGSEA pipeline...")
    tryCatch({
      runSeqGSEA(
        data.dir=data.dir, 
        case.pattern=case.pattern, 
        ctrl.pattern=ctrl.pattern, 
        geneset.file=geneset.file, 
        geneID.type=geneID.type, 
        output.prefix=output.prefix, 
        nCores=nCores, 
        perm.times=perm.times, 
        integrationMethod=integrationMethod, 
        DEonly=DEonly, 
        DEweight=DEweight
      )
      message("SeqGSEA pipeline completed successfully. Results written with prefix: ", output.prefix)
    }, error = function(e) {
      stop("Error during SeqGSEA execution: ", e\$message)
    }, finally = {
      # Clean up parallel backend and connections
      stopCluster(cl)
      allCon <- showConnections()
      socketCon <- as.integer(rownames(allCon)[allCon[, "class"] == "sockconn"])
      if (length(socketCon) > 0) {
        sapply(socketCon, function(ii) close.connection(getConnection(ii)))
      }
    })

    cat <<-END_VERSIONS > versions.yml
    "BIOC_SEQGSEA_ONE_STEP_SEQGSEA":
        seqgsea: \$(Rscript -e 'cat(as.character(packageVersion("seqgsea")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_one_step_seqgsea.csv versions.yml
    """
}

workflow BIOC_SEQGSEA_ONE_STEP_SEQGSEA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ data.dir, geneset.file ] ]

    main:
    BIOC_SEQGSEA_ONE_STEP_SEQGSEA(ch_input)

    emit:
    tables   = BIOC_SEQGSEA_ONE_STEP_SEQGSEA.out.tables
    plots    = BIOC_SEQGSEA_ONE_STEP_SEQGSEA.out.plots
    objects  = BIOC_SEQGSEA_ONE_STEP_SEQGSEA.out.objects
    versions = BIOC_SEQGSEA_ONE_STEP_SEQGSEA.out.versions
}
