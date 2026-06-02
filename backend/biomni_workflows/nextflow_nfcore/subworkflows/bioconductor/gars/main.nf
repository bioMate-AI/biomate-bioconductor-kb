#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: GARS
// Feature selection aims to identify and remove redundant, irrelevant and noisy variables from high-di
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/GARS/inst/doc/GARS.R
// Upstream  : DaMiRseq, MLSeq
// Downstream: none
//
// Install: BiocManager::install("GARS")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GARS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-gars"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-gars:1.26.0--r44_0' :
        'quay.io/biocontainers/bioconductor-gars:1.26.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_gars_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_gars_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_gars_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(GARS)
    library(AllPop)
    library(FitScore)
    library(GARS_GA)
    library(GARS_PlotFeaturesUsage)
    library(GARS_PlotFitnessEvolution)
    library(MatrixFeatures)
    library(jsonlite)

    # --- Genetic Algorithm Feature Selection [] ---
    # Key functions: GARS_GA
    res_GA <- GARS_GA(data=datanorm,
                     classes = SummarizedExperiment::colData(datanorm),
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
                     verbose="no")


    # --- Fitness and Feature Usage Analysis [] ---
    # Key functions: FitScore, GARS_PlotFitnessEvolution, AllPop, GARS_PlotFeaturesUsage
    fitness_scores <- FitScore(res_GA)
    GARS_PlotFitnessEvolution(fitness_scores)
    Allfeat_names <- rownames(datanorm)
    Allpopulations <- AllPop(res_GA)
    GARS_PlotFeaturesUsage(Allpopulations,
                           Allfeat_names,
                           nFeat = 10)


    # --- Feature Extraction and Classification [] ---
    # Key functions: MatrixFeatures, DaMiR.MDSplot, DaMiR.Clustplot, DaMiR.EnsembleLearning
    data_reduced_GARS <- MatrixFeatures(res_GA)
    data_reduced_DaMiR <- as.data.frame(data_reduced_GARS)
    classes_DaMiR <- as.data.frame(SummarizedExperiment::colData(datanorm))
    colnames(classes_DaMiR) <- "class"
    rownames(classes_DaMiR) <- rownames(data_reduced_DaMiR)
    DaMiRseq::DaMiR.MDSplot(data_reduced_DaMiR, classes_DaMiR)
    DaMiRseq::DaMiR.Clustplot(data_reduced_DaMiR, classes_DaMiR)
    Classification.res <- DaMiRseq::DaMiR.EnsembleLearning(
        data_reduced_DaMiR,
        as.factor(classes_DaMiR$class),
        iter=5
    )


    # --- Feature Size Optimization [] ---
    # Key functions: GARS_GA, FitScore, MatrixFeatures
    populs <- list()
    k <- 1
    for (ik in c(7, 8, 9)) {
        populs[[k]] <- GARS_GA(data=datanorm,
                              classes = SummarizedExperiment::colData(datanorm),
                              chr.num = 50,
                              chr.len = ik,
                              generat = 10,
                              co.rate = 0.8,
                              mut.rate = 0.1,
                              n.elit = 5,
                              type.sel = "RW",
                              type.co = "one.p",
                              type.one.p.co = "II.quart",
                              n.gen.conv = 100,
                              plots = "no",
                              verbose="no")
        k <- k + 1
    }
    max_fit <- sapply(populs, function(x) max(FitScore(x)))
    best_popul <- populs[[which.max(max_fit)]]
    best_features <- MatrixFeatures(best_popul)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_gars_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_gars_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_gars_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GARS:", paste0("    gars: ", packageVersion("GARS"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gars_results.csv
    touch ${prefix}_gars_output.rds
    echo "BIOC_GARS:" > versions.yml
    echo "    gars: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GARS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GARS(ch_input)

    emit:
    results  = BIOC_GARS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GARS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GARS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GARS.out.versions  // channel: path(versions.yml)
}
