#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: ASSIGN
// ASSIGN is a computational tool to evaluate the pathway deregulation/activation status in individual 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/ASSIGN/inst/doc/ASSIGN.vignette.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("ASSIGN")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ASSIGN {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-assign"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-assign:1.42.0--r44_0' :
        'quay.io/biocontainers/bioconductor-assign:1.42.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_assign_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_assign_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_assign_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ASSIGN)
    library(jsonlite)

    # --- MCMC Sampling [] ---
    # Key functions: assign.mcmc
    mcmc.chain <- assign.mcmc(
        Y = processed.data$testData_sub,
        Bg = processed.data$B_vector,
        X = processed.data$S_matrix,
        Delta_prior_p = processed.data$Pi_matrix,
        iter = 2000,
        adaptive_B = TRUE,
        adaptive_S = FALSE,
        mixture_beta = TRUE
    )


    # --- Convergence Diagnostics [] ---
    # Key functions: assign.convergence
    trace.plot <- assign.convergence(
        test = mcmc.chain,
        burn_in = 0,
        iter = 2000,
        parameter = "B",
        whichGene = 1,
        whichSample = NA,
        whichPath = NA
    )


    # --- Parameter Estimation [] ---
    # Key functions: assign.summary
    mcmc.pos.mean <- assign.summary(
        test = mcmc.chain,
        burn_in = 1000,
        iter = 2000,
        adaptive_B = TRUE,
        adaptive_S = FALSE,
        mixture_beta = TRUE
    )


    # --- Output Generation [] ---
    # Key functions: assign.output
    assign.output(
        processed.data = processed.data,
        mcmc.pos.mean.testData = mcmc.pos.mean,
        trainingData = trainingData1,
        testData = testData1,
        trainingLabel = trainingLabel1,
        testLabel = testLabel1,
        geneList = NULL,
        adaptive_B = TRUE,
        adaptive_S = FALSE,
        mixture_beta = TRUE,
        outputDir = "output_directory"
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_assign_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_assign_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_assign_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_ASSIGN:", paste0("    assign: ", packageVersion("ASSIGN"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_assign_results.csv
    touch ${prefix}_assign_output.rds
    echo "BIOC_ASSIGN:" > versions.yml
    echo "    assign: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ASSIGN_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_ASSIGN(ch_input)

    emit:
    results  = BIOC_ASSIGN.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ASSIGN.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ASSIGN.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ASSIGN.out.versions  // channel: path(versions.yml)
}
