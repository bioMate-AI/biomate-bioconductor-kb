#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: msqrob2 — dda_maxquant_peptide_workflow
// Analyze MaxQuant DDA peptide-level data to identify differentially abundant proteins.
// Input: peptides.txt, experimental_design.csv
// Container: quay.io/biocontainers/bioconductor-msqrob2:1.18.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: ExploreModelMatrix, QFeatures, data.table, dplyr, ggplot2, msqrob2, stringr, tidyr
// Visualizations: volcano plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Import peptide table and sample annotations
//  * 2. [Core Analysis] Convert to QFeatures object using readQFeatures
//  * 3. [Core Analysis] Replace zeros with NA using zeroIsNA
//  * 4. [Core Analysis] Log2-transform intensities using logTransform
//  * 5. [Core Analysis] Filter out failed protein inferences, shared peptides, decoys, and contaminants using filterFeatures
//  * 6. [Core Analysis] Filter out highly missing peptides using filterNA
//  * 7. [Core Analysis] Normalize intensities using sweep and nfLogMedian
//  * 8. [Visualization & Output] Summarize peptide intensities to protein level using aggregateFeatures
//  * 9. [Core Analysis] Fit robust linear models using msqrob
//  * 10. [Input & Preparation] Define contrasts using makeContrast and perform hypothesis testing using hypothesisTest
//  * 11. [Visualization & Output] Collect results using msqrobCollect and visualize using plotVolcano

nextflow.enable.dsl = 2

process BIOC_MSQROB2_DDA_MAXQUANT_PEPTIDE_WORKFLOW {
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
    .bm_deps <- c("QFeatures", "dplyr", "tidyr", "ggplot2", "msqrob2", "stringr", "ExploreModelMatrix", "SummarizedExperiment")
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
     library(QFeatures)
            library(dplyr)
            library(tidyr)
            library(ggplot2)
            library(msqrob2)
            library(stringr)
            library(ExploreModelMatrix)
            
            # 1. Import peptide table and sample annotations
            peptides <- data.table::fread("peptides.txt", check.names = TRUE, integer64 = "double")
            annot <- read.csv("experimental_design.csv", stringsAsFactors = FALSE)
            
            # Identify the column in annot that maps to the peptide quantification columns
            # and rename it to "quantCols" as expected by readQFeatures
            quant_col_idx <- which.max(sapply(annot, function(x) sum(as.character(x) %in% colnames(peptides))))
            colnames(annot)[quant_col_idx] <- "quantCols"
            
            # 2. Convert to QFeatures object using readQFeatures
            qf <- readQFeatures(assayData = peptides, colData = annot, name = "peptides", fnames = "Sequence")
            
            # 3. Replace zeros with NA using zeroIsNA
            qf <- zeroIsNA(qf, "peptides")
            
            # 4. Log2-transform intensities using logTransform
            qf <- logTransform(qf, base = 2, i = "peptides", name = "peptides_log")
            
            # 5. Filter out failed protein inferences, shared peptides, decoys, and contaminants using filterFeatures
            qf <- filterFeatures(
              qf, ~ Proteins != "" &
              !grepl(";", Proteins)
            )
            qf <- filterFeatures(
              qf, ~ Reverse != "+" &
              Potential.contaminant != "+"
            )
            
            # 6. Filter out highly missing peptides using filterNA
            nObs <- 3
            n <- ncol(qf[["peptides_log"]])
            qf <- filterNA(qf, i = "peptides_log", pNA = (n - nObs) / n)
            
            # 7. Normalize intensities using sweep and nfLogMedian
            qf <- sweep(
              qf, MARGIN = 2, STATS = nfLogMedian(qf, "peptides_log"), i = "peptides_log", name = "peptides_norm"
            )
            
            # 8. Summarize peptide intensities to protein level using aggregateFeatures
            qf <- aggregateFeatures(
              qf, i = "peptides_norm", fcol = "Proteins", na.rm = TRUE, name = "proteins"
            )
            
            # 9. Fit robust linear models using msqrob
            model <- ~ condition
            qf <- msqrob(
              qf, i = "proteins", formula = model, robust = TRUE
            )
            
            # Visualize design to get parameter names for contrast
            vd <- ExploreModelMatrix::VisualizeDesign(
              sampleData = colData(qf),
              designFormula = model
            )
            
            # 10. Define contrasts using makeContrast and perform hypothesis testing using hypothesisTest
            params <- colnames(vd\$designmatrix)
            contrast_param <- params[params != "(Intercept)"][1]
            contrast_formula <- paste0(contrast_param, " = 0")
            
            L <- makeContrast(
              contrast_formula, parameterNames = params
            )
            qf <- hypothesisTest(qf, i = "proteins", contrast = L)
            
            # 11. Collect results using msqrobCollect and visualize using plotVolcano
            inferences <- msqrobCollect(qf[["proteins"]], L)
            
            # Write outputs
            write.csv(inferences, "msqrob2_results.csv", row.names = TRUE)
            saveRDS(qf, "qf_results.rds")
            
            pdf("volcano_plot.pdf")
            print(inferences |> plotVolcano())
            dev.off()

    writeLines(c(
        '"BIOC_MSQROB2_DDA_MAXQUANT_PEPTIDE_WORKFLOW":',
        paste0('    msqrob2: ', as.character(packageVersion('msqrob2')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_dda_maxquant_peptide_workflow.csv versions.yml
    """
}

workflow BIOC_MSQROB2_DDA_MAXQUANT_PEPTIDE_WORKFLOW_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ peptides.txt, experimental_design.csv ] ]

    main:
    BIOC_MSQROB2_DDA_MAXQUANT_PEPTIDE_WORKFLOW(ch_input)

    emit:
    tables   = BIOC_MSQROB2_DDA_MAXQUANT_PEPTIDE_WORKFLOW.out.tables
    plots    = BIOC_MSQROB2_DDA_MAXQUANT_PEPTIDE_WORKFLOW.out.plots
    objects  = BIOC_MSQROB2_DDA_MAXQUANT_PEPTIDE_WORKFLOW.out.objects
    versions = BIOC_MSQROB2_DDA_MAXQUANT_PEPTIDE_WORKFLOW.out.versions
}
