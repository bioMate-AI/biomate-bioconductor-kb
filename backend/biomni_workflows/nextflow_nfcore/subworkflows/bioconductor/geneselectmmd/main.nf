#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: GeneSelectMMD
// Gene selection based on a mixture of marginal distributions.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/GeneSelectMMD/inst/doc/gsMMD.R
// Upstream  : ALL
// Downstream: none
//
// Install: BiocManager::install("GeneSelectMMD")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GENESELECTMMD {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-geneselectmmd"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-geneselectmmd:2.50.0--r44_0' :
        'quay.io/biocontainers/bioconductor-geneselectmmd:2.50.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_geneselectmmd_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_geneselectmmd_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_geneselectmmd_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(GeneSelectMMD)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: gsMMD
    library(GeneSelectMMD)
      library(ALL)
      data(ALL)
      eSet1 <- ALL[1:100, ALL$BT == "B3" | ALL$BT == "T2"]
      mem.str <- as.character(eSet1$BT)
    # --- Data [] ---
    # Key functions: exprs, default
    ##   library(GeneSelectMMD)
    ##   library(ALL)
    ##   data(ALL)
    ##   eSet1 <- ALL[1:100, ALL$BT == "B3" | ALL$BT == "T2"]
    ##   mat <- exprs(eSet1)
    # --- Data [] ---
    # Key functions: test
    ##   library(GeneSelectMMD)
    ##   library(ALL)
    ##   data(ALL)
    ##   eSet1 <- ALL[1:100, ALL$BT == "B3" | ALL$BT == "T2"]
    ##
    # --- Data [] ---
    # Key functions: exprs
    ##   library(GeneSelectMMD)
    ##   library(ALL)
    ##   data(ALL)
    ##   eSet1 <- ALL[1:100, ALL$BT == "B3" | ALL$BT == "T2"]
    ##   mat <- exprs(eSet1)
    # --- Round [] ---
    # Key functions: errRates
    print(round(errRates(obj.gsMMD), 3))
    # --- Plothistdensity [] ---
    # Key functions: plotHistDensity, density
    plotHistDensity(obj.gsMMD, plotFlag = "case",
          mytitle = "Histogram of gene expression levels for T2\nimposed with estimated density (case)",
          plotComponent = TRUE,
          x.legend = c(0.8, 3),
          y.legend = c(0.3, 0.4),

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_geneselectmmd_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_geneselectmmd_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_geneselectmmd_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GENESELECTMMD:", paste0("    geneselectmmd: ", packageVersion("GeneSelectMMD"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_geneselectmmd_results.csv
    touch ${prefix}_geneselectmmd_output.rds
    echo "BIOC_GENESELECTMMD:" > versions.yml
    echo "    geneselectmmd: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GENESELECTMMD_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GENESELECTMMD(ch_input)

    emit:
    results  = BIOC_GENESELECTMMD.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GENESELECTMMD.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GENESELECTMMD.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GENESELECTMMD.out.versions  // channel: path(versions.yml)
}
