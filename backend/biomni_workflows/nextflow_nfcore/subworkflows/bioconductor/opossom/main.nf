#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: oposSOM — matrix_input_workflow
// Run the oposSOM analysis pipeline using a standard numerical matrix of expression values.
// Input: expression_matrix.csv
// Container: quay.io/biocontainers/bioconductor-opossom:2.28.0--r45ha27e39d_0
// R packages: Biobase, biomaRt, oposSOM
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_OPOSSOM_MATRIX_INPUT_WORKFLOW {
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
    .bm_deps <- c("Biobase", "biomaRt", "oposSOM")
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
    library(oposSOM)
    
    # Check for the presence of the required input file
    input_file <- "expression_matrix.csv"
    if (!file.exists(input_file)) {
      stop(paste("Required input file", input_file, "is missing in the working directory."))
    }
    
    # Read the expression matrix from the user input file
    # The file is expected to be a numerical matrix of log-transformed expression values
    # with genes as rows and samples as columns.
    expression_matrix <- as.matrix(read.csv(input_file, row.names = 1, check.names = FALSE))
    
    # 1. Initialize environment with opossom.new
    env <- opossom.new(list(dataset.name="Tissues",
                            dim.1stLvlSom=20))
    
    # 2. Assign expression matrix to env\$indata
    env\$indata <- expression_matrix
    
    # 3. Define sample group labels and colors
    env\$group.labels <- c(rep("Homeostasis", 2),
                              "Endocrine",
                              "Digestion",
                              "Exocrine",
                              "Epithelium",
                              "Reproduction",
                              "Muscle",
                          rep("Immune System", 2),
                          rep("Nervous System", 2) )
    
    env\$group.colors <- c(rep("gold", 2),
                              "red2",
                              "brown",
                              "purple",
                              "cyan",
                              "pink",
                              "green2",
                          rep("blue2", 2),
                          rep("gray", 2) )
    
    # 4. Define pairwise comparison groups
    env\$preferences\$pairwise.comparison.list <-
        list(list(c("liver","kidney cortex"),
                  c("accumbens","cerebral cortex")),
             list(c("tongue","small intestine"),
                  c("accumbens","cerebral cortex")))
    
    # 5. Run the pipeline with opossom.run
    # This will generate the standard oposSOM output directory structure (e.g., "Tissues" folder)
    # containing HTML reports, PDF plots, and CSV tables.
    opossom.run(env)
    
    # Save the final environment object as an RDS file for downstream analysis
    saveRDS(env, file = "opossom_output_env.rds")

    writeLines(c(
        '"BIOC_OPOSSOM_MATRIX_INPUT_WORKFLOW":',
        paste0('        oposSOM: ', as.character(packageVersion("oposSOM")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_matrix_input_workflow.csv versions.yml
    """
}

workflow BIOC_OPOSSOM_MATRIX_INPUT_WORKFLOW_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ expression_matrix.csv ] ]

    main:
    BIOC_OPOSSOM_MATRIX_INPUT_WORKFLOW(ch_input)

    emit:
    tables   = BIOC_OPOSSOM_MATRIX_INPUT_WORKFLOW.out.tables
    plots    = BIOC_OPOSSOM_MATRIX_INPUT_WORKFLOW.out.plots
    objects  = BIOC_OPOSSOM_MATRIX_INPUT_WORKFLOW.out.objects
    versions = BIOC_OPOSSOM_MATRIX_INPUT_WORKFLOW.out.versions
}
