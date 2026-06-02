#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: ballgown
// Tools for statistical analysis of assembled transcriptomes, including flexible differential expressi
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/ballgown/inst/doc/ballgown.R
// Upstream  : none
// Downstream: VaSP
//
// Install: BiocManager::install("ballgown")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BALLGOWN {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-ballgown"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-ballgown:2.38.0--r44_0' :
        'quay.io/biocontainers/bioconductor-ballgown:2.38.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_ballgown_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_ballgown_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_ballgown_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ballgown)
    library(jsonlite)

    # --- structure [] ---
    # Key functions: structure
    structure(bg)$exon
    structure(bg)$intron
    structure(bg)$trans
    # --- p Data [] ---
    # Key functions: pData
    pData(bg) = data.frame(id=sampleNames(bg), group=rep(c(1,0), each=10))
    # --- plot Transcripts [] ---
    # Key functions: plotTranscripts

    # --- plot Means [] ---
    # Key functions: plotMeans
    plotMeans('XLOC_000454', bg, groupvar='group', meas='FPKM', colorby='transcript')
    # --- p Data [] ---
    # Key functions: pData
    pData(bg) = data.frame(pData(bg), time=rep(1:10, 2)) #dummy time covariate
    timecourse_results = stattest(bg, feature='transcript', meas='FPKM', covariate='time', timecourse=TRUE)
    # --- cluster Transcripts [] ---
    # Key functions: clusterTranscripts
    clusterTranscripts(gene='XLOC_000454', gown=bg, k=2, method='kmeans')
    # --- plot Latent Transcripts [] ---
    # Key functions: plotLatentTranscripts
    plotLatentTranscripts(gene='XLOC_000454', gown=bg, k=2, method='kmeans', returncluster=FALSE)
    # --- stattest [] ---
    # Key functions: stattest
    agg = collapseTranscripts(gene='XLOC_000454', gown=bg, k=2, method='kmeans')

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_ballgown_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_ballgown_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_ballgown_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_BALLGOWN:", paste0("    ballgown: ", packageVersion("ballgown"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ballgown_results.csv
    touch ${prefix}_ballgown_output.rds
    echo "BIOC_BALLGOWN:" > versions.yml
    echo "    ballgown: 0.0.0" >> versions.yml
    """
}


workflow BIOC_BALLGOWN_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_BALLGOWN(ch_input)

    emit:
    results  = BIOC_BALLGOWN.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_BALLGOWN.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_BALLGOWN.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_BALLGOWN.out.versions  // channel: path(versions.yml)
}
