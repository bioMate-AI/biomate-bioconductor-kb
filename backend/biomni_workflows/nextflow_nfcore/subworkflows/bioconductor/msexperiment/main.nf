#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: MsExperiment
// Infrastructure to store and manage all aspects related to a complete proteomics or metabolomics mass
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/MsExperiment/inst/doc/MsExperiment.R
// Upstream  : BiocStyle, MsBackendSql, RSQLite, Spectra, SummarizedExperiment
// Downstream: none
//
// Install: BiocManager::install("MsExperiment")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MSEXPERIMENT {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-msexperiment"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-msexperiment:1.8.0--r44_0' :
        'quay.io/biocontainers/bioconductor-msexperiment:1.8.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_msexperiment_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_msexperiment_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_msexperiment_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(DataFrame)
    library(MsExperiment)
    library(MsExperimentFiles)
    library(PXDataset)
    library(Spectra)
    library(SummarizedExperiment)
    library(jsonlite)

    # --- P X Dataset [] ---
    # Key functions: PXDataset, pxfiles
    library("rpx")
    px <- PXDataset("PXD022816")
    pxfiles(px)
    # --- pxget [] ---
    # Key functions: pxget
    (i <- grep(".+0[12].+mzML$", pxfiles(px), value = TRUE))
    fls <- pxget(px, i)
    # --- Ms Experiment [] ---
    # Key functions: MsExperiment
    msexp <- MsExperiment()
    # --- make exp fls [] ---
    # Key functions: MsExperimentFiles
    msfls <- MsExperimentFiles(mzmls = fls,
    # --- add exp fls [] ---
    # Key functions: experimentFiles
    experimentFiles(msexp) <- msfls
    # --- add sample data [] ---
    # Key functions: sampleData
    sampleData(msexp) <- DataFrame(
    mzmls = basename(experimentFiles(msexp)[["mzmls"]]),
    sampleData(msexp)
    # --- Spectra [] ---
    # Key functions: Spectra
    sp <- Spectra(experimentFiles(msexp)[["mzmls"]])
    # --- spectra [] ---
    # Key functions: spectra
    spectra(msexp) <- sp
    # --- experiment Files [] ---
    # Key functions: experimentFiles
    experimentFiles(msexp)[["mzids"]] <- mzids
    experimentFiles(msexp)
    # --- metadata [] ---
    # Key functions: metadata
    metadata(msexp)[["mzmls_to_mzids"]] <- cmd
    metadata(msexp)
    # --- exist Ms Experiment Files [] ---
    # Key functions: existMsExperimentFiles
    existMsExperimentFiles(msexp)
    # --- experiment Files [] ---
    # Key functions: experimentFiles
    msexp <- readRDS("msexp.rds")
    experimentFiles(msexp)
    # --- spectra [] ---
    # Key functions: spectra, plotSpectra
    sp <- spectra(msexp)
    plotSpectra(sp[1000])
    # --- make exp2 [] ---
    # Key functions: MsExperiment, DataFrame, sampleData
    lmse <- MsExperiment()
    sd <- DataFrame(sample_id = c("QC1", "QC2"),
    sample_name = c("QC Pool", "QC Pool"),
    # --- add fls2 [] ---
    # Key functions: experimentFiles
    fls <- dir(system.file("sciex", package = "msdata"), full.names = TRUE)
    basename(fls)
    experimentFiles(lmse) <- MsExperimentFiles(

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_msexperiment_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_msexperiment_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_msexperiment_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MSEXPERIMENT:", paste0("    msexperiment: ", packageVersion("MsExperiment"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_msexperiment_results.csv
    touch ${prefix}_msexperiment_output.rds
    echo "BIOC_MSEXPERIMENT:" > versions.yml
    echo "    msexperiment: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MSEXPERIMENT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MSEXPERIMENT(ch_input)

    emit:
    results  = BIOC_MSEXPERIMENT.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MSEXPERIMENT.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MSEXPERIMENT.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MSEXPERIMENT.out.versions  // channel: path(versions.yml)
}
