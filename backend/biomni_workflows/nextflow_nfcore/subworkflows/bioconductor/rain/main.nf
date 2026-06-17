#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: rain — rhythm_detection_analysis
// Detect rhythmic and asymmetric oscillations in time-series expression data.
// Input: expression_matrix.csv
// Container: quay.io/biocontainers/bioconductor-rain:1.44.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: lattice, rain
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Transpose the input matrix so that time points are rows and genes/series are columns
//  * 2. [Core Analysis] Run the rain function specifying the period, sampling interval (deltat), repeats (nr.series or measure.sequence), and peak asymmet
//  * 3. [Core Analysis] Sort or filter results by p-value to identify top rhythmic candidates

nextflow.enable.dsl = 2

process BIOC_RAIN_RHYTHM_DETECTION_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20-slim"

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
    .bm_deps <- c("rain", "lattice")
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
        library(rain)
        library(lattice)
        
        # 1. Read the user input file and construct the input matrix
        # The input file 'expression_matrix.csv' is expected to have genes as rows and samples/timepoints as columns.
        menetRNASeqMouseLiver <- read.csv("expression_matrix.csv", row.names = 1, check.names = FALSE)
        menetRNASeqMouseLiver <- as.matrix(menetRNASeqMouseLiver)
        
        # 2. Run the rain function specifying the period, sampling interval (deltat), 
        # repeats (nr.series), and peak asymmetry borders.
        # Note: t(menetRNASeqMouseLiver) transposes the matrix so that time points are rows and genes are columns.
        results <- rain(t(menetRNASeqMouseLiver), deltat=1, period=ncol(menetRNASeqMouseLiver), nr.series=1,
                        peak.border=c(0.3, 0.7), verbose=FALSE) 
        
        # 3. Sort results by p-value to identify top rhythmic candidates
        best <- head(order(results\$pVal), 10)
        
        # 4. Write named output files for the results
        write.csv(results, "rain_results_all.csv", row.names = TRUE)
        write.csv(results[best, ], "rain_results_top10.csv", row.names = TRUE)
        saveRDS(results, "rain_results.rds")
        
        # 5. Generate and save the visualization plot
        pdf("rhythmic_genes_plot.pdf", width = 10, height = 8)
        tryCatch({
          # Attempt to plot using the exact vignette layout (requires specific dimensions)
          print(xyplot(as.vector(menetRNASeqMouseLiver[best, , drop=FALSE]) 
                  ~rep(seq_len(ncol(menetRNASeqMouseLiver)), each = length(best)) |rownames(menetRNASeqMouseLiver)[best], 
                  scales = list(y = list(relation = 'free')),
                  layout = c(2, max(1, ceiling(length(best) / 2))), type = 'b', pch = 16, xlab = 'time', 
                  ylab = 'expression value', cex.lab = 1))
        }, error = function(e) {
          # Fallback robust plotting if the input dimensions differ from the vignette dataset
          top_data <- menetRNASeqMouseLiver[best, , drop=FALSE]
          df_list <- list()
          for (i in seq_len(nrow(top_data))) {
            df_list[[i]] <- data.frame(
              Gene = rownames(top_data)[i],
              Time = seq_len(ncol(top_data)),
              Expression = as.numeric(top_data[i, ])
            )
          }
          plot_df <- do.call(rbind, df_list)
          print(xyplot(Expression ~ Time | Gene, data = plot_df,
                       scales = list(y = list(relation = 'free')),
                       layout = c(2, max(1, ceiling(length(best) / 2))), type = 'b', pch = 16,
                       xlab = 'Sample Index', ylab = 'Expression Value'))
        })
        dev.off()

    writeLines(c(
        '"BIOC_RAIN_RHYTHM_DETECTION_ANALYSIS":',
        paste0('    rain: ', as.character(packageVersion('rain')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rhythm_detection_analysis.csv versions.yml
    """
}

workflow BIOC_RAIN_RHYTHM_DETECTION_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ expression_matrix.csv ] ]

    main:
    BIOC_RAIN_RHYTHM_DETECTION_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_RAIN_RHYTHM_DETECTION_ANALYSIS.out.tables
    plots    = BIOC_RAIN_RHYTHM_DETECTION_ANALYSIS.out.plots
    objects  = BIOC_RAIN_RHYTHM_DETECTION_ANALYSIS.out.objects
    versions = BIOC_RAIN_RHYTHM_DETECTION_ANALYSIS.out.versions
}
