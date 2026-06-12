#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: GARS — feature_selection_gars
// Run the genetic algorithm to select a robust subset of features from normalized high-dimensional data and visualize the results.
// Input: datanorm
// Container: quay.io/biocontainers/bioconductor-gars:1.30.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: GARS, SummarizedExperiment
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run GARS_GA to perform genetic algorithm-based feature selection
//  * 2. [Visualization & Output] Extract fitness scores and plot fitness evolution
//  * 3. [Visualization & Output] Extract populations and plot feature usage frequency
//  * 4. [Core Analysis] Extract the reduced expression matrix of selected features

nextflow.enable.dsl = 2

process BIOC_GARS_FEATURE_SELECTION_GARS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20"

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
    .bm_deps <- c("GARS", "SummarizedExperiment")
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
 library(GARS)
        
        # 1. Read User Input
        # The pipeline expects 'datanorm' to be a SummarizedExperiment object
        # containing the normalized expression data and sample metadata (colData).
        if (file.exists("datanorm.rds")) {
          datanorm <- readRDS("datanorm.rds")
        } else {
          stop("Error: Input file 'datanorm.rds' containing the SummarizedExperiment object was not found in the working directory.")
        }
        
        # Set seed for reproducibility
        set.seed(123)
        
        # 2. Run GARS_GA to perform genetic algorithm-based feature selection
        res_GA <- GARS_GA(data=datanorm,
                         classes = colData(datanorm),
                         chr.num = 100,
                         chr.len = 8,
                         generat = 20,
                         co.rate = 0.8,
                         mut.rate = 0.1,
                         n.elit = 10,
                         type.sel = "RW",
                         type.co = "one.p",
                         type.one.p.co = "II.quart",
                         n.gen.conv = 150,
                         plots="no",
                         verbose="yes")
        
        # Save the GarsSelectedFeatures object
        saveRDS(res_GA, "res_GA.rds")
        
        # 3. Extract fitness scores and plot fitness evolution
        fitness_scores <- FitScore(res_GA)
        write.csv(as.data.frame(fitness_scores), "fitness_scores.csv", row.names = FALSE)
        
        pdf("fitness_evolution.pdf", width = 8, height = 6)
        print(GARS_PlotFitnessEvolution(fitness_scores))
        dev.off()
        
        # 4. Extract populations and plot feature usage frequency
        Allfeat_names <- rownames(datanorm)
        Allpopulations <- AllPop(res_GA)
        
        pdf("features_usage.pdf", width = 10, height = 8)
        print(GARS_PlotFeaturesUsage(Allpopulations,
                               Allfeat_names,
                               nFeat = 10))
        dev.off()
        
        # 5. Extract the reduced expression matrix of selected features
        data_reduced_GARS <- MatrixFeatures(res_GA)
        
        # Save the reduced expression matrix
        saveRDS(data_reduced_GARS, "data_reduced_GARS.rds")
        write.csv(as.data.frame(data_reduced_GARS), "data_reduced_GARS.csv")

    writeLines(c(
        '"BIOC_GARS_FEATURE_SELECTION_GARS":',
        paste0('    GARS: ', as.character(packageVersion('GARS')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_feature_selection_gars.csv versions.yml
    """
}

workflow BIOC_GARS_FEATURE_SELECTION_GARS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ datanorm ] ]

    main:
    BIOC_GARS_FEATURE_SELECTION_GARS(ch_input)

    emit:
    tables   = BIOC_GARS_FEATURE_SELECTION_GARS.out.tables
    plots    = BIOC_GARS_FEATURE_SELECTION_GARS.out.plots
    objects  = BIOC_GARS_FEATURE_SELECTION_GARS.out.objects
    versions = BIOC_GARS_FEATURE_SELECTION_GARS.out.versions
}
