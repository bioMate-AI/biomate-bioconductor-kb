#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: grafgen — h_pylori_genome_classification
// Classify Helicobacter pylori genomes from a VCF or PLINK file into reference populations and visualize the classification results.
// Input: geno.file
// Container: quay.io/biocontainers/bioconductor-grafgen:1.6.0--r45ha27e39d_0
// R packages: GrafGen
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GRAFGEN_H_PYLORI_GENOME_CLASSIFICATION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-grafgen:1.6.0--r45ha27e39d_0"

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
    .bm_deps <- c("GrafGen")
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
    
    # 1. Load the GrafGen package
    library(GrafGen)
    
    # Define the user input file from the working directory
    geno.file <- "geno.file"
    
    if (!file.exists(geno.file)) {
      stop("Error: The required input file 'geno.file' does not exist in the working directory.")
    }
    
    # 2. Run the classification algorithm on the genotype file using grafGen
    message("Running grafGen classification...")
    ret <- grafGen(geno.file, print=0)
    
    # 3. Inspect the classification table and population counts
    message("Inspecting classification table (first few rows):")
    print(ret\$table[seq_len(min(5, nrow(ret\$table))), ])
    
    message("Printing population counts:")
    print(ret)
    
    # Save the classification table to a CSV file
    write.csv(ret\$table, "classification_results.csv", row.names = FALSE)
    message("Saved classification table to 'classification_results.csv'")
    
    # Save the full return object as an RDS file
    saveRDS(ret, "grafgen_results.rds")
    message("Saved results object to 'grafgen_results.rds'")
    
    # 4. Generate static plots of genetic distance scores
    message("Generating static plot of genetic distance scores...")
    pdf("genetic_distance_plot.pdf", width = 7, height = 7)
    plot(ret)
    dev.off()
    message("Saved static plot to 'genetic_distance_plot.pdf'")
    
    # 5. Create interactive plots of the reference and user data
    if (interactive()) {
        message("Launching interactive reference plot...")
        interactiveReferencePlot()
    } else {
        message("Skipping interactiveReferencePlot() as the session is non-interactive.")
    }
    
    # 6. Launch the interactive Shiny application for filtering and viewing results
    tmp <- createApp(ret)
    
    # Save the app data components for downstream non-interactive use
    saveRDS(tmp\$reference_results, "reference_results.rds")
    saveRDS(tmp\$user_results, "user_results.rds")
    saveRDS(tmp\$user_metadata, "user_metadata.rds")
    message("Saved Shiny app data components to RDS files.")
    
    if (interactive()) {
        message("Launching interactive Shiny application...")
        reference_results <- tmp\$reference_results
        user_results      <- tmp\$user_results
        user_metadata     <- tmp\$user_metadata
        shiny::runApp(tmp\$app)
    } else {
        message("Skipping Shiny app launch as the session is non-interactive.")
    }
    
    message("Pipeline completed successfully.")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_GRAFGEN_H_PYLORI_GENOME_CLASSIFICATION":
        grafgen: \$(Rscript -e 'cat(as.character(packageVersion("grafgen")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_h_pylori_genome_classification.csv versions.yml
    """
}

workflow BIOC_GRAFGEN_H_PYLORI_GENOME_CLASSIFICATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ geno.file ] ]

    main:
    BIOC_GRAFGEN_H_PYLORI_GENOME_CLASSIFICATION(ch_input)

    emit:
    tables   = BIOC_GRAFGEN_H_PYLORI_GENOME_CLASSIFICATION.out.tables
    plots    = BIOC_GRAFGEN_H_PYLORI_GENOME_CLASSIFICATION.out.plots
    objects  = BIOC_GRAFGEN_H_PYLORI_GENOME_CLASSIFICATION.out.objects
    versions = BIOC_GRAFGEN_H_PYLORI_GENOME_CLASSIFICATION.out.versions
}
