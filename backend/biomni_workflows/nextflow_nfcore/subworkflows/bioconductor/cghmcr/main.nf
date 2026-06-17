#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: cghMCR — segment_gain_or_loss_sgol
// Identify genomic regions of recurrent copy number gain or loss across samples using the Segment Gain Or Loss (SGOL) method.
// Input: sampleData, geneInfo
// Container: quay.io/biocontainers/bioconductor-cghmcr:1.68.0--r45hdfd78af_0
// R packages: CNTools, cghMCR, limma
// Bioconductor: 3.20 | R: 4.4
// Requires: CNTools, cghMCR
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load segment data and gene mapping information
//  * 2. [Core Analysis] Convert segment data to a gene-by-sample matrix using CNTools
//  * 3. [Core Analysis] Compute SGOL scores using SGOL
//  * 4. [Visualization & Output] Plot SGOL scores
//  * 5. [Core Analysis] Extract genes of interest in gains and losses using thresholding and the gol helper function

nextflow.enable.dsl = 2

process BIOC_CGHMCR_SEGMENT_GAIN_OR_LOSS_SGOL {
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
    .bm_deps <- c("CNTools", "cghMCR", "limma")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))  # CRAN binaries (Posit PPM)
      .bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressWarnings(suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=.bin), error=function(e) try(install.packages(.bm_miss), silent=TRUE))))
    }
        
        # Load required libraries
        library(CNTools)
        library(cghMCR)
        
        # Helper function to read input files with various extensions
        read_input_file <- function(base_name) {
          extensions <- c(".csv", ".tsv", ".txt", "")
          for (ext in extensions) {
            file_path <- paste0(base_name, ext)
            if (file.exists(file_path)) {
              if (ext == ".csv") {
                return(read.csv(file_path, stringsAsFactors = FALSE, check.names = FALSE))
              } else if (ext %in% c(".tsv", ".txt")) {
                return(read.delim(file_path, stringsAsFactors = FALSE, check.names = FALSE))
              } else {
                # Try reading as table if no extension
                tryCatch({
                  return(read.table(file_path, header = TRUE, stringsAsFactors = FALSE, check.names = FALSE))
                }, error = function(e) NULL)
              }
            }
          }
          stop(paste("Required input file not found:", base_name))
        }
        
        # 1. Load segment data and gene mapping information from the working directory
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
        sampleData <- read_input_file("sampleData")
        geneInfo <- read_input_file("geneInfo")
        
        # Ensure correct column types for sampleData
        sampleData\$chrom <- as.character(sampleData\$chrom)
        sampleData\$loc.start <- as.numeric(sampleData\$loc.start)
        sampleData\$loc.end <- as.numeric(sampleData\$loc.end)
        sampleData\$num.mark <- as.integer(sampleData\$num.mark)
        sampleData\$seg.mean <- as.numeric(sampleData\$seg.mean)
        
        # Ensure correct column types for geneInfo
        geneInfo\$chrom <- as.character(geneInfo\$chrom)
        geneInfo\$start <- as.numeric(geneInfo\$start)
        geneInfo\$end <- as.numeric(geneInfo\$end)
        
        # 2. Convert segment data to a gene-by-sample matrix using CNTools
        # We use min(20, ...) to prevent sampling errors if the input dataset has fewer than 20 samples.
        set.seed(1234)
        convertedData <- getRS(CNSeg(sampleData[which(is.element(sampleData[, "ID"], sample(unique(sampleData[, "ID"]), min(20, length(unique(sampleData[, "ID"])))))), ]), by = "gene", imput = FALSE, XY = FALSE, geneMap = geneInfo, what = "median")
        
        # 3. Compute SGOL scores using SGOL
        require(cghMCR, quietly = TRUE)
        SGOLScores <- SGOL(convertedData, threshold = c(-0.2, 0.2), method = sum)
        
        # 4. Plot SGOL scores (redirected to a PDF file)
        pdf("sgol_scores_plot.pdf", width = 10, height = 6)
        plot(SGOLScores)
        dev.off()
        
        # 5. Extract genes of interest in gains and losses using thresholding and the gol helper function
        GOIGains <- SGOLScores[which(as.numeric(unlist(gol(SGOLScores[, "gains"]))) > 20), "gains"]
        GOILosses <- SGOLScores[which(as.numeric(unlist(gol(SGOLScores[, "losses"]))) < -20), "losses"]
        
        # Print head of GOIGains to console as in the vignette
        cat("Head of GOIGains:\n")
        print(head(gol(GOIGains)))
        
        # Save meaningful results to output files
        saveRDS(SGOLScores, "sgol_scores.rds")
        
        # Save SGOL scores table
        sgol_df <- data.frame(
          gene = rownames(gol(SGOLScores)),
          gains = as.numeric(unlist(gol(SGOLScores[, "gains"]))),
          losses = as.numeric(unlist(gol(SGOLScores[, "losses"]))),
          stringsAsFactors = FALSE
        )
        write.csv(sgol_df, "sgol_scores.csv", row.names = FALSE)
        
        # Save Genes of Interest (Gains)
        if (length(GOIGains) > 0) {
          gains_df <- data.frame(
            gene = rownames(gol(GOIGains)),
            gains = as.numeric(unlist(gol(GOIGains))),
            stringsAsFactors = FALSE
          )
          write.csv(gains_df, "goi_gains.csv", row.names = FALSE)
        } else {
          write.csv(data.frame(gene = character(), gains = numeric()), "goi_gains.csv", row.names = FALSE)
        }
        
        # Save Genes of Interest (Losses)
        if (length(GOILosses) > 0) {
          losses_df <- data.frame(
            gene = rownames(gol(GOILosses)),
            losses = as.numeric(unlist(gol(GOILosses))),
            stringsAsFactors = FALSE
          )
          write.csv(losses_df, "goi_losses.csv", row.names = FALSE)
        } else {
          write.csv(data.frame(gene = character(), losses = numeric()), "goi_losses.csv", row.names = FALSE)
        }
        
        cat("Workflow completed successfully. Outputs saved to 'sgol_scores_plot.pdf', 'sgol_scores.rds', 'sgol_scores.csv', 'goi_gains.csv', and 'goi_losses.csv'.\n")

    writeLines(c(
        '"BIOC_CGHMCR_SEGMENT_GAIN_OR_LOSS_SGOL":',
        paste0('    cghMCR: ', as.character(packageVersion('cghMCR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_segment_gain_or_loss_sgol.csv versions.yml
    """
}

workflow BIOC_CGHMCR_SEGMENT_GAIN_OR_LOSS_SGOL_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sampleData, geneInfo ] ]

    main:
    BIOC_CGHMCR_SEGMENT_GAIN_OR_LOSS_SGOL(ch_input)

    emit:
    tables   = BIOC_CGHMCR_SEGMENT_GAIN_OR_LOSS_SGOL.out.tables
    plots    = BIOC_CGHMCR_SEGMENT_GAIN_OR_LOSS_SGOL.out.plots
    objects  = BIOC_CGHMCR_SEGMENT_GAIN_OR_LOSS_SGOL.out.objects
    versions = BIOC_CGHMCR_SEGMENT_GAIN_OR_LOSS_SGOL.out.versions
}
