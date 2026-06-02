#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: RadioGx
// Computational tool box for radio-genomic analysis which integrates radio-response data, radio-biolog
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/RadioGx/inst/doc/RadioGx.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("RadioGx")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RADIOGX {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-radiogx"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-radiogx:2.10.0--r44_0' :
        'quay.io/biocontainers/bioconductor-radiogx:2.10.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_radiogx_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_radiogx_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_radiogx_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(RadioGx)
    library(jsonlite)

    # --- available rsets [] ---
    # Key functions: availableRSets
    RSets <- availableRSets()
    # --- download R Set [] ---
    # Key functions: downloadRSet
    Cleveland <- downloadRSet('Cleveland', saveDir='.')
    # --- radiation info accessor [] ---
    # Key functions: radiationInfo
    radInf <- radiationInfo(clevelandSmall)
    # --- kable [] ---
    # Key functions: kable
    knitr::kable(radInf)
    # --- radiation types accessor [] ---
    # Key functions: radiationTypes
    radTypes <- radiationTypes(clevelandSmall)
    # --- molecular data slot accessors [] ---
    # Key functions: mDataNames

    # --- sample meta data [] ---
    # Key functions: phenoInfo
    phenoInf <- phenoInfo(clevelandSmall, 'cnv')
    # --- print sample meta data [] ---
    # Key functions: kable
    knitr::kable(phenoInf[, 1:5], row.names=FALSE)
    # --- feature meta data [] ---
    # Key functions: featureInfo
    featInfo <- featureInfo(clevelandSmall, 'rna')
    # --- print feature meta data [] ---
    # Key functions: kable
    knitr::kable(featInfo[1:3, 1:5], row.names=FALSE)
    # --- molecular data [] ---
    # Key functions: molecularProfiles
    mProf <- molecularProfiles(clevelandSmall, 'rnaseq')
    # --- print molecular profile data [] ---
    # Key functions: kable
    knitr::kable(mProf[1:3, 1:5])
    # --- response data accessors [] ---
    # Key functions: treatmentResponse, sensitivityRaw, sensitivityProfiles, sensitivityInfo
    sens <- treatmentResponse(clevelandSmall)
    sensRaw <- sensitivityRaw(clevelandSmall)
    sensProf <- sensitivityProfiles(clevelandSmall)
    # --- sensitivity Raw [] ---
    # Key functions: sensitivityRaw
    sensRaw <- sensitivityRaw(clevelandSmall)
    # --- selecting cancer cell line [] ---
    # Key functions: sensitivityInfo
    cancerCellLine <- sensitivityInfo(clevelandSmall)$sampleid[1]
    print(cancerCellLine)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_radiogx_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_radiogx_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_radiogx_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_RADIOGX:", paste0("    radiogx: ", packageVersion("RadioGx"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_radiogx_results.csv
    touch ${prefix}_radiogx_output.rds
    echo "BIOC_RADIOGX:" > versions.yml
    echo "    radiogx: 0.0.0" >> versions.yml
    """
}


workflow BIOC_RADIOGX_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_RADIOGX(ch_input)

    emit:
    results  = BIOC_RADIOGX.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_RADIOGX.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_RADIOGX.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_RADIOGX.out.versions  // channel: path(versions.yml)
}
