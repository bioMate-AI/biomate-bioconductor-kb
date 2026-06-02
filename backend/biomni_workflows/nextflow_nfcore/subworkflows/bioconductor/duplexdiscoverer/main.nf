#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: DuplexDiscovereR
// DuplexDiscovereR is a package designed for analyzing data from RNA cross-linking and proximity ligat
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/DuplexDiscovereR/inst/doc/DuplexDiscovereR.R
// Upstream  : Gviz, UpSetR, devtools
// Downstream: none
//
// Install: BiocManager::install("DuplexDiscovereR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DUPLEXDISCOVERER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-duplexdiscoverer"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-duplexdiscoverer:1.0.0--r44_0' :
        'quay.io/biocontainers/bioconductor-duplexdiscoverer:1.0.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_duplexdiscoverer_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_duplexdiscoverer_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_duplexdiscoverer_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(DuplexDiscovereR)
    library(DuplexTrack)
    library(GRanges)
    library(GeneRegionTrack)
    library(jsonlite)

    # --- Duplex Group Clustering and Collapsing [] ---
    # Key functions: collapseIdenticalReads, clusterDuplexGroups, collapse_duplex_groups
    res_collapse <- collapseIdenticalReads(gi_spliced)
    gi_unique <- res_collapse$gi_collapsed
    gi_clustered <- clusterDuplexGroups(gi_unique)
    gi_dgs <- collapse_duplex_groups(gi_clustered)


    # --- Comparative Interaction Analysis [] ---
    # Key functions: compareMultipleInteractions
    samples_list <- list(
        "sample1" = group1,
        "sample2" = group2,
        "sample3" = group3
    )
    res_comp <- compareMultipleInteractions(samples_list)
    upset_data <- res_comp$dt_upset


    # --- Visualization of Duplex Tracks [] ---
    # Key functions: DuplexTrack
    duplex_track <- DuplexTrack(
        gi = gi_clusters,
        gr_region = plotrange,
        labels.fontsize = 12,
        arcConstrain = 4,
        annotation.column1 = "gene_name.A",
        annotation.column2 = "gene_name.B"
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_duplexdiscoverer_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_duplexdiscoverer_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_duplexdiscoverer_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_DUPLEXDISCOVERER:", paste0("    duplexdiscoverer: ", packageVersion("DuplexDiscovereR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_duplexdiscoverer_results.csv
    touch ${prefix}_duplexdiscoverer_output.rds
    echo "BIOC_DUPLEXDISCOVERER:" > versions.yml
    echo "    duplexdiscoverer: 0.0.0" >> versions.yml
    """
}


workflow BIOC_DUPLEXDISCOVERER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_DUPLEXDISCOVERER(ch_input)

    emit:
    results  = BIOC_DUPLEXDISCOVERER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_DUPLEXDISCOVERER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_DUPLEXDISCOVERER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_DUPLEXDISCOVERER.out.versions  // channel: path(versions.yml)
}
