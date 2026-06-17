#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: condiments — differential_topology_analysis
// Perform differential topology, progression, and fate selection analysis on single-cell data across multiple conditions.
// Input: reduced_dim_matrix, condition_labels, cluster_labels
// Container: quay.io/biocontainers/bioconductor-condiments:1.18.0--r45hdfd78af_0
// R packages: condiments, dplyr, ggplot2, knitr, RColorBrewer, slingshot, tidyr
// Bioconductor: 3.20 | R: 4.4
// Requires: condiments, dplyr, ggplot2, slingshot, tidyr
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Compute imbalance scores using imbalance_score
//  * 2. [Core Analysis] Infer a common trajectory using slingshot
//  * 3. [Core Analysis] Test trajectory topology using topologyTest
//  * 4. [Core Analysis] Test for differential progression along lineages using progressionTest
//  * 5. [Core Analysis] Test for differential fate selection between lineages using fateSelectionTest

nextflow.enable.dsl = 2

process BIOC_CONDIMENTS_DIFFERENTIAL_TOPOLOGY_ANALYSIS {
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
    .bm_deps <- c("condiments", "dplyr", "ggplot2", "knitr", "RColorBrewer", "slingshot", "tidyr")
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
    library(condiments)
    library(slingshot)
    library(dplyr)
    library(tidyr)
    library(ggplot2)
    
    # Helper function to find input files with or without extensions
    find_file <- function(base_name) {
      files <- list.files(".", full.names = TRUE)
      matched <- files[grepl(paste0("^\\\\./", base_name, "(\\\\..+)?\$"), files)]
      if (length(matched) == 0) {
        stop(paste("Required input file not found:", base_name))
      }
      return(matched[1])
    }
    
    # Helper function to robustly read input files
    read_input <- function(file_path) {
      ext <- tolower(tools::file_ext(file_path))
      if (ext == "rds") {
        return(readRDS(file_path))
      } else if (ext == "csv") {
        return(read.csv(file_path, header = TRUE, stringsAsFactors = FALSE))
      } else if (ext %in% c("tsv", "txt")) {
        return(read.delim(file_path, header = TRUE, stringsAsFactors = FALSE))
      } else {
        # Fallback trial of formats
        res <- tryCatch(readRDS(file_path), error = function(e) NULL)
        if (!is.null(res)) return(res)
        res <- tryCatch(read.csv(file_path, header = TRUE, stringsAsFactors = FALSE), error = function(e) NULL)
        if (!is.null(res)) return(res)
        res <- tryCatch(read.delim(file_path, header = TRUE, stringsAsFactors = FALSE), error = function(e) NULL)
        if (!is.null(res)) return(res)
        return(readLines(file_path))
      }
    }
    
    # Locate and read the required user input files
    reduced_dim_file <- find_file("reduced_dim_matrix")
    condition_file <- find_file("condition_labels")
    cluster_file <- find_file("cluster_labels")
    
    rd_data <- read_input(reduced_dim_file)
    cond_data <- read_input(condition_file)
    cl_data <- read_input(cluster_file)
    
    # Format reduced dimension matrix
    if (is.vector(rd_data)) {
      stop("reduced_dim_matrix must be a matrix or data frame with at least 2 dimensions.")
    }
    rd_df <- as.data.frame(rd_data)
    colnames(rd_df)[1:2] <- c("Dim1", "Dim2")
    
    # Format condition labels
    if (is.data.frame(cond_data) || is.matrix(cond_data)) {
      conditions <- as.vector(cond_data[, 1])
    } else {
      conditions <- as.vector(cond_data)
    }
    
    # Format cluster labels
    if (is.data.frame(cl_data) || is.matrix(cl_data)) {
      cl <- as.vector(cl_data[, 1])
    } else {
      cl <- as.vector(cl_data)
    }
    
    # Construct the main data frame and reduced dimension matrix
    df <- data.frame(
      Dim1 = rd_df\$Dim1,
      Dim2 = rd_df\$Dim2,
      conditions = conditions,
      cl = cl,
      stringsAsFactors = FALSE
    )
    rd <- as.matrix(df[, c("Dim1", "Dim2")])
    
    # 1. Compute imbalance scores using imbalance_score
    message("Computing imbalance scores...")
    scores <- imbalance_score(Object = df %>% select(Dim1, Dim2) %>% as.matrix(), conditions = df\$conditions)
    df\$scores <- scores\$scores
    df\$scaled_scores <- scores\$scaled_scores
    
    # 2. Infer a common trajectory using slingshot
    message("Inferring common trajectory using Slingshot...")
    sds <- slingshot(rd, df\$cl)
    
    # 3. Test trajectory topology using topologyTest
    message("Testing trajectory topology...")
    top_res <- topologyTest(sds = sds, conditions = df\$conditions)
    
    # 4. Test for differential progression along lineages using progressionTest
    message("Testing for differential progression...")
    prog_res <- progressionTest(sds, conditions = df\$conditions, global = TRUE, lineages = TRUE)
    
    # 5. Test for differential fate selection between lineages using fateSelectionTest
    message("Testing for differential fate selection...")
    dif_res <- fateSelectionTest(sds, conditions = df\$conditions, global = FALSE, pairwise = TRUE)
    
    # Write meaningful results to output files
    message("Writing output files...")
    write.csv(as.data.frame(scores), "imbalance_scores.csv", row.names = FALSE)
    write.csv(as.data.frame(top_res), "topology_test_results.csv", row.names = FALSE)
    write.csv(as.data.frame(prog_res), "progression_test_results.csv", row.names = FALSE)
    write.csv(as.data.frame(dif_res), "fate_selection_test_results.csv", row.names = FALSE)
    saveRDS(sds, "slingshot_dataset.rds")
    
    # Generate and save visualization plots
    pdf("condiments_analysis_plots.pdf", width = 12, height = 5)
    
    # Plot 1: Imbalance scores
    p1 <- ggplot(df, aes(x = Dim1, y = Dim2, col = scaled_scores)) +
      geom_point(alpha = 0.7) +
      scale_color_viridis_c(option = "C") +
      theme_classic() +
      labs(title = "Smoothed Imbalance Scores", x = "Dim 1", y = "Dim 2", col = "Score")
    
    # Plot 2: Trajectory and Clusters
    p2 <- ggplot(df, aes(x = Dim1, y = Dim2, col = as.factor(cl))) +
      geom_point(alpha = 0.5) +
      geom_path(data = slingCurves(sds, as.df = TRUE) %>% arrange(Order),
                aes(group = Lineage), col = "black", linewidth = 1.5) +
      theme_classic() +
      labs(title = "Inferred Trajectory with Slingshot", x = "Dim 1", y = "Dim 2", col = "Cluster")
    
    print(p1)
    print(p2)
    dev.off()
    
    message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_CONDIMENTS_DIFFERENTIAL_TOPOLOGY_ANALYSIS":',
        paste0('    condiments: ', as.character(packageVersion('condiments')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_differential_topology_analysis.csv versions.yml
    """
}

workflow BIOC_CONDIMENTS_DIFFERENTIAL_TOPOLOGY_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ reduced_dim_matrix, condition_labels, cluster_labels ] ]

    main:
    BIOC_CONDIMENTS_DIFFERENTIAL_TOPOLOGY_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_CONDIMENTS_DIFFERENTIAL_TOPOLOGY_ANALYSIS.out.tables
    plots    = BIOC_CONDIMENTS_DIFFERENTIAL_TOPOLOGY_ANALYSIS.out.plots
    objects  = BIOC_CONDIMENTS_DIFFERENTIAL_TOPOLOGY_ANALYSIS.out.objects
    versions = BIOC_CONDIMENTS_DIFFERENTIAL_TOPOLOGY_ANALYSIS.out.versions
}
