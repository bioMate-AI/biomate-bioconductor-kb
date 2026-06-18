#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: clst — threshold_based_classification
// Perform supervised classification of query samples and leave-one-out cross-validation using a pairwise distance matrix and group labels.
// Input: dmat, groups, dvect
// Container: quay.io/biocontainers/bioconductor-clst:1.58.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: clst
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Calculate optimal separation threshold using findThreshold
//  * 2. [Visualization & Output] Visualize distances and threshold using plotDistances and scaleDistPlot
//  * 3. [Core Analysis] Classify a query sample using classify or pull
//  * 4. [Core Analysis] Print classification results using printClst
//  * 5. [Core Analysis] Perform leave-one-out cross-validation using lapply and classify

nextflow.enable.dsl = 2

process BIOC_CLST_THRESHOLD_BASED_CLASSIFICATION {
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
    .bm_deps <- c("clst")
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
    
    # Load required library
    library(clst)
    
    # Helper function to robustly find and read input files
    find_and_read <- function(base_name, is_matrix = FALSE, is_factor = FALSE) {
      possible_files <- c(
        base_name,
        paste0(base_name, ".rds"),
        paste0(base_name, ".csv"),
        paste0(base_name, ".tsv"),
        paste0(base_name, ".txt")
      )
      file_to_read <- NULL
      for (f in possible_files) {
        if (file.exists(f)) {
          file_to_read <- f
          break
        }
      }
      if (is.null(file_to_read)) {
        stop(paste("Error: Could not find input file for", base_name))
      }
      
      if (grepl("\\\\.rds\$", file_to_read, ignore.case = TRUE)) {
        obj <- readRDS(file_to_read)
      } else {
        obj <- tryCatch({
          if (is_matrix) {
            df_mat <- read.csv(file_to_read, header = TRUE, row.names = 1, check.names = FALSE)
            as.matrix(df_mat)
          } else {
            df <- read.csv(file_to_read, header = FALSE, stringsAsFactors = FALSE)
            if (ncol(df) == 1) {
              df[[1]]
            } else if (nrow(df) == 1) {
              as.vector(t(df))
            } else {
              as.matrix(df)
            }
          }
        }, error = function(e) {
          scan(file_to_read, what = character(), quiet = TRUE)
        })
      }
      
      if (is_matrix) {
        obj <- as.matrix(obj)
      }
      if (is_factor) {
        obj <- as.factor(obj)
      }
      return(obj)
    }
    
    # 1. Load inputs from the working directory
    dmat <- find_and_read("dmat", is_matrix = TRUE)
    mode(dmat) <- "numeric"
    
    groups <- find_and_read("groups", is_factor = TRUE)
    
    dvect <- find_and_read("dvect")
    dvect <- as.numeric(dvect)
    
    # Safeguard: Ensure dvect has names matching dmat columns
    if (is.null(names(dvect)) && ncol(dmat) == length(dvect)) {
      names(dvect) <- colnames(dmat)
    }
    
    # 2. Calculate optimal separation threshold using findThreshold
    thresh <- findThreshold(dmat, groups, type="mutinfo")
    saveRDS(thresh, "thresh.rds")
    
    thresh2 <- findThreshold(dmat, groups, type="mutinfo", prob=NA)
    saveRDS(thresh2, "thresh2.rds")
    
    # Write threshold intervals to a text file
    writeLines(
      c(
        "Threshold 1 Interval:",
        capture.output(print(thresh\$interval)),
        "\nThreshold 2 Interval (prob=NA):",
        capture.output(print(thresh2\$interval))
      ),
      "threshold_intervals.txt"
    )
    
    # 3. Visualize distances and threshold using plotDistances and scaleDistPlot
    ii <- c(1, min(125, length(groups)))
    
    pdf("scale_dist_plot_initial.pdf")
    plot(scaleDistPlot(dmat, groups, indices=ii, O=ii))
    dev.off()
    
    pdf("plot_distances_thresh.pdf")
    plot(do.call(plotDistances, thresh))
    dev.off()
    
    pdf("plot_distances_thresh2.pdf")
    plot(do.call(plotDistances, thresh2))
    dev.off()
    
    # 4. Classify the user-provided query sample
    cc_user_query <- classify(dmat, groups, dvect)
    cat_out_user <- capture.output(printClst(cc_user_query))
    writeLines(cat_out_user, "user_query_classification.txt")
    
    # 5. Replicate vignette's single-sample classification steps with dynamic indices
    ind1 <- 1
    if (length(groups) >= ind1) {
      species1 <- gettextf('I. %s', groups[ind1])
      dmat1 <- dmat[-ind1, -ind1, drop=FALSE]
      groups1 <- groups[-ind1]
      dvect1 <- dmat[ind1, -ind1]
      cc1 <- classify(dmat1, groups1, dvect1)
      cat_out1 <- capture.output({
        cat('class of "unknown" sample is', species1, "\n")
        printClst(cc1)
      })
      writeLines(cat_out1, "vignette_sample1_classification.txt")
    }
    
    ind2 <- min(125, length(groups))
    if (length(groups) >= ind2) {
      species2 <- gettextf('I. %s', groups[ind2])
      pp <- pull(dmat, groups, ind2)
      cc2 <- do.call(classify, pp)
      cat_out2 <- capture.output({
        cat(paste('class of "unknown" sample is', species2), "\n")
        printClst(cc2)
      })
      writeLines(cat_out2, "vignette_sample2_classification.txt")
    }
    
    # 6. Perform leave-one-out cross-validation (Default minScore)
    loo <- lapply(seq_along(groups), function(i){
      do.call(classify, pull(dmat, groups, i))
    })
    saveRDS(loo, "loo_default.rds")
    
    matches <- lapply(loo, function(x) rev(x)[[1]]\$matches)
    result <- sapply(matches, paste, collapse='-')
    tab1 <- table(ifelse(result=='','no match',result), groups)
    write.csv(as.data.frame.matrix(tab1), "loo_table_default.csv")
    
    confusion <- sapply(matches, length) > 1
    no_match <- sapply(matches, length) < 1
    
    pdf("scale_dist_plot_loo_default.pdf")
    plot(scaleDistPlot(dmat, groups, fill=confusion, O=confusion, X=no_match))
    dev.off()
    
    # 7. Perform leave-one-out cross-validation (minScore = 0.65)
    loo2 <- lapply(seq_along(groups), function(i){
      do.call(classify, c(pull(dmat, groups, i), minScore=0.65))
    })
    saveRDS(loo2, "loo_minScore_0.65.rds")
    
    matches2 <- lapply(loo2, function(x) rev(x)[[1]]\$matches)
    result2 <- sapply(matches2, paste, collapse='-')
    tab2 <- table(ifelse(result2=='','no match',result2), groups)
    write.csv(as.data.frame.matrix(tab2), "loo_table_minScore_0.65.csv")
    
    confusion2 <- sapply(matches2, length) > 1
    no_match2 <- sapply(matches2, length) < 1
    
    pdf("scale_dist_plot_loo_minScore_0.65.pdf")
    plot(scaleDistPlot(dmat, groups, fill=confusion2, O=confusion2,
                        X=no_match2, indices=no_match2))
    dev.off()
    
    # Print classification of a specific LOO sample (index 118 or dynamic equivalent)
    target_ind <- min(118, length(groups))
    if (length(loo2) >= target_ind) {
      cat_out_loo_sample <- capture.output(printClst(loo2[[target_ind]]))
      writeLines(cat_out_loo_sample, "loo_sample_classification.txt")
    }

    writeLines(c(
        '"BIOC_CLST_THRESHOLD_BASED_CLASSIFICATION":',
        paste0('    clst: ', as.character(packageVersion('clst')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_threshold_based_classification.csv versions.yml
    """
}

workflow BIOC_CLST_THRESHOLD_BASED_CLASSIFICATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ dmat, groups, dvect ] ]

    main:
    BIOC_CLST_THRESHOLD_BASED_CLASSIFICATION(ch_input)

    emit:
    tables   = BIOC_CLST_THRESHOLD_BASED_CLASSIFICATION.out.tables
    plots    = BIOC_CLST_THRESHOLD_BASED_CLASSIFICATION.out.plots
    objects  = BIOC_CLST_THRESHOLD_BASED_CLASSIFICATION.out.objects
    versions = BIOC_CLST_THRESHOLD_BASED_CLASSIFICATION.out.versions
}
