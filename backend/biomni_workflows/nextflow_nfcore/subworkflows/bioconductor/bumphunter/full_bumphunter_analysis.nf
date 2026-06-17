#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: bumphunter — full_bumphunter_analysis
// Perform a complete bump hunting analysis on a matrix of genomic measurements using a design matrix and permutation testing.
// Input: y, X, chr, pos, cl
// Container: quay.io/biocontainers/bioconductor-bumphunter:1.52.0--r45hdfd78af_0
// R packages: bumphunter, doParallel
// Bioconductor: 3.20 | R: 4.4
// Requires: bumphunter, doParallel
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Group genomic locations into clusters using clusterMaker
//  * 2. [Core Analysis] Register parallel backend using doParallel for faster computation
//  * 3. [Core Analysis] Run bumphunter to fit linear models, smooth coefficients, and perform permutation testing
//  * 4. [Core Analysis] Clean up parallel connections using foreachCleanup

nextflow.enable.dsl = 2

process BIOC_BUMPHUNTER_FULL_BUMPHUNTER_ANALYSIS {
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
    .bm_deps <- c("bumphunter", "doParallel")
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
    library(bumphunter)
    library(doParallel)
    
    # Helper function to read user inputs from the working directory
    read_input <- function(name, type = "vector") {
      rds_path <- paste0(name, ".rds")
      csv_path <- paste0(name, ".csv")
      txt_path <- paste0(name, ".txt")
      
      if (file.exists(rds_path)) {
        return(readRDS(rds_path))
      } else if (file.exists(csv_path)) {
        if (type == "matrix") {
          df <- read.csv(csv_path, header = TRUE, row.names = 1)
          return(as.matrix(df))
        } else {
          df <- read.csv(csv_path, header = TRUE)
          return(df[[1]])
        }
      } else if (file.exists(txt_path)) {
        if (type == "matrix") {
          return(as.matrix(read.table(txt_path, header = TRUE, row.names = 1)))
        } else {
          return(scan(txt_path, what = if (name == "chr") character() else numeric(), quiet = TRUE))
        }
      } else {
        stop(paste("Required input file for", name, "not found (.rds, .csv, or .txt)"))
      }
    }
    
    # Read user inputs
    y <- read_input("y", "matrix")
    X <- read_input("X", "matrix")
    chr <- read_input("chr", "vector")
    pos <- read_input("pos", "vector")
    
    # 1. Group genomic locations into clusters using clusterMaker
    cl <- clusterMaker(chr, pos, maxGap = 300)
    
    # 2. Register parallel backend using doParallel for faster computation
    registerDoParallel(cores = 2)
    
    # 3. Run bumphunter to fit linear models, smooth coefficients, and perform permutation testing
    tab <- bumphunter(y, X, chr, pos, cl, cutoff=.5, B=250, verbose = TRUE)
    
    # 4. Clean up parallel connections using foreachCleanup
    bumphunter:::foreachCleanup()
    
    # Write outputs
    saveRDS(tab, "bumphunter_results.rds")
    if (!is.null(tab\$table)) {
      write.csv(tab\$table, "bumphunter_table.csv", row.names = FALSE)
    }

    writeLines(c(
        '"BIOC_BUMPHUNTER_FULL_BUMPHUNTER_ANALYSIS":',
        paste0('    bumphunter: ', as.character(packageVersion('bumphunter')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_full_bumphunter_analysis.csv versions.yml
    """
}

workflow BIOC_BUMPHUNTER_FULL_BUMPHUNTER_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ y, X, chr, pos, cl ] ]

    main:
    BIOC_BUMPHUNTER_FULL_BUMPHUNTER_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_BUMPHUNTER_FULL_BUMPHUNTER_ANALYSIS.out.tables
    plots    = BIOC_BUMPHUNTER_FULL_BUMPHUNTER_ANALYSIS.out.plots
    objects  = BIOC_BUMPHUNTER_FULL_BUMPHUNTER_ANALYSIS.out.objects
    versions = BIOC_BUMPHUNTER_FULL_BUMPHUNTER_ANALYSIS.out.versions
}
