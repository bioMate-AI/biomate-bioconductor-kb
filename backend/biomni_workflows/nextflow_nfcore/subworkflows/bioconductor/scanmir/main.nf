#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: scanMiR
// A set of tools for working with miRNA affinity models (KdModels), efficiently scanning for miRNA bin
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/scanMiR/inst/doc/Kdmodels.R
// Upstream  : BiocStyle, Biostrings
// Downstream: scanMiRApp
//
// Install: BiocManager::install("scanMiR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SCANMIR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-scanmir"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-scanmir:1.12.0--r44_0' :
        'quay.io/biocontainers/bioconductor-scanmir:1.12.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_scanmir_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_scanmir_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_scanmir_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(KdModelList)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: data
    ---------------------------------------------------------------------
    library(scanMiR)
    data(SampleKdModel)
    SampleKdModel
    # --- Plotkdmodel [] ---
    # Key functions: plotKdModel
    ---------------------------------------------------------------------
    plotKdModel(SampleKdModel, what="seeds")
    # --- Assignkdtype [] ---
    # Key functions: assignKdType
    ---------------------------------------------------------------------
    assignKdType("ACGTACGTACGT", SampleKdModel)
    # or using multiple sequences:
    assignKdType(c("CTAGCATTAAGT","ACGTACGTACGT"), SampleKdModel)
    # --- Kdmodellist [] ---
    # Key functions: KdModelList
    ---------------------------------------------------------------------
    # we create a copy of the KdModel, and give it a different name:
    mod2 <- SampleKdModel
    mod2$name <- "dummy-miRNA"
    kml <- KdModelList(SampleKdModel, mod2)
    # --- Conservation [] ---
    # Key functions: conservation
    ---------------------------------------------------------------------
    conservation(kml)
    # --- Dummykddata [] ---
    # Key functions: dummyKdData
    ---------------------------------------------------------------------
    kd <- dummyKdData()
    head(kd)
    # --- Getkdmodel [] ---
    # Key functions: getKdModel
    ---------------------------------------------------------------------
    mod3 <- getKdModel(kd=kd, mirseq="TTAATGCTAATCGTGATAGGGGTT", name = "my-miRNA")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_scanmir_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_scanmir_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_scanmir_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SCANMIR:", paste0("    scanmir: ", packageVersion("scanMiR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_scanmir_results.csv
    touch ${prefix}_scanmir_output.rds
    echo "BIOC_SCANMIR:" > versions.yml
    echo "    scanmir: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SCANMIR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SCANMIR(ch_input)

    emit:
    results  = BIOC_SCANMIR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SCANMIR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SCANMIR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SCANMIR.out.versions  // channel: path(versions.yml)
}
