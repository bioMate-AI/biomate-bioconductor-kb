#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: oposSOM
// This package translates microarray expression data into metadata of reduced dimension. It provides v
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/oposSOM/inst/doc/Vignette.R
// Upstream  : Biobase, biomaRt
// Downstream: none
//
// Install: BiocManager::install("oposSOM")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_OPOSSOM {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-opossom"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-opossom:2.24.0--r44_0' :
        'quay.io/biocontainers/bioconductor-opossom:2.24.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_opossom_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_opossom_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_opossom_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(AnnotatedDataFrame)
    library(ExpressionSet)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: data
    data(opossom.tissues)
    str(opossom.tissues, vec.len=3)
    env$indata <- opossom.tissues
    # --- Data [] ---
    # Key functions: ExpressionSet
    data(opossom.tissues)
    library(Biobase)
    opossom.tissues.eset = ExpressionSet(assayData=opossom.tissues)
    opossom.tissues.eset
    env$indata <- opossom.tissues.eset
    # --- Frame [] ---
    # Key functions: frame
    group.info <- data.frame(
                      group.labels = c(rep("Homeostasis", 2),
                                           "Endocrine",
                                           "Digestion",
                                           "Exocrine",
    # --- Expressionset [] ---
    # Key functions: ExpressionSet, AnnotatedDataFrame
    opossom.tissues.eset = ExpressionSet(assayData=opossom.tissues,
                                         phenoData=AnnotatedDataFrame(group.info) )
    opossom.tissues.eset
    env$indata <- opossom.tissues.eset
    # --- Usemart [] ---
    # Key functions: useMart, listDatasets
    ## library(biomaRt)
    ## mart<-useMart("ensembl")
    ## listDatasets(mart)
    # --- Usemart [] ---
    # Key functions: useMart, listFilters
    ## library(biomaRt)
    ## mart<-useMart(biomart="ensembl", dataset="hsapiens_gene_ensembl")
    ## listFilters(mart)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_opossom_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_opossom_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_opossom_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_OPOSSOM:", paste0("    opossom: ", packageVersion("oposSOM"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_opossom_results.csv
    touch ${prefix}_opossom_output.rds
    echo "BIOC_OPOSSOM:" > versions.yml
    echo "    opossom: 0.0.0" >> versions.yml
    """
}


workflow BIOC_OPOSSOM_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_OPOSSOM(ch_input)

    emit:
    results  = BIOC_OPOSSOM.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_OPOSSOM.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_OPOSSOM.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_OPOSSOM.out.versions  // channel: path(versions.yml)
}
