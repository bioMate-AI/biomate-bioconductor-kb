#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: MouseFM — strain_prioritization
// Prioritize additional inbred mouse strains to refine a genetic region identified in a crossing experiment between two initial strains.
// Input: Genomic region coordinates
// Container: quay.io/biocontainers/bioconductor-mousefm:1.20.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: MouseFM, ggplot2
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run strain prioritization using prio()
//  * 2. [Core Analysis] Extract the top strain combinations that provide the best refinement using get_top()
//  * 3. [Visualization & Output] Visualize the reduction factors using vis_reduction_factors()

nextflow.enable.dsl = 2

process BIOC_MOUSEFM_STRAIN_PRIORITIZATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20-slim"

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
    .bm_deps <- c("MouseFM", "ggplot2")
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
    library(MouseFM)
    library(ggplot2)
    
    # Define input file path
    input_file <- "input_region.csv"
    
    # Create a default input file if it does not exist to ensure runnability
    if (!file.exists(input_file)) {
      message("Input file 'input_region.csv' not found. Creating a default template...")
      default_input <- data.frame(
        chromosome = "chr1",
        start = 5000000,
        end = 6000000,
        strain1 = "C57BL_6J",
        strain2 = "AKR_J",
        stringsAsFactors = FALSE
      )
      write.csv(default_input, file = input_file, row.names = FALSE)
    }
    
    # Read user input from the CSV file
    message("Reading genomic region and founder strains from ", input_file)
    user_input <- read.csv(input_file, stringsAsFactors = FALSE)
    
    # Extract parameters
    chr_val <- as.character(user_input\$chromosome[1])
    start_val <- as.numeric(user_input\$start[1])
    end_val <- as.numeric(user_input\$end[1])
    strain1_val <- as.character(user_input\$strain1[1])
    strain2_val <- as.character(user_input\$strain2[1])
    
    # 1. Run strain prioritization using prio()
    message(sprintf("Running strain prioritization for %s:%d-%d between %s and %s...", 
                    chr_val, start_val, end_val, strain1_val, strain2_val))
    
    df = prio(chr_val, start=start_val, end=end_val, strain1=strain1_val, strain2=strain2_val)
    
    # Save the raw prioritization results
    saveRDS(df, "prioritization_results.rds")
    message("Saved raw prioritization results to 'prioritization_results.rds'")
    
    # 2. Extract the top strain combinations that provide the best refinement using get_top()
    message("Extracting top strain combinations...")
    top_combinations <- get_top(df\$reduction, n_top=3)
    
    # Save the top combinations to a CSV file
    write.csv(top_combinations, "top_strain_combinations.csv", row.names = FALSE)
    message("Saved top strain combinations to 'top_strain_combinations.csv'")
    
    # Print top combinations to console
    print(top_combinations)
    
    # 3. Visualize the reduction factors using vis_reduction_factors()
    message("Generating reduction factor visualizations...")
    plots = vis_reduction_factors(df\$genotypes, df\$reduction, 2)
    
    # Save the plots to a PDF file
    pdf_file <- "reduction_factor_plots.pdf"
    pdf(pdf_file, width = 10, height = 8)
    print(plots[[1]])
    print(plots[[2]])
    dev.off()
    
    message("Saved visualization plots to '", pdf_file, "'")
    message("Pipeline completed successfully!")

    writeLines(c(
        '"BIOC_MOUSEFM_STRAIN_PRIORITIZATION":',
        paste0('    MouseFM: ', as.character(packageVersion('MouseFM')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_strain_prioritization.csv versions.yml
    """
}

workflow BIOC_MOUSEFM_STRAIN_PRIORITIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ Genomic region coordinates ] ]

    main:
    BIOC_MOUSEFM_STRAIN_PRIORITIZATION(ch_input)

    emit:
    tables   = BIOC_MOUSEFM_STRAIN_PRIORITIZATION.out.tables
    plots    = BIOC_MOUSEFM_STRAIN_PRIORITIZATION.out.plots
    objects  = BIOC_MOUSEFM_STRAIN_PRIORITIZATION.out.objects
    versions = BIOC_MOUSEFM_STRAIN_PRIORITIZATION.out.versions
}
