#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: treeclimbR
// The arrangement of hypotheses in a hierarchical structure appears in many research fields and often 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/treeclimbR/inst/doc/treeclimbR.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("treeclimbR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_TREECLIMBR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-treeclimbr"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-treeclimbr:1.2.0--r44_0' :
        'quay.io/biocontainers/bioconductor-treeclimbr:1.2.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_treeclimbr_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_treeclimbr_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_treeclimbr_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(treeclimbR)
    library(jsonlite)

    # --- Data import and preprocessing [] ---
    # Key functions: joinNode, unlist, ggtree, aes, geom_text2
    da_lse <- readRDS(system.file("extdata", "da_sim_100_30_18de.rds",
    nds <- joinNode(tree = rowTree(da_lse),
    node = rownames(da_lse)[rowData(da_lse)$Signal])
    # --- ShowNode analysis [] ---
    # Key functions: showNode, aggTSE, runDA, nodeResult, getCand, geom_point2, labs, theme
    ds_res <- runDS(SE = ds_se, tree = colTree(ds_tse), option = "glmQL",
    design = model.matrix(~ group, data = colData(ds_se)),
    contrast = c(0, 1), filter_min_count = 0,

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_treeclimbr_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_treeclimbr_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_treeclimbr_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_TREECLIMBR:", paste0("    treeclimbr: ", packageVersion("treeclimbR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_treeclimbr_results.csv
    touch ${prefix}_treeclimbr_output.rds
    echo "BIOC_TREECLIMBR:" > versions.yml
    echo "    treeclimbr: 0.0.0" >> versions.yml
    """
}


workflow BIOC_TREECLIMBR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_TREECLIMBR(ch_input)

    emit:
    results  = BIOC_TREECLIMBR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_TREECLIMBR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_TREECLIMBR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_TREECLIMBR.out.versions  // channel: path(versions.yml)
}
