#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: optimalFlow — supervised_cytometry_classification
// Classify and gate a new, ungated cytometry using a database of gated cytometries and pre-computed templates.
// Input: test.cytometry, database, templates.optimalFlow
// Container: quay.io/biocontainers/bioconductor-optimalflow:1.22.0--r45h575d39b_0
// R packages: ellipse, optimalFlow
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_OPTIMALFLOW_SUPERVISED_CYTOMETRY_CLASSIFICATION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-optimalflow:1.22.0--r45h575d39b_0"

    input:
    tuple val(meta), path(input_files, stageAs: '?/*')

    output:
    tuple val(meta), path("*.csv"), emit: tables, optional: true
    tuple val(meta), path("*.pdf"), emit: plots,  optional: true
    tuple val(meta), path("*.rds"), emit: objects, optional: true
    path "versions.yml",            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("ellipse", "optimalFlow")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
    }

    # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
    for (.bm_d in list.files(".", full.names = TRUE)) {
      if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
        for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
          if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
        }
      }
    }
    
    # Load required libraries
    library(optimalFlow)
    library(ellipse)
    
    # Define noise.types as NULL (default)
    noise.types <- NULL
    
    # Read user input files from the working directory
    test.cytometry <- readRDS("test.cytometry")
    database <- readRDS("database")
    templates.optimalFlow <- readRDS("templates.optimalFlow")
    
    # Filter test.cytometry if it contains the Population ID column and has not been pre-filtered
    if ("Population ID (name)" %in% colnames(test.cytometry)) {
      test.cytometry <- test.cytometry[which(match(test.cytometry\$`Population ID (name)`, c("Monocytes", "CD4+CD8-", "Mature SIg Kappa", "TCRgd-"), nomatch = 0) > 0), ]
    }
    
    # Generate templates for barycenter and hdbscan consensus methods using the database
    templates.optimalFlow.barycenter <- optimalFlowTemplates(
      database = database, templates.number = 5, consensus.method = "k-barycenter",
      barycenters.number = 4, bar.repetitions = 10, alpha.bar = 0.05, cl.paral = 1
    )
    
    templates.optimalFlow.hdbscan <- optimalFlowTemplates(
      database = database, templates.number = 5, consensus.method = "hierarchical",
      cl.paral = 1
    )
    
    # 1. Supervised classification using pooling consensus method (QDA)
    classification.optimalFlow <- 
      optimalFlowClassification(
        test.cytometry[, 1:10], database, templates.optimalFlow, 
        consensus.method = "pooling", cl.paral = 1
        )
    
    scoreF1.optimalFlow <- optimalFlow::f1Score(classification.optimalFlow\$cluster,
                                                test.cytometry, noise.types)
    
    # 2. Supervised classification using k-barycenter consensus method
    classification.optimalFlow.barycenter <-
      optimalFlowClassification(
        test.cytometry[, 1:10],
        database, templates.optimalFlow.barycenter, consensus.method = "k-barycenter", cl.paral = 1
        )
    
    scoreF1.optimalFlow.barycenter <- 
      f1ScoreVoting(
        classification.optimalFlow.barycenter\$cluster.vote, classification.optimalFlow.barycenter\$cluster,
        test.cytometry,
        1.01, noise.types
        )
    
    # 3. Supervised classification using hierarchical consensus method
    classification.optimalFlow.hdbscan <-
      optimalFlowClassification(
        test.cytometry[, 1:10],
        database, templates.optimalFlow.hdbscan, consensus.method = "hierarchical", cl.paral = 1
        )
    
    scoreF1.optimalFlow.hdbscan <-
      f1ScoreVoting(
        classification.optimalFlow.hdbscan\$cluster.vote, classification.optimalFlow.hdbscan\$cluster,
        test.cytometry,
        1.01, noise.types
      )
    
    # 4. Supervised classification using matching (label-transfer)
    classification.optimalFlow.2 <-
      optimalFlowClassification(
        test.cytometry[, 1:10],
        database, templates.optimalFlow, consensus.method = "pooling", classif.method = "matching",
        cost.function = "ellipses", cl.paral = 1
        )
    
    scoreF1.optimalFlow.2 <-
      f1ScoreVoting(
        classification.optimalFlow.2\$cluster.vote, classification.optimalFlow.2\$cluster,
        test.cytometry,
        1.01, noise.types
        )
    
    # 5. Supervised classification using random forest
    classification.optimalFlow.3 <-
      optimalFlowClassification(
        test.cytometry[, 1:10],
        database, templates.optimalFlow, consensus.method = "pooling",
        classif.method = "random forest", cl.paral = 1
        )
    
    scoreF1.optimalFlow.3 <-
      optimalFlow::f1Score(classification.optimalFlow.3\$cluster,
        test.cytometry,
        noise.types
        )
    
    # Save classification objects
    saveRDS(classification.optimalFlow, "classification_optimalFlow_pooling.rds")
    saveRDS(classification.optimalFlow.barycenter, "classification_optimalFlow_barycenter.rds")
    saveRDS(classification.optimalFlow.hdbscan, "classification_optimalFlow_hdbscan.rds")
    saveRDS(classification.optimalFlow.2, "classification_optimalFlow_matching.rds")
    saveRDS(classification.optimalFlow.3, "classification_optimalFlow_rf.rds")
    
    # Save F1 score results
    write.csv(as.data.frame(scoreF1.optimalFlow), "f1_score_pooling.csv", row.names = TRUE)
    write.csv(as.data.frame(scoreF1.optimalFlow.barycenter\$F1_score), "f1_score_barycenter.csv", row.names = TRUE)
    write.csv(as.data.frame(scoreF1.optimalFlow.hdbscan\$F1_score), "f1_score_hdbscan.csv", row.names = TRUE)
    write.csv(as.data.frame(scoreF1.optimalFlow.2\$F1_score), "f1_score_matching.csv", row.names = TRUE)
    write.csv(as.data.frame(scoreF1.optimalFlow.3), "f1_score_rf.csv", row.names = TRUE)
    
    # Generate diagnostic plots
    pdf("optimalFlow_templates_plots.pdf", width = 10, height = 8)
    if (length(templates.optimalFlow\$templates) >= 3) {
      cytoPlot(templates.optimalFlow\$templates[[3]], dimensions = c(4,3), xlim = c(0, 8000), ylim = c(0, 8000), xlab = "Dimension 4", ylab = "Dimension 3")
    }
    dev.off()

    writeLines(c(
        '"BIOC_OPTIMALFLOW_SUPERVISED_CYTOMETRY_CLASSIFICATION":',
        paste0('        optimalFlow: ', as.character(packageVersion("optimalFlow")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_supervised_cytometry_classification.csv versions.yml
    """
}

workflow BIOC_OPTIMALFLOW_SUPERVISED_CYTOMETRY_CLASSIFICATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ test.cytometry, database, templates.optimalFlow ] ]

    main:
    BIOC_OPTIMALFLOW_SUPERVISED_CYTOMETRY_CLASSIFICATION(ch_input)

    emit:
    tables   = BIOC_OPTIMALFLOW_SUPERVISED_CYTOMETRY_CLASSIFICATION.out.tables
    plots    = BIOC_OPTIMALFLOW_SUPERVISED_CYTOMETRY_CLASSIFICATION.out.plots
    objects  = BIOC_OPTIMALFLOW_SUPERVISED_CYTOMETRY_CLASSIFICATION.out.objects
    versions = BIOC_OPTIMALFLOW_SUPERVISED_CYTOMETRY_CLASSIFICATION.out.versions
}
