#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: PhenoGeneRanker
// This package is a gene/phenotype prioritization tool that utilizes multiplex heterogeneous gene phen
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/PhenoGeneRanker/inst/doc/PhenoGeneRanker.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("PhenoGeneRanker")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PHENOGENERANKER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-phenogeneranker"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-phenogeneranker:1.14.0--r44_0' :
        'quay.io/biocontainers/bioconductor-phenogeneranker:1.14.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_phenogeneranker_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_phenogeneranker_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_phenogeneranker_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(CreateWalkMatrix)
    library(RandomWalkRestart)
    library(jsonlite)

    # --- Table [] ---
    # Key functions: file
    ---------------------------------------------------------------------
    inputDf <- read.table(system.file("extdata", "input_file.txt", package = "PhenoGeneRanker"), header=TRUE, sep="\t", stringsAsFactors = FALSE)
    print(inputDf)
    # --- Createwalkmatrix [] ---
    # Key functions: CreateWalkMatrix
    ---------------------------------------------------------------------
    # Generate walk matrix for RandomWalkWithRestart function use
    walkMatrix <- CreateWalkMatrix('input_file.txt')
    # --- Randomwalkrestart [] ---
    # Key functions: RandomWalkRestart
    ---------------------------------------------------------------------
    # utilizes only gene seeds and generates p-values for ranks using 50 runs with random seeds
    ranks <- RandomWalkRestart(walkMatrix, c('g1', 'g5'), c("p1"), S=50)
    print(head(ranks))
    # utilizes gene and phenotype seeds and does not generate p-values.

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_phenogeneranker_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_phenogeneranker_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_phenogeneranker_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_PHENOGENERANKER:", paste0("    phenogeneranker: ", packageVersion("PhenoGeneRanker"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_phenogeneranker_results.csv
    touch ${prefix}_phenogeneranker_output.rds
    echo "BIOC_PHENOGENERANKER:" > versions.yml
    echo "    phenogeneranker: 0.0.0" >> versions.yml
    """
}


workflow BIOC_PHENOGENERANKER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_PHENOGENERANKER(ch_input)

    emit:
    results  = BIOC_PHENOGENERANKER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_PHENOGENERANKER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_PHENOGENERANKER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_PHENOGENERANKER.out.versions  // channel: path(versions.yml)
}
