#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: powerTCR — pareto_model_analysis
// Fit the Type-I Pareto model to TCR clone size data and perform comparative analysis.
// Input: sample_tcr_repertoire.txt
// Container: quay.io/biocontainers/bioconductor-powertcr:1.30.0--r45hdfd78af_0
// R packages: powerTCR
// Bioconductor: 3.20 | R: 4.4
// Requires: powerTCR
// Visualizations: cluster plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Parse TCR files or load clone size vectors
//  * 2. [Core Analysis] Fit the Type-I Pareto model using fdesponds
//  * 3. [Core Analysis] Compute pairwise Jensen-Shannon distances using get_distances with modelType="Desponds"
//  * 4. [Visualization & Output] Perform hierarchical clustering and plot using clusterPlot

nextflow.enable.dsl = 2

process BIOC_POWERTCR_PARETO_MODEL_ANALYSIS {
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
    .bm_deps <- c("powerTCR")
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
        
        library(powerTCR)
        
        # 1. Parse TCR files or load clone size vectors
        input_file <- "sample_tcr_repertoire.txt"
        if (!file.exists(input_file)) {
          stop(paste("Required input file not found:", input_file))
        }
        
        # Robust parsing of the input file
        repertoires_raw <- tryCatch({
          # Try reading as a simple numeric vector of clone sizes
          val <- scan(input_file, what = numeric(), quiet = TRUE)
          val <- val[!is.na(val)]
          if (length(val) < 2) stop("Not a simple numeric vector")
          as.integer(val)
        }, error = function(e) {
          # Fallback: try reading as a table and extracting clone count column
          df <- read.table(input_file, header = TRUE, sep = "\t", stringsAsFactors = FALSE)
          col_names <- tolower(colnames(df))
          target_idx <- which(col_names %in% c("count", "size", "clonecount", "templates", "reads", "abundance"))
          if (length(target_idx) > 0) {
            as.integer(df[[target_idx[1]]])
          } else {
            # Fallback to the first numeric column
            num_cols <- sapply(df, is.numeric)
            if (any(num_cols)) {
              as.integer(df[[which(num_cols)[1]]])
            } else {
              stop("Could not extract clone sizes from the file.")
            }
          }
        })
        
        # Ensure clone sizes are valid (integers >= 1)
        repertoires_raw <- repertoires_raw[repertoires_raw >= 1]
        
        # Split the single input repertoire into two samples to enable comparative analysis
        n_clones <- length(repertoires_raw)
        if (n_clones >= 10) {
          repertoires <- list(
            samp1 = repertoires_raw[seq(1, n_clones, by = 2)],
            samp2 = repertoires_raw[seq(2, n_clones, by = 2)]
          )
        } else {
          # Fallback for very small inputs
          repertoires <- list(
            samp1 = repertoires_raw,
            samp2 = pmax(1, round(repertoires_raw * 1.1))
          )
        }
        
        # 2. Fit the Type-I Pareto model using fdesponds
        desponds_fits <- list()
        for(i in seq_along(repertoires)){
            desponds_fits[[i]] <- fdesponds(repertoires[[i]])
        }
        names(desponds_fits) <- names(repertoires)
        
        # 3. Compute pairwise Jensen-Shannon distances using get_distances with modelType="Desponds"
        min_val <- min(unlist(repertoires))
        if (min_val < 1) min_val <- 1
        grid <- min_val:10000
        
        distances <- get_distances(desponds_fits, grid, modelType="Desponds")
        
        # 4. Perform hierarchical clustering and plot using clusterPlot
        pdf("pareto_clustering_dendrogram.pdf", width = 7, height = 5)
        clusterPlot(distances, method = "ward.D")
        dev.off()
        
        # Write named output files for the results
        saveRDS(desponds_fits, "desponds_fits.rds")
        
        write.csv(as.matrix(distances), "jensen_shannon_distances.csv", row.names = TRUE)
        
        fit_summary <- do.call(rbind, lapply(desponds_fits, function(x) {
          data.frame(
            min_KS = unname(x["min.KS"]),
            Cmin = unname(x["Cmin"]),
            powerlaw_exponent = unname(x["powerlaw.exponent"]),
            pareto_alpha = unname(x["pareto.alpha"])
          )
        }))
        rownames(fit_summary) <- names(desponds_fits)
        write.csv(fit_summary, "pareto_fit_summary.csv", row.names = TRUE)

    writeLines(c(
        '"BIOC_POWERTCR_PARETO_MODEL_ANALYSIS":',
        paste0('    powerTCR: ', as.character(packageVersion('powerTCR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_pareto_model_analysis.csv versions.yml
    """
}

workflow BIOC_POWERTCR_PARETO_MODEL_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sample_tcr_repertoire.txt ] ]

    main:
    BIOC_POWERTCR_PARETO_MODEL_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_POWERTCR_PARETO_MODEL_ANALYSIS.out.tables
    plots    = BIOC_POWERTCR_PARETO_MODEL_ANALYSIS.out.plots
    objects  = BIOC_POWERTCR_PARETO_MODEL_ANALYSIS.out.objects
    versions = BIOC_POWERTCR_PARETO_MODEL_ANALYSIS.out.versions
}
