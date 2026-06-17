#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: safe — standard_safe_analysis
// Perform resampling-based pathway analysis on two-sample gene expression data using built-in annotations.
// Input: e3.upp, p3.upp$p53
// Container: quay.io/biocontainers/bioconductor-safe:3.50.0--r45hdfd78af_0
// R packages: breastcancerupp, doParallel, hgu133a.db, safe
// Bioconductor: 3.20 | R: 4.4
// Requires: hgu133a.db, safe
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run safe with platform annotation
//  * 2. [Core Analysis] Tabulate top results using safe.toptable
//  * 3. [Core Analysis] Extract gene-specific results using gene.results
//  * 4. [Visualization & Output] Plot pathway results using safeplot

nextflow.enable.dsl = 2

process BIOC_SAFE_STANDARD_SAFE_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim"

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
    .bm_deps <- c("breastcancerupp", "doParallel", "hgu133a.db", "safe")
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
        library(safe)
        library(hgu133a.db)
        
        # Set seed for reproducibility
        set.seed(12345)
        
        # Helper function to robustly read user input files
        read_input <- function(file_path) {
          if (!file.exists(file_path)) {
            stop(paste("Error: Required input file missing:", file_path))
          }
          
          # Try reading as RDS
          obj <- tryCatch({
            readRDS(file_path)
          }, error = function(e) {
            NULL
          })
          if (!is.null(obj)) return(obj)
          
          # Try reading as table (matrix/data.frame)
          obj <- tryCatch({
            as.matrix(read.table(file_path, header = TRUE, row.names = 1, check.names = FALSE))
          }, error = function(e) {
            NULL
          })
          if (!is.null(obj)) return(obj)
          
          # Try reading as simple vector
          obj <- tryCatch({
            scan(file_path, quiet = TRUE)
          }, error = function(e) {
            stop(paste("Error: Failed to read file", file_path))
          })
          return(obj)
        }
        
        # Read user input files from the working directory
        e3.upp <- read_input("e3.upp")
        p53_vector <- read_input("p3.upp\$p53")
        
        # Construct the p3.upp object to match the documented code structure
        p3.upp <- list(p53 = p53_vector)
        
        # Define the genes annotation object as specified in the package documentation
        genes <- unlist(as.list(hgu133aSYMBOL))
        drop <- grep("AFFX", names(genes))
        genes <- genes[-drop]
        
        # === DOCUMENTED CODE STAGES ===
        
        # Stage 1: Run safe with platform annotation
        results <- safe(e3.upp, p3.upp\$p53, platform = "hgu133a.db",
                        annotate = "REACTOME", print.it = FALSE)
        saveRDS(results, "safe_results.rds")
        
        # Stage 2: Tabulate top results using safe.toptable
        top_table <- safe.toptable(results, number = 10)
        write.csv(top_table, "safe_toptable.csv", row.names = TRUE)
        
        # Stage 3: Extract gene-specific results using gene.results
        top_pathway <- as.character(top_table\$GenesetID[1])
        gene.results(results, cat.name = top_pathway, gene.names = genes)
        
        # Also save the gene-specific results to an RDS file for downstream use
        gene_res_list <- gene.results(results, cat.name = top_pathway, gene.names = genes, print.it = FALSE)
        saveRDS(gene_res_list, "gene_results_top_pathway.rds")
        
        # Stage 4: Plot pathway results using safeplot
        pdf("safeplot_top_pathway.pdf", width = 10, height = 8)
        safeplot(results, cat.name = top_pathway, gene.names = genes)
        dev.off()

    writeLines(c(
        '"BIOC_SAFE_STANDARD_SAFE_ANALYSIS":',
        paste0('    safe: ', as.character(packageVersion('safe')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_standard_safe_analysis.csv versions.yml
    """
}

workflow BIOC_SAFE_STANDARD_SAFE_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ e3.upp, p3.upp$p53 ] ]

    main:
    BIOC_SAFE_STANDARD_SAFE_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_SAFE_STANDARD_SAFE_ANALYSIS.out.tables
    plots    = BIOC_SAFE_STANDARD_SAFE_ANALYSIS.out.plots
    objects  = BIOC_SAFE_STANDARD_SAFE_ANALYSIS.out.objects
    versions = BIOC_SAFE_STANDARD_SAFE_ANALYSIS.out.versions
}
