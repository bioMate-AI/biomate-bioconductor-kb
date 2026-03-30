#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: MatrixRider
// Calculates a single number for a whole sequence that reflects the propensity of a DNA binding protei
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/MatrixRider/inst/doc/MatrixRider.R
// Upstream  : Biostrings, JASPAR2014, TFBSTools
// Downstream: none
//
// Install: BiocManager::install("MatrixRider")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MATRIXRIDER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-matrixrider"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-matrixrider:1.38.0--r44_0' :
        'quay.io/biocontainers/bioconductor-matrixrider:1.38.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_matrixrider_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_matrixrider_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_matrixrider_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(DNAString)
    library(PFMatrixList)
    library(jsonlite)

    # --- Obtainsinglepfmgetseqoccupancy [] ---
    # Key functions: getMatrixByID, DNAString, getSeqOccupancy
    library(MatrixRider)
    library(JASPAR2014)
    library(TFBSTools)
    library(Biostrings)
    pfm <- getMatrixByID(JASPAR2014,"MA0004.1")
    # --- Obtainmultiplepfmgetseqoccupancy [] ---
    # Key functions: getMatrixByID, PFMatrixList, name, getSeqOccupancy
    pfm2 <- getMatrixByID(JASPAR2014,"MA0005.1")
    pfms <- PFMatrixList(pfm, pfm2)
    names(pfms) <- c(name(pfm), name(pfm2))
    ## This calculates total affinity for both the PFMatrixes.
    getSeqOccupancy(sequence, pfms, 0)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_matrixrider_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_matrixrider_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_matrixrider_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MATRIXRIDER:", paste0("    matrixrider: ", packageVersion("MatrixRider"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_matrixrider_results.csv
    touch ${prefix}_matrixrider_output.rds
    echo "BIOC_MATRIXRIDER:" > versions.yml
    echo "    matrixrider: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MATRIXRIDER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MATRIXRIDER(ch_input)

    emit:
    results  = BIOC_MATRIXRIDER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MATRIXRIDER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MATRIXRIDER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MATRIXRIDER.out.versions  // channel: path(versions.yml)
}
