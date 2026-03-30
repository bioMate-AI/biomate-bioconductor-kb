#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: genArise
// genArise is an easy to use tool for dual color microarray data. Its GUI-Tk based environment let any
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/genArise/inst/doc/genArise.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("genArise")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GENARISE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-genarise"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-genarise:1.82.0--r44_0' :
        'quay.io/biocontainers/bioconductor-genarise:1.82.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_genarise_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_genarise_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_genarise_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(genArise)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: attr, imageLimma
    data(Simon)
    datos <- attr(Simon, "spotData")
    M <- log(datos$Cy3, 2) - log(datos$Cy5, 2)
    imageLimma(M, 23, 24, 2, 2)
    # --- Data [] ---
    # Key functions: correct
    data(Simon)
    c.spot <- bg.correct(Simon)
    ri.plot(c.spot)
    # --- Data [] ---
    # Key functions: norm
    data(Simon)
    n.spot <- grid.norm(mySpot = Simon, nr = 23, nc = 24)
    ri.plot(n.spot)
    # --- Data [] ---
    # Key functions: spot
    data(Simon)
    f.spot <- filter.spot(mySpot = Simon)
    ri.plot(f.spot)
    # --- Data [] ---
    # Key functions: spotUnique
    data(Simon)
    u.spot <- spotUnique(mySpot = Simon)
    ri.plot(u.spot)
    # --- Data [] ---
    # Key functions: meanUnique
    data(Simon)
    u.spot <- meanUnique(mySpot = Simon)
    ri.plot(u.spot)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_genarise_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_genarise_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_genarise_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GENARISE:", paste0("    genarise: ", packageVersion("genArise"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_genarise_results.csv
    touch ${prefix}_genarise_output.rds
    echo "BIOC_GENARISE:" > versions.yml
    echo "    genarise: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GENARISE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GENARISE(ch_input)

    emit:
    results  = BIOC_GENARISE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GENARISE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GENARISE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GENARISE.out.versions  // channel: path(versions.yml)
}
