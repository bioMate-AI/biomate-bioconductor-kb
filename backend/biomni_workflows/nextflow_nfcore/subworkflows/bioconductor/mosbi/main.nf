#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: mosbi — ensemble_biclustering
// Run multiple biclustering algorithms on a data matrix, construct a similarity network with an error model, extract robust communities, and generate consensus en
// Input: data_matrix
// Container: quay.io/biocontainers/bioconductor-mosbi:1.16.0--r45ha27e39d_0
// R packages: mosbi
// Bioconductor: 3.20 | R: 4.4
// Requires: mosbi
// Visualizations: heatmap
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Prepare and normalize data (log-transform and z-score)
//  * 2. [Core Analysis] Run multiple biclustering algorithms (Fabia, ISA, Plaid, QUBIC) and combine results
//  * 3. [Core Analysis] Compute a bicluster similarity network with an error model
//  * 4. [Core Analysis] Extract Louvain communities of biclusters
//  * 5. [Core Analysis] Generate consensus ensemble biclusters

nextflow.enable.dsl = 2

process BIOC_MOSBI_ENSEMBLE_BICLUSTERING {
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
    .bm_deps <- c("mosbi")
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
        library(mosbi)
        
        # Helper functions from documented code
        z_score <- function(x, margin = 2) {
            z_fun <- function(y) {
                (y - mean(y, na.rm = TRUE)) / sd(y, na.rm = TRUE)
            }
        
            if (margin == 2) {
                return(apply(x, margin, z_fun))
            } else if (margin == 1) {
                return(t(apply(x, margin, z_fun)))
            }
        }
        
        bicluster_histo <- function(biclusters) {
            cols <- mosbi::colhistogram(biclusters)
            rows <- mosbi::rowhistogram(biclusters)
        
            graphics::par(mfrow = c(1, 2))
            hist(cols, main = "Column size ditribution")
            hist(rows, main = "Row size ditribution")
        }
        
        # 1. Read and Prepare User Input Data
        # The pipeline reads 'data_matrix' from the working directory.
        # It supports RDS, CSV, or TSV formats.
        if (file.exists("data_matrix.rds")) {
            data_matrix <- readRDS("data_matrix.rds")
        } else if (file.exists("data_matrix.csv")) {
            data_matrix <- as.matrix(read.csv("data_matrix.csv", row.names = 1, check.names = FALSE))
        } else if (file.exists("data_matrix.tsv")) {
            data_matrix <- as.matrix(read.delim("data_matrix.tsv", row.names = 1, check.names = FALSE))
        } else if (file.exists("data_matrix")) {
            data_matrix <- tryCatch({
                as.matrix(read.csv("data_matrix", row.names = 1, check.names = FALSE))
            }, error = function(e) {
                as.matrix(read.table("data_matrix", row.names = 1, header = TRUE, check.names = FALSE))
            })
        } else {
            stop("Required input file 'data_matrix' (or with .csv/.tsv/.rds extension) not found in the working directory.")
        }
        
        # Ensure data_matrix is a numeric matrix
        data_matrix <- as.matrix(data_matrix)
        class(data_matrix) <- "numeric"
        
        # Ensure rownames and colnames exist
        if (is.null(rownames(data_matrix))) {
            rownames(data_matrix) <- paste0("Feature", seq_len(nrow(data_matrix)))
        }
        if (is.null(colnames(data_matrix))) {
            colnames(data_matrix) <- paste0("Sample", seq_len(ncol(data_matrix)))
        }
        
        # Apply log2 and z_score normalization
        data_matrix <- z_score(log2(data_matrix), margin = 1)
        
        # Open PDF device to capture all plots
        pdf("mosbi_analysis_plots.pdf", width = 11, height = 8.5)
        
        # Plot initial heatmap of the data matrix
        stats::heatmap(data_matrix)
        
        # 2. Run Biclustering Algorithms
        # Fabia
        fb <- tryCatch({
            mosbi::run_fabia(data_matrix)
        }, error = function(e) {
            message("Fabia failed: ", e\$message)
            return(list())
        })
        
        # isa2
        BCisa <- tryCatch({
            mosbi::run_isa(data_matrix)
        }, error = function(e) {
            message("ISA failed: ", e\$message)
            return(list())
        })
        
        # Plaid
        BCplaid <- tryCatch({
            mosbi::run_plaid(data_matrix)
        }, error = function(e) {
            message("Plaid failed: ", e\$message)
            return(list())
        })
        
        # QUBIC
        BCqubic <- tryCatch({
            mosbi::run_qubic(data_matrix)
        }, error = function(e) {
            message("QUBIC failed: ", e\$message)
            return(list())
        })
        
        # Merge results of all algorithms
        all_bics <- c(fb, BCisa, BCplaid, BCqubic)
        
        # Plot bicluster size distribution histogram
        if (length(all_bics) > 0) {
            bicluster_histo(all_bics)
        } else {
            stop("No biclusters were found by any of the algorithms. Cannot proceed with network construction.")
        }
        
        # 3. Compute Bicluster Similarity Network with Error Model
        bic_net <- mosbi::bicluster_network(all_bics, # List of biclusters
            data_matrix, # Data matrix
            n_randomizations = 5,
            # Number of randomizations for the error model
            MARGIN = "both",
            # Use datapoints for metric evaluation
            metric = 4, # Fowlkes–Mallows index
            n_steps = 1000,
            # At how many steps should the cut-off be evaluated
            plot_edge_dist = TRUE
            # Plot the evaluation of cut-off estimation
        )
        
        # Save the bicluster network object
        saveRDS(bic_net, "bicluster_network.rds")
        
        # Plot adjacency heatmap
        stats::heatmap(get_adjacency(bic_net))
        
        # Plot network
        plot(bic_net)
        
        # Plot algorithm network
        mosbi::plot_algo_network(bic_net, all_bics, vertex.label = NA)
        
        # Prepare groups for plotting (e.g., weeks or sample groups)
        # If colnames contain '.', split them to extract groups. Otherwise, use a fallback grouping.
        has_dot <- any(grepl("\\\\.", colnames(data_matrix)))
        if (has_dot) {
            weeks <- vapply(
                strsplit(colnames(data_matrix), "\\\\."),
                function(x) {
                    return(x[1])
                }, ""
            )
        } else {
            # Fallback: Group by the first 4 characters of the column names
            weeks <- substr(colnames(data_matrix), 1, min(4, max(nchar(colnames(data_matrix)))))
        }
        names(weeks) <- colnames(data_matrix)
        
        print(sort(unique(weeks)))
        
        # Generate colors dynamically based on the number of unique groups
        unique_weeks <- sort(unique(weeks))
        num_weeks <- length(unique_weeks)
        if (num_weeks <= 5) {
            week_cols <- c("yellow", "orange", "red", "green", "brown")[1:num_weeks]
        } else {
            week_cols <- grDevices::rainbow(num_weeks)
        }
        
        # Plot network colored by week/group
        mosbi::plot_piechart_bicluster_network(bic_net, all_bics, weeks,
            week_cols,
            vertex.label = NA
        )
        graphics::legend("topright",
            legend = sort(unique(weeks)),
            fill = week_cols, title = "Group"
        )
        
        # 4. Extract Louvain Communities
        coms <- mosbi::get_louvain_communities(bic_net,
            min_size = 3,
            bics = all_bics
        )
        
        # Save the communities object
        saveRDS(coms, "louvain_communities.rds")
        
        # Plot all communities and print algorithm composition
        if (length(coms) > 0) {
            for (i in seq(1, length(coms))) {
                tmp_bics <- mosbi::select_biclusters_from_bicluster_network(
                    coms[[i]],
                    all_bics
                )
        
                mosbi::plot_piechart_bicluster_network(coms[[i]], tmp_bics,
                    weeks, week_cols,
                    main = paste0("Community ", i)
                )
                graphics::legend("topright",
                    legend = sort(unique(weeks)),
                    fill = week_cols, title = "Group"
                )
        
                cat("\nCommunity ", i, " consists of results from the following algorithms:\n")
                cat(get_bic_net_algorithms(coms[[i]]))
                cat("\n")
            }
        } else {
            message("No communities of minimum size 3 were found.")
        }
        
        # 5. Generate Consensus Ensemble Biclusters
        ensemble_bicluster_list <- tryCatch({
            mosbi::ensemble_biclusters(coms, all_bics,
                data_matrix,
                row_threshold = .1,
                col_threshold = .1
            )
        }, error = function(e) {
            message("Error generating ensemble biclusters: ", e\$message)
            return(list())
        })
        
        # Close the PDF device
        dev.off()
        
        # Save the final ensemble biclusters
        saveRDS(ensemble_bicluster_list, "ensemble_biclusters.rds")
        
        # Write a CSV summary of the ensemble biclusters
        if (length(ensemble_bicluster_list) > 0) {
            tryCatch({
                summary_list <- list()
                for (i in seq_along(ensemble_bicluster_list)) {
                    bic <- ensemble_bicluster_list[[i]]
                    r_names <- bic@row_names
                    c_names <- bic@col_names
                    summary_list[[i]] <- data.frame(
                        Bicluster_ID = i,
                        Num_Rows = length(r_names),
                        Num_Cols = length(c_names),
                        Rows = paste(r_names, collapse = ";"),
                        Cols = paste(c_names, collapse = ";")
                    )
                }
                summary_df <- do.call(rbind, summary_list)
                write.csv(summary_df, "ensemble_biclusters_summary.csv", row.names = FALSE)
                message("Successfully saved ensemble biclusters summary to 'ensemble_biclusters_summary.csv'")
            }, error = function(e) {
                message("Could not write detailed CSV summary: ", e\$message)
            })
        } else {
            message("No ensemble biclusters were generated.")
        }
        
        message("Pipeline completed successfully. Outputs saved: 'mosbi_analysis_plots.pdf', 'bicluster_network.rds', 'louvain_communities.rds', 'ensemble_biclusters.rds', and 'ensemble_biclusters_summary.csv'.")

    writeLines(c(
        '"BIOC_MOSBI_ENSEMBLE_BICLUSTERING":',
        paste0('    mosbi: ', as.character(packageVersion('mosbi')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ensemble_biclustering.csv versions.yml
    """
}

workflow BIOC_MOSBI_ENSEMBLE_BICLUSTERING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ data_matrix ] ]

    main:
    BIOC_MOSBI_ENSEMBLE_BICLUSTERING(ch_input)

    emit:
    tables   = BIOC_MOSBI_ENSEMBLE_BICLUSTERING.out.tables
    plots    = BIOC_MOSBI_ENSEMBLE_BICLUSTERING.out.plots
    objects  = BIOC_MOSBI_ENSEMBLE_BICLUSTERING.out.objects
    versions = BIOC_MOSBI_ENSEMBLE_BICLUSTERING.out.versions
}
