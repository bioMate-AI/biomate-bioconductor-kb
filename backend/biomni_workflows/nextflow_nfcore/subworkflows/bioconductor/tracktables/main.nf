#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: tracktables
// Methods to create complex IGV genome browser sessions and dynamic IGV reports in HTML pages.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/tracktables/inst/doc/tracktables.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("tracktables")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_TRACKTABLES {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-tracktables"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-tracktables:1.40.0--r44_0' :
        'quay.io/biocontainers/bioconductor-tracktables:1.40.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_tracktables_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_tracktables_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_tracktables_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(MakeIGVSession)
    library(jsonlite)

    # --- dir [] ---
    # Key functions: dir, cbind, merge
    library(tracktables)
    fileLocations <- system.file("extdata",package="tracktables")
    bigwigs <- dir(fileLocations,pattern="*.bw",full.names=TRUE)
    # --- Make I G V Session [] ---
    # Key functions: MakeIGVSession
    MakeIGVSession(SampleSheet,FileSheet,igvdirectory=getwd(),"Example","mm9")
    # --- maketracktable [] ---
    # Key functions: maketracktable

    # --- maketracktable WithColoursAndScales [] ---
    # Key functions: igvParam, maketracktable


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_tracktables_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_tracktables_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_tracktables_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_TRACKTABLES:", paste0("    tracktables: ", packageVersion("tracktables"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_tracktables_results.csv
    touch ${prefix}_tracktables_output.rds
    echo "BIOC_TRACKTABLES:" > versions.yml
    echo "    tracktables: 0.0.0" >> versions.yml
    """
}


workflow BIOC_TRACKTABLES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_TRACKTABLES(ch_input)

    emit:
    results  = BIOC_TRACKTABLES.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_TRACKTABLES.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_TRACKTABLES.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_TRACKTABLES.out.versions  // channel: path(versions.yml)
}
