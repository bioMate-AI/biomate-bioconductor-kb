#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: BioGA — genetic_algorithm_feature_selection
// Optimize gene selection for trait prediction using a genetic algorithm.
// Input: genomic_data.matrix
// Container: quay.io/biocontainers/bioconductor-bioga:1.4.0--r45ha27e39d_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: BioGA, SummarizedExperiment
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Initialize the candidate population using initialize_population_cpp
//  * 2. [Core Analysis] Evaluate population fitness using evaluate_fitness_cpp
//  * 3. [Core Analysis] Select parent individuals using selection_cpp
//  * 4. [Core Analysis] Generate offspring using crossover_cpp
//  * 5. [Core Analysis] Apply mutation to offspring using mutation_cpp
//  * 6. [Core Analysis] Replace weak population members with offspring using replacement_cpp
//  * 7. [Visualization & Output] Plot the fitness history over generations using plot_fitness_history

nextflow.enable.dsl = 2

process BIOC_BIOGA_GENETIC_ALGORITHM_FEATURE_SELECTION {
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
    .bm_deps <- c("BioGA")
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
    
    # Load necessary packages
    library(BioGA)
    
    # Define input file path
    input_file <- "genomic_data.matrix"
    
    if (!file.exists(input_file)) {
      stop(paste("Required input file", input_file, "not found in the working directory."))
    }
    
    # Read the genomic data matrix robustly
    genomic_data_raw <- tryCatch({
      readRDS(input_file)
    }, error = function(e) {
      # If not RDS, try reading as a delimited text file
      as.matrix(read.table(input_file, header = TRUE, row.names = 1, check.names = FALSE))
    })
    
    # Ensure it is a matrix
    genomic_data_matrix <- as.matrix(genomic_data_raw)
    
    # Create SummarizedExperiment object to mimic the documented workflow
    se <- SummarizedExperiment::SummarizedExperiment(assays = list(counts = genomic_data_matrix))
    
    # Convert SummarizedExperiment to matrix for compatibility with BioGA package
    genomic_data <- assay(se)
    
    # Define parameters for genetic algorithm (from documented code)
    population_size <- 100
    generations <- 20
    mutation_rate <- 0.1
    
    # Initialize population (select the number of candidate you wish `population`)
    population <- BioGA::initialize_population_cpp(genomic_data,
        population_size = 5
    )
    
    # Initialize fitness history
    fitness_history <- list()
    
    # Initialize time progress
    start_time <- Sys.time()
    
    # Run genetic algorithm optimization
    generation <- 0
    while (TRUE) {
        generation <- generation + 1
    
        # Evaluate fitness
        fitness <- BioGA::evaluate_fitness_cpp(genomic_data, population)
        fitness_history[[generation]] <- fitness
    
        # Check termination condition
        if (generation == generations) { # defined number of generations
            break
        }
    
        # Selection
        selected_parents <- BioGA::selection_cpp(population,
            fitness,
            num_parents = 2
        )
    
        # Crossover and Mutation
        offspring <- BioGA::crossover_cpp(selected_parents, offspring_size = 2)
        # (no mutation in this example)
        mutated_offspring <- BioGA::mutation_cpp(offspring, mutation_rate = 0)
    
        # Replacement
        population <- BioGA::replacement_cpp(population, mutated_offspring,
            num_to_replace = 1
        )
    
        # Calculate time progress
        elapsed_time <- difftime(Sys.time(), start_time, units = "secs")
    
        # Print time progress
        cat(
            "\rGeneration:", generation, "- Elapsed Time:",
            format(elapsed_time, units = "secs"), "     "
        )
    }
    cat("\nOptimization complete.\n")
    
    # Plot fitness change over generations and save to PDF
    pdf("fitness_history_plot.pdf", width = 7, height = 5)
    p <- BioGA::plot_fitness_history(fitness_history)
    if (inherits(p, "ggplot")) {
      print(p)
    }
    dev.off()
    
    # Save the final population and fitness history as RDS objects
    saveRDS(population, "final_population.rds")
    saveRDS(fitness_history, "fitness_history.rds")
    
    # Export fitness history as a structured CSV table
    fitness_df <- do.call(rbind, lapply(seq_along(fitness_history), function(g) {
      data.frame(
        Generation = g,
        Individual = seq_along(fitness_history[[g]]),
        Fitness = fitness_history[[g]]
      )
    }))
    write.csv(fitness_df, "fitness_history.csv", row.names = FALSE)
    
    cat("Outputs saved: 'fitness_history_plot.pdf', 'final_population.rds', 'fitness_history.rds', and 'fitness_history.csv'.\n")

    writeLines(c(
        '"BIOC_BIOGA_GENETIC_ALGORITHM_FEATURE_SELECTION":',
        paste0('    BioGA: ', as.character(packageVersion('BioGA')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_genetic_algorithm_feature_selection.csv versions.yml
    """
}

workflow BIOC_BIOGA_GENETIC_ALGORITHM_FEATURE_SELECTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ genomic_data.matrix ] ]

    main:
    BIOC_BIOGA_GENETIC_ALGORITHM_FEATURE_SELECTION(ch_input)

    emit:
    tables   = BIOC_BIOGA_GENETIC_ALGORITHM_FEATURE_SELECTION.out.tables
    plots    = BIOC_BIOGA_GENETIC_ALGORITHM_FEATURE_SELECTION.out.plots
    objects  = BIOC_BIOGA_GENETIC_ALGORITHM_FEATURE_SELECTION.out.objects
    versions = BIOC_BIOGA_GENETIC_ALGORITHM_FEATURE_SELECTION.out.versions
}
