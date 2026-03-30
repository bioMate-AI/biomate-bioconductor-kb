#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: FRGEpistasis
// A Tool for Epistasis Analysis Based on Functional Regression Model
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/FRGEpistasis/inst/doc/FRGEpistasis.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("FRGEpistasis")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_FRGEPISTASIS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-frgepistasis"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-frgepistasis:1.42.0--r44_0' :
        'quay.io/biocontainers/bioconductor-frgepistasis:1.42.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_frgepistasis_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_frgepistasis_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_frgepistasis_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(FRGEpistasis)
    library(jsonlite)

    # --- Table [] ---
    # Key functions: file
    geno_info <- read.table(system.file("extdata", "simGeno-chr2.raw", package="FRGEpistasis"),header=TRUE)
    geno_info[1:5,1:9]
    # --- Csv [] ---
    # Key functions: csv
    pheno_info <- read.csv(system.file("extdata", "phenotype.csv", package="FRGEpistasis"),header=TRUE)
    pheno_info[1:5,]
    # --- Table [] ---
    # Key functions: file
    geno_files<-read.table(system.file("extdata", "list_geno.txt", package="FRGEpistasis"))
    geno_files

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_frgepistasis_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_frgepistasis_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_frgepistasis_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_FRGEPISTASIS:", paste0("    frgepistasis: ", packageVersion("FRGEpistasis"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_frgepistasis_results.csv
    touch ${prefix}_frgepistasis_output.rds
    echo "BIOC_FRGEPISTASIS:" > versions.yml
    echo "    frgepistasis: 0.0.0" >> versions.yml
    """
}


workflow BIOC_FRGEPISTASIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_FRGEPISTASIS(ch_input)

    emit:
    results  = BIOC_FRGEPISTASIS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_FRGEPISTASIS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_FRGEPISTASIS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_FRGEPISTASIS.out.versions  // channel: path(versions.yml)
}
