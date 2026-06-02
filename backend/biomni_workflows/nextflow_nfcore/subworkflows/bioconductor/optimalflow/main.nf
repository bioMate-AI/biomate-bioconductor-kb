#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: optimalFlow
// Optimal-transport techniques applied to supervised flow cytometry gating.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/optimalFlow/inst/doc/optimalFlow_vignette.R
// Upstream  : optimalFlowData, ellipse
// Downstream: none
//
// Install: BiocManager::install("optimalFlow")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_OPTIMALFLOW {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-optimalflow"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-optimalflow:1.18.0--r44_0' :
        'quay.io/biocontainers/bioconductor-optimalflow:1.18.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_optimalflow_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_optimalflow_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_optimalflow_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(optimalFlow)
    library(jsonlite)


    # --- Ej1 [] ---
    # Key functions: buildDatabase, optimalFlowTemplates
    database <- buildDatabase(
     dataset_names = paste0('Cytometry', c(2:5, 7:9, 12:17, 19, 21)),
       population_ids = c('Monocytes', 'CD4+CD8-', 'Mature SIg Kappa', 'TCRgd-'))
    templates.optimalFlow <-
      optimalFlowTemplates(
        database = database, templates.number = 5, cl.paral = 1
        )
    length(templates.optimalFlow$templates) # The number of clusters, and, hence, of templates 
    length(templates.optimalFlow$templates[[1]]) # The number of elements of the first template, it contains four cell types
    templates.optimalFlow$templates[[1]][[1]] # The first element of the first template
    templates.optimalFlow$clustering

    # --- Ej1114 [] ---
    # Key functions: cytoPlotDatabase, cytoPlot
    length(templates.optimalFlow$database.elliptical) # the number of elements in the database
    length(templates.optimalFlow$database.elliptical[[1]]) # the number of cell types in the first element of the database
    templates.optimalFlow$database.elliptical[[1]][[1]] # the parameters corresponding to the first cell type in the first cytometry of the database
    cytoPlotDatabase(templates.optimalFlow$database.elliptical[which(templates.optimalFlow$clustering == 3)], dimensions = c(4,3), xlim = c(0, 8000), ylim = c(0, 8000), xlab = "", ylab = "")
    cytoPlot(templates.optimalFlow$templates[[3]], dimensions = c(4,3), xlim = c(0, 8000), ylim = c(0, 8000), xlab = "", ylab = "")
    cytoPlotDatabase(templates.optimalFlow$database.elliptical[which(templates.optimalFlow$clustering == 3)], dimensions = c(4,3), xlim = c(0, 8000), ylim = c(0, 8000), xlab = "", ylab = "", colour = FALSE)

    # --- Ej5 [] ---
    # Key functions: optimalFlowTemplates, hierarchical, cytoPlot
    templates.optimalFlow.barycenter <- 
      optimalFlowTemplates(
        database = database, templates.number = 5, consensus.method = "k-barycenter",
        barycenters.number = 4, bar.repetitions = 10, alpha.bar = 0.05, cl.paral = 1
        )
    templates.optimalFlow.hdbscan <- 
      optimalFlowTemplates(
        database = database, templates.number = 5, consensus.method = "hierarchical",
        cl.paral = 1
        )
    cytoPlot(templates.optimalFlow.barycenter$templates[[3]], dimensions = c(4,3), xlim = c(0, 8000), ylim = c(0, 8000), xlab = "", ylab = "")
    cytoPlot(templates.optimalFlow.hdbscan$templates[[3]], dimensions = c(4,3), xlim = c(0, 8000), ylim = c(0, 8000), xlab = "", ylab = "")

    # --- Ej77 [] ---
    # Key functions: optimalFlowTemplates, cytoPlot, hdbscan, hierarchical, match, optimalFlowClassification, pooling
    templates.optimalFlow.unsup <-
      optimalFlowTemplates(
        database = database, hclust.method = "hdbscan", cl.paral = 1, consensus.method = "hierarchical"
        )
    print(templates.optimalFlow.unsup$clustering)
    print(templates.optimalFlow$clustering)
    cytoPlot(templates.optimalFlow.unsup$templates[[5]], dimensions = c(4,3), xlim = c(0, 8000), ylim = c(0, 8000), xlab = "", ylab = "")
    test.cytometry <- Cytometry1[which(match(Cytometry1$`Population ID (name)`, c("Monocytes", "CD4+CD8-", "Mature SIg Kappa", "TCRgd-"), nomatch = 0) > 0), ]
    classification.optimalFlow <- 
      optimalFlowClassification(
        test.cytometry[, 1:10], database, templates.optimalFlow, 
        consensus.method = "pooling", cl.paral = 1
        )
    head(classification.optimalFlow$cluster)
    table(classification.optimalFlow$cluster)

    # --- Ej83 [] ---
    # Key functions: f1Score, optimalFlowClassification
    length(classification.optimalFlow$clusterings)
    table(classification.optimalFlow$clusterings[[1]]$cluster)
    classification.optimalFlow$assigned.template.index
    templates.optimalFlow$clustering
    scoreF1.optimalFlow <- optimalFlow::f1Score(classification.optimalFlow$cluster,
                                                test.cytometry, noise.types)
    print(scoreF1.optimalFlow)
    classification.optimalFlow.barycenter <-
      optimalFlowClassification(
        test.cytometry[, 1:10],
        database, templates.optimalFlow.barycenter, consensus.method = "k-barycenter", cl.paral = 1
        )

    # --- Ej92 [] ---
    # Key functions: f1ScoreVoting, optimalFlowClassification, hierarchical
    table(classification.optimalFlow.barycenter$cluster)
    classification.optimalFlow.barycenter$cluster.vote
    classification.optimalFlow.barycenter$assigned.template.index
    templates.optimalFlow.barycenter$clustering
    scoreF1.optimalFlow.barycenter <- 
      f1ScoreVoting(
        classification.optimalFlow.barycenter$cluster.vote, classification.optimalFlow.barycenter$cluster,
        test.cytometry,
        1.01, noise.types
        )
    print(scoreF1.optimalFlow.barycenter$F1_score)
    classification.optimalFlow.hdbscan <-
      optimalFlowClassification(
        test.cytometry[, 1:10],
        database, templates.optimalFlow.hdbscan, consensus.method = "hierarchical", cl.paral = 1
        )
    table(classification.optimalFlow.hdbscan$cluster)
    classification.optimalFlow.hdbscan$cluster.vote
    classification.optimalFlow.hdbscan$assigned.template.index
    templates.optimalFlow.hdbscan$clustering

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_optimalflow_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_optimalflow_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_optimalflow_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_OPTIMALFLOW:", paste0("    optimalflow: ", packageVersion("optimalFlow"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_optimalflow_results.csv
    touch ${prefix}_optimalflow_output.rds
    echo "BIOC_OPTIMALFLOW:" > versions.yml
    echo "    optimalflow: 0.0.0" >> versions.yml
    """
}


workflow BIOC_OPTIMALFLOW_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_OPTIMALFLOW(ch_input)

    emit:
    results  = BIOC_OPTIMALFLOW.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_OPTIMALFLOW.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_OPTIMALFLOW.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_OPTIMALFLOW.out.versions  // channel: path(versions.yml)
}
