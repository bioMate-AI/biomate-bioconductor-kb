#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: puma
// Most analyses of Affymetrix GeneChip data (including tranditional 3' arrays and exon arrays and Huma
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/puma/inst/doc/puma.R
// Upstream  : Rmpi, oligo, pumadata, snow
// Downstream: none
//
// Install: BiocManager::install("puma")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PUMA {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-puma"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-puma:3.48.0--r44_0' :
        'quay.io/biocontainers/bioconductor-puma:3.48.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_puma_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_puma_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_puma_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(puma)
    library(PMmmgmos)
    library(jsonlite)

    # --- Expression Estimation with mmgmos [] ---
    # Key functions: mmgmos, exprs, assayDataElement
    eset_estrogen_mmgmos <- mmgmos(oligo.estrogen, gsnorm="none")
    expression_values <- exprs(eset_estrogen_mmgmos)
    standard_errors <- assayDataElement(
        eset_estrogen_mmgmos,
        "se.exprs"
    )


    # --- Exon Level Estimation [] ---
    # Key functions: gmoExon, exprs, assayDataElement
    data(eset_gmoExon, package = "pumadata")
    gene_exprs <- exprs(eset_gmoExon$gene)
    gene_se <- assayDataElement(eset_gmoExon$gene, "se.exprs")
    transcript_exprs <- exprs(eset_gmoExon$transcript)


    # --- Differential Expression Analysis [] ---
    # Key functions: pumaDE
    data(eset_estrogen_mmgmos, package = "pumadata")
    puma_de_results <- pumaDE(eset_estrogen_mmgmos)


    # --- Visualization and Export [] ---
    # Key functions: pumaPCA, write.reslts
    data(eset_estrogen_mmgmos, package = "pumadata")
    pca_results <- pumaPCA(eset_estrogen_mmgmos)
    write.reslts(
        eset_estrogen_mmgmos,
        file = "eset_estrogen_mmgmos"
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_puma_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_puma_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_puma_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_PUMA:", paste0("    puma: ", packageVersion("puma"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_puma_results.csv
    touch ${prefix}_puma_output.rds
    echo "BIOC_PUMA:" > versions.yml
    echo "    puma: 0.0.0" >> versions.yml
    """
}


workflow BIOC_PUMA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_PUMA(ch_input)

    emit:
    results  = BIOC_PUMA.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_PUMA.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_PUMA.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_PUMA.out.versions  // channel: path(versions.yml)
}
