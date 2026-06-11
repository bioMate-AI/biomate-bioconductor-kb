#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: OncoSimulR — simulating_progression_with_dag_restrictions
// Specify fitness restrictions using a directed acyclic graph (DAG) or poset, simulate population growth, and sample the population.
// Input: data.frame
// Container: quay.io/biocontainers/bioconductor-oncosimulr:4.12.0--r45ha27e39d_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: OncoSimulR
// Visualizations: trajectory plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Specify fitness effects using allFitnessEffects with the restriction data frame
//  * 2. [Core Analysis] Simulate individual trajectories using oncoSimulIndiv
//  * 3. [Core Analysis] Sample the simulated population using samplePop

nextflow.enable.dsl = 2

process BIOC_ONCOSIMULR_SIMULATING_PROGRESSION_WITH_DAG_RESTRICTIONS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20"

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
    .bm_deps <- c("OncoSimulR")
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
    library(OncoSimulR)
    
    # 1. Read the user-provided DAG/poset restrictions from the working directory
    # The file must be named "dag_restrictions.csv" and contain columns: parent, child, s, sh, typeDep
    input_file <- "dag_restrictions.csv"
    if (!file.exists(input_file)) {
      stop(paste("Required input file", input_file, "not found in the working directory."))
    }
    
    dag_df <- read.csv(input_file, stringsAsFactors = FALSE)
    
    # Dynamically extract driver names (all unique genes excluding "Root")
    all_genes <- unique(c(dag_df\$parent, dag_df\$child))
    drv_names <- all_genes[all_genes != "Root"]
    
    # Stage 1: Specify fitness effects using allFitnessEffects with the restriction data frame
    pancr <- allFitnessEffects(
        dag_df,
        drvNames = drv_names)
    
    # Stage 2: Simulate individual trajectories using oncoSimulIndiv
    # Keeping the exact documented function call and arguments
    ep2 <- oncoSimulIndiv(pancr, model = "McFL",
                         mu = 1e-6,
                         sampleEvery = 0.02,
                         keepEvery = 1,
                         initSize = 1000,
                         finalTime = 20000,
                         detectionDrivers = 3,
                         onlyCancer = FALSE)
    
    # Stage 3: Sample the simulated population using samplePop
    sampled_pop <- samplePop(ep2)
    
    # Write meaningful output files
    # 1. Save the simulation object as an RDS file
    saveRDS(ep2, file = "simulation_results.rds")
    
    # 2. Save the sampled population matrix as a CSV
    write.csv(as.data.frame(sampled_pop), file = "sampled_population.csv", row.names = TRUE)
    
    # 3. Save the DAG structure plot as a PDF
    pdf("dag_structure_plot.pdf")
    tryCatch({
      plot(pancr)
    }, error = function(e) {
      warning("Could not plot DAG structure: ", e\$message)
    })
    dev.off()
    
    # 4. Save the simulation trajectory plot as a PDF
    pdf("simulation_trajectory_plot.pdf")
    tryCatch({
      plot(ep2, show = "genotypes")
    }, error = function(e) {
      warning("Could not plot simulation trajectory: ", e\$message)
    })
    dev.off()

    writeLines(c(
        '"BIOC_ONCOSIMULR_SIMULATING_PROGRESSION_WITH_DAG_RESTRICTIONS":',
        paste0('    OncoSimulR: ', as.character(packageVersion('OncoSimulR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_simulating_progression_with_dag_restrictions.csv versions.yml
    """
}

workflow BIOC_ONCOSIMULR_SIMULATING_PROGRESSION_WITH_DAG_RESTRICTIONS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ data.frame ] ]

    main:
    BIOC_ONCOSIMULR_SIMULATING_PROGRESSION_WITH_DAG_RESTRICTIONS(ch_input)

    emit:
    tables   = BIOC_ONCOSIMULR_SIMULATING_PROGRESSION_WITH_DAG_RESTRICTIONS.out.tables
    plots    = BIOC_ONCOSIMULR_SIMULATING_PROGRESSION_WITH_DAG_RESTRICTIONS.out.plots
    objects  = BIOC_ONCOSIMULR_SIMULATING_PROGRESSION_WITH_DAG_RESTRICTIONS.out.objects
    versions = BIOC_ONCOSIMULR_SIMULATING_PROGRESSION_WITH_DAG_RESTRICTIONS.out.versions
}
