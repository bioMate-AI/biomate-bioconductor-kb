#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: goTools — compare_and_plot_gene_lists
// Compare the functional profiles of multiple probe ID lists using Gene Ontology and plot the results.
// Input: subset
// Container: quay.io/biocontainers/bioconductor-gotools:1.84.0--r45hdfd78af_0
// R packages: GO.db, goTools
// Bioconductor: 3.20 | R: 4.4
// Requires: GO.db, goTools
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Load the goTools package
//  * 2. [Visualization & Output] Load the GO.db annotation database
//  * 3. [Visualization & Output] Define the subset of probe lists to compare by reading
//  * 4. [Visualization & Output] Run ontoCompare to map probes, calculate percentages, and
//  * 5. [Visualization & Output] Save the meaningful results to output files

nextflow.enable.dsl = 2

process BIOC_GOTOOLS_COMPARE_AND_PLOT_GENE_LISTS {
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
    .bm_deps <- c("GO.db", "goTools")
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
    
    # --- Load the goTools package ---
    library("goTools", verbose=FALSE)
    
    # --- Load the GO.db annotation database ---
    library(GO.db)
    
    # --- Define the subset of probe lists to compare by reading ---
    # The pipeline expects 'subset.rds' (a serialized R list of probe ID vectors)
    # or 'subset.csv' (where each column represents a probe list) in the working directory.
    if (file.exists("subset.rds")) {
      subset <- readRDS("subset.rds")
    } else if (file.exists("subset.csv")) {
      input_data <- read.csv("subset.csv", header = TRUE, stringsAsFactors = FALSE)
      subset <- as.list(input_data)
      # Clean up any NA or empty values resulting from unequal column lengths
      subset <- lapply(subset, function(x) {
        clean_x <- x[!is.na(x) & x != ""]
        return(clean_x)
      })
    } else {
      stop("Error: Required input file 'subset.rds' or 'subset.csv' not found in the working directory.")
    }
    
    # Validate that the input is a list
    if (!is.list(subset)) {
      stop("Error: The input 'subset' must be a list of character vectors containing probe IDs.")
    }
    
    # --- Run ontoCompare to map probes, calculate percentages, and ---
    # We wrap the call in a PDF device to capture the plot generated when plot=TRUE.
    pdf("ontoCompare_plot.pdf", width = 10, height = 8)
    
    res <- ontoCompare(subset, probeType="hgu133a", plot=TRUE)
    
    dev.off()
    
    # --- Save the meaningful results to output files ---
    # Save the raw results object as an RDS file
    saveRDS(res, "ontoCompare_results.rds")
    
    # Convert the results to a data frame and save as a CSV table
    res_df <- as.data.frame(res)
    write.csv(res_df, "ontoCompare_results.csv", row.names = TRUE)

    writeLines(c(
        '"BIOC_GOTOOLS_COMPARE_AND_PLOT_GENE_LISTS":',
        paste0('    goTools: ', as.character(packageVersion('goTools')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_compare_and_plot_gene_lists.csv versions.yml
    """
}

workflow BIOC_GOTOOLS_COMPARE_AND_PLOT_GENE_LISTS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ subset ] ]

    main:
    BIOC_GOTOOLS_COMPARE_AND_PLOT_GENE_LISTS(ch_input)

    emit:
    tables   = BIOC_GOTOOLS_COMPARE_AND_PLOT_GENE_LISTS.out.tables
    plots    = BIOC_GOTOOLS_COMPARE_AND_PLOT_GENE_LISTS.out.plots
    objects  = BIOC_GOTOOLS_COMPARE_AND_PLOT_GENE_LISTS.out.objects
    versions = BIOC_GOTOOLS_COMPARE_AND_PLOT_GENE_LISTS.out.versions
}
