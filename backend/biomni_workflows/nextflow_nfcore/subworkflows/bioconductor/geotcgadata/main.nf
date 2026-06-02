#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: GeoTcgaData
// Gene Expression Omnibus(GEO) and The Cancer Genome Atlas (TCGA) provide us with a wealth of data, su
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/GeoTcgaData/inst/doc/GeoTcgaData.R
// Upstream  : ChAMP
// Downstream: none
//
// Install: BiocManager::install("GeoTcgaData")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GEOTCGADATA {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-geotcgadata"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-geotcgadata:2.6.0--r44_0' :
        'quay.io/biocontainers/bioconductor-geotcgadata:2.6.0--r44_0'}"

    input:
    tuple val(meta), path(deseq2results)

    output:
    tuple val(meta), path("${meta.id}_geotcgadata_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_geotcgadata_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_geotcgadata_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(GeoTcgaData)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: countToFpkm
    ---------------------------------------------------------------------
    data(gene_cov)
    lung_squ_count2 <- matrix(c(1,2,3,4,5,6,7,8,9),ncol=3)
    rownames(lung_squ_count2) <- c("DISC1","TCOF1","SPPL3")
    colnames(lung_squ_count2) <- c("sample1","sample2","sample3")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_geotcgadata_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_geotcgadata_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_geotcgadata_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GEOTCGADATA:", paste0("    geotcgadata: ", packageVersion("GeoTcgaData"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_geotcgadata_results.csv
    touch ${prefix}_geotcgadata_output.rds
    echo "BIOC_GEOTCGADATA:" > versions.yml
    echo "    geotcgadata: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GEOTCGADATA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(deseq2results) ]

    main:
    BIOC_GEOTCGADATA(ch_input)

    emit:
    results  = BIOC_GEOTCGADATA.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GEOTCGADATA.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GEOTCGADATA.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GEOTCGADATA.out.versions  // channel: path(versions.yml)
}
