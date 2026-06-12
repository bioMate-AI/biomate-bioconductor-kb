#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: massiR — microarray_expressionset_workflow
// Predict sample sex from an ExpressionSet object and append the predicted sex back to the ExpressionSet phenoData.
// Input: expression_set.RData, y_probes.csv
// Container: quay.io/biocontainers/bioconductor-massir:1.46.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, massiR
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Select Y chromosome probes from the ExpressionSet using massi_select
//  * 2. [Core Analysis] Predict sample sex using massi_cluster
//  * 3. [Core Analysis] Extract predicted sex results
//  * 4. [Core Analysis] Match sample order and add results to the ExpressionSet phenoData

nextflow.enable.dsl = 2

process BIOC_MASSIR_MICROARRAY_EXPRESSIONSET_WORKFLOW {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

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
    .bm_deps <- c("massiR", "Biobase")
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
    library(massiR)
    library(Biobase)
    
    # ==========================================
    # 1. Load User Input Files
    # ==========================================
    
    # Load the ExpressionSet object from expression_set.RData
    env <- new.env()
    load("expression_set.RData", envir = env)
    eset_objs <- ls(env)[sapply(ls(env), function(x) inherits(env[[x]], "ExpressionSet"))]
    if (length(eset_objs) == 0) {
      stop("Error: No ExpressionSet object found in expression_set.RData")
    }
    massi.eset <- env[[eset_objs[1]]]
    
    # Load Y chromosome probe identifiers from y_probes.csv
    # The file must have probe identifiers as row names (first column)
    massi.test.probes <- read.csv("y_probes.csv", row.names = 1, header = TRUE)
    
    # ==========================================
    # 2. Run Documented massiR Workflow
    # ==========================================
    
    eset.select.out <- 
      massi_select(massi.eset, massi.test.probes)
    
    eset.results <- 
      massi_cluster(eset.select.out)
    
    eset.sample.results <- 
      data.frame(eset.results[[2]])
    
    sexData <- 
      data.frame(eset.sample.results[c("ID", "sex")])
    
    eset.names <- 
      colnames(exprs(massi.eset))
    
    sexData <- sexData[match(eset.names, sexData\$ID),]
    
    # Append the new annotations to the existing phenoData
    pData(massi.eset)\$ID <- sexData\$ID
    pData(massi.eset)\$sex <- sexData\$sex
    
    # ==========================================
    # 3. Write Output Files
    # ==========================================
    
    # Save the predicted sex table
    write.csv(sexData, "predicted_sex_results.csv", row.names = FALSE)
    
    # Save the updated ExpressionSet object
    saveRDS(massi.eset, "expression_set_with_sex.rds")
    
    # Generate and save diagnostic plots
    pdf("massiR_diagnostic_plots.pdf", width = 10, height = 8)
    tryCatch({
      massi_cluster_plot(eset.select.out, eset.results)
    }, error = function(e) {
      warning("Could not generate cluster plots: ", e\$message)
    })
    dev.off()

    writeLines(c(
        '"BIOC_MASSIR_MICROARRAY_EXPRESSIONSET_WORKFLOW":',
        paste0('    massiR: ', as.character(packageVersion('massiR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_microarray_expressionset_workflow.csv versions.yml
    """
}

workflow BIOC_MASSIR_MICROARRAY_EXPRESSIONSET_WORKFLOW_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ expression_set.RData, y_probes.csv ] ]

    main:
    BIOC_MASSIR_MICROARRAY_EXPRESSIONSET_WORKFLOW(ch_input)

    emit:
    tables   = BIOC_MASSIR_MICROARRAY_EXPRESSIONSET_WORKFLOW.out.tables
    plots    = BIOC_MASSIR_MICROARRAY_EXPRESSIONSET_WORKFLOW.out.plots
    objects  = BIOC_MASSIR_MICROARRAY_EXPRESSIONSET_WORKFLOW.out.objects
    versions = BIOC_MASSIR_MICROARRAY_EXPRESSIONSET_WORKFLOW.out.versions
}
