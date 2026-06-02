#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: oposSOM
// This package translates microarray expression data into metadata of reduced dimension. It provides v
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/oposSOM/inst/doc/Vignette.R
// Upstream  : Biobase, biomaRt
// Downstream: none
//
// Install: BiocManager::install("oposSOM")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_OPOSSOM {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-opossom"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-opossom:2.24.0--r44_0' :
        'quay.io/biocontainers/bioconductor-opossom:2.24.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_opossom_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_opossom_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_opossom_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(oposSOM)
    library(AnnotatedDataFrame)
    library(ExpressionSet)
    library(jsonlite)

    # --- Environment Initialization [Initialization] ---
    # Key functions: opossom.new
    env <- opossom.new(list(
        dataset.name = "Tissues",
        dim.1stLvlSom = 20,
        dim.2ndLvlSom = 20
    ))

    # --- Data Preparation [Data Loading] ---
    # Key functions: ExpressionSet, AnnotatedDataFrame
    data(opossom.tissues)
    group.info <- data.frame(
        group.labels = c(rep("Homeostasis", 2), "Endocrine", "Digestion",
                         "Exocrine", "Epithelium", "Reproduction", "Muscle",
                         rep("Immune System", 2), rep("Nervous System", 2)),
        group.colors = c(rep("gold", 2), "red2", "brown", "purple", "cyan",
                         "pink", "green2", rep("blue2", 2), rep("gray", 2)),
        row.names = colnames(opossom.tissues)
    )
    env$indata <- ExpressionSet(
        assayData = opossom.tissues,
        phenoData = AnnotatedDataFrame(group.info)
    )

    # --- Analysis Configuration [Configuration] ---
    # Key functions: opossom.new
    env$preferences$pairwise.comparison.list <- list(
        list(c("liver", "kidney cortex"),
             c("accumbens", "cerebral cortex")),
        list(c("tongue", "small intestine"),
             c("accumbens", "cerebral cortex"))
    )
    env$preferences$database.dataset <- "hsapiens_gene_ensembl"

    # --- SOM Pipeline Execution [Execution] ---
    # Key functions: opossom.run
    opossom.run(env)


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_opossom_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_opossom_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_opossom_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_OPOSSOM:", paste0("    opossom: ", packageVersion("oposSOM"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_opossom_results.csv
    touch ${prefix}_opossom_output.rds
    echo "BIOC_OPOSSOM:" > versions.yml
    echo "    opossom: 0.0.0" >> versions.yml
    """
}


workflow BIOC_OPOSSOM_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_OPOSSOM(ch_input)

    emit:
    results  = BIOC_OPOSSOM.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_OPOSSOM.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_OPOSSOM.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_OPOSSOM.out.versions  // channel: path(versions.yml)
}
