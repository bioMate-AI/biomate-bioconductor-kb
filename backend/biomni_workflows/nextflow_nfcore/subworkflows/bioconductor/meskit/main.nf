#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: MesKit
// MesKit provides commonly used analysis and visualization modules based on mutational data generated 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/MesKit/inst/doc/MesKit.R
// Upstream  : ComplexHeatmap, clusterProfiler
// Downstream: none
//
// Install: BiocManager::install("MesKit")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MESKIT {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-meskit"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-meskit:1.16.0--r44_0' :
        'quay.io/biocontainers/bioconductor-meskit:1.16.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_meskit_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_meskit_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_meskit_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(MesKit)
    library(jsonlite)


    # --- Warning=false [] ---
    # Key functions: mathScore
    # calculate MATH score of each sample
    mathScore(maf, patient.id = 'V402')

    # --- Warning = False [] ---
    # Key functions: mutTrunkBranch
    mutClass <- mutTrunkBranch(phyloTree, CT = TRUE, plot = TRUE)
    names(mutClass)

    # --- Warning = False [] ---
    # Key functions: meskit
    mutClass$mutTrunkBranch.res
    mutClass$mutTrunkBranch.plot

    # --- Warning = False [] ---
    # Key functions: triMatrix, plotMutSigProfile
    trimatrix_V402 <- triMatrix(phyloTree, level = 5)
    # Visualize the 96 trinucleodide mutational profile
    plotMutSigProfile(trimatrix_V402)[[1]]

    # --- Warning = False [] ---
    # Key functions: Heatmap
    # Below plot shows cosine similarities between the mutational profile of each group and COSMIC signatures
    library(ComplexHeatmap)
    ComplexHeatmap::Heatmap(fit_V402$V402$cosine.similarity, name = "Cosine similarity")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_meskit_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_meskit_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_meskit_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MESKIT:", paste0("    meskit: ", packageVersion("MesKit"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_meskit_results.csv
    touch ${prefix}_meskit_output.rds
    echo "BIOC_MESKIT:" > versions.yml
    echo "    meskit: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MESKIT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MESKIT(ch_input)

    emit:
    results  = BIOC_MESKIT.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MESKIT.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MESKIT.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MESKIT.out.versions  // channel: path(versions.yml)
}
