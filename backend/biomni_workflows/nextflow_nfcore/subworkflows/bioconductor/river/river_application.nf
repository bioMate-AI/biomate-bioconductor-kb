#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: river — river_application
// Train the RIVER model on all instances and compute posterior probabilities of rare variants being functional for downstream prioritization.
// Input: simulation_RIVER.gz
// Container: quay.io/biocontainers/bioconductor-river:1.34.0--r45hdfd78af_0
// R packages: RIVER
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RIVER_RIVER_APPLICATION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-river:1.34.0--r45hdfd78af_0"

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
    
    # Define input file (must be in the working directory)
    filename <- "simulation_RIVER.gz"
    
    # Check if input file exists
    if (!file.exists(filename)) {
      stop(paste("Error: Input file", filename, "not found in the working directory. Please ensure 'simulation_RIVER.gz' is present."))
    }
    
    # 1. Import experimental data using getData
    message("Importing experimental data...")
    dataInput <- getData(filename)
    
    # 2. Train and predict posterior probabilities using appRIVER
    message("Training RIVER model and predicting posterior probabilities...")
    postprobs <- appRIVER(
      dataInput, 
      pseudoc=50, 
      theta_init=matrix(c(.99, .01, .3, .7), nrow=2), 
      costs=c(100, 10, 1, .1, .01, 1e-3, 1e-4), 
      verbose=TRUE
    )
    
    # 3. Extract posterior probabilities for downstream analysis
    message("Extracting posterior probabilities...")
    example_probs <- data.frame(
      Subject=postprobs\$indiv_name, 
      Gene=postprobs\$gene_name, 
      RIVERpp=postprobs\$RIVER_posterior, 
      GAMpp=postprobs\$GAM_posterior
    )
    
    # Print the head of the extracted probabilities to console
    print(head(example_probs))
    
    # Save posterior probabilities to a CSV file
    write.csv(example_probs, "river_posterior_probabilities.csv", row.names=FALSE)
    message("Saved posterior probabilities to 'river_posterior_probabilities.csv'")
    
    # Save the full postprobs object as an RDS file
    saveRDS(postprobs, "river_postprobs_model.rds")
    message("Saved full model object to 'river_postprobs_model.rds'")
    
    # Print and save estimated parameters (beta and theta)
    message("RIVER Model Parameters:")
    print("Beta (Genomic Feature Coefficients):")
    print(postprobs\$fitRIVER\$beta)
    print("Theta (Conditional Probabilities P(E|FR)):")
    print(postprobs\$fitRIVER\$theta)
    
    # Save parameters to text files
    write.table(as.data.frame(postprobs\$fitRIVER\$beta), "river_fit_beta.txt", col.names=TRUE, row.names=TRUE, quote=FALSE, sep="\t")
    write.table(postprobs\$fitRIVER\$theta, "river_fit_theta.txt", col.names=FALSE, row.names=FALSE, quote=FALSE, sep="\t")
    message("Saved model parameters to 'river_fit_beta.txt' and 'river_fit_theta.txt'")
    
    # 4. Plot the posterior probabilities using plotPosteriors
    message("Generating posterior probabilities plot...")
    pdf("river_posteriors_plot.pdf", width=8, height=6)
    plotPosteriors(postprobs, outliers=as.numeric(unlist(dataInput\$Outlier))-1)
    dev.off()
    message("Saved plot to 'river_posteriors_plot.pdf'")
    
    message("Pipeline completed successfully.")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_RIVER_RIVER_APPLICATION":
        river: \$(Rscript -e 'cat(as.character(packageVersion("river")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_river_application.csv versions.yml
    """
}

workflow BIOC_RIVER_RIVER_APPLICATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ simulation_RIVER.gz ] ]

    main:
    BIOC_RIVER_RIVER_APPLICATION(ch_input)

    emit:
    tables   = BIOC_RIVER_RIVER_APPLICATION.out.tables
    plots    = BIOC_RIVER_RIVER_APPLICATION.out.plots
    objects  = BIOC_RIVER_RIVER_APPLICATION.out.objects
    versions = BIOC_RIVER_RIVER_APPLICATION.out.versions
}
