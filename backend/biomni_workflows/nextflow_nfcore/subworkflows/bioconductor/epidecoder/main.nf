#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: epidecodeR
// epidecodeR is a package capable of analysing impact of degree of DNA/RNA epigenetic chemical modific
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/epidecodeR/inst/doc/epidecodeR.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("epidecodeR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_EPIDECODER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-epidecoder"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-epidecoder:1.14.0--r44_0' :
        'quay.io/biocontainers/bioconductor-epidecoder:1.14.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_epidecoder_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_epidecoder_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_epidecoder_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(epidecodeR)
    library(jsonlite)

    # --- Head [] ---
    # Key functions: get_theoretical_table
    ---------------------------------------------------------------------
    head (get_theoretical_table(epiobj))
    # --- Head [] ---
    # Key functions: get_empirical_table
    ---------------------------------------------------------------------
    head (get_empirical_table(epiobj))
    # --- Head [] ---
    # Key functions: get_grpcounts
    ---------------------------------------------------------------------
    head (get_grpcounts(epiobj))
    # --- Get Grptables [] ---
    # Key functions: get_grptables
    ---------------------------------------------------------------------
    grptables_list<-get_grptables(epiobj)
    head (grptables_list$'0')
    head (grptables_list$'1')
    head (grptables_list$'2to4')

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_epidecoder_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_epidecoder_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_epidecoder_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_EPIDECODER:", paste0("    epidecoder: ", packageVersion("epidecodeR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_epidecoder_results.csv
    touch ${prefix}_epidecoder_output.rds
    echo "BIOC_EPIDECODER:" > versions.yml
    echo "    epidecoder: 0.0.0" >> versions.yml
    """
}


workflow BIOC_EPIDECODER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_EPIDECODER(ch_input)

    emit:
    results  = BIOC_EPIDECODER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_EPIDECODER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_EPIDECODER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_EPIDECODER.out.versions  // channel: path(versions.yml)
}
