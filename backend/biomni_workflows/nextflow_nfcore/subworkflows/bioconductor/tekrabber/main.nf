#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: TEKRABber — two_species_comparison
// Compare orthologous gene and transposable element (TE) expression and estimate their correlations between two different species.
// Input: geneCountRef, geneCountCompare, teCountRef, teCountCompare, rmsk
// Container: quay.io/biocontainers/bioconductor-tekrabber:1.14.1--r45ha27e39d_0
// R packages: bslib, gridlayout, plotly, shiny, TEKRABber
// Bioconductor: 3.20 | R: 4.4
// Requires: TEKRABber
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Query orthologs and calculate scaling factors using orthologScale()
//  * 2. [Core Analysis] Format inputs for DE and correlation analysis using DECorrInputs()
//  * 3. [Core Analysis] Perform differential expression analysis using DEgeneTE() with expDesign = TRUE
//  * 4. [Core Analysis] Estimate correlations between genes and TEs using corrOrthologTE()
//  * 5. [Visualization & Output] Visualize results using appTEKRABber()

nextflow.enable.dsl = 2

process BIOC_TEKRABBER_TWO_SPECIES_COMPARISON {
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
    .bm_deps <- c("bslib", "gridlayout", "plotly", "shiny", "TEKRABber")
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
        library(TEKRABber)
        
        # Parse command line arguments for species names
        args <- commandArgs(trailingOnly = TRUE)
        speciesRef <- ifelse(length(args) >= 1, args[1], "hsapiens")
        speciesCompare <- ifelse(length(args) >= 2, args[2], "ptroglodytes")
        
        # Helper function to find and read input files from the working directory
        find_and_read <- function(base_name) {
          possible_files <- c(
            base_name,
            paste0(base_name, ".csv"),
            paste0(base_name, ".tsv"),
            paste0(base_name, ".txt")
          )
          for (f in possible_files) {
            if (file.exists(f)) {
              message(paste("Reading", f, "..."))
              if (grepl("\\\\.tsv\$", f) || grepl("\\\\.txt\$", f)) {
                return(read.delim(f, header = TRUE, check.names = FALSE, stringsAsFactors = FALSE))
              } else {
                return(read.csv(f, header = TRUE, check.names = FALSE, stringsAsFactors = FALSE))
              }
            }
          }
          stop(paste("Required input file not found in working directory:", base_name))
        }
        
        # 1. Read user input files
        geneCountRef <- find_and_read("geneCountRef")
        geneCountCompare <- find_and_read("geneCountCompare")
        teCountRef <- find_and_read("teCountRef")
        teCountCompare <- find_and_read("teCountCompare")
        rmsk <- find_and_read("rmsk")
        
        # 2. Query orthologs and calculate scaling factors
        fetchData <- orthologScale(
            speciesRef = speciesRef,
            speciesCompare = speciesCompare,
            geneCountRef = geneCountRef,
            geneCountCompare = geneCountCompare,
            teCountRef = teCountRef,
            teCountCompare = teCountCompare,
            rmsk = rmsk
        )
        
        # 3. Format inputs for DE and correlation analysis
        inputBundle <- DECorrInputs(fetchData)
        
        # 4. Perform differential expression analysis
        meta <- data.frame(
            species = c(rep(speciesRef, ncol(geneCountRef) - 1), 
            rep(speciesCompare, ncol(geneCountCompare) - 1))
        )
        
        meta\$species <- factor(meta\$species, levels = c(speciesRef, speciesCompare))
        rownames(meta) <- colnames(inputBundle\$geneInputDESeq2)
        
        hmchimpDE <- DEgeneTE(
            geneTable = inputBundle\$geneInputDESeq2,
            teTable = inputBundle\$teInputDESeq2,
            metadata = meta,
            expDesign = TRUE
        )
        
        # 5. Estimate correlations between genes and TEs
        hmCorrResult <- corrOrthologTE(
            geneInput = hmchimpDE\$geneCorrInputRef,
            teInput = hmchimpDE\$teCorrInputRef,
            numCore = 1,
            corrMethod = "pearson",
            padjMethod = "fdr"
        )
        
        chimpCorrResult <- corrOrthologTE(
            geneInput = hmchimpDE\$geneCorrInputCompare,
            teInput = hmchimpDE\$teCorrInputCompare,
            numCore = 1,
            corrMethod = "pearson",
            padjMethod = "fdr"
        )
        
        # 6. Save meaningful results to files
        write.csv(hmCorrResult, "hmCorrResult.csv", row.names = FALSE)
        write.csv(chimpCorrResult, "chimpCorrResult.csv", row.names = FALSE)
        saveRDS(fetchData, "fetchData.rds")
        saveRDS(inputBundle, "inputBundle.rds")
        saveRDS(hmchimpDE, "hmchimpDE.rds")
        message("Results successfully saved to 'hmCorrResult.csv', 'chimpCorrResult.csv', and RDS objects.")
        
        # 7. Visualize results using appTEKRABber() (if running interactively)
        if (interactive()) {
            appTEKRABber(
                corrRef = hmCorrResult,
                corrCompare = chimpCorrResult,
                DEobject = hmchimpDE
            )
        } else {
            message("Skipping interactive appTEKRABber() visualization because session is non-interactive.")
        }

    writeLines(c(
        '"BIOC_TEKRABBER_TWO_SPECIES_COMPARISON":',
        paste0('    TEKRABber: ', as.character(packageVersion('TEKRABber')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_two_species_comparison.csv versions.yml
    """
}

workflow BIOC_TEKRABBER_TWO_SPECIES_COMPARISON_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ geneCountRef, geneCountCompare, teCountRef, teCountCompare, rmsk ] ]

    main:
    BIOC_TEKRABBER_TWO_SPECIES_COMPARISON(ch_input)

    emit:
    tables   = BIOC_TEKRABBER_TWO_SPECIES_COMPARISON.out.tables
    plots    = BIOC_TEKRABBER_TWO_SPECIES_COMPARISON.out.plots
    objects  = BIOC_TEKRABBER_TWO_SPECIES_COMPARISON.out.objects
    versions = BIOC_TEKRABBER_TWO_SPECIES_COMPARISON.out.versions
}
