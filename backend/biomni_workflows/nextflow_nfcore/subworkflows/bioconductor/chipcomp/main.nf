#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: ChIPComp
// ChIPComp detects differentially bound sharp binding sites across multiple conditions considering mat
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/ChIPComp/inst/doc/ChIPComp.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("ChIPComp")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CHIPCOMP {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-chipcomp"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-chipcomp:1.36.0--r44_0' :
        'quay.io/biocontainers/bioconductor-chipcomp:1.36.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_chipcomp_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_chipcomp_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_chipcomp_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ChIPComp)
    library(jsonlite)

    # --- Makeconf [] ---
    # Key functions: makeConf
    library(ChIPComp)
    confs=makeConf(system.file("extdata", "conf.csv", package="ChIPComp"))
    conf=confs$conf
    design=confs$design
    # --- Frame [] ---
    # Key functions: frame, factor

    # --- Makecountset [] ---
    # Key functions: makeCountSet
    countSet=makeCountSet(conf,design,filetype="bed", species="hg19",binsize=1000)
    # --- Chipcomp [] ---
    # Key functions: ChIPComp
    countSet=ChIPComp(countSet)
    print(countSet)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_chipcomp_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_chipcomp_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_chipcomp_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CHIPCOMP:", paste0("    chipcomp: ", packageVersion("ChIPComp"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_chipcomp_results.csv
    touch ${prefix}_chipcomp_output.rds
    echo "BIOC_CHIPCOMP:" > versions.yml
    echo "    chipcomp: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CHIPCOMP_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CHIPCOMP(ch_input)

    emit:
    results  = BIOC_CHIPCOMP.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CHIPCOMP.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CHIPCOMP.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CHIPCOMP.out.versions  // channel: path(versions.yml)
}
