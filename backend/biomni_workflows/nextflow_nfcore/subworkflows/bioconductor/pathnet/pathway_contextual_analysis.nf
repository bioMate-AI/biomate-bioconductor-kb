#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: PathNet — pathway_contextual_analysis
// Identify pathway contextual associations and overlap scores to find biologically related pathways based on the connectivity of differentially expressed genes.
// Input: brain_regions_data.txt, adjacency_data.txt, pathway_data.txt
// Container: quay.io/biocontainers/bioconductor-pathnet:1.50.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: PathNet
// Visualizations: heatmap
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the direct evidence, adjacency matrix, and pathway data
//  * 2. [Core Analysis] Filter the adjacency matrix to match the gene IDs present in the direct evidence
//  * 3. [Core Analysis] Run the PathNet function with Contextual_Analysis set to TRUE
//  * 4. [Visualization & Output] Retrieve the contextual association p-values and pathway overlap scores from the output list

nextflow.enable.dsl = 2

process BIOC_PATHNET_PATHWAY_CONTEXTUAL_ANALYSIS {
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
            
            # Load the required library
            library("PathNet")
            
            # 1. Load the direct evidence, adjacency matrix, and pathway data from the working directory
            brain_regions <- as.matrix(read.table(
              file = "brain_regions_data.txt", 
              sep = "\t", 
              header = TRUE
            ))
            
            A <- as.matrix(read.table(
              file = "adjacency_data.txt", 
              sep = "\t", 
              header = TRUE
            ))
            
            pathway <- read.table(
              file = "pathway_data.txt", 
              sep = "\t", 
              header = TRUE
            )
            
            # 2. Filter the adjacency matrix to match the gene IDs present in the direct evidence
            gene_ID <- brain_regions[, 1]
            A <- A[rownames(A) %in% gene_ID, rownames(A) %in% gene_ID]
            
            # 3. Run the PathNet function with Contextual_Analysis set to TRUE
            # (Using the exact documented function call and arguments)
            results <- PathNet(Enrichment_Analysis = FALSE, 
                    Contextual_Analysis= TRUE, 
                    DirectEvidence_info = brain_regions, 
                    Adjacency = A, 
                    pathway = pathway, 
                    Column_DirectEvidence = ncol(brain_regions), 
                    use_sig_pathways = FALSE, 
                    n_perm = 2000, threshold = 0.05)
            
            # 4. Retrieve the contextual association p-values and pathway overlap scores
            conn_p_val_subset <- results\$conn_p_value[1:min(4, nrow(results\$conn_p_value)), 1:min(2, ncol(results\$conn_p_value)), drop = FALSE]
            pathway_overlap_subset <- results\$pathway_overlap[1:min(4, nrow(results\$pathway_overlap)), 1:min(2, ncol(results\$pathway_overlap)), drop = FALSE]
            
            # Print the retrieved subsets to the console
            cat("--- Contextual Association p-values (Subset) ---\n")
            print(conn_p_val_subset)
            cat("\n--- Pathway Overlap Scores (Subset) ---\n")
            print(pathway_overlap_subset)
            
            # Write named output files for the meaningful results
            write.csv(results\$conn_p_value, file = "pathnet_conn_p_value.csv", row.names = TRUE)
            write.csv(results\$pathway_overlap, file = "pathnet_pathway_overlap.csv", row.names = TRUE)
            saveRDS(results, file = "pathnet_results.rds")
            
            # Generate a PDF heatmap of a subset of the contextual association p-values
            pdf("pathnet_contextual_heatmap.pdf", width = 10, height = 10)
            sub_matrix <- results\$conn_p_value[1:min(20, nrow(results\$conn_p_value)), 1:min(20, ncol(results\$conn_p_value)), drop = FALSE]
            heatmap(
              sub_matrix, 
              main = "PathNet Contextual Association p-values (Top Subset)", 
              Rowv = NA, 
              Colv = NA, 
              scale = "none",
              col = heat.colors(256)
            )
            dev.off()

    writeLines(c(
        '"BIOC_PATHNET_PATHWAY_CONTEXTUAL_ANALYSIS":',
        paste0('    PathNet: ', as.character(packageVersion('PathNet')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_pathway_contextual_analysis.csv versions.yml
    """
}

workflow BIOC_PATHNET_PATHWAY_CONTEXTUAL_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ brain_regions_data.txt, adjacency_data.txt, pathway_data.txt ] ]

    main:
    BIOC_PATHNET_PATHWAY_CONTEXTUAL_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_PATHNET_PATHWAY_CONTEXTUAL_ANALYSIS.out.tables
    plots    = BIOC_PATHNET_PATHWAY_CONTEXTUAL_ANALYSIS.out.plots
    objects  = BIOC_PATHNET_PATHWAY_CONTEXTUAL_ANALYSIS.out.objects
    versions = BIOC_PATHNET_PATHWAY_CONTEXTUAL_ANALYSIS.out.versions
}
