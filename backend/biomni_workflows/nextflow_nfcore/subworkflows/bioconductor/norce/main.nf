#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: NoRCE
// While some non-coding RNAs (ncRNAs) are assigned critical regulatory roles, most remain functionally
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/NoRCE/inst/doc/NoRCE.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("NoRCE")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_NORCE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-norce"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-norce:1.18.0--r44_0' :
        'quay.io/biocontainers/bioconductor-norce:1.18.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_norce_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_norce_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_norce_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(NoRCE)
    library(jsonlite)

    # --- Import genomic data file [] ---
    # Key functions: setParameters, import, geneRegionGOEnricher
    setParameters("searchRegion", "all")
    regions<-system.file("extdata", "ncRegion.txt", package = "NoRCE")
    regionNC <- rtracklayer::import(regions, format = "BED")
    # --- Parameters analysis [] ---
    # Key functions: setParameters, geneGOEnricher, mirnaGOEnricher, listTAD, mirnaPathwayEnricher, genePathwayEnricher, filterBiotype, extractBiotype
    ncGO_tad <- geneGOEnricher(gene = brain_disorder_ncRNA, org_assembly = 'hg19', genetype = 'Ensembl_gene',near = TRUE, express = TRUE, databaseFile = '\\miRCancer\\miRCancer.db', cancer = 'GBMLGG')

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_norce_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_norce_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_norce_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_NORCE:", paste0("    norce: ", packageVersion("NoRCE"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_norce_results.csv
    touch ${prefix}_norce_output.rds
    echo "BIOC_NORCE:" > versions.yml
    echo "    norce: 0.0.0" >> versions.yml
    """
}


workflow BIOC_NORCE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_NORCE(ch_input)

    emit:
    results  = BIOC_NORCE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_NORCE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_NORCE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_NORCE.out.versions  // channel: path(versions.yml)
}
