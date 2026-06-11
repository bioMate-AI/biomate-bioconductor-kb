#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: msstatslip — proteolytic_resistance_analysis
// Calculate proteolytic resistance ratios and perform differential analysis of proteolytic resistance patterns across conditions using fully tryptic peptides.
// Input: raw_lip, raw_prot, fasta_file
// Container: quay.io/biocontainers/bioconductor-msstatslip:1.16.0--r45ha27e39d_0
// R packages: MSstatsLiP, data.table, tidyverse
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MSSTATSLIP_PROTEOLYTIC_RESISTANCE_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-msstatslip:1.16.0--r45ha27e39d_0"

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
    .bm_deps <- c("MSstatsLiP", "data.table", "tidyverse")
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
    library(MSstatsLiP)
    library(tidyverse)
    library(data.table)
    
    # 1. Read user input files from the working directory
    # Spectronaut exports are typically comma- or tab-separated. 
    # data.table::fread is highly robust for reading both formats.
    raw_lip <- data.table::fread("raw_lip", data.table = FALSE)
    raw_prot <- data.table::fread("raw_prot", data.table = FALSE)
    fasta_file <- "fasta_file"
    
    # 2. Convert raw data to MSstatsLiP format
    msstats_data <- SpectronauttoMSstatsLiPFormat(raw_lip, fasta_file, raw_prot)
    
    # 3. Select only fully tryptic (FT) peptides in both LiP and TrP datasets
    FullyTrP <- msstats_data[["LiP"]] %>% 
      distinct(ProteinName, PeptideSequence) %>% 
      calculateTrypticity(fasta_file) %>% 
      filter(fully_TRI) %>%
      filter(MissedCleavage == FALSE) %>% 
      select(ProteinName, PeptideSequence, StartPos, EndPos)
    
    msstats_data[["LiP"]] <- msstats_data[["LiP"]] %>% 
      select(-ProteinName) %>% inner_join(FullyTrP, by = "PeptideSequence")
    
    msstats_data[["TrP"]] <- msstats_data[["TrP"]] %>% 
      select(-ProteinName) %>% inner_join(FullyTrP, by = "PeptideSequence")
    
    # 4. Align condition and BioReplicate nomenclature
    msstats_data[["LiP"]] = msstats_data[["LiP"]] %>% 
      mutate(BioReplicate = paste0(Condition,".",BioReplicate))
    
    msstats_data[["TrP"]] = msstats_data[["TrP"]] %>% 
      mutate(BioReplicate = paste0(Condition,".",BioReplicate))
    
    # 5. Summarize data
    MSstatsLiP_Summarized <- dataSummarizationLiP(msstats_data, normalization.LiP = "equalizeMedians")
    
    # Save summarized data
    saveRDS(MSstatsLiP_Summarized, file = "MSstatsLiP_Summarized.rds")
    
    # 6. Model differential abundance
    MSstatsLiP_model = groupComparisonLiP(MSstatsLiP_Summarized)
    
    # Save modeling results
    saveRDS(MSstatsLiP_model, file = "MSstatsLiP_model.rds")
    if (!is.null(MSstatsLiP_model[["LiP.Model"]])) {
      write.csv(MSstatsLiP_model[["LiP.Model"]], "MSstatsLiP_model_LiP.csv", row.names = FALSE)
    }
    if (!is.null(MSstatsLiP_model[["TrP.Model"]])) {
      write.csv(MSstatsLiP_model[["TrP.Model"]], "MSstatsLiP_model_TrP.csv", row.names = FALSE)
    }
    if (!is.null(MSstatsLiP_model[["Adjusted.LiP.Model"]])) {
      write.csv(MSstatsLiP_model[["Adjusted.LiP.Model"]], "MSstatsLiP_model_Adjusted.csv", row.names = FALSE)
    }
    
    # 7. Calculate proteolytic resistance ratios and perform differential analysis
    Accessibility = calculateProteolyticResistance(MSstatsLiP_Summarized, 
                                                   fasta_file, 
                                                   differential_analysis = TRUE)
    
    # Save proteolytic resistance results
    saveRDS(Accessibility, file = "Accessibility.rds")
    if (!is.null(Accessibility\$RunLevelData)) {
      write.csv(Accessibility\$RunLevelData, "Accessibility_RunLevelData.csv", row.names = FALSE)
    }
    if (!is.null(Accessibility\$groupComparison)) {
      write.csv(Accessibility\$groupComparison, "Accessibility_groupComparison.csv", row.names = FALSE)
    }
    
    # 8. Plot proteolytic resistance results as barcodes
    # We wrap the plotting functions in pdf() to save the outputs as files.
    pdf("ResistanceBarcodePlot_F1.pdf", width = 10, height = 6)
    tryCatch({
      ResistanceBarcodePlotLiP(Accessibility,
                               fasta_file,
                               which.prot = "P16622",
                               which.condition = "F1",
                               address = FALSE)
    }, error = function(e) {
      message("Could not plot ResistanceBarcodePlot_F1: ", e\$message)
    })
    dev.off()
    
    pdf("ResistanceBarcodePlot_F1_vs_F2.pdf", width = 10, height = 6)
    tryCatch({
      ResistanceBarcodePlotLiP(Accessibility,
                               fasta_file,
                               which.prot = "P16622",
                               which.condition = "F1",
                               differential_analysis = TRUE,
                               which.comp = "F1 vs F2",
                               address = FALSE)
    }, error = function(e) {
      message("Could not plot ResistanceBarcodePlot_F1_vs_F2: ", e\$message)
    })
    dev.off()

    writeLines(c(
        '"BIOC_MSSTATSLIP_PROTEOLYTIC_RESISTANCE_ANALYSIS":',
        paste0('        msstatslip: ', as.character(packageVersion("msstatslip")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_proteolytic_resistance_analysis.csv versions.yml
    """
}

workflow BIOC_MSSTATSLIP_PROTEOLYTIC_RESISTANCE_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ raw_lip, raw_prot, fasta_file ] ]

    main:
    BIOC_MSSTATSLIP_PROTEOLYTIC_RESISTANCE_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_MSSTATSLIP_PROTEOLYTIC_RESISTANCE_ANALYSIS.out.tables
    plots    = BIOC_MSSTATSLIP_PROTEOLYTIC_RESISTANCE_ANALYSIS.out.plots
    objects  = BIOC_MSSTATSLIP_PROTEOLYTIC_RESISTANCE_ANALYSIS.out.objects
    versions = BIOC_MSSTATSLIP_PROTEOLYTIC_RESISTANCE_ANALYSIS.out.versions
}
