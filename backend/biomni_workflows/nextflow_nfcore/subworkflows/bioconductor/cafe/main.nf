#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: CAFE
// Detection and visualizations of gross chromosomal aberrations using Affymetrix expression microarray
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/CAFE/inst/doc/CAFE-manual.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("CAFE")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CAFE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-cafe"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-cafe:1.42.0--r44_0' :
        'quay.io/biocontainers/bioconductor-cafe:1.42.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_cafe_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_cafe_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_cafe_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ProcessCels)
    library(jsonlite)

    # --- Cafe Manual.Rnw:93 94 [] ---
    # Key functions: ProcessCels
    ## datalist <- ProcessCels()
    # --- Cafe Manual.Rnw:107 109 [] ---
    # Key functions: data
    data("CAFE_data")
    #will put object named {\bf CAFE}_data in your global environment
    # --- Cafe Manual.Rnw:127 133 [] ---
    # Key functions: chromosomeStats
    #we first have to decide which samples we want to use.
    names(CAFE_data[[2]]) #to see which samples we got
    sam <- c(1,3) #so we use sample numbers 1, and 3 to compare against the rest
    chromosomeStats(CAFE_data,chromNum=17,samples=sam,
                    test="fisher",bonferroni=FALSE,enrichment="greater")
    # --- Cafe Manual.Rnw:138 140 [] ---
    # Key functions: chromosomeStats
    chromosomeStats(CAFE_data,chromNum=17,samples=sam,
                    test="chisqr",bonferroni=FALSE,enrichment="greater")
    # --- Cafe Manual.Rnw:147 149 [] ---
    # Key functions: chromosomeStats
    chromosomeStats(CAFE_data,chromNum="ALL",samples=sam,
                    test="fisher",bonferroni=TRUE,enrichment="greater")
    # --- Cafe Manual.Rnw:157 160 [] ---
    # Key functions: bandStats
    bandStats(CAFE_data,chromNum=17,samples=sam,test="fisher",
              bonferroni=TRUE,enrichment="greater")
    #multiple bands per chromosome, so need bonferroni!
    # --- Cafe Manual.Rnw:178 179 [] ---
    # Key functions: rawPlot
    p <- rawPlot(CAFE_data,samples=c(1,3,10),chromNum=17)
    # --- Cafe Manual.Rnw:200 201 [] ---
    # Key functions: slidPlot
    p <- slidPlot(CAFE_data,samples=c(1,3,10),chromNum=17,k=100)
    # --- Cafe Manual.Rnw:228 229 [] ---
    # Key functions: discontPlot
    p <- discontPlot(CAFE_data,samples=c(1,3,10),chromNum=17,gamma=100)
    # --- Cafe Manual.Rnw:246 247 [] ---
    # Key functions: facetPlot
    p <- facetPlot(CAFE_data,samples=c(1,3,10),slid=TRUE,combine=TRUE,k=100)
    # --- Cafe Manual.Rnw:271 274 [] ---
    # Key functions: ProcessCels, chromosomeStats, discontPlot
    ## data <- ProcessCels()
    ## chromosomeStats(data,samples=c(1,3),chromNum="ALL")
    ## discontPlot(data,samples=c(1,3),chromNum="ALL",gamma=100)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_cafe_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_cafe_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_cafe_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CAFE:", paste0("    cafe: ", packageVersion("CAFE"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cafe_results.csv
    touch ${prefix}_cafe_output.rds
    echo "BIOC_CAFE:" > versions.yml
    echo "    cafe: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CAFE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CAFE(ch_input)

    emit:
    results  = BIOC_CAFE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CAFE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CAFE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CAFE.out.versions  // channel: path(versions.yml)
}
