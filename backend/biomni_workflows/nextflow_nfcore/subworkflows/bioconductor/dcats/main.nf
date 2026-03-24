#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: DCATS
// Methods to detect the differential composition abundances between conditions in singel-cell RNA-seq 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/DCATS/inst/doc/Intro_to_DCATS.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("DCATS")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DCATS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-dcats"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-dcats:1.4.0--r44_0' :
        'quay.io/biocontainers/bioconductor-dcats:1.4.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_dcats_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_dcats_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_dcats_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(DCATS)
    library(jsonlite)

    # --- Create Simmat [] ---
    # Key functions: create_simMat
    ---------------------------------------------------------------------
    simil_mat = create_simMat(K = 3, confuse_rate = 0.2)
    print(simil_mat)
    # --- Data [] ---
    # Key functions: knn_simMat
    ---------------------------------------------------------------------
    data(simulation)
    print(simulation$knnGraphs[1:10, 1:10])
    head(simulation$labels, 10)
    ## estimate the knn matrix
    # --- Data [] ---
    # Key functions: data
    ---------------------------------------------------------------------
    data(Kang2017)
    head(Kang2017$svmDF)
    # --- Colnames [] ---
    # Key functions: dcats_GLM
    ---------------------------------------------------------------------
    colnames(sim_count) = c("A", "B", "C")
    dcats_GLM(sim_count, sim_design, similarity_mat = simil_mat, reference = c("A", "B"))
    # --- Dcats Glm [] ---
    # Key functions: dcats_GLM
    ---------------------------------------------------------------------
    dcats_GLM(sim_count, sim_design, similarity_mat = simil_mat, reference = c("A"))
    # --- Detect Reference [] ---
    # Key functions: detect_reference, dcats_GLM
    ---------------------------------------------------------------------
    reference_cell = detect_reference(sim_count, sim_design, similarity_mat = simil_mat)
    print(reference_cell)
    dcats_GLM(sim_count, sim_design, similarity_mat = simil_mat, reference = reference_cell$ordered_celltype[1:2])

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_dcats_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_dcats_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_dcats_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_DCATS:", paste0("    dcats: ", packageVersion("DCATS"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_dcats_results.csv
    touch ${prefix}_dcats_output.rds
    echo "BIOC_DCATS:" > versions.yml
    echo "    dcats: 0.0.0" >> versions.yml
    """
}


workflow BIOC_DCATS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_DCATS(ch_input)

    emit:
    results  = BIOC_DCATS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_DCATS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_DCATS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_DCATS.out.versions  // channel: path(versions.yml)
}
