#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: RIVER — river_model_application
// Train the RIVER model on all instances and estimate the posterior probabilities of rare variants having regulatory impact.
// Input: simulation_RIVER.gz
// Container: quay.io/biocontainers/bioconductor-river:1.34.0--r45hdfd78af_0
// R packages: RIVER
// Bioconductor: 3.20 | R: 4.4
// Requires: RIVER
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Import and standardize the experimental data using getData
//  * 2. [Core Analysis] Train the model and compute posterior probabilities using appRIVER
//  * 3. [Core Analysis] Extract and format the posterior probabilities for downstream analysis
//  * 4. [Visualization & Output] Visualize the posterior probabilities using plotPosteriors

nextflow.enable.dsl = 2

process BIOC_RIVER_RIVER_MODEL_APPLICATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20"

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
    .bm_deps <- c("RIVER")
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
    library(RIVER)
    
    # Define the input file name (must be in the working directory)
    filename <- "simulation_RIVER.gz"
    
    # Check if the input file exists
    if (!file.exists(filename)) {
      stop(paste("Error: Required input file '", filename, "' not found in the working directory.", sep=""))
    }
    
    # 1. Import and standardize the experimental data using getData
    message("Importing and standardizing data...")
    dataInput <- getData(filename)
    
    # 2. Train the model and compute posterior probabilities using appRIVER
    message("Training RIVER model and estimating posterior probabilities...")
    postprobs <- appRIVER(dataInput)
    
    # 3. Extract and format the posterior probabilities for downstream analysis
    message("Extracting posterior probabilities...")
    example_probs <- data.frame(
      Subject = postprobs\$indiv_name, 
      Gene = postprobs\$gene_name, 
      RIVERpp = postprobs\$RIVER_posterior, 
      GAMpp = postprobs\$GAM_posterior
    )
    
    # Display the first few rows of the formatted probabilities
    message("Preview of estimated probabilities:")
    print(head(example_probs))
    
    # Save the formatted probabilities to a CSV file
    output_csv <- "river_posterior_probabilities.csv"
    write.csv(example_probs, file = output_csv, row.names = FALSE)
    message(paste("Saved posterior probabilities to", output_csv))
    
    # Save the complete postprobs object as an RDS file for downstream R analyses
    output_rds <- "river_postprobs.rds"
    saveRDS(postprobs, file = output_rds)
    message(paste("Saved fitted model and posteriors object to", output_rds))
    
    # 4. Visualize the posterior probabilities using plotPosteriors
    message("Generating posterior probability plot...")
    output_pdf <- "river_posteriors_plot.pdf"
    pdf(output_pdf, width = 8, height = 6)
    
    # Call plotPosteriors and handle potential ggplot return object
    p <- plotPosteriors(postprobs, outliers = as.numeric(unlist(dataInput\$Outlier)) - 1)
    if (inherits(p, "ggplot") || !is.null(p)) {
      print(p)
    }
    
    dev.off()
    message(paste("Saved posteriors plot to", output_pdf))
    message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_RIVER_RIVER_MODEL_APPLICATION":',
        paste0('    RIVER: ', as.character(packageVersion('RIVER')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_river_model_application.csv versions.yml
    """
}

workflow BIOC_RIVER_RIVER_MODEL_APPLICATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ simulation_RIVER.gz ] ]

    main:
    BIOC_RIVER_RIVER_MODEL_APPLICATION(ch_input)

    emit:
    tables   = BIOC_RIVER_RIVER_MODEL_APPLICATION.out.tables
    plots    = BIOC_RIVER_RIVER_MODEL_APPLICATION.out.plots
    objects  = BIOC_RIVER_RIVER_MODEL_APPLICATION.out.objects
    versions = BIOC_RIVER_RIVER_MODEL_APPLICATION.out.versions
}
