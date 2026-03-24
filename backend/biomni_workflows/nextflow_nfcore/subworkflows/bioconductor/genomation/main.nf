#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: genomation
// A package for summary and annotation of genomic intervals. Users can visualize and quantify genomic 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/genomation/inst/doc/GenomationManual.R
// Upstream  : AnnotationHub, GenomicRanges, genomationData, knitr
// Downstream: none
//
// Install: BiocManager::install("genomation")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GENOMATION {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-genomation"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-genomation:1.38.0--r44_0' :
        'quay.io/biocontainers/bioconductor-genomation:1.38.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_genomation_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_genomation_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_genomation_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(genomation)
    library(jsonlite)

    # --- ReadGeneric analysis [] ---
    # Key functions: readGeneric, heatMatrix, plotMeta, multiHeatMatrix, plotGeneAnnotation, query
    sml = ScoreMatrixList(bam.files, ctcf.peaks, bin.num=50, type='bam')
    sampleInfo = read.table(system.file('extdata/SamplesInfo.txt',
    names(sml) = sampleInfo$sampleName[match(names(sml),sampleInfo$fileName)]

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_genomation_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_genomation_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_genomation_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GENOMATION:", paste0("    genomation: ", packageVersion("genomation"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_genomation_results.csv
    touch ${prefix}_genomation_output.rds
    echo "BIOC_GENOMATION:" > versions.yml
    echo "    genomation: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GENOMATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GENOMATION(ch_input)

    emit:
    results  = BIOC_GENOMATION.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GENOMATION.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GENOMATION.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GENOMATION.out.versions  // channel: path(versions.yml)
}
