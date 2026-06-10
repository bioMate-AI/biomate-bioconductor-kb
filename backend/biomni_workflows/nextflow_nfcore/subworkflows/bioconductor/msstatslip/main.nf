#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: msstatslip — lip_ms_differential_abundance_analysis
// Preprocess, summarize, and model LiP-MS and TrP-MS datasets to identify significantly altered peptides and proteins.
// Input: LiPRawData, TrPRawData, ExampleFastaFile.fasta
// Container: quay.io/biocontainers/bioconductor-msstatslip:1.16.0--r45ha27e39d_0
// R packages: data.table, gghighlight, MSstatsLiP, tidyverse
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MSSTATSLIP_LIP_MS_DIFFERENTIAL_ABUNDANCE_ANALYSIS {
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
    .bm_deps <- c("data.table", "gghighlight", "MSstatsLiP", "tidyverse")
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
    library(data.table)
    
    # 1. Read User Inputs from the working directory
    LiPRawData <- data.table::fread("LiPRawData", data.table = FALSE)
    TrPRawData <- data.table::fread("TrPRawData", data.table = FALSE)
    fasta_file <- "ExampleFastaFile.fasta"
    
    # 2. Convert raw data to MSstatsLiP format
    MSstatsLiP_data <- SpectronauttoMSstatsLiPFormat(LiPRawData, 
                                                     fasta_file, 
                                                     TrPRawData, 
                                                     use_log_file = FALSE, 
                                                     append = FALSE)
    
    # 3. Align condition names
    MSstatsLiP_data[["LiP"]][MSstatsLiP_data[["LiP"]]\$Condition == "Control", 
                             "Condition"] = "Ctrl"
    MSstatsLiP_data[["TrP"]]\$Condition = substr(MSstatsLiP_data[["TrP"]]\$Condition, 
                                                1, 
                                                nchar(MSstatsLiP_data[["TrP"]]\$Condition) - 1)
    
    # 4. Summarize feature intensities
    MSstatsLiP_Summarized <- dataSummarizationLiP(MSstatsLiP_data,
                                                  MBimpute = FALSE, 
                                                  use_log_file = FALSE, 
                                                  append = FALSE)
    
    # Save summarized data object
    saveRDS(MSstatsLiP_Summarized, "MSstatsLiP_Summarized.rds")
    
    # 5. Generate quality control, profile, and PCA plots
    # Open a PDF device to capture all diagnostic plots
    pdf("MSstatsLiP_QC_and_Profiling_Plots.pdf", width = 11, height = 8.5)
    
    trypticHistogramLiP(MSstatsLiP_Summarized, 
                        fasta_file,
                        color_scale = "bright",
                        address = FALSE)
    
    correlationPlotLiP(MSstatsLiP_Summarized, address = FALSE)
    
    dataProcessPlotsLiP(MSstatsLiP_Summarized,
                        type = 'QCPLOT',
                        which.Peptide = "allonly",
                        address = FALSE)
    
    dataProcessPlotsLiP(MSstatsLiP_Summarized,
                        type = 'ProfilePlot',
                        which.Peptide = c("P14164_ILQNDLK"),
                        address = FALSE)
    
    PCAPlotLiP(MSstatsLiP_Summarized,
               bar.plot = FALSE,
               protein.pca = FALSE,
               comparison.pca = TRUE,
               which.comparison = c("Ctrl", "Osmo"),
               address = FALSE)
    
    PCAPlotLiP(MSstatsLiP_Summarized,
               bar.plot = FALSE,
               protein.pca = TRUE,
               comparison.pca = FALSE,
               which.pep = c("P14164_ILQNDLK", "P17891_ALQLINQDDADIIGGRDR"),
               address = FALSE)
    
    dev.off()
    
    # 6. Run differential abundance modeling
    MSstatsLiP_model <- groupComparisonLiP(MSstatsLiP_Summarized,
                                           fasta = fasta_file,
                                           use_log_file = FALSE, 
                                           append = FALSE)
    
    # Save model results
    saveRDS(MSstatsLiP_model, "MSstatsLiP_model.rds")
    
    if (!is.null(MSstatsLiP_model[["LiP.Model"]])) {
      write.csv(MSstatsLiP_model[["LiP.Model"]], "MSstatsLiP_model_LiP.csv", row.names = FALSE)
    }
    if (!is.null(MSstatsLiP_model[["Adjusted.LiP.Model"]])) {
      write.csv(MSstatsLiP_model[["Adjusted.LiP.Model"]], "MSstatsLiP_model_Adjusted_LiP.csv", row.names = FALSE)
    }
    if (!is.null(MSstatsLiP_model[["TrP.Model"]])) {
      write.csv(MSstatsLiP_model[["TrP.Model"]], "MSstatsLiP_model_TrP.csv", row.names = FALSE)
    }
    
    # 7. Visualize modeling results
    # Open a PDF device to capture all result plots
    pdf("MSstatsLiP_Modeling_Plots.pdf", width = 11, height = 8.5)
    
    groupComparisonPlotsLiP(MSstatsLiP_model, 
                            type = "VolcanoPlot", 
                            address = FALSE)
    
    groupComparisonPlotsLiP(MSstatsLiP_model,
                            type = "HEATMAP",
                            numProtein = 50,
                            address = FALSE)
    
    StructuralBarcodePlotLiP(MSstatsLiP_model, 
                             fasta_file, 
                             model_type = "Adjusted", 
                             which.prot = c("P53858"),
                             address = FALSE)
    
    dev.off()

    cat <<-END_VERSIONS > versions.yml
    "BIOC_MSSTATSLIP_LIP_MS_DIFFERENTIAL_ABUNDANCE_ANALYSIS":
        msstatslip: \$(Rscript -e 'cat(as.character(packageVersion("msstatslip")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_lip_ms_differential_abundance_analysis.csv versions.yml
    """
}

workflow BIOC_MSSTATSLIP_LIP_MS_DIFFERENTIAL_ABUNDANCE_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ LiPRawData, TrPRawData, ExampleFastaFile.fasta ] ]

    main:
    BIOC_MSSTATSLIP_LIP_MS_DIFFERENTIAL_ABUNDANCE_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_MSSTATSLIP_LIP_MS_DIFFERENTIAL_ABUNDANCE_ANALYSIS.out.tables
    plots    = BIOC_MSSTATSLIP_LIP_MS_DIFFERENTIAL_ABUNDANCE_ANALYSIS.out.plots
    objects  = BIOC_MSSTATSLIP_LIP_MS_DIFFERENTIAL_ABUNDANCE_ANALYSIS.out.objects
    versions = BIOC_MSSTATSLIP_LIP_MS_DIFFERENTIAL_ABUNDANCE_ANALYSIS.out.versions
}
