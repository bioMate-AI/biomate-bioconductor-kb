#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: QUBIC — standard_biclustering
// Perform standard qualitative biclustering on a gene expression matrix, visualize results with heatmaps, and construct co-expression networks.
// Input: expression_matrix.csv
// Container: quay.io/biocontainers/bioconductor-qubic:1.38.0--r45ha27e39d_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: QUBIC, RColorBrewer
// Visualizations: heatmap, cluster plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Discretize the expression matrix
//  * 2. [Core Analysis] Run the QUBIC algorithm
//  * 3. [Visualization & Output] Visualize specific biclusters using heatmaps
//  * 4. [Input & Preparation] Construct co-expression networks
//  * 5. [Visualization & Output] Export networks to XGMML format

nextflow.enable.dsl = 2

process BIOC_QUBIC_STANDARD_BICLUSTERING {
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
    .bm_deps <- c("QUBIC", "RColorBrewer")
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
    library(QUBIC)
    library(RColorBrewer)
    
    # 1. Read the user input file
    if (!file.exists("expression_matrix.csv")) {
      stop("Required input file 'expression_matrix.csv' not found in the working directory.")
    }
    
    # Read the expression matrix (genes as rows, conditions as columns)
    ecoli_df <- read.csv("expression_matrix.csv", row.names = 1, check.names = FALSE)
    ecoli <- as.matrix(ecoli_df)
    
    # 2. Discretize the expression matrix
    # Discretize the full expression matrix instead of a subset
    matrix2 <- qudiscretize(ecoli)
    
    # Save discretized matrix
    write.csv(matrix2, "discretized_subset.csv")
    
    # 3. Run the QUBIC algorithm
    # Exact call:
    res <- qubiclust(ecoli, r = 1, q = 0.06, c = 0.95, o = 100, f = 0.25, k = max(ncol(ecoli)%/%20, 2))
    
    # Save the biclustering result object
    saveRDS(res, "qubic_biclust_result.rds")
    
    # Write a summary of the biclusters to a text file
    sink("biclust_summary.txt")
    print(summary(res))
    sink()
    
    # 4. Visualize specific biclusters using heatmaps
    paleta <- colorRampPalette(rev(brewer.pal(11, "RdYlBu")))(11)
    
    pdf("bicluster_heatmap.pdf", width = 10, height = 8)
    # Exact call wrapped in tryCatch for robustness (dynamically selecting index 1)
    tryCatch({
      quheatmap(ecoli, res, number = 1, showlabel = TRUE, col = paleta)
    }, error = function(e) {
      message("Note: Heatmap for bicluster 1 could not be plotted. Error: ", e\$message)
    })
    dev.off()
    
    # 5. Construct co-expression networks
    # Exact call wrapped in tryCatch
    net <- NULL
    tryCatch({
      net <- qunetwork(ecoli, res, number = 1, group = 1, method = "spearman")
      saveRDS(net, "coexpression_network.rds")
    }, error = function(e) {
      message("Note: Network construction for bicluster 1 failed. Error: ", e\$message)
    })
    
    # 6. Export networks to XGMML format
    # Exact call wrapped in tryCatch and sinked to a file
    sink("network.xml")
    tryCatch({
      if (!is.null(net)) {
        qunet2xml(net, minimum = 0.6, color = cbind(rainbow(length(net[[2]]) - 1), "gray"))
      } else {
        message("No network available to export.")
      }
    }, error = function(e) {
      message("Note: Exporting network to XML failed. Error: ", e\$message)
    })
    sink()
    
    message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_QUBIC_STANDARD_BICLUSTERING":',
        paste0('    QUBIC: ', as.character(packageVersion('QUBIC')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_standard_biclustering.csv versions.yml
    """
}

workflow BIOC_QUBIC_STANDARD_BICLUSTERING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ expression_matrix.csv ] ]

    main:
    BIOC_QUBIC_STANDARD_BICLUSTERING(ch_input)

    emit:
    tables   = BIOC_QUBIC_STANDARD_BICLUSTERING.out.tables
    plots    = BIOC_QUBIC_STANDARD_BICLUSTERING.out.plots
    objects  = BIOC_QUBIC_STANDARD_BICLUSTERING.out.objects
    versions = BIOC_QUBIC_STANDARD_BICLUSTERING.out.versions
}
