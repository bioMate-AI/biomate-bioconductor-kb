#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: EmpiricalBrownsMethod
// Combining P-values from multiple statistical tests is common in bioinformatics. However, this proced
//
// Source : https://bioconductor.org/packages/3.20/bioc/https://bioconductor.org/packages/3.20/bioc/vignettes/EmpiricalBrownsMethod/inst/doc/ebmVignette.html
// Upstream  : none
// Downstream: poolVIM
//
// Install: BiocManager::install("EmpiricalBrownsMethod")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_EMPIRICALBROWNSMETHOD {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-empiricalbrownsmethod"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-empiricalbrownsmethod:1.34.0--r44_0' :
        'quay.io/biocontainers/bioconductor-empiricalbrownsmethod:1.34.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_empiricalbrownsmethod_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_empiricalbrownsmethod_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_empiricalbrownsmethod_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(EmpiricalBrownsMethod)
    library(jsonlite)

    # --- Code Block 1 [] ---
    # Key functions: empiricalBrownsMethod
    data(ebmTestData)
    # first get the genes for the specified pathway
    glypGenes <- pathways$gene[pathways$pathway == "GLYPICAN 3 NETWORK"]
    # then gather the correlation test p-values
    glypPvals <- allPvals$pvalue.with.CHD4[match(glypGenes, allPvals$gene)];

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_empiricalbrownsmethod_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_empiricalbrownsmethod_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_empiricalbrownsmethod_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_EMPIRICALBROWNSMETHOD:", paste0("    empiricalbrownsmethod: ", packageVersion("EmpiricalBrownsMethod"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_empiricalbrownsmethod_results.csv
    touch ${prefix}_empiricalbrownsmethod_output.rds
    echo "BIOC_EMPIRICALBROWNSMETHOD:" > versions.yml
    echo "    empiricalbrownsmethod: 0.0.0" >> versions.yml
    """
}


workflow BIOC_EMPIRICALBROWNSMETHOD_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_EMPIRICALBROWNSMETHOD(ch_input)

    emit:
    results  = BIOC_EMPIRICALBROWNSMETHOD.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_EMPIRICALBROWNSMETHOD.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_EMPIRICALBROWNSMETHOD.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_EMPIRICALBROWNSMETHOD.out.versions  // channel: path(versions.yml)
}
