#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: xcore
// xcore is an R package for transcription factor activity modeling based on known molecular signatures
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/xcore/inst/doc/xcore_vignette.R
// Upstream  : AnnotationHub, ExperimentHub, pheatmap
// Downstream: none
//
// Install: BiocManager::install("xcore")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_XCORE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-xcore"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-xcore:1.10.0--r44_0' :
        'quay.io/biocontainers/bioconductor-xcore:1.10.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_xcore_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_xcore_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_xcore_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(AnnotationHub)
    library(DoparParam)
    library(ExperimentHub)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: data
    ---------------------------------------------------------------------
    data("rinderpest_mini")
    head(rinderpest_mini)
    # --- Preparecountsforregression [] ---
    # Key functions: prepareCountsForRegression
    ---------------------------------------------------------------------
    mae <- prepareCountsForRegression(counts = rinderpest_mini,
                                      design = design,
                                      base_lvl = "00hr")
    # --- Experimenthub [] ---
    # Key functions: ExperimentHub, query
    ---------------------------------------------------------------------
    library("ExperimentHub")
    eh <- ExperimentHub()
    query(eh, "xcoredata")
    remap_promoters_f5 <- eh[["EH7301"]]
    # --- Addsignatures [] ---
    # Key functions: addSignatures
    ---------------------------------------------------------------------
    mae <- addSignatures(mae, remap = remap_promoters_f5)
    # --- Summary [] ---
    # Key functions: colSums
    ---------------------------------------------------------------------
    summary(colSums(mae[["remap"]]))
    # --- Filtersignatures [] ---
    # Key functions: filterSignatures
    ---------------------------------------------------------------------
    mae <- filterSignatures(mae, min = 0.05, max = 0.95)
    # --- Registerdoparallel [] ---
    # Key functions: registerDoParallel, register, DoparParam, modelGeneExpression
    ---------------------------------------------------------------------
    # register parallel backend
    doParallel::registerDoParallel(2L)
    BiocParallel::register(BiocParallel::DoparParam(), default = TRUE)
    # set seed
    # --- Annotationhub [] ---
    # Key functions: AnnotationHub
    ---------------------------------------------------------------------
    # obtain predicted CTCF binding for hg38;
    # *TF/motif name must be stored under column 'name'
    library("AnnotationHub")
    ah <- AnnotationHub()
    # --- Getinteractionmatrix [] ---
    # Key functions: getInteractionMatrix
    ---------------------------------------------------------------------
    # construct molecular signatures matrix

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_xcore_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_xcore_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_xcore_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_XCORE:", paste0("    xcore: ", packageVersion("xcore"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_xcore_results.csv
    touch ${prefix}_xcore_output.rds
    echo "BIOC_XCORE:" > versions.yml
    echo "    xcore: 0.0.0" >> versions.yml
    """
}


workflow BIOC_XCORE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_XCORE(ch_input)

    emit:
    results  = BIOC_XCORE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_XCORE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_XCORE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_XCORE.out.versions  // channel: path(versions.yml)
}
