#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: mgsa
// Model-based Gene Set Analysis (MGSA) is a Bayesian modeling approach for gene set enrichment. The pa
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/mgsa/inst/doc/mgsa.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("mgsa")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MGSA {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-mgsa"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-mgsa:1.54.0--r44_0' :
        'quay.io/biocontainers/bioconductor-mgsa:1.54.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_mgsa_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_mgsa_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_mgsa_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(mgsa)
    library(jsonlite)

    # --- Loadex [] ---
    # Key functions: data
    library(mgsa)
    data("example")
    example_go
    example_o
    # --- Fitex [] ---
    # Key functions: mgsa
    set.seed(0)
    fit = mgsa(example_o, example_go)
    fit
    # --- Setsresults [] ---
    # Key functions: setsResults
    res = setsResults(fit)
    subset(res, estimate > 0.5)
    # --- Readgaf [] ---
    # Key functions: readGAF

    # --- Mgsa Custom Set [] ---
    # Key functions: mgsa
    mgsa( c("A", "B"), list(set1=LETTERS[1:3], set2=LETTERS[2:5]) )
    # --- Mgsa Custom Set [] ---
    # Key functions: new, mgsa
    myset = new( "MgsaSets", sets=list(set1=LETTERS[1:3], set2=LETTERS[2:5]) )
    mgsa(c("A", "B"), myset)
    mgsa(c("B", "C"), myset)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_mgsa_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_mgsa_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_mgsa_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MGSA:", paste0("    mgsa: ", packageVersion("mgsa"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_mgsa_results.csv
    touch ${prefix}_mgsa_output.rds
    echo "BIOC_MGSA:" > versions.yml
    echo "    mgsa: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MGSA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MGSA(ch_input)

    emit:
    results  = BIOC_MGSA.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MGSA.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MGSA.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MGSA.out.versions  // channel: path(versions.yml)
}
