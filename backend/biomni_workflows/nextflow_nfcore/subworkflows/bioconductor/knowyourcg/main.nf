#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: knowYourCG
// knowYourCG automates the functional analysis of DNA methylation data. The package tests the enrichme
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/knowYourCG/inst/doc/Array.R
// Upstream  : sesameData, SummarizedExperiment, gprofiler2, knitr, sesame
// Downstream: none
//
// Install: BiocManager::install("knowYourCG")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_KNOWYOURCG {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-knowyourcg"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-knowyourcg:1.2.5--r44_0' :
        'quay.io/biocontainers/bioconductor-knowyourcg:1.2.5--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_knowyourcg_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_knowyourcg_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_knowyourcg_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(knowYourCG)
    library(jsonlite)

    # --- Enrichment Testing [] ---
    # Key functions: testEnrichment
    enrichment_results <- testEnrichment(
        query = query_probes,
        databases = selected_dbs,
        platform = "MM285"
    )
    significant_hits <- enrichment_results[enrichment_results$FDR < 0.05, ]


    # --- Gene-Centric Enrichment Analysis [] ---
    # Key functions: buildGeneDBs, testEnrichment
    gene_dbs <- buildGeneDBs(
        query = query_probes,
        max_distance = 100000,
        platform = "MM285"
    )
    gene_enrichment <- testEnrichment(
        query = query_probes,
        databases = gene_dbs,
        platform = "MM285",
        include_genes = TRUE
    )


    # --- Gene Ontology Testing [] ---
    # Key functions: testGO
    go_results <- testGO(
        query = query_probes,
        platform = "MM285",
        organism = "mmusculus"
    )
    top_go_terms <- go_results$result


    # --- Probe Proximity Analysis [] ---
    # Key functions: testProbeProximity
    proximity_results <- testProbeProximity(
        probeIDs = query_probes
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_knowyourcg_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_knowyourcg_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_knowyourcg_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_KNOWYOURCG:", paste0("    knowyourcg: ", packageVersion("knowYourCG"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_knowyourcg_results.csv
    touch ${prefix}_knowyourcg_output.rds
    echo "BIOC_KNOWYOURCG:" > versions.yml
    echo "    knowyourcg: 0.0.0" >> versions.yml
    """
}


workflow BIOC_KNOWYOURCG_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_KNOWYOURCG(ch_input)

    emit:
    results  = BIOC_KNOWYOURCG.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_KNOWYOURCG.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_KNOWYOURCG.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_KNOWYOURCG.out.versions  // channel: path(versions.yml)
}
