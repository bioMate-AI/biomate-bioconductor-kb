#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: scRepertoire
// scRepertoire is a toolkit for processing and analyzing single-cell T-cell receptor (TCR) and immunog
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/scRepertoire/inst/doc/vignette.R
// Upstream  : BiocStyle, circlize, ggraph, scales, scater
// Downstream: none
//
// Install: BiocManager::install("scRepertoire")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SCREPERTOIRE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-screpertoire"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-screpertoire:2.2.1--r44_0' :
        'quay.io/biocontainers/bioconductor-screpertoire:2.2.1--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_screpertoire_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_screpertoire_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_screpertoire_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(scRepertoire)
    library(jsonlite)

    # --- Clonal Quantification and Abundance [] ---
    # Key functions: clonalQuant, clonalAbundance, clonalLength
    quant <- clonalQuant(
        combined.TCR, cloneCall="strict", chain = "both", scale = TRUE
    )
    abundance <- clonalAbundance(
        combined.TCR, cloneCall = "gene", scale = TRUE
    )
    len <- clonalLength(
        combined.TCR, cloneCall="aa", chain = "both"
    )


    # --- Clonal Comparison and Dynamics [] ---
    # Key functions: clonalCompare, clonalScatter
    comp <- clonalCompare(
        combined.TCR, top.clones = 10, 
        samples = c("P17B", "P17L"), cloneCall="aa", graph = "alluvial"
    )
    scat <- clonalScatter(
        combined.TCR, cloneCall ="gene", x.axis = "P18B", y.axis = "P18L",
        dot.size = "total", graph = "proportion"
    )


    # --- Clonal Homeostasis and Proportion [] ---
    # Key functions: clonalHomeostasis, clonalProportion
    homeo <- clonalHomeostasis(
        combined.TCR, cloneCall = "gene",
        cloneSize = c(Rare = 0.001, Small = 0.01, Medium = 0.1, Large = 0.3)
    )
    prop <- clonalProportion(
        combined.TCR, cloneCall = "nt",
        clonalSplit = c(1, 5, 10, 100, 1000)
    )


    # --- Gene Usage and Diversity Analysis [] ---
    # Key functions: vizGenes, percentAA, positionalEntropy, percentGenes
    vgenes <- vizGenes(
        combined.TCR, x.axis = "TRBV", plot = "barplot", scale = TRUE
    )
    pct_aa <- percentAA(
        combined.TCR, chain = "TRB", aa.length = 20
    )
    entropy <- positionalEntropy(
        combined.TCR, chain = "TRB", aa.length = 20
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_screpertoire_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_screpertoire_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_screpertoire_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SCREPERTOIRE:", paste0("    screpertoire: ", packageVersion("scRepertoire"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_screpertoire_results.csv
    touch ${prefix}_screpertoire_output.rds
    echo "BIOC_SCREPERTOIRE:" > versions.yml
    echo "    screpertoire: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SCREPERTOIRE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SCREPERTOIRE(ch_input)

    emit:
    results  = BIOC_SCREPERTOIRE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SCREPERTOIRE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SCREPERTOIRE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SCREPERTOIRE.out.versions  // channel: path(versions.yml)
}
