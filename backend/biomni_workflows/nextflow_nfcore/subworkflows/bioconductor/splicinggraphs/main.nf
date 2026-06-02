#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: SplicingGraphs
// This package allows the user to create, manipulate, and visualize splicing graphs and their bubbles 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/SplicingGraphs/inst/doc/SplicingGraphs.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("SplicingGraphs")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SPLICINGGRAPHS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-splicinggraphs"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-splicinggraphs:1.46.0--r44_0' :
        'quay.io/biocontainers/bioconductor-splicinggraphs:1.46.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_splicinggraphs_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_splicinggraphs_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_splicinggraphs_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(CharacterList)
    library(FALSE)
    library(GRanges)
    library(IRanges)
    library(ScanBamParam)
    library(SplicingGraphs)
    library(jsonlite)

    # --- Splicing Graph Feature Extraction [] ---
    # Key functions: sgedges, sgnodes, sgedgesByGene
    edges_3183 <- sgedges(sg["3183"])
    nodes_3183 <- sgnodes(sg["3183"])
    edges_by_gene <- sgedgesByGene(sg)


    # --- Alternative Splicing Event Detection [] ---
    # Key functions: bubbles
    as_bubbles <- bubbles(sg["7597"])
    codes <- as_bubbles$AScode


    # --- Read Assignment and Counting [] ---
    # Key functions: countReads, sgedgesByTranscript
    sg_counts <- countReads(sg)
    edges_by_tx <- sgedgesByTranscript(sg["3183"], with.hits.mcols = TRUE)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_splicinggraphs_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_splicinggraphs_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_splicinggraphs_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SPLICINGGRAPHS:", paste0("    splicinggraphs: ", packageVersion("SplicingGraphs"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_splicinggraphs_results.csv
    touch ${prefix}_splicinggraphs_output.rds
    echo "BIOC_SPLICINGGRAPHS:" > versions.yml
    echo "    splicinggraphs: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SPLICINGGRAPHS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SPLICINGGRAPHS(ch_input)

    emit:
    results  = BIOC_SPLICINGGRAPHS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SPLICINGGRAPHS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SPLICINGGRAPHS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SPLICINGGRAPHS.out.versions  // channel: path(versions.yml)
}
