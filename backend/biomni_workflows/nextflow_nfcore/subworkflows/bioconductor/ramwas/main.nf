#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: ramwas
// A complete toolset for methylome-wide association studies (MWAS). It is specifically designed for da
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/ramwas/inst/doc/RW1_intro.R
// Upstream  : knitr, pander
// Downstream: none
//
// Install: BiocManager::install("ramwas")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RAMWAS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-ramwas"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-ramwas:1.30.0--r44_0' :
        'quay.io/biocontainers/bioconductor-ramwas:1.30.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_ramwas_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_ramwas_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_ramwas_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ramwas)
    library(jsonlite)

    # --- Alignment Scanning and Quality Control [] ---
    # Key functions: ramwas1scanBams, ramwas2collectqc, parameterPreprocess
    ramwas1scanBams(param)
    ramwas2collectqc(param)
    pfull <- parameterPreprocess(param)
    qc <- readRDS(paste0(pfull$dirrqc, "/BAM007.qc.rds"))


    # --- Coverage Normalisation and Fragment Size Estimation [] ---
    # Key functions: ramwas3normalizedCoverage, plotFragmentSizeDistributionEstimate
    ramwas3normalizedCoverage(param)
    pfull <- parameterPreprocess(param)
    qc <- readRDS(paste0(pfull$dirqc, "/summary_total/qclist.rds"))
    frdata <- qc$total$hist.isolated.dist1
    estimate <- as.double(readLines(
        con = paste0(pfull$dirproject, "/Fragment_size_distribution.txt")
    ))
    plotFragmentSizeDistributionEstimate(frdata, estimate)


    # --- Principal Component Analysis [] ---
    # Key functions: ramwas4PCA, plotPCvalues, plotPCvectors
    ramwas4PCA(param)
    pfull <- parameterPreprocess(param)
    eigenvalues <- fm.load(paste0(pfull$dirpca, "/eigenvalues"))
    eigenvectors <- fm.open(
        filenamebase = paste0(pfull$dirpca, "/eigenvectors"),
        readonly = TRUE
    )
    plotPCvalues(eigenvalues)
    plotPCvectors(eigenvectors[, 1], 1)
    close(eigenvectors)


    # --- Association Analysis and Visualisation [] ---
    # Key functions: ramwas5MWAS, getMWASandLocations, qqPlotFast, manPlotPrepare, manPlotFast
    ramwas5MWAS(param)
    mwas <- getMWASandLocations(param)
    qqPlotFast(mwas$`p-value`)
    man <- manPlotPrepare(
        pvalues = mwas$`p-value`,
        chr = mwas$chr,
        pos = mwas$start,
        chrmargins = 0
    )
    manPlotFast(man)


    # --- Cross Validation and Prediction [] ---
    # Key functions: ramwas7riskScoreCV, plotPrediction, plotCVcors
    ramwas7riskScoreCV(param)
    pfull <- parameterPreprocess(param)
    cv <- readRDS(paste0(pfull$dircv, "/rds/CpGs=000050_alpha=0.000000.rds"))
    plotPrediction(
        param = pfull,
        outcome = cv$outcome,
        forecast = cv$forecast,
        cpgs2use = 50,
        main = "Prediction success"
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_ramwas_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_ramwas_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_ramwas_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_RAMWAS:", paste0("    ramwas: ", packageVersion("ramwas"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ramwas_results.csv
    touch ${prefix}_ramwas_output.rds
    echo "BIOC_RAMWAS:" > versions.yml
    echo "    ramwas: 0.0.0" >> versions.yml
    """
}


workflow BIOC_RAMWAS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_RAMWAS(ch_input)

    emit:
    results  = BIOC_RAMWAS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_RAMWAS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_RAMWAS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_RAMWAS.out.versions  // channel: path(versions.yml)
}
