#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: safe — custom_cmatrix_safe_analysis
// Build a custom category matrix and run SAFE analysis.
// Input: e3.upp, p3.upp$p53, genes
// Container: quay.io/biocontainers/bioconductor-safe:3.50.0--r45hdfd78af_0
// R packages: hgu133a.db, reactome.db, safe
// Bioconductor: 3.20 | R: 4.4
// Requires: hgu133a.db, reactome.db, safe
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Map gene identifiers to Entrez IDs
//  * 2. [Input & Preparation] Build category matrix using getCmatrix
//  * 3. [Core Analysis] Run safe using the custom category matrix

nextflow.enable.dsl = 2

process BIOC_SAFE_CUSTOM_CMATRIX_SAFE_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

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
    .bm_deps <- c("hgu133a.db", "reactome.db", "safe")
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
    library(safe)
    library(hgu133a.db)
    library(reactome.db)
    
    # Read user inputs from the working directory
    if (file.exists("e3.upp")) {
      e3.upp <- tryCatch(readRDS("e3.upp"), error = function(e) as.matrix(read.table("e3.upp", header = TRUE, row.names = 1)))
    } else {
      stop("Error: e3.upp file not found in the working directory.")
    }
    
    if (file.exists("p3.upp")) {
      p3.upp <- tryCatch(readRDS("p3.upp"), error = function(e) read.table("p3.upp", header = TRUE))
    } else if (file.exists("p3.upp\$p53")) {
      # Fallback in case the file is literally named "p3.upp\$p53"
      p53_vec <- tryCatch(readRDS("p3.upp\$p53"), error = function(e) readLines("p3.upp\$p53"))
      p3.upp <- list(p53 = p53_vec)
    } else {
      stop("Error: p3.upp file not found in the working directory.")
    }
    
    # Ensure p3.upp is structured so that p3.upp\$p53 is accessible
    if (!is.list(p3.upp) && !is.data.frame(p3.upp)) {
      p3.upp <- list(p53 = p3.upp)
    } else if (is.list(p3.upp) && !"p53" %in% names(p3.upp)) {
      if (is.data.frame(p3.upp)) {
        p3.upp\$p53 <- p3.upp[[1]]
      } else {
        p3.upp <- list(p53 = unlist(p3.upp))
      }
    }
    
    if (file.exists("genes")) {
      genes <- tryCatch(readRDS("genes"), error = function(e) {
        val <- readLines("genes")
        all_genes <- unlist(as.list(hgu133aSYMBOL))
        all_genes[all_genes %in% val]
      })
    } else {
      stop("Error: genes file not found in the working directory.")
    }
    
    # 1. Map gene identifiers to Entrez IDs
    entrez <- unlist(mget(names(genes), hgu133aENTREZID, ifnotfound = NA))
    entrez <- entrez[!is.na(entrez)]
    
    # 2. Build category matrix using getCmatrix
    C.mat <- getCmatrix(gene.list = as.list(reactomeEXTID2PATHID),
                        present.genes = entrez, prefix = "REACTOME:",
                        min.size = 10, max.size = 500)
    
    # 3. Run safe using the custom category matrix
    results <- safe(e3.upp, p3.upp\$p53, C.mat, print.it = FALSE)
    
    # Save the results object
    saveRDS(results, "safe_results.rds")
    
    # Generate and save top table of results
    tbl <- safe.toptable(results, number = 10)
    write.csv(tbl, "safe_toptable.csv", row.names = FALSE)
    
    # Generate and save a SAFE plot for the top significant category
    if (!is.null(tbl) && nrow(tbl) > 0) {
      top_cat <- tbl\$GenesetID[1]
      pdf("safe_plot.pdf")
      safeplot(results, cat.name = top_cat, gene.names = genes)
      dev.off()
    }

    writeLines(c(
        '"BIOC_SAFE_CUSTOM_CMATRIX_SAFE_ANALYSIS":',
        paste0('    safe: ', as.character(packageVersion('safe')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_custom_cmatrix_safe_analysis.csv versions.yml
    """
}

workflow BIOC_SAFE_CUSTOM_CMATRIX_SAFE_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ e3.upp, p3.upp$p53, genes ] ]

    main:
    BIOC_SAFE_CUSTOM_CMATRIX_SAFE_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_SAFE_CUSTOM_CMATRIX_SAFE_ANALYSIS.out.tables
    plots    = BIOC_SAFE_CUSTOM_CMATRIX_SAFE_ANALYSIS.out.plots
    objects  = BIOC_SAFE_CUSTOM_CMATRIX_SAFE_ANALYSIS.out.objects
    versions = BIOC_SAFE_CUSTOM_CMATRIX_SAFE_ANALYSIS.out.versions
}
