#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: padma — standard_pathway_deviation_analysis
// Calculate individualized pathway-centric deviation scores and gene-level contributions from multi-omic data, and visualize the results.
// Input: mae
// Container: quay.io/biocontainers/bioconductor-padma:1.20.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: MultiAssayExperiment, padma
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Format/read multi-omic data as a MultiAssayExperiment
//  * 2. [Visualization & Output] Retrieve the target pathway name or gene list
//  * 3. [Visualization & Output] Run the padma analysis to compute deviation scores
//  * 4. [Visualization & Output] Extract pathway deviation scores and gene-specific
//  * 5. [Visualization & Output] Visualize individual factor maps, partial factor maps,

nextflow.enable.dsl = 2

process BIOC_PADMA_STANDARD_PATHWAY_DEVIATION_ANALYSIS {
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
    .bm_deps <- c("MultiAssayExperiment", "padma", "SummarizedExperiment")
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
        library(MultiAssayExperiment)
        library(SummarizedExperiment)
        library(padma)
        
        # --- Format/read multi-omic data as a MultiAssayExperiment ---
        # Read the user-provided 'mae' object from the working directory
        if (file.exists("mae")) {
          mae <- readRDS("mae")
        } else if (file.exists("mae.rds")) {
          mae <- readRDS("mae.rds")
        } else {
          stop("Error: Input file 'mae' or 'mae.rds' not found in the working directory.")
        }
        
        # --- Retrieve the target pathway name or gene list ---
        # Retrieve the D4GDI pathway name from the built-in msigdb data frame
        D4GDI <- padma::msigdb[grep("D4GDI", padma::msigdb\$geneset), "geneset"]
        if (length(D4GDI) == 0) {
          # Fallback to the first available pathway if D4GDI is not found
          D4GDI <- padma::msigdb\$geneset[1]
        }
        
        # --- Run the padma analysis to compute deviation scores ---
        run_padma <- 
          padma(mae, pathway_name = D4GDI, verbose = FALSE)
        
        # --- Extract pathway deviation scores and gene-specific ---
        # Extract pathway deviation scores using assay()
        pathway_scores <- assay(run_padma)
        write.csv(as.data.frame(pathway_scores), "pathway_deviation_scores.csv", row.names = TRUE)
        
        # Extract gene-specific deviation scores using pathway_gene_deviation()
        gene_scores <- pathway_gene_deviation(run_padma)
        write.csv(as.data.frame(gene_scores), "gene_deviation_scores.csv", row.names = TRUE)
        
        # Save the full padma results object
        saveRDS(run_padma, "padma_results.rds")
        
        # --- Visualize individual factor maps, partial factor maps, ---
        # Save Factor Map
        pdf("factor_map.pdf")
        print(factorMap(run_padma, dim_x = 1, dim_y = 2))
        dev.off()
        
        # Save Partial Factor Map (with fallback for custom user IDs)
        pdf("factor_map_partial.pdf")
        tryCatch({
          print(factorMap(run_padma,
                     partial_id = "TCGA-78-7536",
                     dim_x = 1, dim_y = 2))
        }, error = function(e) {
          message("Default partial_id 'TCGA-78-7536' not found or failed. Attempting with first available sample ID.")
          sample_ids <- rownames(MultiAssayExperiment::colData(mae))
          if (length(sample_ids) > 0) {
            tryCatch({
              print(factorMap(run_padma,
                         partial_id = sample_ids[1],
                         dim_x = 1, dim_y = 2))
            }, error = function(err2) {
              message("Could not generate partial factor map: ", err2\$message)
            })
          }
        }, finally = {
          dev.off()
        })
        
        # Save Omics Contribution Plot
        pdf("omics_contribution.pdf")
        print(omicsContrib(run_padma, max_dim = 10))
        dev.off()

    writeLines(c(
        '"BIOC_PADMA_STANDARD_PATHWAY_DEVIATION_ANALYSIS":',
        paste0('    padma: ', as.character(packageVersion('padma')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_standard_pathway_deviation_analysis.csv versions.yml
    """
}

workflow BIOC_PADMA_STANDARD_PATHWAY_DEVIATION_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ mae ] ]

    main:
    BIOC_PADMA_STANDARD_PATHWAY_DEVIATION_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_PADMA_STANDARD_PATHWAY_DEVIATION_ANALYSIS.out.tables
    plots    = BIOC_PADMA_STANDARD_PATHWAY_DEVIATION_ANALYSIS.out.plots
    objects  = BIOC_PADMA_STANDARD_PATHWAY_DEVIATION_ANALYSIS.out.objects
    versions = BIOC_PADMA_STANDARD_PATHWAY_DEVIATION_ANALYSIS.out.versions
}
