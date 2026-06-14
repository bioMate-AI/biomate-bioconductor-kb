#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: DeMixT — demixt_bulk_deconvolution
// Perform two- or three-component deconvolution on bulk transcriptomic data (RNA-seq or microarray) using the log-normal model to estimate proportions and deconvo
// Input: PRAD, Normal.id, Tumor.id
// Container: quay.io/biocontainers/bioconductor-demixt:1.26.0--r45ha27e39d_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: DeMixT, SummarizedExperiment, psych
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Load Input Data
//  * 2. [Visualization & Output] Preprocess and Filter Data
//  * 3. [Visualization & Output] Create SummarizedExperiment Objects
//  * 4. [Visualization & Output] Run DeMixT Deconvolution across Parameter Grid
//  * 5. [Visualization & Output] Identify Optimal Parameters and Extract Results
//  * 6. [Visualization & Output] Save Outputs and Generate Plots

nextflow.enable.dsl = 2

process BIOC_DEMIXT_DEMIXT_BULK_DECONVOLUTION {
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
    .bm_deps <- c("DeMixT", "SummarizedExperiment")
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
        l        library(SummarizedExperiment)
ibrary(DeMixT)
        
        # Helper function to load user input files robustly
        load_input <- function(name) {
          if (file.exists(paste0(name, ".rds"))) {
            message("Loading ", name, " from RDS file...")
            return(readRDS(paste0(name, ".rds")))
          } else if (file.exists(paste0(name, ".csv"))) {
            message("Loading ", name, " from CSV file...")
            df <- read.csv(paste0(name, ".csv"), row.names = 1, check.names = FALSE)
            if (ncol(df) == 1 && name != "PRAD") {
              return(as.vector(df[[1]]))
            }
            return(as.matrix(df))
          } else if (file.exists(paste0(name, ".tsv"))) {
            message("Loading ", name, " from TSV file...")
            df <- read.delim(paste0(name, ".tsv"), row.names = 1, check.names = FALSE)
            if (ncol(df) == 1 && name != "PRAD") {
              return(as.vector(df[[1]]))
            }
            return(as.matrix(df))
          } else if (file.exists(name)) {
            message("Loading ", name, " directly...")
            try_rds <- tryCatch({ readRDS(name) }, error = function(e) NULL)
            if (!is.null(try_rds)) return(try_rds)
            try_csv <- tryCatch({
              df <- read.csv(name, row.names = 1, check.names = FALSE)
              if (ncol(df) == 1 && name != "PRAD") return(as.vector(df[[1]]))
              as.matrix(df)
            }, error = function(e) NULL)
            if (!is.null(try_csv)) return(try_csv)
          }
          stop(paste("Error: Could not find or read input file for:", name))
        }
        
        # ----------------------------------------------------------------------
        # --- Load Input Data ---
        # ----------------------------------------------------------------------
        if (file.exists("PRAD.RData")) {
          message("Loading data from PRAD.RData...")
          load("PRAD.RData")
        } else {
          PRAD <- load_input("PRAD")
          Normal.id <- load_input("Normal.id")
          Tumor.id <- load_input("Tumor.id")
        }
        
        # Ensure sample IDs are character vectors
        Normal.id <- as.character(Normal.id)
        Tumor.id <- as.character(Tumor.id)
        
        # Ensure PRAD is a matrix
        PRAD <- as.matrix(PRAD)
        
        # Subset PRAD to only include the specified normal and tumor samples
        PRAD <- PRAD[, c(Normal.id, Tumor.id)]
        
        # ----------------------------------------------------------------------
        # --- Preprocess and Filter Data ---
        # ----------------------------------------------------------------------
        selected.genes = 9000
        cutoff_normal_range = c(0.1, 1.0)
        cutoff_tumor_range = c(0, 2.5)
        cutoff_step = 0.1
        
        preprocessed_data = DeMixT_preprocessing(PRAD, Normal.id, Tumor.id, selected.genes, cutoff_normal_range, cutoff_tumor_range, cutoff_step)
        PRAD_filter = preprocessed_data\$count.matrix
        sd_cutoff_normal = preprocessed_data\$sd_cutoff_normal
        sd_cutoff_tumor = preprocessed_data\$sd_cutoff_tumor
        
        # ----------------------------------------------------------------------
        # --- Create SummarizedExperiment Objects ---
        # ----------------------------------------------------------------------
        set.seed(1234)
        data.Y = SummarizedExperiment(assays = list(counts = PRAD_filter[, Tumor.id]))
        data.N1 <- SummarizedExperiment(assays = list(counts = PRAD_filter[, Normal.id]))
        
        # ----------------------------------------------------------------------
        # --- Run DeMixT Deconvolution across Parameter Grid ---
        # ----------------------------------------------------------------------
        nspikesin_list = c(0, 5, 10)
        ngene.selected_list = c(500, 1000, 1500, 2500)
        
        PiT_GS_PRAD <- c()
        row_names <- c()
        
        for(nspikesin in nspikesin_list){
          for(ngene.selected in ngene.selected_list){
            name = paste("PRAD_demixt_GS_res_nspikesin", nspikesin, "ngene.selected", ngene.selected, sep = "_")
            name = paste(name, ".RData", sep = "")
            
            message("Running DeMixT for nspikein = ", nspikesin, ", ngene.selected = ", ngene.selected, "...")
            
            res_run <- tryCatch({
              DeMixT(data.Y = data.Y, 
                     data.N1 = data.N1, 
                     ngene.selected.for.pi = ngene.selected, 
                     ngene.Profile.selected = ngene.selected, 
                     filter.sd = 0.7, 
                     gene.selection.method = "GS", 
                     nspikein = nspikesin)
            }, error = function(e) {
              message("Warning: DeMixT run failed for nspikein = ", nspikesin, ", ngene.selected = ", ngene.selected, ". Error: ", e\$message)
              NULL
            })
            
            if (!is.null(res_run)) {
              save(res_run, file = name)
              PiT_GS_PRAD <- cbind(PiT_GS_PRAD, res_run\$pi[2, ])
              row_names <- c(row_names, paste(nspikesin, ngene.selected, sep = "_"))
            }
          }
        }
        
        if (length(row_names) > 0) {
          colnames(PiT_GS_PRAD) <- row_names
        } else {
          stop("Error: All DeMixT parameter grid runs failed.")
        }
        
        # ----------------------------------------------------------------------
        # --- Identify Optimal Parameters and Extract Results ---
        # ----------------------------------------------------------------------
        PiT_GS_PRAD <- as.data.frame(PiT_GS_PRAD)
        Spearman_correlations <- list()
        
        for(entry_1 in colnames(PiT_GS_PRAD)) {
          cor.values <- c()
          for (entry_2 in colnames(PiT_GS_PRAD)) {
            if (entry_1 == entry_2) next
            cor.values <- c(cor.values, cor(PiT_GS_PRAD[, entry_1], PiT_GS_PRAD[, entry_2], method = "spearman"))
          }
          Spearman_correlations[[entry_1]] <- mean(cor.values, na.rm = TRUE)
        }
        
        Spearman_correlations <- unlist(Spearman_correlations)
        
        # Select the optimal parameter combination with the highest average correlation
        best_combination <- names(Spearman_correlations)[which.max(Spearman_correlations)]
        message("Optimal parameter combination identified: ", best_combination)
        
        # Load the optimal results
        best_file <- paste("PRAD_demixt_GS_res_nspikesin", gsub("_", "_ngene.selected_", best_combination), sep = "_")
        best_file <- paste(best_file, ".RData", sep = "")
        load(best_file)
        
        # ----------------------------------------------------------------------
        # --- Save Outputs and Generate Plots ---
        # ----------------------------------------------------------------------
        # Save estimated proportions
        write.csv(res_run\$pi, file = "estimated_proportions.csv", row.names = TRUE)
        
        # Save deconvolved expression profiles
        if (!is.null(res_run\$ExprT)) {
          write.csv(res_run\$ExprT, file = "deconvolved_expression_tumor.csv", row.names = TRUE)
        }
        if (!is.null(res_run\$ExprN1)) {
          write.csv(res_run\$ExprN1, file = "deconvolved_expression_normal.csv", row.names = TRUE)
        }
        
        # Save the optimal deconvolution object
        saveRDS(res_run, file = "optimal_deconvolution_results.rds")
        
        # Generate pairwise correlation plot
        pdf("pairwise_correlations.pdf", width = 10, height = 10)
        if (requireNamespace("psych", quietly = TRUE)) {
          psych::pairs.panels(PiT_GS_PRAD, method = "spearman", 
                              hist.col = "#00AFBB", density = TRUE, 
                              ellipses = TRUE, 
                              main = 'Correlations of Tumor Proportions with GS', 
                              xlim = c(0,1), ylim = c(0,1))
        } else {
          pairs(PiT_GS_PRAD, main = "Correlations of Tumor Proportions with GS", xlim = c(0,1), ylim = c(0,1))
        }
        dev.off()
        
        message("Pipeline completed successfully. Outputs saved to working directory.")

    writeLines(c(
        '"BIOC_DEMIXT_DEMIXT_BULK_DECONVOLUTION":',
        paste0('    DeMixT: ', as.character(packageVersion('DeMixT')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_demixt_bulk_deconvolution.csv versions.yml
    """
}

workflow BIOC_DEMIXT_DEMIXT_BULK_DECONVOLUTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ PRAD, Normal.id, Tumor.id ] ]

    main:
    BIOC_DEMIXT_DEMIXT_BULK_DECONVOLUTION(ch_input)

    emit:
    tables   = BIOC_DEMIXT_DEMIXT_BULK_DECONVOLUTION.out.tables
    plots    = BIOC_DEMIXT_DEMIXT_BULK_DECONVOLUTION.out.plots
    objects  = BIOC_DEMIXT_DEMIXT_BULK_DECONVOLUTION.out.objects
    versions = BIOC_DEMIXT_DEMIXT_BULK_DECONVOLUTION.out.versions
}
