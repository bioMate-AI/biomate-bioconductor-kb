#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: GARS — find_optimal_features_loop
// Run GARS_GA across a range of chromosome lengths to identify the feature subset size that yields the highest fitness score.
// Input: datanorm
// Container: quay.io/biocontainers/bioconductor-gars:1.30.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: GARS, SummarizedExperiment
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Loop through different chromosome lengths (chr.len) and run GARS_GA for each
//  * 2. [Core Analysis] Extract the maximum fitness score for each run
//  * 3. [Core Analysis] Identify the best population with the highest fitness score
//  * 4. [Core Analysis] Extract the selected features from the best population

nextflow.enable.dsl = 2

process BIOC_GARS_FIND_OPTIMAL_FEATURES_LOOP {
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
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
    
    # Load required libraries
    library(GARS)
    
    # Read input file from the working directory
    if (file.exists("datanorm.rds")) {
      datanorm <- readRDS("datanorm.rds")
    } else if (file.exists("datanorm")) {
      datanorm <- readRDS("datanorm")
    } else {
      stop("Input file 'datanorm.rds' or 'datanorm' not found in the working directory.")
    }
    
    # Handle class labels depending on the input object type
    if (inherits(datanorm, "SummarizedExperiment")) {
      classes_info <- colData(datanorm)
    } else {
      classes_info <- data.frame(class = gsub('[0-9]+', '', colnames(datanorm)))
      rownames(classes_info) <- colnames(datanorm)
    }
    
    # 1. Loop through different chromosome lengths (chr.len) and run GARS_GA for each
    populs <- list()
    k=1
    for (ik in c(7,8,9)){
      set.seed(1)
      cat(ik, "features","\n")
      populs[[k]] <- GARS_GA(data=datanorm,
                            classes = classes_info,
                            chr.num = 100,
                            chr.len = ik,
                            generat = 20,
                            co.rate = 0.8,
                            mut.rate = 0.1,
                            n.elit = 10,
                            type.sel = "RW",
                            type.co = "one.p",
                            type.one.p.co = "II.quart",
                            n.gen.conv = 150,
                            plots = "no",
                            verbose="no")
    
      k <- k +1
    
    }
    
    # 2. Extract the maximum fitness score for each run
    max_fit <- 0
    
    for (i in seq_len(length(populs))){
      max_fit[i] <- max(FitScore(populs[[i]]))
    }
    
    # Save max fitness scores to a CSV file
    max_fit_df <- data.frame(
      chr_len = c(7, 8, 9),
      max_fitness = max_fit
    )
    write.csv(max_fit_df, "max_fitness_scores.csv", row.names = FALSE)
    
    # 3. Identify the best population with the highest fitness score
    best_popul <- populs[[which.max(max_fit)]]
    saveRDS(best_popul, "best_population.rds")
    
    # 4. Extract the selected features from the best population
    selected_features_matrix <- MatrixFeatures(best_popul)
    write.csv(as.data.frame(selected_features_matrix), "selected_features.csv", row.names = TRUE)
    
    # Generate and save diagnostic plots for the best population
    tryCatch({
      pdf("best_fitness_evolution.pdf")
      best_fitness_scores <- FitScore(best_popul)
      GARS_PlotFitnessEvolution(best_fitness_scores)
      dev.off()
    }, error = function(e) {
      warning("Could not generate fitness evolution plot: ", e\$message)
    })
    
    tryCatch({
      pdf("best_features_usage.pdf")
      Allfeat_names <- rownames(datanorm)
      Allpopulations <- AllPop(best_popul)
      GARS_PlotFeaturesUsage(Allpopulations, Allfeat_names, nFeat = 10)
      dev.off()
    }, error = function(e) {
      warning("Could not generate features usage plot: ", e\$message)
    })

    writeLines(c(
        '"BIOC_GARS_FIND_OPTIMAL_FEATURES_LOOP":',
        paste0('    GARS: ', as.character(packageVersion('GARS')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_find_optimal_features_loop.csv versions.yml
    """
}

workflow BIOC_GARS_FIND_OPTIMAL_FEATURES_LOOP_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ datanorm ] ]

    main:
    BIOC_GARS_FIND_OPTIMAL_FEATURES_LOOP(ch_input)

    emit:
    tables   = BIOC_GARS_FIND_OPTIMAL_FEATURES_LOOP.out.tables
    plots    = BIOC_GARS_FIND_OPTIMAL_FEATURES_LOOP.out.plots
    objects  = BIOC_GARS_FIND_OPTIMAL_FEATURES_LOOP.out.objects
    versions = BIOC_GARS_FIND_OPTIMAL_FEATURES_LOOP.out.versions
}
