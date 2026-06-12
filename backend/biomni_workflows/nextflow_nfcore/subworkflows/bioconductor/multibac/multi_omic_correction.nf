#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: MultiBaC — multi_omic_correction
// Correct batch effects across multi-omic datasets distributed across different batches using a common omic.
// Input: A.rna, A.gro, B.rna, B.ribo, C.rna, C.par
// Container: quay.io/biocontainers/bioconductor-multibac:1.20.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: MultiAssayExperiment, MultiBaC, ggplot2, ropls
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Create the multi-omic mbac object using createMbac
//  * 2. [Core Analysis] Run the MultiBaC wrapper function to fit PLS models, predict missing omics, and perform batch correction
//  * 3. [Core Analysis] Alternatively, run step-by-step using genModelList, genMissingOmics, and batchCorrection
//  * 4. [Visualization & Output] Visualize results using the plot method

nextflow.enable.dsl = 2

process BIOC_MULTIBAC_MULTI_OMIC_CORRECTION {
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
    .bm_deps <- c("MultiBaC", "MultiAssayExperiment", "ggplot2", "ropls", "SummarizedExperiment")
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
          library(SummarizedExperiment)
      library(MultiBaC)
        library(MultiAssayExperiment)
        library(ggplot2)
        library(ropls)
        
        # Helper function to read input matrices robustly from the working directory
        read_input_matrix <- function(base_name) {
          extensions <- c("", ".rds", ".csv", ".tsv", ".txt")
          for (ext in extensions) {
            file_path <- paste0(base_name, ext)
            if (file.exists(file_path)) {
              if (grepl("\\\\.rds\$", file_path, ignore.case = TRUE)) {
                return(as.matrix(readRDS(file_path)))
              } else if (grepl("\\\\.csv\$", file_path, ignore.case = TRUE)) {
                return(as.matrix(read.csv(file_path, row.names = 1, check.names = FALSE)))
              } else if (grepl("\\\\.(tsv|txt)\$", file_path, ignore.case = TRUE)) {
                return(as.matrix(read.delim(file_path, row.names = 1, check.names = FALSE)))
              } else {
                try_read <- try(as.matrix(read.table(file_path, header = TRUE, row.names = 1, check.names = FALSE)), silent = TRUE)
                if (!inherits(try_read, "try-error")) {
                  return(try_read)
                }
              }
            }
          }
          stop(paste("Required input file not found for base name:", base_name))
        }
        
        # Helper function to extract experimental conditions from column names
        extract_conditions <- function(cnames, n_cols) {
          if (is.null(cnames)) return(rep("Cond1", n_cols))
          
          # Remove common replicate suffixes (e.g., "_1", ".1", "_rep1", "rep1")
          # Requires punctuation or "rep"/"r" to avoid stripping numbers from conditions like "Th17"
          conds <- gsub("([_\\\\.-]+(rep|r)?|(rep|r))\\\\d+\$", "", cnames, ignore.case = TRUE)
          
          # Remove omic/batch prefixes (e.g., "A.rna_") to ensure conditions match across batches
          conds <- gsub("^[A-Za-z0-9]+\\\\.[A-Za-z0-9]+_", "", conds)
          
          # Fallback for empty strings
          conds[conds == ""] <- "Cond1"
          
          return(conds)
        }
        
        # Read user input files
        A.rna  <- read_input_matrix("A.rna")
        A.gro  <- read_input_matrix("A.gro")
        B.rna  <- read_input_matrix("B.rna")
        B.ribo <- read_input_matrix("B.ribo")
        C.rna  <- read_input_matrix("C.rna")
        C.par  <- read_input_matrix("C.par")
        
        # Step 1: Create the multi-omic mbac object using createMbac
        my_mbac <- createMbac (inputOmics = list(A.rna, A.gro, 
                                                       B.rna, B.ribo, 
                                                       C.rna, C.par), 
                            batchFactor = c("A", "A", 
                                            "B", "B", 
                                            "C", "C"),
                            experimentalDesign = list("A" = extract_conditions(colnames(A.rna), ncol(A.rna)),
                                               "B" = extract_conditions(colnames(B.rna), ncol(B.rna)),
                                               "C" = extract_conditions(colnames(C.rna), ncol(C.rna))),
                            omicNames = c("RNA", "GRO", 
                                          "RNA", "RIBO", 
                                          "RNA", "PAR"))
        
        # Step 2: Run the MultiBaC wrapper function to fit PLS models, predict missing omics, and perform batch correction
        my_final_mbac <- MultiBaC (my_mbac,
                  				test.comp = NULL, scale = FALSE, 
                  				center = TRUE, crossval = NULL, 
                  				Interaction = TRUE,
                  				Variability = 0.9,
                  				showplot = TRUE,
                  				showinfo = TRUE)
        
        # Step 3: Alternatively, run step-by-step using genModelList, genMissingOmics, and batchCorrection
        my_mbac_2 <- genModelList (my_mbac, test.comp = NULL, 
                      			  scale = FALSE, center = TRUE,
                      			  crossval = NULL,
                      			  showinfo = TRUE)
        
        multiBatchDesign <- genMissingOmics(my_mbac_2)
        
        my_finalwise_mbac <- batchCorrection(my_mbac_2, 
                                             multiBatchDesign = multiBatchDesign,
                                             Interaction = TRUE,
                                             Variability = 0.90)
        
        # Step 4: Visualize results using the plot method and save to PDF
        options(device.ask.default = FALSE)
        if (names(dev.cur()) != "null device") {
          devAskNewPage(ask = FALSE)
        }
        
        pdf("multibac_plots.pdf", width = 10, height = 8)
        
        tryCatch({
          plot (my_final_mbac, typeP = "inner", comp2plot = c(1,2))
        }, error = function(e) {
          warning("Failed to plot inner correlation: ", e\$message)
        })
        
        tryCatch({
          plot (my_final_mbac, typeP = "batch")
        }, error = function(e) {
          warning("Failed to plot batch effect estimation: ", e\$message)
        })
        
        tryCatch({
          plot (my_final_mbac, typeP = "pca.org",
                cex.axis = 1, cex.lab = 1, cex = 3, bty = "L", 
                cex.main = 1.2, pch = 19)
        }, error = function(e) {
          warning("Failed to plot original PCA: ", e\$message)
        })
        
        tryCatch({
          plot (my_final_mbac, typeP = "pca.cor", 
                cex.axis = 1, cex.lab = 1, cex = 3, bty = "L", 
                cex.main = 1.2, pch = 19)
        }, error = function(e) {
          warning("Failed to plot corrected PCA: ", e\$message)
        })
        
        dev.off()
        
        # Save meaningful results to RDS files
        saveRDS(my_final_mbac, "my_final_mbac.rds")
        saveRDS(my_finalwise_mbac, "my_finalwise_mbac.rds")
        
        # Export corrected data matrices as CSV files
        if (!is.null(my_final_mbac\$CorrectedData)) {
          for (batch_name in names(my_final_mbac\$CorrectedData)) {
            mae <- my_final_mbac\$CorrectedData[[batch_name]]
            for (omic_name in names(experiments(mae))) {
              mat <- as.matrix(assay(mae, omic_name))
              write.csv(mat, file = paste0("corrected_", batch_name, "_", omic_name, ".csv"))
            }
          }
        }

    writeLines(c(
        '"BIOC_MULTIBAC_MULTI_OMIC_CORRECTION":',
        paste0('    MultiBaC: ', as.character(packageVersion('MultiBaC')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_multi_omic_correction.csv versions.yml
    """
}

workflow BIOC_MULTIBAC_MULTI_OMIC_CORRECTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ A.rna, A.gro, B.rna, B.ribo, C.rna, C.par ] ]

    main:
    BIOC_MULTIBAC_MULTI_OMIC_CORRECTION(ch_input)

    emit:
    tables   = BIOC_MULTIBAC_MULTI_OMIC_CORRECTION.out.tables
    plots    = BIOC_MULTIBAC_MULTI_OMIC_CORRECTION.out.plots
    objects  = BIOC_MULTIBAC_MULTI_OMIC_CORRECTION.out.objects
    versions = BIOC_MULTIBAC_MULTI_OMIC_CORRECTION.out.versions
}
