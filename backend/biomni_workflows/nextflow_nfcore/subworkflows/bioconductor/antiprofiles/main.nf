#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: antiProfiles
// Implements gene expression anti-profiles as described in Corrada Bravo et al., BMC Bioinformatics 20
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/antiProfiles/inst/doc/antiProfiles.R
// Upstream  : RColorBrewer, antiProfilesData
// Downstream: none
//
// Install: BiocManager::install("antiProfiles")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ANTIPROFILES {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-antiprofiles"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-antiprofiles:1.46.0--r44_0' :
        'quay.io/biocontainers/bioconductor-antiprofiles:1.46.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_antiprofiles_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_antiprofiles_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_antiprofiles_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(antiProfiles)
    library(jsonlite)

    # --- Loaddata [] ---
    # Key functions: show
    data(apColonData)
    show(apColonData)
    # look at sample types by experiment and status
    table(apColonData$Status, apColonData$SubType, apColonData$ExperimentID)
    # --- Getstats [] ---
    # Key functions: pData, apStats, exprs, getProbeStats
    trainSamples=pData(apColonData)$ExperimentID=="GSE4183"
    colonStats=apStats(exprs(apColonData)[,trainSamples],
                       pData(apColonData)$Status[trainSamples],minL=5)
    head(getProbeStats(colonStats))
    # --- Plotstat [] ---
    # Key functions: getProbeStats
    hist(getProbeStats(colonStats)$stat, nc=100,
         main="Histogram of log variance ratio", xlab="log2 variance ratio")
    # --- Buildap [] ---
    # Key functions: buildAntiProfile, show
    ap=buildAntiProfile(colonStats, tissueSpec=FALSE, sigsize=100)
    show(ap)
    # --- Plotscore [] ---
    # Key functions: apCount, exprs, palette, pal, dotchart, pData
    counts=apCount(ap, exprs(apColonData)[,!trainSamples])
    palette(brewer.pal(8,"Dark2"))
    # plot in score order
    o=order(counts)
    dotchart(counts[o],col=pData(apColonData)$Status[!trainSamples][o]+1,

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_antiprofiles_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_antiprofiles_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_antiprofiles_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_ANTIPROFILES:", paste0("    antiprofiles: ", packageVersion("antiProfiles"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_antiprofiles_results.csv
    touch ${prefix}_antiprofiles_output.rds
    echo "BIOC_ANTIPROFILES:" > versions.yml
    echo "    antiprofiles: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ANTIPROFILES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_ANTIPROFILES(ch_input)

    emit:
    results  = BIOC_ANTIPROFILES.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ANTIPROFILES.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ANTIPROFILES.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ANTIPROFILES.out.versions  // channel: path(versions.yml)
}
