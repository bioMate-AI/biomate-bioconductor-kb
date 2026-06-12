#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: netresponse — network_functional_response_analysis
// Detect and visualize subnetworks with context-specific activation patterns using functional data and a network.
// Input: D, network
// Container: quay.io/biocontainers/bioconductor-netresponse:1.70.0--r45h01b2380_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: ggplot2, netresponse
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Fit NetResponse model using detect.responses
//  * 2. [Core Analysis] Extract subnetworks using get.subnets
//  * 3. [Visualization & Output] Visualize responses using plot_responses (PCA, network, heatmap, boxplot)
//  * 4. [Visualization & Output] Plot color scale using plot_scale
//  * 5. [Core Analysis] Retrieve soft and hard cluster assignments using sample2response and response2sample
//  * 6. [Core Analysis] Retrieve model parameters using get.model.parameters

nextflow.enable.dsl = 2

process BIOC_NETRESPONSE_NETWORK_FUNCTIONAL_RESPONSE_ANALYSIS {
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
    .bm_deps <- c("netresponse", "ggplot2")
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
    library(netresponse)
    library(ggplot2)
    
    # ==========================================
    # 1. Read User Input Files
    # ==========================================
    
    # Read functional measurements matrix D
    if (file.exists("D.csv")) {
      D <- as.matrix(read.csv("D.csv", row.names = 1, check.names = FALSE))
    } else if (file.exists("D.tsv")) {
      D <- as.matrix(read.delim("D.tsv", row.names = 1, check.names = FALSE))
    } else if (file.exists("D.rds")) {
      D <- readRDS("D.rds")
    } else {
      stop("Error: Input file 'D' (D.csv, D.tsv, or D.rds) not found in the working directory.")
    }
    
    # Read network topology matrix
    if (file.exists("network.csv")) {
      network <- as.matrix(read.csv("network.csv", row.names = 1, check.names = FALSE))
    } else if (file.exists("network.tsv")) {
      network <- as.matrix(read.delim("network.tsv", row.names = 1, check.names = FALSE))
    } else if (file.exists("network.rds")) {
      network <- readRDS("network.rds")
    } else {
      stop("Error: Input file 'network' (network.csv, network.tsv, or network.rds) not found in the working directory.")
    }
    
    # ==========================================
    # 2. Fit NetResponse Model
    # ==========================================
    
    set.seed(4243)
    res <- detect.responses(D, network, mixture.method = "vdp", pca.basis = TRUE)
    
    # Save the fitted model object
    saveRDS(res, "netresponse_model.rds")
    
    # List subnets (each is a list of nodes)
    subnets_list <- get.subnets(res)
    saveRDS(subnets_list, "detected_subnets.rds")
    
    subnet.id <- names(subnets_list)[[1]]
    
    # ==========================================
    # 3. Visualize Responses
    # ==========================================
    
    # Open PDF device to capture all plots
    pdf("netresponse_plots.pdf", width = 10, height = 8)
    
    # PCA visualization
    vis <- plot_responses(res, subnet.id, plot_mode = "pca")
    
    # Modify the resulting ggplot2 object to enhance visualization
    p <- vis\$p # Pick the ggplot2 object from results
    p <- p + geom_point(size = 3) # Modify point size
    print(p)
    
    # Network visualization
    vis <- plot_responses(res, subnet.id, plot_mode = "network")
    
    # Heatmap visualization
    vis <- plot_responses(res, subnet.id, plot_mode = "heatmap")
    
    # Boxplot visualization
    vis <- plot_responses(res, subnet.id, plot_mode = "boxplot_data")
    
    # Color scale plotting
    plot_scale(vis\$breaks, vis\$palette, two.sided = TRUE)
    
    dev.off()
    
    # ==========================================
    # 4. Retrieve Cluster Assignments & Parameters
    # ==========================================
    
    # The vignette hardcodes 'Subnet-1'. To ensure compatibility with custom user data,
    # we define 'Subnet-1' but fall back to the first detected subnet if it is not present.
    subnet.id <- 'Subnet-1'
    if (!(subnet.id %in% names(subnets_list))) {
      warning("Subnet-1 not found in results. Using the first available subnet instead.")
      subnet.id <- names(subnets_list)[[1]]
    }
    
    # Sample - response probabilities (soft cluster assignment)
    response.probs <- sample2response(res, subnet.id)
    write.csv(as.data.frame(round(response.probs, 6)), "response_probabilities.csv", row.names = TRUE)
    
    # Sample - response hard assignments
    hard.clusters <- response2sample(res, subnet.id)
    write.csv(as.data.frame(hard.clusters), "hard_clusters.csv", row.names = TRUE)
    
    # Retrieve model parameters
    params <- get.model.parameters(res, subnet.id)
    saveRDS(params, "model_parameters.rds")

    writeLines(c(
        '"BIOC_NETRESPONSE_NETWORK_FUNCTIONAL_RESPONSE_ANALYSIS":',
        paste0('    netresponse: ', as.character(packageVersion('netresponse')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_network_functional_response_analysis.csv versions.yml
    """
}

workflow BIOC_NETRESPONSE_NETWORK_FUNCTIONAL_RESPONSE_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ D, network ] ]

    main:
    BIOC_NETRESPONSE_NETWORK_FUNCTIONAL_RESPONSE_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_NETRESPONSE_NETWORK_FUNCTIONAL_RESPONSE_ANALYSIS.out.tables
    plots    = BIOC_NETRESPONSE_NETWORK_FUNCTIONAL_RESPONSE_ANALYSIS.out.plots
    objects  = BIOC_NETRESPONSE_NETWORK_FUNCTIONAL_RESPONSE_ANALYSIS.out.objects
    versions = BIOC_NETRESPONSE_NETWORK_FUNCTIONAL_RESPONSE_ANALYSIS.out.versions
}
