#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: rnaEditr
// RNAeditr analyzes site-specific RNA editing events, as well as hyper-editing regions. The editing fr
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/rnaEditr/inst/doc/introduction_to_rnaEditr.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("rnaEditr")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RNAEDITR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-rnaeditr"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-rnaeditr:1.16.0--r44_0' :
        'quay.io/biocontainers/bioconductor-rnaeditr:1.16.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_rnaeditr_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_rnaeditr_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_rnaeditr_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(AddMetaData)
    library(AllCloseByRegions)
    library(AnnotateResults)
    library(CreateEditingTable)
    library(TestAssociations)
    library(TransformToGR)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: data
    ---------------------------------------------------------------------
    data(rnaedit_df)
    # --- Createeditingtable [] ---
    # Key functions: CreateEditingTable
    ---------------------------------------------------------------------
    rnaedit2_df <- CreateEditingTable(
      rnaEditMatrix = rnaedit_df
    )
    # --- Transformtogr [] ---
    # Key functions: TransformToGR
    ---------------------------------------------------------------------
    # If input is gene symbol
    inputGenes_gr <- TransformToGR(
      # input a character vector of gene symbols
      genes_char = c("PHACTR4", "CCR5", "METTL7A"),
    # --- Transformtogr [] ---
    # Key functions: TransformToGR, AddMetaData
    ---------------------------------------------------------------------
    # If input is region ranges
    inputRegions_gr <- TransformToGR(
      # input a character vector of region ranges.
      genes_char = c("chr22:18555686-18573797", "chr22:36883233-36908148"),
    # --- Annotateresults [] ---
    # Key functions: AnnotateResults, TestAssociations, AllCloseByRegions
    ---------------------------------------------------------------------
    tumor_annot_df <- AnnotateResults(
      # the output dataset from function TestAssociations().
      results_df = tumor_region_df,
      # close-by regions which is a output of AllCloseByRegions().

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_rnaeditr_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_rnaeditr_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_rnaeditr_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_RNAEDITR:", paste0("    rnaeditr: ", packageVersion("rnaEditr"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rnaeditr_results.csv
    touch ${prefix}_rnaeditr_output.rds
    echo "BIOC_RNAEDITR:" > versions.yml
    echo "    rnaeditr: 0.0.0" >> versions.yml
    """
}


workflow BIOC_RNAEDITR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_RNAEDITR(ch_input)

    emit:
    results  = BIOC_RNAEDITR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_RNAEDITR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_RNAEDITR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_RNAEDITR.out.versions  // channel: path(versions.yml)
}
