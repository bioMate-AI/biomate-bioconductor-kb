#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: attract
// This package contains the functions to find the gene expression modules that represent the drivers o
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/attract/inst/doc/attract.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("attract")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ATTRACT {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-attract"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-attract:1.58.0--r44_0' :
        'quay.io/biocontainers/bioconductor-attract:1.58.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_attract_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_attract_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_attract_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(attract)
    library(jsonlite)

    # --- Filtering Flat Genes [] ---
    # Key functions: removeFlatGenes
    remove.these.genes <- removeFlatGenes(
        loring.eset,
        "celltype",
        contrasts = NULL,
        limma.cutoff = 0.05
    )


    # --- Finding Attractor States [] ---
    # Key functions: findAttractors
    attractor.states <- findAttractors(
        loring.eset,
        "celltype",
        annotation = "illuminaHumanv1.db",
        database = "KEGG",
        analysis = "microarray",
        databaseGeneFormat = NULL,
        expressionSetGeneFormat = NULL
    )


    # --- Finding Synexpression Groups [] ---
    # Key functions: findSynexprs
    mapk.syn <- findSynexprs(
        "04010",
        attractor.states,
        "celltype",
        remove.these.genes
    )
    top5.syn <- findSynexprs(
        attractor.states@rankedPathways[1:5, 1],
        attractor.states,
        "celltype",
        removeGenes = remove.these.genes
    )


    # --- Visualizing Synexpression Groups [] ---
    # Key functions: plotsynexprs
    pretty.col <- rainbow(3)
    for (i in 1:3) {
        plotsynexprs(
            mapk.syn,
            tickMarks = c(6, 28, 47, 60),
            tickLabels = c("ESC", "PRO", "NSC", "TER"),
            vertLines = c(12.5, 43.5, 51.5),
            index = i,
            main = paste("Synexpression Group ", i, sep = ""),
            col = pretty.col[i]
        )
    }


    # --- Functional Enrichment and Correlation [] ---
    # Key functions: findCorrPartners, calcFuncSynexprs
    mapk.cor <- findCorrPartners(
        mapk.syn,
        loring.eset,
        remove.these.genes
    )
    mapk.func <- calcFuncSynexprs(
        mapk.syn,
        attractor.states,
        "CC",
        annotation = "illuminaHumanv1.db",
        analysis = "microarray",
        expressionSetGeneFormat = NULL
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_attract_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_attract_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_attract_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_ATTRACT:", paste0("    attract: ", packageVersion("attract"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_attract_results.csv
    touch ${prefix}_attract_output.rds
    echo "BIOC_ATTRACT:" > versions.yml
    echo "    attract: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ATTRACT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_ATTRACT(ch_input)

    emit:
    results  = BIOC_ATTRACT.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ATTRACT.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ATTRACT.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ATTRACT.out.versions  // channel: path(versions.yml)
}
