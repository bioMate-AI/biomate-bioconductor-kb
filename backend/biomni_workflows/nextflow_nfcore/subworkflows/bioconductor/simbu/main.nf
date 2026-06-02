#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: SimBu
// SimBu can be used to simulate bulk RNA-seq datasets with known cell type fractions. You can either u
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/SimBu/inst/doc/SimBu.R
// Upstream  : Seurat, curl
// Downstream: none
//
// Install: BiocManager::install("SimBu")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SIMBU {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-simbu"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-simbu:1.8.0--r44_0' :
        'quay.io/biocontainers/bioconductor-simbu:1.8.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_simbu_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_simbu_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_simbu_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(SimBu)
    library(jsonlite)

    # --- Bulk Simulation [] ---
    # Key functions: simulate_bulk
    simulation1 <- SimBu::simulate_bulk(
        data = ds,
        scenario = "random",
        scaling_factor = "NONE",
        ncells = 100,
        nsamples = 5,
        run_parallel = FALSE
    )
    simulation2 <- SimBu::simulate_bulk(
        data = ds,
        scenario = "even",
        scaling_factor = "NONE",
        ncells = 100,
        nsamples = 5,
        run_parallel = FALSE
    )


    # --- Simulation Merging and Visualisation [] ---
    # Key functions: merge_simulations, plot_simulation
    merged_simulations <- SimBu::merge_simulations(
        sim_list = list(simulation1, simulation2)
    )
    g_plot <- SimBu::plot_simulation(
        simulation = merged_simulations
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_simbu_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_simbu_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_simbu_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SIMBU:", paste0("    simbu: ", packageVersion("SimBu"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_simbu_results.csv
    touch ${prefix}_simbu_output.rds
    echo "BIOC_SIMBU:" > versions.yml
    echo "    simbu: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SIMBU_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SIMBU(ch_input)

    emit:
    results  = BIOC_SIMBU.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SIMBU.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SIMBU.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SIMBU.out.versions  // channel: path(versions.yml)
}
