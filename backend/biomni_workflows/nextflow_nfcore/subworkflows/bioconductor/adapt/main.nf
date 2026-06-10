#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ADAPT — microbiome_differential_abundance
// Perform differential abundance analysis on microbiome count data using Tobit models with optional covariate adjustment, and visualize the results.
// Input: phyloseq_object
// Container: quay.io/biocontainers/bioconductor-adapt:1.4.0--r45ha27e39d_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: ADAPT, phyloseq
// Visualizations: volcano plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the package and input data
//  * 2. [Core Analysis] Run the differential abundance analysis with or without covariate adjustment using adapt()
//  * 3. [Visualization & Output] Extract and summarize the analysis results using summary()
//  * 4. [Visualization & Output] Visualize the differentially abundant taxa using plot()

nextflow.enable.dsl = 2

process BIOC_ADAPT_MICROBIOME_DIFFERENTIAL_ABUNDANCE {
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
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
        
    # Load required libraries
    library(ADAPT)
    library(phyloseq)
    
    # 1. Load the input data from the working directory
    input_path <- "phyloseq_object"
    if (!file.exists(input_path) && file.exists("phyloseq_object.rds")) {
      input_path <- "phyloseq_object.rds"
    }
    
    if (!file.exists(input_path)) {
      stop("Error: Input file 'phyloseq_object' or 'phyloseq_object.rds' not found in the working directory.")
    }
    
    physeq_data <- readRDS(input_path)
    
    # Dynamically determine metadata variables for the analysis
    meta_vars <- sample_variables(physeq_data)
    if (length(meta_vars) < 1) {
      stop("Error: The phyloseq object must contain sample metadata with at least one variable.")
    }
    
    cond_var <- meta_vars[1]
    base_cond <- as.character(unique(get_variable(physeq_data, cond_var)))[1]
    
    # 2. Run the differential abundance analysis with and without covariate adjustment
    # Unadjusted model
    saliva_output_noadjust <- adapt(input_data=physeq_data, cond.var=cond_var, base.cond=base_cond)
    
    # Adjusted model (wrapped in tryCatch in case the optional covariate is not present or suitable in the user's metadata)
    saliva_output_adjust <- tryCatch({
      if (length(meta_vars) > 1) {
        adj_var <- meta_vars[2]
        adapt(input_data=physeq_data, cond.var=cond_var, base.cond=base_cond, adj.var=adj_var)
      } else {
        message("Warning: No additional metadata variables available for covariate adjustment.")
        NULL
      }
    }, error = function(e) {
      message("Warning: Adjusted model could not be run.")
      message("Error details: ", e\$message)
      NULL
    })
    
    # 3. Extract and summarize the analysis results
    DAtaxa_result <- summary(saliva_output_noadjust, select="da")
    head(DAtaxa_result)
    
    # Save tabular results and model objects
    write.csv(DAtaxa_result, file = "DAtaxa_result.csv", row.names = TRUE)
    saveRDS(saliva_output_noadjust, file = "saliva_output_noadjust.rds")
    if (!is.null(saliva_output_adjust)) {
      saveRDS(saliva_output_adjust, file = "saliva_output_adjust.rds")
    }
    
    # 4. Visualize the differentially abundant taxa and save to PDF
    pdf("volcano_plot.pdf", width = 7, height = 5)
    plot(saliva_output_noadjust, n.label=5)
    dev.off()

    writeLines(c(
        '"BIOC_ADAPT_MICROBIOME_DIFFERENTIAL_ABUNDANCE":',
        paste0('    ADAPT: ', as.character(packageVersion('ADAPT')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_microbiome_differential_abundance.csv versions.yml
    """
}

workflow BIOC_ADAPT_MICROBIOME_DIFFERENTIAL_ABUNDANCE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ phyloseq_object ] ]

    main:
    BIOC_ADAPT_MICROBIOME_DIFFERENTIAL_ABUNDANCE(ch_input)

    emit:
    tables   = BIOC_ADAPT_MICROBIOME_DIFFERENTIAL_ABUNDANCE.out.tables
    plots    = BIOC_ADAPT_MICROBIOME_DIFFERENTIAL_ABUNDANCE.out.plots
    objects  = BIOC_ADAPT_MICROBIOME_DIFFERENTIAL_ABUNDANCE.out.objects
    versions = BIOC_ADAPT_MICROBIOME_DIFFERENTIAL_ABUNDANCE.out.versions
}
