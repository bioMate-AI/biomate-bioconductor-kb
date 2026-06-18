#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: INDEED — partial_correlation_analysis
// Perform differential network analysis using partial correlation (graphical lasso) with permutation testing and visualize the resulting network.
// Input: data, class_label, id, p_val
// Container: quay.io/biocontainers/bioconductor-indeed:2.24.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: INDEED, htmlwidgets
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Select tuning parameter rho using select_rho_partial
//  * 2. [Core Analysis] Perform partial correlation analysis using partial_cor
//  * 3. [Visualization & Output] Visualize the differential network using network_display

nextflow.enable.dsl = 2

process BIOC_INDEED_PARTIAL_CORRELATION_ANALYSIS {
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
    .bm_deps <- c("INDEED")
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
    library(INDEED)
    
    # ==========================================
    # 1. Read User Input Files
    # ==========================================
    
    # Read data matrix (features as rows, subjects as columns)
    data_input <- as.matrix(read.csv("data.csv", row.names = 1, header = TRUE, check.names = FALSE))
    
    # Read class labels (one label per subject)
    class_label_df <- read.csv("class_label.csv", header = FALSE, stringsAsFactors = FALSE)
    class_label_input <- as.vector(class_label_df[[1]])
    
    # Read feature IDs
    id_df <- read.csv("id.csv", header = FALSE, stringsAsFactors = FALSE)
    id_input <- as.vector(id_df[[1]])
    
    # Read p-values and handle potential headers robustly
    p_val_df <- read.csv("p_val.csv", header = FALSE, stringsAsFactors = FALSE)
    p_val_input <- p_val_df[[1]]
    if (is.character(p_val_input) || is.factor(p_val_input)) {
      p_val_numeric <- suppressWarnings(as.numeric(p_val_input))
      if (any(is.na(p_val_numeric))) {
        # Re-read with header = TRUE if the first element was likely a header string
        p_val_df <- read.csv("p_val.csv", header = TRUE, stringsAsFactors = FALSE)
        p_val_input <- as.numeric(p_val_df[[1]])
      } else {
        p_val_input <- p_val_numeric
      }
    } else {
      p_val_input <- as.numeric(p_val_input)
    }
    
    # ==========================================
    # 2. Run INDEED Pipeline
    # ==========================================
    
    # Step 1: Select tuning parameter rho and plot the error curve
    pdf("error_curve.pdf")
    pre_data <- select_rho_partial(data = data_input, class_label = class_label_input, id = id_input,
                                   error_curve = "YES")
    dev.off()
    
    # Step 2: Perform partial correlation analysis
    result <- partial_cor(data_list = pre_data, rho_group1 = 'min', rho_group2 = "min",
                          permutation = 1000, p_val = p_val_input, permutation_thres = 0.05)
    
    # Step 3: Visualize the differential network
    net <- network_display(results = result, nodesize= 'Node_Degree', nodecolor= 'Activity_Score',
                           edgewidth= 'NO', layout= 'nice')
    
    # ==========================================
    # 3. Save Outputs
    # ==========================================
    
    # Save the full result object
    saveRDS(result, "indeed_results.rds")
    
    # Save activity scores table
    if (!is.null(result\$activity_score)) {
      write.csv(result\$activity_score, "activity_scores.csv", row.names = FALSE)
    }
    
    # Save differential network adjacency matrix
    if (!is.null(result\$diff_graph)) {
      write.csv(as.data.frame(result\$diff_graph), "differential_network_adj_matrix.csv")
    }
    
    # Save the interactive network visualization as an HTML file
    if (requireNamespace("htmlwidgets", quietly = TRUE)) {
      htmlwidgets::saveWidget(net, "differential_network.html", selfcontained = TRUE)
    }

    writeLines(c(
        '"BIOC_INDEED_PARTIAL_CORRELATION_ANALYSIS":',
        paste0('    INDEED: ', as.character(packageVersion('INDEED')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_partial_correlation_analysis.csv versions.yml
    """
}

workflow BIOC_INDEED_PARTIAL_CORRELATION_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ data, class_label, id, p_val ] ]

    main:
    BIOC_INDEED_PARTIAL_CORRELATION_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_INDEED_PARTIAL_CORRELATION_ANALYSIS.out.tables
    plots    = BIOC_INDEED_PARTIAL_CORRELATION_ANALYSIS.out.plots
    objects  = BIOC_INDEED_PARTIAL_CORRELATION_ANALYSIS.out.objects
    versions = BIOC_INDEED_PARTIAL_CORRELATION_ANALYSIS.out.versions
}
