#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: MultiBaC — single_omic_correction
// Correct batch effects and reduce systematic noise in a single-omic dataset across multiple batches.
// Input: A.rna, B.rna, C.rna
// Container: quay.io/biocontainers/bioconductor-multibac:1.20.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: MultiAssayExperiment, MultiBaC
// Visualizations: PCA plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Create the mbac S3 object using createMbac
//  * 2. [Core Analysis] Run batch correction and/or noise reduction using ARSyNbac
//  * 3. [Visualization & Output] Plot the corrected data using the plot method

nextflow.enable.dsl = 2

process BIOC_MULTIBAC_SINGLE_OMIC_CORRECTION {
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
    .bm_deps <- c("MultiBaC", "MultiAssayExperiment", "SummarizedExperiment")
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
    library(MultiBaC)
    library(SummarizedExperiment)
    library(MultiAssayExperiment)
    
    # Helper function to read input matrices robustly
    read_input_matrix <- function(file_path) {
      if (!file.exists(file_path)) {
        stop(paste("Required input file not found:", file_path))
      }
      
      # Attempt reading as RDS first
      mat <- tryCatch({
        readRDS(file_path)
      }, error = function(e) {
        NULL
      })
      
      if (!is.null(mat)) {
        return(as.matrix(mat))
      }
      
      # Attempt reading as CSV
      mat <- tryCatch({
        read.csv(file_path, row.names = 1, check.names = FALSE)
      }, error = function(e) {
        NULL
      })
      
      if (!is.null(mat)) {
        return(as.matrix(mat))
      }
      
      # Attempt reading as TSV/tabular
      mat <- tryCatch({
        read.table(file_path, header = TRUE, row.names = 1, sep = "\t", check.names = FALSE)
      }, error = function(e) {
        NULL
      })
      
      if (!is.null(mat)) {
        return(as.matrix(mat))
      }
      
      stop(paste("Failed to parse matrix from file:", file_path))
    }
    
    # Helper function to extract condition from column names dynamically
    get_condition <- function(mat) {
      cols <- colnames(mat)
      if (is.null(cols)) {
        return(rep("Unknown", ncol(mat)))
      }
      # Remove trailing replicate identifiers (e.g., _1, _2, _rep1)
      conds <- gsub("_([Rr]ep)?[0-9]+\$", "", cols)
      # Remove leading batch prefix up to the first underscore (e.g., A.rna_)
      conds <- gsub("^[^_]+_", "", conds)
      # Fallback for empty strings
      conds[conds == ""] <- "Unknown"
      return(conds)
    }
    
    # 1. Read User Inputs
    A.rna <- read_input_matrix("A.rna")
    B.rna <- read_input_matrix("B.rna")
    C.rna <- read_input_matrix("C.rna")
    
    # Extract experimental designs dynamically based on input dimensions and names
    cond_A <- get_condition(A.rna)
    cond_B <- get_condition(B.rna)
    cond_C <- get_condition(C.rna)
    
    # Define custom plotting parameters dynamically to match user data dimensions
    batch_names <- c("A", "B", "C")
    batch_colors <- c("brown2", "dodgerblue", "forestgreen")
    
    all_conds <- unique(c(cond_A, cond_B, cond_C))
    available_pchs <- c(19, 1, 17, 15, 8, 4, 3, 18, 2, 5, 6)
    cond_pchs <- available_pchs[1:length(all_conds)]
    if (any(is.na(cond_pchs))) {
      cond_pchs <- rep(available_pchs, length.out = length(all_conds))
    }
    
    custom_pch <- c(
      cond_pchs[match(cond_A, all_conds)],
      cond_pchs[match(cond_B, all_conds)],
      cond_pchs[match(cond_C, all_conds)]
    )
    
    legend_text <- c("Color: Batch", batch_names, "Shape: Cond.", all_conds)
    legend_pch <- c(NA, rep(15, length(batch_names)), NA, cond_pchs)
    legend_col <- c(NA, batch_colors, NA, rep("black", length(all_conds)))
    
    # 2. Create the mbac S3 object
    data_RNA <- createMbac (inputOmics = list(A.rna, B.rna, C.rna), 
                        batchFactor = c("A", "B", "C"),
                        experimentalDesign = list("A" = cond_A,
                                                  "B" = cond_B,
                                                  "C" = cond_C),
                        omicNames = "RNA")
    
    # 3. Run batch correction and noise reduction
    arsyn_1 <- ARSyNbac(data_RNA, modelName = "RNA", Variability = 0.95, 
                     batchEstimation = TRUE, filterNoise = FALSE, Interaction = FALSE)
    
    # 4. Plot the corrected data and save to PDF
    pdf("batch_correction_pca.pdf", width = 12, height = 7)
    par(mfrow = c(1, 2))
    plot(arsyn_1, typeP="pca.cor", bty = "L",
         pch = custom_pch, cex = 3, col.per.group = batch_colors,
         legend.text = legend_text,
         args.legend = list("x" = "topright",
                            "pch" = legend_pch,
                            "col" = legend_col,
                            "bty" = "n",
                            "cex" = 1.2))
    dev.off()
    
    # 5. Save meaningful outputs
    # Save the full corrected mbac object
    saveRDS(arsyn_1, "arsyn_corrected_mbac.rds")
    
    # Extract and save corrected matrices for each batch
    corrected_A <- as.matrix(assay(arsyn_1\$CorrectedData\$A))
    corrected_B <- as.matrix(assay(arsyn_1\$CorrectedData\$B))
    corrected_C <- as.matrix(assay(arsyn_1\$CorrectedData\$C))
    
    write.csv(corrected_A, "corrected_A_rna.csv", row.names = TRUE)
    write.csv(corrected_B, "corrected_B_rna.csv", row.names = TRUE)
    write.csv(corrected_C, "corrected_C_rna.csv", row.names = TRUE)
    
    message("Pipeline completed successfully. Outputs saved to working directory.")

    writeLines(c(
        '"BIOC_MULTIBAC_SINGLE_OMIC_CORRECTION":',
        paste0('    MultiBaC: ', as.character(packageVersion('MultiBaC')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_single_omic_correction.csv versions.yml
    """
}

workflow BIOC_MULTIBAC_SINGLE_OMIC_CORRECTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ A.rna, B.rna, C.rna ] ]

    main:
    BIOC_MULTIBAC_SINGLE_OMIC_CORRECTION(ch_input)

    emit:
    tables   = BIOC_MULTIBAC_SINGLE_OMIC_CORRECTION.out.tables
    plots    = BIOC_MULTIBAC_SINGLE_OMIC_CORRECTION.out.plots
    objects  = BIOC_MULTIBAC_SINGLE_OMIC_CORRECTION.out.objects
    versions = BIOC_MULTIBAC_SINGLE_OMIC_CORRECTION.out.versions
}
