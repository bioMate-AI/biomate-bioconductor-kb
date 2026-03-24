#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: AffyRNADegradation
// The package helps with the assessment and correction of RNA degradation effects in Affymetrix 3' exp
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/AffyRNADegradation/inst/doc/vignette.R
// Upstream  : AmpAffyExample, vsn
// Downstream: none
//
// Install: BiocManager::install("AffyRNADegradation")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_AFFYRNADEGRADATION {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-affyrnadegradation"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-affyrnadegradation:1.52.0--r44_0' :
        'quay.io/biocontainers/bioconductor-affyrnadegradation:1.52.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_affyrnadegradation_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_affyrnadegradation_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_affyrnadegradation_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(GetTongs)
    library(PlotTongs)
    library(RNADegradation)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: data
    library(AffyRNADegradation)
    library(AmpAffyExample)
    data(AmpData)
    AmpData
    # --- Plottongs [] ---
    # Key functions: GetTongs, PlotTongs
    tongs <- GetTongs(AmpData, chip.idx = 4)
    PlotTongs(tongs)
    # --- Correctaffy [] ---
    # Key functions: RNADegradation
    rna.deg <- RNADegradation(AmpData, location.type = "index")
    # --- Saveprobelocations [] ---
    # Key functions: cdfName
    ## filename = paste(cdfName(AmpData), ".Rd", sep="")
    ## save(probeDists, file = filename)
    # --- Vsncorrect [] ---
    # Key functions: call, alist, afbatch, RNADegradation, computeExprSet
    ## library(vsn)
    ## affydata.vsn <- do.call(affy:::normalize, c(alist(AmpData, "vsn"), NULL))
    ## affydata.vsn <- afbatch(RNADegradation(affydata.vsn))
    ## expr <- computeExprSet(affydata.vsn, summary.method="medianpolish", pmcorrect.method="pmonly")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_affyrnadegradation_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_affyrnadegradation_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_affyrnadegradation_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_AFFYRNADEGRADATION:", paste0("    affyrnadegradation: ", packageVersion("AffyRNADegradation"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_affyrnadegradation_results.csv
    touch ${prefix}_affyrnadegradation_output.rds
    echo "BIOC_AFFYRNADEGRADATION:" > versions.yml
    echo "    affyrnadegradation: 0.0.0" >> versions.yml
    """
}


workflow BIOC_AFFYRNADEGRADATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_AFFYRNADEGRADATION(ch_input)

    emit:
    results  = BIOC_AFFYRNADEGRADATION.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_AFFYRNADEGRADATION.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_AFFYRNADEGRADATION.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_AFFYRNADEGRADATION.out.versions  // channel: path(versions.yml)
}
