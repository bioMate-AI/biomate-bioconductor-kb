#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: msqrob2 — dia_precursor_workflow
// Analyze DIA precursor-level data (from DIA-NN or Spectronaut) to identify differentially abundant proteins.
// Input: report.parquet, experimental_design.csv
// Container: quay.io/biocontainers/bioconductor-msqrob2:1.18.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: ExploreModelMatrix, MsCoreUtils, QFeatures, arrow, dplyr, ggplot2, msqrob2, stringr, tidyr
// Visualizations: volcano plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Import precursor table and sample annotations
//  * 2. [Core Analysis] Convert long-format precursor table to QFeatures object using readQFeatures
//  * 3. [Core Analysis] Replace zeros with NA using zeroIsNA
//  * 4. [Core Analysis] Filter out questionable identifications, decoys, and non-proteotypic peptides using filterFeatures
//  * 5. [Core Analysis] Join run-specific assays into a single precursor assay using joinAssays
//  * 6. [Core Analysis] Filter out highly missing precursors using filterNA
//  * 7. [Core Analysis] Filter out "one-hit wonder" proteins (proteins with only one peptide) using filterFeatures
//  * 8. [Core Analysis] Log2-transform intensities using logTransform
//  * 9. [Core Analysis] Normalize intensities using sweep and nfLogMedian
//  * 10. [Visualization & Output] Summarize precursor intensities to protein level using aggregateFeatures with maxLFQ or medianPolish
//  * 11. [Core Analysis] Fit robust linear models using msqrob
//  * 12. [Core Analysis] Generate pairwise contrasts using createPairwiseContrasts and makeContrast
//  * 13. [Core Analysis] Perform hypothesis testing using hypothesisTest
//  * 14. [Visualization & Output] Collect results using msqrobCollect and visualize using plotVolcano

nextflow.enable.dsl = 2

process BIOC_MSQROB2_DIA_PRECURSOR_WORKFLOW {
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
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
            
            # Load required libraries
            library(QFeatures)
            library(dplyr)
            library(tidyr)
            library(ggplot2)
            library(msqrob2)
            library(stringr)
            library(ExploreModelMatrix)
            library(arrow)
            
            # 1. Import precursor table and sample annotations
            precursorFile <- "report.parquet"
            precursors <- arrow::read_parquet(precursorFile)
            
            # Read the user-provided experimental design
            annot <- read.csv("experimental_design.csv", stringsAsFactors = FALSE)
            
            # Ensure runCol is present and matches the Run column in precursors
            if (!"runCol" %in% colnames(annot)) {
                if ("Run" %in% colnames(annot)) {
                    annot\$runCol <- annot\$Run
                } else if ("run" %in% colnames(annot)) {
                    annot\$runCol <- annot\$run
                } else {
                    annot\$runCol <- annot[, 1]
                }
            }
            
            # Ensure condition is present and formatted as a factor
            if (!"condition" %in% colnames(annot)) {
                if ("Condition" %in% colnames(annot)) {
                    annot\$condition <- as.factor(annot\$Condition)
                } else {
                    annot\$condition <- as.factor(annot[, 2])
                }
            } else {
                annot\$condition <- as.factor(annot\$condition)
            }
            
            # Ensure rep is present and formatted as a factor
            if (!"rep" %in% colnames(annot)) {
                if ("Rep" %in% colnames(annot)) {
                    annot\$rep <- as.factor(annot\$Rep)
                } else if ("Replicate" %in% colnames(annot)) {
                    annot\$rep <- as.factor(annot\$Replicate)
                } else {
                    annot\$rep <- as.factor(1)
                }
            } else {
                annot\$rep <- as.factor(annot\$rep)
            }
            
            # Set row names of annot to match the runCol for QFeatures matching
            rownames(annot) <- annot\$runCol
            
            # 2. Convert long-format precursor table to QFeatures object using readQFeatures
            (qf <- readQFeatures(
                assayData = precursors,
                colData = annot,
                quantCols = "Precursor.Quantity",
                runCol = "Run",
                fnames = "Precursor.Id"
            ))
            
            # 3. Replace zeros with NA using zeroIsNA
            qf <- zeroIsNA(qf, names(qf))
            
            # 4. Filter out questionable identifications, decoys, and non-proteotypic peptides using filterFeatures
            qf <- qf |>
                filterFeatures(~ Q.Value <= 0.01 &
                    PG.Q.Value <= 0.01 &
                    Lib.Q.Value <= 0.01 &
                    Lib.PG.Q.Value <= 0.01 &
                    Precursor.Id != "" &
                    Decoy == 0 &
                    Proteotypic == 1)
            
            # 5. Join run-specific assays into a single precursor assay using joinAssays
            (qf <- joinAssays(
                x = qf,
                i = names(qf),
                name = "precursors"
            ))
            
            # 6. Filter out highly missing precursors using filterNA
            n <- ncol(qf[["precursors"]])
            nObs <- min(4, n)
            (qf <- filterNA(qf, i = "precursors", pNA = (n - nObs) / n))
            
            # 7. Filter out "one-hit wonder" proteins (proteins with only one peptide) using filterFeatures
            rd <- rowData(qf[["precursors"]])
            peps_per_prot <- tapply(rd\$Stripped.Sequence, as.character(rd\$Protein.Group), function(x) length(unique(x)))
            rowData(qf[["precursors"]])\$pepsPerProt <- as.numeric(peps_per_prot[as.character(rd\$Protein.Group)])
            qf <- filterFeatures(qf, ~ pepsPerProt > 1)
            
            # 8. Log2-transform intensities using logTransform
            qf <- logTransform(qf, base = 2, i = "precursors", name = "precursors_log")
            
            # 9. Normalize intensities using sweep and nfLogMedian
            qf <- sweep(
                qf, MARGIN = 2, STATS = nfLogMedian(qf, "precursors_log"), i = "precursors_log", name = "precursors_norm"
            )
            
            # 10. Summarize precursor intensities to protein level using aggregateFeatures
            (qf <- aggregateFeatures(
                qf,
                i = "precursors_norm",
                name = "proteins",
                fcol = "Protein.Group",
                fun = MsCoreUtils::medianPolish,
                na.rm = TRUE
            ))
            
            # 11. Fit robust linear models using msqrob
            model <- ~ condition
            qf <- msqrob(
                qf, i = "proteins", formula = model, robust = TRUE
            )
            
            # 12. Generate pairwise contrasts
            # Define vd to retrieve the design matrix parameter names
            vd <- ExploreModelMatrix::VisualizeDesign(
                sampleData = colData(qf),
                designFormula = model,
                textSizeFitted = 4
            )
            
            cond_params <- grep("^condition", colnames(vd\$designmatrix), value = TRUE)
            allHypotheses <- paste0(cond_params, " = 0")
            if (length(cond_params) > 1) {
                combos <- combn(cond_params, 2)
                allHypotheses <- c(allHypotheses, paste0(combos[2, ], " - ", combos[1, ], " = 0"))
            }
            
            (L <- makeContrast(
                allHypotheses,
                parameterNames = colnames(vd\$designmatrix)
            ))
            
            # 13. Perform hypothesis testing using hypothesisTest
            qf <- hypothesisTest(qf, i = "proteins", contrast = L)
            
            # 14. Collect results using msqrobCollect and visualize using plotVolcano
            inferences <- msqrobCollect(qf[["proteins"]], L)
            volcanoplots <- inferences |> plotVolcano() + facet_wrap(~contrast)
            
            # Write output files
            write.csv(inferences, "msqrob2_results.csv", row.names = TRUE)
            
            # Save significant proteins (FDR < 0.05)
            sig_proteins <- inferences |> filter(adjPval < 0.05)
            write.csv(sig_proteins, "significant_proteins.csv", row.names = TRUE)
            
            # Save volcano plot to PDF
            pdf("volcano_plot.pdf", width = 8, height = 6)
            print(volcanoplots)
            dev.off()
            
            # Save the final QFeatures object
            saveRDS(qf, "qfeatures_object.rds")

    writeLines(c(
        '"BIOC_MSQROB2_DIA_PRECURSOR_WORKFLOW":',
        paste0('    msqrob2: ', as.character(packageVersion('msqrob2')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_dia_precursor_workflow.csv versions.yml
    """
}

workflow BIOC_MSQROB2_DIA_PRECURSOR_WORKFLOW_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ report.parquet, experimental_design.csv ] ]

    main:
    BIOC_MSQROB2_DIA_PRECURSOR_WORKFLOW(ch_input)

    emit:
    tables   = BIOC_MSQROB2_DIA_PRECURSOR_WORKFLOW.out.tables
    plots    = BIOC_MSQROB2_DIA_PRECURSOR_WORKFLOW.out.plots
    objects  = BIOC_MSQROB2_DIA_PRECURSOR_WORKFLOW.out.objects
    versions = BIOC_MSQROB2_DIA_PRECURSOR_WORKFLOW.out.versions
}
