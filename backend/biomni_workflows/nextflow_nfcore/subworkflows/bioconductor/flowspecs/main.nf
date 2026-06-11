#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: flowSpecs — spectral_cytometry_preprocessing
// Perform spectral unmixing, arcsinh transformation, artifact correction, and export spectral cytometry data to a long dataframe.
// Input: unmixCtrls, fullPanel
// Container: quay.io/biocontainers/bioconductor-flowspecs:1.24.0--r45hdfd78af_0
// R packages: flowCore, flowSpecs
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_FLOWSPECS_SPECTRAL_CYTOMETRY_PREPROCESSING {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-flowspecs:1.24.0--r45hdfd78af_0"

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
    .bm_deps <- c("flowCore", "flowSpecs")
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
    library(flowSpecs)
    library(flowCore)
    
    # ==========================================
    # 1. Read User Inputs from Working Directory
    # ==========================================
    
    # Expecting "fullPanel.fcs" and single-stained control FCS files in the working directory.
    if (!file.exists("fullPanel.fcs")) {
      stop("Error: 'fullPanel.fcs' not found in the working directory.")
    }
    
    # Read the fully stained sample
    fullPanel <- read.FCS("fullPanel.fcs", transformation = FALSE)
    
    # Identify control files (all FCS files except fullPanel.fcs)
    all_fcs_files <- list.files(pattern = "\\\\.fcs\$")
    control_files <- all_fcs_files[all_fcs_files != "fullPanel.fcs"]
    
    if (length(control_files) == 0) {
      stop("Error: No single-stained control FCS files found in the working directory.")
    }
    
    # Read the single-stained controls as a flowSet
    unmixCtrls <- read.flowSet(control_files)
    
    # ==========================================
    # 2. Calculate Spectral Unmixing Matrix
    # ==========================================
    specMat <- specMatCalc(unmixCtrls, groupNames = c("Beads_", "Dead_"), autoFluoName = "PBMC_unstained.fcs")
    saveRDS(specMat, "spectral_unmixing_matrix.rds")
    
    # ==========================================
    # 3. Perform Spectral Unmixing
    # ==========================================
    fullPanelUnmix <- specUnmix(fullPanel, specMat)
    saveRDS(fullPanelUnmix, "fullPanel_unmixed.rds")
    
    # ==========================================
    # 4. Arcsinh Transformation
    # ==========================================
    fullPanelTrans <- arcTrans(fullPanelUnmix, transNames = colnames(fullPanelUnmix)[6:18])
    saveRDS(fullPanelTrans, "fullPanel_transformed.rds")
    
    # ==========================================
    # 5. Visualize Potential Unmixing Artifacts
    # ==========================================
    pdf("oneVsAllPlot_transformed.pdf", width = 10, height = 8)
    oneVsAllPlot(fullPanelTrans, "AF647_IgM", saveResult = FALSE)
    dev.off()
    
    # ==========================================
    # 6. Create Correction Matrix & Correct Artifacts
    # ==========================================
    corrMat <- corrMatCreate(specMat)
    corrMat["BV650_CD56", "AF647_IgM"] <- -0.03
    fullPanelCorr <- correctUnmix(fullPanelUnmix, corrMat)
    saveRDS(fullPanelCorr, "fullPanel_corrected.rds")
    
    # Visualize corrected results
    pdf("oneVsAllPlot_corrected.pdf", width = 10, height = 8)
    oneVsAllPlot(fullPanelCorr, "AF647_IgM", saveResult = FALSE)
    dev.off()
    
    # ==========================================
    # 7. Convert to Long Dataframe with Metadata
    # ==========================================
    fullPanelFs <- flowSet(fullPanelTrans)
    sampleNames(fullPanelFs) <- "PBMC_full_panel_d1.fcs"
    
    fullPanelDf <- flowSet2LongDf(fullPanelFs, idInfo = list("Tissue" = "|_full_panel_..\\\\.fcs", "Donor" = "...._full_panel_|\\\\.fcs"))
    
    # Save the final processed dataframe
    write.csv(fullPanelDf, "fullPanel_processed_long.csv", row.names = FALSE)

    writeLines(c(
        '"BIOC_FLOWSPECS_SPECTRAL_CYTOMETRY_PREPROCESSING":',
        paste0('        flowSpecs: ', as.character(packageVersion("flowSpecs")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_spectral_cytometry_preprocessing.csv versions.yml
    """
}

workflow BIOC_FLOWSPECS_SPECTRAL_CYTOMETRY_PREPROCESSING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ unmixCtrls, fullPanel ] ]

    main:
    BIOC_FLOWSPECS_SPECTRAL_CYTOMETRY_PREPROCESSING(ch_input)

    emit:
    tables   = BIOC_FLOWSPECS_SPECTRAL_CYTOMETRY_PREPROCESSING.out.tables
    plots    = BIOC_FLOWSPECS_SPECTRAL_CYTOMETRY_PREPROCESSING.out.plots
    objects  = BIOC_FLOWSPECS_SPECTRAL_CYTOMETRY_PREPROCESSING.out.objects
    versions = BIOC_FLOWSPECS_SPECTRAL_CYTOMETRY_PREPROCESSING.out.versions
}
