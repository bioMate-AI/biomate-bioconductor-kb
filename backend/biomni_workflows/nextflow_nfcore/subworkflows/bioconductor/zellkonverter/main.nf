#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: zellkonverter
// Provides methods to convert between Python AnnData objects and SingleCellExperiment objects. These a
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/zellkonverter/inst/doc/zellkonverter.R
// Upstream  : scRNAseq, basilisk
// Downstream: scATAC.Explorer, OSCA.intro
//
// Install: BiocManager::install("zellkonverter")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ZELLKONVERTER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-zellkonverter"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-zellkonverter:1.16.0--r44_0' :
        'quay.io/biocontainers/bioconductor-zellkonverter:1.16.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_zellkonverter_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_zellkonverter_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_zellkonverter_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(AnnData2SCE)
    library(AnnDataDependencies)
    library(SCE2AnnData)
    library(SegerstolpePancreasData)
    library(ZeiselBrainData)
    library(jsonlite)

    # --- read H5 A D [] ---
    # Key functions: readH5AD
    library(zellkonverter)
    # --- Zeisel Brain Data [] ---
    # Key functions: ZeiselBrainData, tempfile, writeH5AD
    library(scRNAseq)
    sce_zeisel <- ZeiselBrainData()
    out_path <- tempfile(pattern = ".h5ad")
    # --- Segerstolpe Pancreas Data [] ---
    # Key functions: SegerstolpePancreasData, basiliskRun, SCE2AnnData, AnnData2SCE
    library(basilisk)
    library(scRNAseq)
    seger <- SegerstolpePancreasData()
    # --- Ann Data Dependencies [] ---
    # Key functions: AnnDataDependencies
    AnnDataDependencies()
    # --- read H5 A D [] ---
    # Key functions: readH5AD
    readH5AD(example_h5ad, verbose = TRUE)
    # --- set Zellkonverter Verbose [] ---
    # Key functions: setZellkonverterVerbose
    setZellkonverterVerbose(TRUE)
    sessionInfo()

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_zellkonverter_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_zellkonverter_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_zellkonverter_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_ZELLKONVERTER:", paste0("    zellkonverter: ", packageVersion("zellkonverter"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_zellkonverter_results.csv
    touch ${prefix}_zellkonverter_output.rds
    echo "BIOC_ZELLKONVERTER:" > versions.yml
    echo "    zellkonverter: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ZELLKONVERTER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_ZELLKONVERTER(ch_input)

    emit:
    results  = BIOC_ZELLKONVERTER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ZELLKONVERTER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ZELLKONVERTER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ZELLKONVERTER.out.versions  // channel: path(versions.yml)
}
