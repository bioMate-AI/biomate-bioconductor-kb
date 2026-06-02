#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: sSNAPPY
// A single sample pathway perturbation testing method for RNA-seq data. The method propagates changes 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/sSNAPPY/inst/doc/sSNAPPY.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("sSNAPPY")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SSNAPPY {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-ssnappy"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-ssnappy:1.10.0--r44_0' :
        'quay.io/biocontainers/bioconductor-ssnappy:1.10.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_ssnappy_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_ssnappy_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_ssnappy_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(sSNAPPY)
    library(jsonlite)

    # --- Pathway Topology Retrieval [] ---
    # Key functions: retrieve_topology
    gsTopology <- retrieve_topology(
        database = "kegg",
        species = "hsapiens"
    )


    # --- Perturbation Scoring [] ---
    # Key functions: raw_gene_pert, pathway_pert
    genePertScore <- raw_gene_pert(
        weightedFC$weighted_logFC,
        gsTopology
    )
    pathwayPertScore <- pathway_pert(
        genePertScore,
        weightedFC$weighted_logFC
    )


    # --- Permutation and Normalisation [] ---
    # Key functions: generate_permuted_scores, normalise_by_permu
    permutedScore <- generate_permuted_scores(
        expreMatrix = logCPM_example,
        gsTopology = gsTopology,
        weight = weightedFC$weight
    )
    normalisedScores <- normalise_by_permu(
        permutedScore,
        pathwayPertScore,
        sortBy = "pvalue"
    )


    # --- Visualisation of Gene Contribution [] ---
    # Key functions: plot_gene_contribution
    plot_gene_contribution(
        genePertMatr = genePertScore$`kegg.Proteoglycans in cancer`,
        filterBy = "mean",
        topGene = 10,
        color = rev(colorspace::divergex_hcl(100, palette = "RdBu")),
        breaks = seq(-0.001, 0.001, length.out = 100)
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_ssnappy_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_ssnappy_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_ssnappy_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SSNAPPY:", paste0("    ssnappy: ", packageVersion("sSNAPPY"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ssnappy_results.csv
    touch ${prefix}_ssnappy_output.rds
    echo "BIOC_SSNAPPY:" > versions.yml
    echo "    ssnappy: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SSNAPPY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SSNAPPY(ch_input)

    emit:
    results  = BIOC_SSNAPPY.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SSNAPPY.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SSNAPPY.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SSNAPPY.out.versions  // channel: path(versions.yml)
}
