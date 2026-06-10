#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: clevRvis — explore_alternative_trees
// Determine all valid parental relations based on clone fractions and timepoints to explore alternative phylogenetic trees.
// Input: fracTable, timepoints
// Container: quay.io/biocontainers/bioconductor-clevrvis:1.10.0--r45hdfd78af_0
// R packages: clevRvis
// Bioconductor: 3.20 | R: 4.4
// Requires: clevRvis
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Define clone fractions and timepoints
//  * 2. [Core Analysis] Run exploreTrees to find valid parental relations

nextflow.enable.dsl = 2

process BIOC_CLEVRVIS_EXPLORE_ALTERNATIVE_TREES {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20"

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
    .bm_deps <- c("clevRvis")
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
        
        # Load required library
        library(clevRvis)
        
        # 1. Define clone fractions and timepoints by reading user input files
        # The pipeline reads 'fracTable' and 'timepoints' from the working directory.
        # We handle potential file extensions (.csv, .txt, or no extension) for robustness.
        
        if (file.exists("timepoints")) {
          timepoints <- as.numeric(unlist(strsplit(readLines("timepoints"), "[,[:space:]]+")))
          timepoints <- timepoints[!is.na(timepoints)]
        } else if (file.exists("timepoints.csv")) {
          timepoints <- as.numeric(unlist(read.csv("timepoints.csv", header = FALSE)))
          timepoints <- timepoints[!is.na(timepoints)]
        } else if (file.exists("timepoints.txt")) {
          timepoints <- as.numeric(unlist(strsplit(readLines("timepoints.txt"), "[,[:space:]]+")))
          timepoints <- timepoints[!is.na(timepoints)]
        } else {
          stop("Error: Input file 'timepoints' (numeric vector of time points) not found in the working directory.")
        }
        
        if (file.exists("fracTable")) {
          fracTable <- as.matrix(read.table("fracTable", header = FALSE))
        } else if (file.exists("fracTable.csv")) {
          fracTable <- as.matrix(read.csv("fracTable.csv", header = FALSE))
        } else if (file.exists("fracTable.txt")) {
          fracTable <- as.matrix(read.table("fracTable.txt", header = FALSE))
        } else {
          stop("Error: Input file 'fracTable' (numeric matrix of CCFs) not found in the working directory.")
        }
        
        # Ensure fracTable is a numeric matrix
        mode(fracTable) <- "numeric"
        
        # 2. Run exploreTrees to find valid parental relations
        trees <- exploreTrees(fracTable, timepoints)
        
        # Print the identified alternative trees to the console
        print(trees)
        
        # 3. Write named output files for the meaningful results
        # Save the trees object as an RDS file
        saveRDS(trees, file = "alternative_trees.rds")
        
        # Save a text summary of the alternative trees
        sink("alternative_trees_summary.txt")
        cat("Alternative Phylogenetic Trees (Parental Relations):\n")
        cat("==================================================\n\n")
        print(trees)
        sink()
        
        # Save the trees as a CSV table where each row represents a valid parental relation vector
        if (length(trees) > 0) {
          trees_df <- do.call(rbind, lapply(names(trees), function(name) {
            c(Tree_Name = name, Parent_Relations = paste(trees[[name]], collapse = ","))
          }))
          write.csv(trees_df, file = "alternative_trees.csv", row.names = FALSE)
        }

    writeLines(c(
        '"BIOC_CLEVRVIS_EXPLORE_ALTERNATIVE_TREES":',
        paste0('    clevRvis: ', as.character(packageVersion('clevRvis')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_explore_alternative_trees.csv versions.yml
    """
}

workflow BIOC_CLEVRVIS_EXPLORE_ALTERNATIVE_TREES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ fracTable, timepoints ] ]

    main:
    BIOC_CLEVRVIS_EXPLORE_ALTERNATIVE_TREES(ch_input)

    emit:
    tables   = BIOC_CLEVRVIS_EXPLORE_ALTERNATIVE_TREES.out.tables
    plots    = BIOC_CLEVRVIS_EXPLORE_ALTERNATIVE_TREES.out.plots
    objects  = BIOC_CLEVRVIS_EXPLORE_ALTERNATIVE_TREES.out.objects
    versions = BIOC_CLEVRVIS_EXPLORE_ALTERNATIVE_TREES.out.versions
}
