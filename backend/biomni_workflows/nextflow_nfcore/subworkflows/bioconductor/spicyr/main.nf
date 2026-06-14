#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: spicyR — pairwise_localization_modeling
// Test for changes in pairwise cell type localization across conditions using linear or mixed-effects models.
// Input: kerenSPE, diabetesData
// Container: quay.io/biocontainers/bioconductor-spicyr:1.22.0--r45hdfd78af_0
// R packages: SummarizedExperiment, BiocStyle, dplyr, ggplot2, spatialdatasets, SpatialExperiment, spicyR, survival
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SPICYR_PAIRWISE_LOCALIZATION_MODELING {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-spicyr:1.22.0--r45hdfd78af_0"

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
    .bm_deps <- c("SummarizedExperiment", "BiocStyle", "dplyr", "ggplot2", "spatialdatasets", "SpatialExperiment", "spicyR", "survival")
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
    
    # Load required packages
    library(SummarizedExperiment)
    
    # Define S4 class union workaround for the inheritance bug
    methods::setClassUnion("ExpData", c("matrix", "dgCMatrix", "ExpressionSet",
                                        "SummarizedExperiment"))
    
    library(spicyR)
    library(ggplot2)
    library(SpatialExperiment)
    library(dplyr)
    library(survival)
    
    # Helper function to load inputs from the working directory
    load_input <- function(filename) {
      if (file.exists(filename)) {
        return(readRDS(filename))
      } else if (file.exists(paste0(filename, ".rds"))) {
        return(readRDS(paste0(filename, ".rds")))
      } else {
        stop(paste("Required input file not found:", filename))
      }
    }
    
    # Read user inputs
    kerenSPE <- load_input("kerenSPE")
    diabetesData <- load_input("diabetesData")
    
    # --- Test for change in localization for a specific pair of ---
    spicyTestPair <- spicy(
      kerenSPE,
      condition = "tumour_type",
      from = "CD8_T_cell",
      to = "Neutrophils"
    )
    
    # Extract and save results for the specific pair
    testPairResults <- topPairs(spicyTestPair)
    write.csv(testPairResults, "spicyTestPair_results.csv", row.names = TRUE)
    saveRDS(spicyTestPair, "spicyTestPair.rds")
    
    # --- Test for change in localization for all pairwise cell ---
    spicyTest <- spicy(
      kerenSPE,
      condition = "tumour_type"
    )
    
    # Extract and save results for all pairwise combinations
    testResults <- topPairs(spicyTest)
    write.csv(testResults, "spicyTest_results.csv", row.names = TRUE)
    saveRDS(spicyTest, "spicyTest.rds")
    
    # --- Extract image-level L-function metrics using bind() ---
    bindResults <- bind(spicyTest)
    write.csv(bindResults, "spicyTest_bind.csv", row.names = TRUE)
    
    # --- Visualize significant relationships using signifPlot() ---
    pdf("signifPlot.pdf", width = 8, height = 8)
    signifPlot(
      spicyTest,
      breaks = c(-3, 3, 1),
      marksToPlot = c("Macrophages", "DC_or_Mono", "dn_T_CD3", "Neutrophils",
                      "CD8_T_cell", "Keratin_Tumour")
    )
    dev.off()
    
    # --- Generate boxplots for specific cell-cell relationships ---
    pdf("spicyBoxPlot.pdf", width = 6, height = 6)
    spicyBoxPlot(results = spicyTest, 
                 # from = "Macrophages",
                 # to = "dn_T_CD3"
                 rank = 1)
    dev.off()
    
    # --- Perform mixed-effects modeling by specifying the subject ---
    spicyMixedTest <- spicy(
      diabetesData,
      condition = "stage",
      subject = "case"
    )
    
    # Extract and save mixed-effects modeling results
    mixedResults <- topPairs(spicyMixedTest)
    write.csv(mixedResults, "spicyMixedTest_results.csv", row.names = TRUE)
    saveRDS(spicyMixedTest, "spicyMixedTest.rds")

    writeLines(c(
        '"BIOC_SPICYR_PAIRWISE_LOCALIZATION_MODELING":',
        paste0('        spicyR: ', as.character(packageVersion("spicyR")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_pairwise_localization_modeling.csv versions.yml
    """
}

workflow BIOC_SPICYR_PAIRWISE_LOCALIZATION_MODELING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ kerenSPE, diabetesData ] ]

    main:
    BIOC_SPICYR_PAIRWISE_LOCALIZATION_MODELING(ch_input)

    emit:
    tables   = BIOC_SPICYR_PAIRWISE_LOCALIZATION_MODELING.out.tables
    plots    = BIOC_SPICYR_PAIRWISE_LOCALIZATION_MODELING.out.plots
    objects  = BIOC_SPICYR_PAIRWISE_LOCALIZATION_MODELING.out.objects
    versions = BIOC_SPICYR_PAIRWISE_LOCALIZATION_MODELING.out.versions
}
