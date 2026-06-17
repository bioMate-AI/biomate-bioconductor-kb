#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: nempi — prior_guided_perturbation_inference
// Infer unobserved perturbations using a probabilistic prior matrix of potential perturbations.
// Input: data, Gamma
// Container: quay.io/biocontainers/bioconductor-nempi:1.18.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: epiNEM, mnem, nempi
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Construct and normalize the prior matrix Gamma
//  * 2. [Core Analysis] Run nempi guided by the prior matrix Gamma
//  * 3. [Core Analysis] Evaluate the inference accuracy using pifit

nextflow.enable.dsl = 2

process BIOC_NEMPI_PRIOR_GUIDED_PERTURBATION_INFERENCE {
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
    .bm_deps <- c("nempi", "mnem", "epiNEM")
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
        library(nempi)
        library(mnem)
        library(epiNEM)
        
        # ==========================================
        # STAGE 1: Read User Inputs & Setup Prior Matrix Gamma
        # ==========================================
        
        # Read gene expression log odds data
        if (file.exists("data.rds")) {
            data <- readRDS("data.rds")
        } else if (file.exists("data.csv")) {
            data <- as.matrix(read.csv("data.csv", row.names = 1, check.names = FALSE))
        } else {
            stop("Required input file 'data.csv' or 'data.rds' not found in the working directory.")
        }
        
        # Read prior probability matrix of perturbations Gamma
        if (file.exists("Gamma.rds")) {
            Gamma <- readRDS("Gamma.rds")
        } else if (file.exists("Gamma.csv")) {
            Gamma <- as.matrix(read.csv("Gamma.csv", row.names = 1, check.names = FALSE))
        } else {
            stop("Required input file 'Gamma.csv' or 'Gamma.rds' not found in the working directory.")
        }
        
        # Read ground truth simmini object if available (needed for pifit evaluation)
        if (file.exists("simmini.rds")) {
            simmini <- readRDS("simmini.rds")
        } else {
            simmini <- NULL
        }
        
        # Determine number of perturbed genes (P-genes)
        Pgenes <- nrow(Gamma)
        
        # Normalize the prior matrix Gamma as documented
        Gamma <- apply(Gamma, 2, function(x) return(x/sum(x)))
        Gamma[is.na(Gamma)] <- 0
        
        # ==========================================
        # STAGE 2: Run nempi Guided by Prior Matrix Gamma
        # ==========================================
        
        # Run Nested Effects Models-based perturbation inference
        res <- nempi(data, Gamma = Gamma)
        
        # Save the primary inference result
        saveRDS(res, "nempi_result.rds")
        
        # ==========================================
        # STAGE 3: Evaluate Inference Accuracy Using pifit
        # ==========================================
        
        fit <- NULL
        tryCatch({
            if (!is.null(simmini)) {
                fit <- pifit(res, simmini, data)
                print(fit\$auc)
                writeLines(as.character(fit\$auc), "auc.txt")
                saveRDS(fit, "pifit_result.rds")
            }
        }, error = function(e) {
            warning("Evaluation with pifit failed or was skipped: ", e\$message)
        })
        
        # ==========================================
        # STAGE 4: Compute Final Perturbation Matrix & Export Plots
        # ==========================================
        
        # Compute final perturbation matrix Omega
        Omega <- t(mnem::transitive.closure(res\$res\$adj)) %*% res\$Gamma
        write.csv(Omega, "Omega.csv")
        
        # Generate and save diagnostic plots
        pdf("plots.pdf", width = 10, height = 8)
        
        # Plot 1: Input Data Heatmap
        tryCatch({
            epiNEM::HeatmapOP(data, col = "RdBu", cexRow = 0.75, cexCol = 0.75,
                              bordercol = "transparent", xrot = 0,
                              dendrogram = "both")
        }, error = function(e) {
            message("Could not plot data heatmap: ", e\$message)
        })
        
        # Plot 2: Prior Matrix Gamma Heatmap
        tryCatch({
            epiNEM::HeatmapOP(Gamma, col = "RdBu", cexRow = 0.75, cexCol = 0.75,
                              bordercol = "transparent", xrot = 0,
                              dendrogram = "both")
        }, error = function(e) {
            message("Could not plot Gamma heatmap: ", e\$message)
        })
        
        # Plot 3: nempi Result Plot
        tryCatch({
            col_palette <- rgb(seq(0, 1, length.out = 10), seq(1, 0, length.out = 10),
                               seq(1, 0, length.out = 10))
            plot(res, heatlist = list(col = "RdBu"), barlist = list(col = col_palette))
        }, error = function(e) {
            message("Could not plot nempi result: ", e\$message)
        })
        
        # Plot 4: Final Perturbation Matrix Omega Heatmap
        tryCatch({
            epiNEM::HeatmapOP(Omega, col = "RdBu", cexRow = 0.75, cexCol = 0.75,
                              bordercol = "transparent", xrot = 0,
                              dendrogram = "both")
        }, error = function(e) {
            message("Could not plot Omega heatmap: ", e\$message)
        })
        
        dev.off()

    writeLines(c(
        '"BIOC_NEMPI_PRIOR_GUIDED_PERTURBATION_INFERENCE":',
        paste0('    nempi: ', as.character(packageVersion('nempi')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_prior_guided_perturbation_inference.csv versions.yml
    """
}

workflow BIOC_NEMPI_PRIOR_GUIDED_PERTURBATION_INFERENCE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ data, Gamma ] ]

    main:
    BIOC_NEMPI_PRIOR_GUIDED_PERTURBATION_INFERENCE(ch_input)

    emit:
    tables   = BIOC_NEMPI_PRIOR_GUIDED_PERTURBATION_INFERENCE.out.tables
    plots    = BIOC_NEMPI_PRIOR_GUIDED_PERTURBATION_INFERENCE.out.plots
    objects  = BIOC_NEMPI_PRIOR_GUIDED_PERTURBATION_INFERENCE.out.objects
    versions = BIOC_NEMPI_PRIOR_GUIDED_PERTURBATION_INFERENCE.out.versions
}
