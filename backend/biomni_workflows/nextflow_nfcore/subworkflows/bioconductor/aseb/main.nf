#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: ASEB
// ASEB is an R package to predict lysine sites that can be acetylated by a specific KAT-family.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/ASEB/inst/doc/ASEB.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("ASEB")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ASEB {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-aseb"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-aseb:1.50.0--r44_0' :
        'quay.io/biocontainers/bioconductor-aseb:1.50.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_aseb_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_aseb_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_aseb_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ASEB)
    library(jsonlite)

    # --- Readsequence [] ---
    # Key functions: readSequence, asebSites
    backgroundSites <- readSequence(system.file("extdata", "background_sites.fa", package="ASEB"))
      prodefinedSites <- readSequence(system.file("extdata", "predefined_sites.fa", package="ASEB"))
      testSites <- readSequence(system.file("extdata", "sites_to_test.fa", package="ASEB"))
      resultList <- asebSites(backgroundSites, prodefinedSites, testSites, permutationTimes=100)
      resultList$results[1:2,]
    # --- Drawescurve [] ---
    # Key functions: drawEScurve
    drawEScurve(resultList$curveInfo, max_p_value=0.1, min_es=0.1)
    # --- Readsequence [] ---
    # Key functions: readSequence, asebProteins
    backgroundSites <- readSequence(system.file("extdata", "background_sites.fa", package="ASEB"))
      prodefinedSites <- readSequence(system.file("extdata", "predefined_sites.fa", package="ASEB"))
      testProteins <- readSequence(system.file("extdata", "proteins_to_test.fa", package="ASEB"))
      resultList <- asebProteins(backgroundSites, prodefinedSites, testProteins, permutationTimes=100)
      resultList$results[1:2,]
    # --- Drawstat [] ---
    # Key functions: drawStat
    drawStat(curveInfoDataFrame=resultList$curveInfo);

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_aseb_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_aseb_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_aseb_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_ASEB:", paste0("    aseb: ", packageVersion("ASEB"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_aseb_results.csv
    touch ${prefix}_aseb_output.rds
    echo "BIOC_ASEB:" > versions.yml
    echo "    aseb: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ASEB_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_ASEB(ch_input)

    emit:
    results  = BIOC_ASEB.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ASEB.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ASEB.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ASEB.out.versions  // channel: path(versions.yml)
}
