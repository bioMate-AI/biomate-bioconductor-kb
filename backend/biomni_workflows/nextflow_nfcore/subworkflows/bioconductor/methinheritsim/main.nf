#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: methInheritSim
// Simulate a multigeneration methylation case versus control experiment with inheritance relation usin
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/methInheritSim/inst/doc/methInheritSim.R
// Upstream  : knitr
// Downstream: none
//
// Install: BiocManager::install("methInheritSim")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_METHINHERITSIM {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-methinheritsim"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-methinheritsim:1.28.0--r44_0' :
        'quay.io/biocontainers/bioconductor-methinheritsim:1.28.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_methinheritsim_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_methinheritsim_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_methinheritsim_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(methInheritSim)
    library(jsonlite)

    # --- Dataset Initialization [methinheritsim] ---
    # Key functions: runSim
    # Load the synthetic template dataset provided by the package
    data("samplesForChrSynthetic", package = "methInheritSim")
    
    # Define the initial parameters for the simulation run
    nb_blocks <- 10
    nb_cpgs <- 20
    total_sites <- nb_blocks * nb_cpgs
    generation_count <- 3

    # --- Multi-Generation Simulation [methinheritsim] ---
    # Key functions: runSim
    data("samplesForChrSynthetic", package = "methInheritSim")
    temp_dir <- "simulation_output"
    
    # Execute the main simulation across multiple generations
    runSim(methData = samplesForChrSynthetic,
           nbSynCHR = 1,
           nbSimulation = 2,
           nbBlock = 10, nbCpG = 20,
           nbGeneration = 3,
           vNbSample = c(3, 6),
           vpDiff = c(0.9),
           vpDiffsd = c(0.1),
           vDiff = c(0.8),
           vInheritance = c(0.5),
           propInherite = 0.3,
           rateDiff = 0.3,
           minRate = 0.2,
           propHetero = 0.5,
           keepDiff = FALSE,
           outputDir = temp_dir,
           fileID = "S1",
           runAnalysis = TRUE,
           nbCores = 1,
           vSeed = 32)

    # --- Methylation State Analysis [methinheritsim] ---
    # Key functions: runSim
    # Load simulated GRanges and state differential files
    synthetic_chr <- readRDS("simulation_output/syntheticChr_S1_1.rds")
    state_diff <- readRDS("simulation_output/stateDiff_S1_1_3_0.9_0.8_0.5_1.rds")
    methyl_gr <- readRDS("simulation_output/methylGR_S1_1_3_0.9_0.8_0.5_1.rds")
    
    # Extract specific generation and sample GRanges for downstream analysis
    f1_sample3_gr <- methyl_gr[[1]][[3]]
    f3_sample4_gr <- methyl_gr[[3]][[4]]

    # --- Differential Methylation Evaluation [methinheritsim] ---
    # Key functions: runSim
    # Load treatment design and differential methylation statistics
    treatment_design <- readRDS("simulation_output/treatment_S1_1_3.rds")
    meth_diff_stats <- readRDS("simulation_output/methDiff_S1_1_3_0.9_0.8_0.5_1.rds")
    
    # Extract differential methylation statistics for the first generation
    f1_diff_stats <- meth_diff_stats[[1]]
    
    # Load and extract multi-sample methylation events
    meth_events <- readRDS("simulation_output/meth_S1_1_3_0.9_0.8_0.5_1.rds")
    f1_meth_events <- meth_events[[1]]


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_methinheritsim_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_methinheritsim_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_methinheritsim_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_METHINHERITSIM:", paste0("    methinheritsim: ", packageVersion("methInheritSim"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_methinheritsim_results.csv
    touch ${prefix}_methinheritsim_output.rds
    echo "BIOC_METHINHERITSIM:" > versions.yml
    echo "    methinheritsim: 0.0.0" >> versions.yml
    """
}


workflow BIOC_METHINHERITSIM_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_METHINHERITSIM(ch_input)

    emit:
    results  = BIOC_METHINHERITSIM.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_METHINHERITSIM.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_METHINHERITSIM.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_METHINHERITSIM.out.versions  // channel: path(versions.yml)
}
