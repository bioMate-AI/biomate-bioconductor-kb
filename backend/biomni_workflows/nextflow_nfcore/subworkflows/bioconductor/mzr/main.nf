#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: mzR
// mzR provides a unified API to the common file formats and parsers available for mass spectrometry da
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/mzR/inst/doc/mzR.R
// Upstream  : msdata
// Downstream: MSnbase
//
// Install: BiocManager::install("mzR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MZR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-mzr"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-mzr:2.40.0--r44_0' :
        'quay.io/biocontainers/bioconductor-mzr:2.40.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_mzr_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_mzr_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_mzr_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(mzR)
    library(msdata)
    library(jsonlite)


    # --- Openraw [] ---
    # Key functions: openMSfile, msdata
    library(mzR)
    library(msdata)

    mzxml <- system.file("threonine/threonine_i2_e35_pH_tree.mzXML",
                         package = "msdata")
    aa <- openMSfile(mzxml)

    # --- Get Header Information [] ---
    # Key functions: runInfo, instrumentInfo, header
    runInfo(aa)
    instrumentInfo(aa)
    header(aa,1)

    # --- Plotspectrum [] ---
    # Key functions: peaks, peaksCount
    pl <- peaks(aa,10)
    peaksCount(aa,10)
    head(pl)
    plot(pl[,1], pl[,2], type="h", lwd=1)

    # --- Close The File [] ---
    # Key functions: close
    close(aa)

    # --- Openid [] ---
    # Key functions: openIDfile, mzid, msdata
    library(mzR)
    library(msdata)

    file <- system.file("mzid", "Tandem.mzid.gz", package="msdata")
    x <- openIDfile(file)

    # --- Metadata [] ---
    # Key functions: mzidInfo
    mzidInfo(x)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_mzr_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_mzr_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_mzr_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MZR:", paste0("    mzr: ", packageVersion("mzR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_mzr_results.csv
    touch ${prefix}_mzr_output.rds
    echo "BIOC_MZR:" > versions.yml
    echo "    mzr: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MZR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MZR(ch_input)

    emit:
    results  = BIOC_MZR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MZR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MZR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MZR.out.versions  // channel: path(versions.yml)
}
