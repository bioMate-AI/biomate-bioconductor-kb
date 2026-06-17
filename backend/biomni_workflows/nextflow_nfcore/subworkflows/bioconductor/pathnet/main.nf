#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: PathNet — pathway_enrichment_analysis
// Identify significantly enriched pathways by combining direct gene expression evidence with pathway topological neighbor information.
// Input: brain_regions_data.txt, adjacency_data.txt, pathway_data.txt
// Container: quay.io/biocontainers/bioconductor-pathnet:1.50.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: PathNet
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the direct evidence, adjacency matrix, and pathway data
//  * 2. [Core Analysis] Filter the adjacency matrix to match the gene IDs present in the direct evidence
//  * 3. [Core Analysis] Run the PathNet function with Enrichment_Analysis set to TRUE
//  * 4. [Visualization & Output] Retrieve enrichment results and combined evidence from the output list

nextflow.enable.dsl = 2

process BIOC_PATHNET_PATHWAY_ENRICHMENT_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim"

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
    .bm_deps <- c("PathNet")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))  # CRAN binaries (Posit PPM)
      .bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressWarnings(suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=.bin), error=function(e) try(install.packages(.bm_miss), silent=TRUE))))
    }
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
        
        # Load the required library
        library("PathNet")
        
        # Stage 1: Load the direct evidence, adjacency matrix, and pathway data from the working directory
        brain_regions <- as.matrix(read.table(
          file = "brain_regions_data.txt", sep = "\t", header = TRUE))
        
        A <- as.matrix(read.table(
          file = "adjacency_data.txt", sep = "\t", header = TRUE))
        
        pathway <- read.table(
          file = "pathway_data.txt", sep = "\t", header = TRUE)
        
        # Stage 2: Filter the adjacency matrix to match the gene IDs present in the direct evidence
        gene_ID <- brain_regions[, 1]
        A <- A[rownames(A) %in% gene_ID, rownames(A) %in% gene_ID]
        
        # Stage 3: Run the PathNet function with Enrichment_Analysis set to TRUE
        results <- PathNet(Enrichment_Analysis = TRUE, 
                DirectEvidence_info = brain_regions, 
                Adjacency = A, 
                pathway = pathway, 
                Column_DirectEvidence = ncol(brain_regions),
                n_perm = 2000, threshold = 0.05) 
        
        # Stage 4: Retrieve enrichment results and combined evidence from the output list
        enrichment_results <- results\$enrichment_results
        enrichment_combined_evidence <- results\$enrichment_combined_evidence
        
        # Write the results to output files
        write.csv(enrichment_results, file = "enrichment_results.csv", row.names = FALSE)
        write.csv(enrichment_combined_evidence, file = "enrichment_combined_evidence.csv", row.names = FALSE)
        saveRDS(results, file = "pathnet_results.rds")

    writeLines(c(
        '"BIOC_PATHNET_PATHWAY_ENRICHMENT_ANALYSIS":',
        paste0('    PathNet: ', as.character(packageVersion('PathNet')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_pathway_enrichment_analysis.csv versions.yml
    """
}

workflow BIOC_PATHNET_PATHWAY_ENRICHMENT_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ brain_regions_data.txt, adjacency_data.txt, pathway_data.txt ] ]

    main:
    BIOC_PATHNET_PATHWAY_ENRICHMENT_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_PATHNET_PATHWAY_ENRICHMENT_ANALYSIS.out.tables
    plots    = BIOC_PATHNET_PATHWAY_ENRICHMENT_ANALYSIS.out.plots
    objects  = BIOC_PATHNET_PATHWAY_ENRICHMENT_ANALYSIS.out.objects
    versions = BIOC_PATHNET_PATHWAY_ENRICHMENT_ANALYSIS.out.versions
}
