#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: M3C — monte_carlo_consensus_clustering
// Run Monte Carlo reference-based consensus clustering to find the optimal number of clusters (K) with statistical significance (p-values) and visualize the resul
// Input: mydata, desx
// Container: quay.io/biocontainers/bioconductor-m3c:1.32.0--r45hdfd78af_0
// R packages: ComplexHeatmap, M3C
// Bioconductor: 3.20 | R: 4.4
// Requires: M3C
// Visualizations: PCA plot, cluster plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Filter features by variance/MAD using featurefilter
//  * 2. [Core Analysis] Perform exploratory data analysis using pca
//  * 3. [Core Analysis] Run M3C with Monte Carlo simulation (method=1) to calculate stability scores and p-values
//  * 4. [Core Analysis] Inspect scores and p-values
//  * 5. [Core Analysis] Test association of clinical variables with discovered clusters using a chi-squared test
//  * 6. [Visualization & Output] Plot CDF, PAC, RCSI, and p-value curves
//  * 7. [Visualization & Output] Extract ordered data, annotations, and consensus matrix for downstream visualization
//  * 8. [Core Analysis] Perform visual check of cluster structure in principal component space

nextflow.enable.dsl = 2

process BIOC_M3C_MONTE_CARLO_CONSENSUS_CLUSTERING {
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
    .bm_deps <- c("ComplexHeatmap", "M3C")
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
    library(M3C)
    
    # Helper function to find and read input files robustly
    find_and_read <- function(base_name, required = TRUE, row_names = 1) {
      extensions <- c("", ".csv", ".tsv", ".txt", ".rds")
      found_file <- NULL
      for (ext in extensions) {
        path <- paste0(base_name, ext)
        if (file.exists(path)) {
          found_file <- path
          break
        }
      }
      
      if (is.null(found_file)) {
        if (required) {
          stop(paste("Required input file for", base_name, "not found in the working directory."))
        } else {
          return(NULL)
        }
      }
      
      message("Reading ", base_name, " from ", found_file)
      
      if (grepl("\\\\.rds\$", found_file, ignore.case = TRUE)) {
        return(readRDS(found_file))
      } else if (grepl("\\\\.csv\$", found_file, ignore.case = TRUE)) {
        return(read.csv(found_file, row.names = row_names, check.names = FALSE))
      } else {
        # Try reading as tab/space-separated table
        return(read.table(found_file, header = TRUE, row.names = row_names, check.names = FALSE))
      }
    }
    
    # 1. Read User Input Files
    mydata <- find_and_read("mydata", required = TRUE, row_names = 1)
    mydata <- as.matrix(mydata)
    
    desx <- find_and_read("desx", required = FALSE, row_names = NULL)
    if (!is.null(desx)) {
      desx <- as.data.frame(desx)
    }
    
    # 2. Filter features by variance/MAD using featurefilter
    filtered_results <- featurefilter(mydata, percentile=10, method='MAD', topN=5)
    
    # Save filtered results and update mydata for downstream steps
    if (is.list(filtered_results)) {
      if (!is.null(filtered_results\$filtered_data)) {
        write.csv(filtered_results\$filtered_data, "filtered_data.csv", row.names = TRUE)
        mydata <- filtered_results\$filtered_data
      }
      if (!is.null(filtered_results\$statistics)) {
        write.csv(filtered_results\$statistics, "feature_statistics.csv", row.names = TRUE)
      }
    } else {
      write.csv(filtered_results, "filtered_results.csv", row.names = TRUE)
      mydata <- filtered_results
    }
    
    # 3. Perform exploratory data analysis using pca
    pdf("pca_exploratory.pdf")
    pca(mydata,legendtextsize = 10,axistextsize = 10,dotsize=2)
    dev.off()
    
    # 4. Run M3C with Monte Carlo simulation
    res <- M3C(mydata, des = desx, removeplots = TRUE, iters=25, 
               objective='PAC', fsize=8, lthick=1, dotsize=1.25)
    
    # Save scores
    write.csv(res\$scores, "m3c_scores.csv", row.names = FALSE)
    print(res\$scores)
    
    # 5. Test association of clinical variables with discovered clusters using a chi-squared test
    tryCatch({
      for (k in seq(2,10)){
        myresults <- res\$realdataresults[[k]]\$ordered_annotation
        if (!is.null(myresults) && "consensuscluster" %in% colnames(myresults)) {
          clin_vars <- setdiff(colnames(myresults), "consensuscluster")
          if (length(clin_vars) > 0) {
            for (clin_var in clin_vars) {
              chifit <- suppressWarnings(chisq.test(table(myresults[c('consensuscluster', clin_var)])))
              print(chifit\$p.value)
            }
          } else {
            message("Skipping chi-squared test for K=", k, " (no clinical variables found)")
          }
        } else {
          message("Skipping chi-squared test for K=", k, " (missing consensuscluster column)")
        }
      }
    }, error = function(e) {
      message("Chi-squared test loop encountered an error: ", e\$message)
    })
    
    # 6. Plot CDF, PAC, RCSI, and p-value curves
    pdf("m3c_plots.pdf")
    print(res\$plots[[1]])
    print(res\$plots[[2]])
    print(res\$plots[[4]])
    print(res\$plots[[3]])
    dev.off()
    
    # 7. Extract ordered data, annotations, and consensus matrix for downstream visualization
    optimal_K <- res\$scores\$K[which.max(res\$scores\$RCSI)]
    
    data <- res\$realdataresults[[optimal_K]]\$ordered_data 
    annon <- res\$realdataresults[[optimal_K]]\$ordered_annotation 
    
    # If desx was not provided, ordered_annotation is NULL. 
    # We extract the cluster assignments directly and format them to match ordered_data.
    if (is.null(annon)) {
      annon <- data.frame(consensuscluster = res\$realdataresults[[optimal_K]]\$assignments)
      if (!is.null(colnames(data)) && all(colnames(data) %in% rownames(annon))) {
        annon <- annon[colnames(data), , drop = FALSE]
      }
    }
    
    ccmatrix <- res\$realdataresults[[optimal_K]]\$consensus_matrix
    
    write.csv(data, paste0("ordered_data_k", optimal_K, ".csv"), row.names = TRUE)
    write.csv(annon, paste0("ordered_annotation_k", optimal_K, ".csv"), row.names = TRUE)
    write.csv(ccmatrix, paste0("consensus_matrix_k", optimal_K, ".csv"), row.names = TRUE)
    
    print(head(annon))
    
    # 8. Perform visual check of cluster structure in principal component space
    pdf("pca_clusters.pdf")
    pca(data,labels=annon\$consensuscluster,legendtextsize = 10,axistextsize = 10,dotsize=2)
    dev.off()
    
    # Save the complete M3C results object
    saveRDS(res, "m3c_results.rds")

    writeLines(c(
        '"BIOC_M3C_MONTE_CARLO_CONSENSUS_CLUSTERING":',
        paste0('    M3C: ', as.character(packageVersion('M3C')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_monte_carlo_consensus_clustering.csv versions.yml
    """
}

workflow BIOC_M3C_MONTE_CARLO_CONSENSUS_CLUSTERING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ mydata, desx ] ]

    main:
    BIOC_M3C_MONTE_CARLO_CONSENSUS_CLUSTERING(ch_input)

    emit:
    tables   = BIOC_M3C_MONTE_CARLO_CONSENSUS_CLUSTERING.out.tables
    plots    = BIOC_M3C_MONTE_CARLO_CONSENSUS_CLUSTERING.out.plots
    objects  = BIOC_M3C_MONTE_CARLO_CONSENSUS_CLUSTERING.out.objects
    versions = BIOC_M3C_MONTE_CARLO_CONSENSUS_CLUSTERING.out.versions
}
