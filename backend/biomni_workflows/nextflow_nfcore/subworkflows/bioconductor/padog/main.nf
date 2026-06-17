#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: PADOG — pathway_analysis_with_padog
// Run PADOG pathway analysis on a gene expression matrix with group labels.
// Input: esetm, group, annotation
// Container: quay.io/biocontainers/bioconductor-padog:1.52.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: PADOG, doParallel
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] esetm (gene expression matrix)
//  * 2. [Core Analysis] group (vector of class labels)
//  * 3. [Core Analysis] annotation (annotation package name)

nextflow.enable.dsl = 2

process BIOC_PADOG_PATHWAY_ANALYSIS_WITH_PADOG {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20-slim"

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
    .bm_deps <- c("PADOG", "doParallel")
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
    library(PADOG)
    
    # Read user inputs
    # --- esetm (gene expression matrix) ---
    if (file.exists("esetm.csv")) {
      esetm <- as.matrix(read.csv("esetm.csv", row.names = 1, check.names = FALSE))
    } else if (file.exists("esetm.tsv")) {
      esetm <- as.matrix(read.delim("esetm.tsv", row.names = 1, check.names = FALSE))
    } else if (file.exists("esetm.txt")) {
      esetm <- as.matrix(read.table("esetm.txt", header = TRUE, row.names = 1, check.names = FALSE))
    } else {
      stop("Error: esetm file not found (expected esetm.csv, esetm.tsv, or esetm.txt)")
    }
    
    # --- group (vector of class labels) ---
    if (file.exists("group.txt")) {
      group <- readLines("group.txt")
    } else if (file.exists("group.csv")) {
      group <- read.csv("group.csv", header = FALSE)[[1]]
    } else {
      stop("Error: group file not found (expected group.txt or group.csv)")
    }
    
    # --- annotation (annotation package name) ---
    if (file.exists("annotation.txt")) {
      annotation <- trimws(readLines("annotation.txt")[1])
    } else {
      stop("Error: annotation file not found (expected annotation.txt)")
    }
    
    # Optional inputs with defaults
    paired <- FALSE
    if (file.exists("paired.txt")) {
      paired <- as.logical(trimws(readLines("paired.txt")[1]))
    }
    
    block <- NULL
    if (file.exists("block.txt")) {
      block <- readLines("block.txt")
    }
    
    targetgs <- NULL
    if (file.exists("targetgs.txt")) {
      targetgs <- readLines("targetgs.txt")
    }
    
    # Construct the dlist object to match the documented code structure
    dlist <- list(
      dat.m = esetm,
      ano = list(
        Group = group,
        Block = block
      ),
      design = if (paired) "Paired" else "Unpaired",
      annotation = annotation,
      targetGeneSets = targetgs
    )
    
    # Set up parallel backend if available
    if (requireNamespace("doParallel", quietly = TRUE)) {
      library(doParallel)
      cores <- min(2, parallel::detectCores() - 1)
      if (is.na(cores) || cores < 1) cores <- 1
      registerDoParallel(cores = cores)
    }
    
    # Run PADOG
    pdf("padog_plots.pdf")
    myr = padog(
        esetm = dlist\$dat.m,
        group = dlist\$ano\$Group,
        paired = dlist\$design == "Paired",
        block = dlist\$ano\$Block,
        targetgs = dlist\$targetGeneSets,
        annotation = dlist\$annotation,
        gslist = "KEGGRESTpathway",
        organism = "hsa",
        verbose = FALSE,
        Nmin = 3,
        NI = 1000,
        plots = TRUE,
        dseed = 1,
        parallel = requireNamespace("doParallel", quietly = TRUE)
    )
    dev.off()
    
    # Save results
    write.csv(myr, "padog_results.csv", row.names = TRUE)
    saveRDS(myr, "padog_results.rds")

    writeLines(c(
        '"BIOC_PADOG_PATHWAY_ANALYSIS_WITH_PADOG":',
        paste0('    PADOG: ', as.character(packageVersion('PADOG')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_pathway_analysis_with_padog.csv versions.yml
    """
}

workflow BIOC_PADOG_PATHWAY_ANALYSIS_WITH_PADOG_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ esetm, group, annotation ] ]

    main:
    BIOC_PADOG_PATHWAY_ANALYSIS_WITH_PADOG(ch_input)

    emit:
    tables   = BIOC_PADOG_PATHWAY_ANALYSIS_WITH_PADOG.out.tables
    plots    = BIOC_PADOG_PATHWAY_ANALYSIS_WITH_PADOG.out.plots
    objects  = BIOC_PADOG_PATHWAY_ANALYSIS_WITH_PADOG.out.objects
    versions = BIOC_PADOG_PATHWAY_ANALYSIS_WITH_PADOG.out.versions
}
