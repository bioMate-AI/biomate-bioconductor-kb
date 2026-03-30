#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: GEOfastq
// GEOfastq is used to download fastq files from the European Nucleotide Archive (ENA) starting with an
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/GEOfastq/inst/doc/GEOfastq.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("GEOfastq")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GEOFASTQ {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-geofastq"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-geofastq:1.14.0--r44_0' :
        'quay.io/biocontainers/bioconductor-geofastq:1.14.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_geofastq_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_geofastq_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_geofastq_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(GEOfastq)
    library(jsonlite)

    # --- Crawl Gse [] ---
    # Key functions: crawl_gse
    ---------------------------------------------------------------------
    gse_name <- 'GSE133758'
    gse_text <- crawl_gse(gse_name)
    # --- Extract Gsms [] ---
    # Key functions: extract_gsms, crawl_gsms
    ---------------------------------------------------------------------
    gsm_names <- extract_gsms(gse_text)
    gsm_name <- gsm_names[182]
    srp_meta <- crawl_gsms(gsm_name)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_geofastq_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_geofastq_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_geofastq_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GEOFASTQ:", paste0("    geofastq: ", packageVersion("GEOfastq"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_geofastq_results.csv
    touch ${prefix}_geofastq_output.rds
    echo "BIOC_GEOFASTQ:" > versions.yml
    echo "    geofastq: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GEOFASTQ_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GEOFASTQ(ch_input)

    emit:
    results  = BIOC_GEOFASTQ.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GEOFASTQ.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GEOFASTQ.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GEOFASTQ.out.versions  // channel: path(versions.yml)
}
