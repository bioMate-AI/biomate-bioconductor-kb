#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: logicFS — interaction_importance_logicfs
// Identify and measure the importance of SNP interactions using logic regression feature selection.
// Input: data.logicfs, cl.logicfs
// Container: quay.io/biocontainers/bioconductor-logicfs:2.30.0--r45hdfd78af_0
// R packages: logicFS
// Bioconductor: 3.20 | R: 4.4
// Requires: logicFS
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the package and data
//  * 2. [Core Analysis] Convert categorical SNP variables into binary dummy variables
//  * 3. [Input & Preparation] Set up simulated annealing control parameters
//  * 4. [Core Analysis] Run logic regression feature selection
//  * 5. [Visualization & Output] Visualize interaction importance

nextflow.enable.dsl = 2

process BIOC_LOGICFS_INTERACTION_IMPORTANCE_LOGICFS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-variant_calling:3.20-slim"

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
    .bm_deps <- c("logicFS")
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
    
    # 1. Load the package and data
    library(logicFS)
    
    # Robust loader for the user input files
    load_input <- function(filepath) {
      if (!file.exists(filepath)) {
        stop(paste("Error: Required input file '", filepath, "' not found in the working directory.", sep = ""))
      }
      
      # Try reading as RDS
      obj <- tryCatch(readRDS(filepath), error = function(e) NULL)
      if (!is.null(obj)) return(obj)
      
      # Try reading as table (for matrix/dataframe)
      obj <- tryCatch({
        df <- read.table(filepath, header = TRUE, check.names = FALSE)
        as.matrix(df)
      }, error = function(e) NULL)
      if (!is.null(obj)) return(obj)
      
      # Try reading as simple vector (scan)
      obj <- tryCatch(scan(filepath, quiet = TRUE), error = function(e) NULL)
      if (!is.null(obj)) return(obj)
      
      stop(paste("Error: Failed to parse file '", filepath, "'. Please ensure it is a valid RDS, CSV, or text file.", sep = ""))
    }
    
    data.logicfs <- load_input("data.logicfs")
    cl.logicfs <- load_input("cl.logicfs")
    
    # Ensure cl.logicfs is a vector
    if (is.matrix(cl.logicfs) || is.data.frame(cl.logicfs)) {
      cl.logicfs <- as.vector(as.matrix(cl.logicfs))
    }
    
    # Ensure data.logicfs is a matrix
    if (!is.matrix(data.logicfs)) {
      data.logicfs <- as.matrix(data.logicfs)
    }
    
    # 2. Convert categorical SNP variables into binary dummy variables
    bin.snps <- make.snp.dummy(data.logicfs)
    
    # Save binary SNPs to CSV
    write.csv(as.data.frame(bin.snps), "binary_snps.csv", row.names = TRUE)
    
    # 3. Set up simulated annealing control parameters
    my.anneal <- logreg.anneal.control(start = 2, end = -2, iter = 10000)
    
    # 4. Run logic regression feature selection
    log.out <- logicFS(bin.snps, cl.logicfs, B = 20, nleaves = 10, rand = 1234, anneal.control = my.anneal)
    
    # Save the text summary of the model
    sink("logicFS_summary.txt")
    print(log.out)
    sink()
    
    # Save the RDS object
    saveRDS(log.out, "logicFS_result.rds")
    
    # 5. Visualize interaction importance
    pdf("logicFS_importance_plot.pdf", width = 8, height = 6)
    plot(log.out)
    dev.off()

    writeLines(c(
        '"BIOC_LOGICFS_INTERACTION_IMPORTANCE_LOGICFS":',
        paste0('    logicFS: ', as.character(packageVersion('logicFS')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_interaction_importance_logicfs.csv versions.yml
    """
}

workflow BIOC_LOGICFS_INTERACTION_IMPORTANCE_LOGICFS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ data.logicfs, cl.logicfs ] ]

    main:
    BIOC_LOGICFS_INTERACTION_IMPORTANCE_LOGICFS(ch_input)

    emit:
    tables   = BIOC_LOGICFS_INTERACTION_IMPORTANCE_LOGICFS.out.tables
    plots    = BIOC_LOGICFS_INTERACTION_IMPORTANCE_LOGICFS.out.plots
    objects  = BIOC_LOGICFS_INTERACTION_IMPORTANCE_LOGICFS.out.objects
    versions = BIOC_LOGICFS_INTERACTION_IMPORTANCE_LOGICFS.out.versions
}
