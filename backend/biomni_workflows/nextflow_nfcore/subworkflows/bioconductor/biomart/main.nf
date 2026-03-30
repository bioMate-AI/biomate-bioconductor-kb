#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: biomaRt
// In recent years a wealth of biological data has become available in public data repositories. Easy a
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/biomaRt/inst/doc/accessing_ensembl.R
// Upstream  : none
// Downstream: chromPlot, customProDB, DrugVsDisease, GenomicOZone, MineICA
//
// Install: BiocManager::install("biomaRt")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BIOMART {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-biomart"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-biomart:2.62.1--r44_0' :
        'quay.io/biocontainers/bioconductor-biomart:2.62.1--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_biomart_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_biomart_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_biomart_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(biomaRt)
    library(jsonlite)

    # --- Query BioMart annotation [] ---
    # Key functions: getBM
    getBM(attributes = c('refsnp_id','allele','chrom_start','chrom_strand'),
    filters = c('chr_name','start','end'),
    values = list(8, 148350, 148420),
    # --- UseEnsembl analysis [] ---
    # Key functions: useEnsembl, listDatasets, searchDatasets, useDataset, listEnsemblArchives, listEnsembl, listEnsemblGenomes, useEnsemblGenomes
    human <- useEnsembl("ensembl", dataset = "hsapiens_gene_ensembl")
    mouse <- useEnsembl("ensembl", dataset = "mmusculus_gene_ensembl")
    getLDS(attributes = c("hgnc_symbol","chromosome_name", "start_position"),

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_biomart_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_biomart_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_biomart_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_BIOMART:", paste0("    biomart: ", packageVersion("biomaRt"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_biomart_results.csv
    touch ${prefix}_biomart_output.rds
    echo "BIOC_BIOMART:" > versions.yml
    echo "    biomart: 0.0.0" >> versions.yml
    """
}


workflow BIOC_BIOMART_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_BIOMART(ch_input)

    emit:
    results  = BIOC_BIOMART.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_BIOMART.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_BIOMART.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_BIOMART.out.versions  // channel: path(versions.yml)
}
