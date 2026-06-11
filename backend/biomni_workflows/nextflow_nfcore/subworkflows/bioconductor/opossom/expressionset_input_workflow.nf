#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: oposSOM — expressionset_input_workflow
// Run the oposSOM analysis pipeline using a Biobase ExpressionSet object containing expression data and phenotype metadata.
// Input: expression_set.RData
// Container: quay.io/biocontainers/bioconductor-opossom:2.28.0--r45ha27e39d_0
// R packages: Biobase, oposSOM
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_OPOSSOM_EXPRESSIONSET_INPUT_WORKFLOW {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-opossom:2.28.0--r45ha27e39d_0"

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
    .bm_deps <- c("Biobase", "oposSOM")
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
    
    library(oposSOM)
    library(Biobase)
    
    # 1. Initialize environment with opossom.new
    env <- opossom.new(list(dataset.name="Tissues",
                            dim.1stLvlSom=20))
    
    # 2. Load ExpressionSet from the user input file
    local_env <- new.env()
    load("expression_set.RData", envir = local_env)
    
    eset_obj <- NULL
    for (name in ls(local_env)) {
      if (inherits(local_env[[name]], "ExpressionSet")) {
        eset_obj <- local_env[[name]]
        break
      }
    }
    
    if (is.null(eset_obj)) {
      stop("Error: No ExpressionSet object found in expression_set.RData")
    }
    
    # 3. Assign ExpressionSet to env\$indata
    env\$indata <- eset_obj
    
    # 4. Define pairwise comparison groups
    # We use the documented pairwise comparison list if the expected samples exist.
    # Otherwise, we dynamically adapt it to the available samples to prevent pipeline failure.
    sample_names <- colnames(eset_obj)
    expected_samples <- c("liver", "kidney cortex", "accumbens", "cerebral cortex", "tongue", "small intestine")
    
    if (all(expected_samples %in% sample_names)) {
      env\$preferences\$pairwise.comparison.list <-
          list(list(c("liver","kidney cortex"),
                    c("accumbens","cerebral cortex")),
               list(c("tongue","small intestine"),
                    c("accumbens","cerebral cortex")))
    } else {
      if (length(sample_names) >= 4) {
        env\$preferences\$pairwise.comparison.list <-
            list(list(sample_names[1:2],
                      sample_names[3:4]))
      } else {
        env\$preferences\$pairwise.comparison.list <- NULL
      }
    }
    
    # 5. Run the pipeline with opossom.run
    opossom.run(env)
    
    # Save the final environment object containing all results
    saveRDS(env, file = "opossom_output_env.rds")

    writeLines(c(
        '"BIOC_OPOSSOM_EXPRESSIONSET_INPUT_WORKFLOW":',
        paste0('        oposSOM: ', as.character(packageVersion("oposSOM")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_expressionset_input_workflow.csv versions.yml
    """
}

workflow BIOC_OPOSSOM_EXPRESSIONSET_INPUT_WORKFLOW_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ expression_set.RData ] ]

    main:
    BIOC_OPOSSOM_EXPRESSIONSET_INPUT_WORKFLOW(ch_input)

    emit:
    tables   = BIOC_OPOSSOM_EXPRESSIONSET_INPUT_WORKFLOW.out.tables
    plots    = BIOC_OPOSSOM_EXPRESSIONSET_INPUT_WORKFLOW.out.plots
    objects  = BIOC_OPOSSOM_EXPRESSIONSET_INPUT_WORKFLOW.out.objects
    versions = BIOC_OPOSSOM_EXPRESSIONSET_INPUT_WORKFLOW.out.versions
}
