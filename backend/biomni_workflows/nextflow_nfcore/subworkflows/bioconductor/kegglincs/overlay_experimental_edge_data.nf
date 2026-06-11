#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: KEGGlincs — overlay_experimental_edge_data
// Map experimental knock-out or edge-relation data onto expanded KEGG pathways to analyze and visualize cell-line specific pathway topology.
// Input: hsa04115, PC3, HA1E
// Container: quay.io/biocontainers/bioconductor-kegglincs:1.36.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: KEGGlincs, KOdata
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Download and parse KGML using get_KGML
//  * 2. [Core Analysis] Expand node and edge mappings using expand_KEGG_mappings and expand_KEGG_edges
//  * 3. [Core Analysis] Check pathway gene coverage across cell lines using path_genes_by_cell_type
//  * 4. [Core Analysis] Extract overlap/edge data using overlap_info
//  * 5. [Core Analysis] Append experimental data to edges using add_edge_data
//  * 6. [Core Analysis] Generate node and edge mapping info with significance markup using node_mapping_info and edge_mapping_info
//  * 7. [Input & Preparation] Create an igraph object using get_graph_object
//  * 8. [Visualization & Output] Visualize the conditional-formatted network in Cytoscape using cyto_vis (or use the master function KEGG_lincs)

nextflow.enable.dsl = 2

process BIOC_KEGGLINCS_OVERLAY_EXPERIMENTAL_EDGE_DATA {
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
    library(KEGGlincs)
    library(KOdata)
    
    # Read inputs from the working directory
    pathway_id <- "hsa04115"
    if (file.exists("hsa04115")) {
      lines <- readLines("hsa04115", warn = FALSE)
      if (length(lines) > 0 && nzchar(trimws(lines[1]))) {
        pathway_id <- trimws(lines[1])
      }
    }
    
    cell_line_1 <- "PC3"
    if (file.exists("PC3")) {
      lines <- readLines("PC3", warn = FALSE)
      if (length(lines) > 0 && nzchar(trimws(lines[1]))) {
        cell_line_1 <- trimws(lines[1])
      }
    }
    
    cell_line_2 <- "HA1E"
    if (file.exists("HA1E")) {
      lines <- readLines("HA1E", warn = FALSE)
      if (length(lines) > 0 && nzchar(trimws(lines[1]))) {
        cell_line_2 <- trimws(lines[1])
      }
    }
    
    # 1. Download and parse KGML using get_KGML
    # Wrap Cytoscape-dependent master function in tryCatch to ensure pipeline robustness
    tryCatch({
      KEGG_lincs(pathway_id)
    }, error = function(e) {
      message("Cytoscape connection failed for initial KEGG_lincs: ", e\$message)
    })
    
    p53_KGML <- get_KGML(pathway_id)
    
    # 2. Expand node and edge mappings using expand_KEGG_mappings and expand_KEGG_edges
    p53_KEGG_mappings <- expand_KEGG_mappings(p53_KGML)
    p53_edges <- expand_KEGG_edges(p53_KGML, p53_KEGG_mappings)
    
    # 3. Check pathway gene coverage across cell lines using path_genes_by_cell_type
    # Save the coverage plot to a PDF file
    pdf("pathway_coverage_by_cell_line.pdf")
    path_genes_by_cell_type(p53_KEGG_mappings)
    dev.off()
    
    p53_L1000_summary <- path_genes_by_cell_type(p53_KEGG_mappings, get_KOs = TRUE, generate_plot = FALSE)
    
    # 4. Extract overlap/edge data using overlap_info
    p53_PC3_data <- overlap_info(p53_KGML, p53_KEGG_mappings, cell_line_1)
    p53_HA1E_data <- overlap_info(p53_KGML, p53_KEGG_mappings, cell_line_2)
    p53_PC3_data_with_gene_lists <- overlap_info(p53_KGML, p53_KEGG_mappings, cell_line_1, keep_counts_only = FALSE)
    
    # 5. Append experimental data to edges using add_edge_data
    p53_PC3_edges <- add_edge_data(p53_edges, p53_KEGG_mappings, p53_PC3_data, only_mapped = TRUE, data_column_no = c(3,10,12))
    p53_HA1E_edges <- add_edge_data(p53_edges, p53_KEGG_mappings, p53_HA1E_data, only_mapped = TRUE, data_column_no = c(3,10,12))
    
    # 6. Generate node and edge mapping info with significance markup using node_mapping_info and edge_mapping_info
    p53_node_map <- node_mapping_info(p53_KEGG_mappings)
    p53_edge_map_PC3 <- edge_mapping_info(p53_PC3_edges, data_added = TRUE, significance_markup = TRUE)
    p53_edge_map_HA1E <- edge_mapping_info(p53_HA1E_edges, data_added = TRUE, significance_markup = TRUE)
    
    # 7. Create an igraph object using get_graph_object
    PC3_GO <- get_graph_object(p53_node_map, p53_edge_map_PC3)
    HA1E_GO <- get_graph_object(p53_node_map, p53_edge_map_HA1E)
    
    # 8. Visualize the conditional-formatted network in Cytoscape using cyto_vis (or use the master function KEGG_lincs)
    tryCatch({
      cyto_vis(PC3_GO, paste0("Pathway = ", pathway_id, ", Cell line = ", cell_line_1))
    }, error = function(e) {
      message("Cytoscape connection failed for cyto_vis (PC3): ", e\$message)
    })
    
    tryCatch({
      cyto_vis(HA1E_GO, paste0("Pathway = ", pathway_id, ", Cell line = ", cell_line_2))
    }, error = function(e) {
      message("Cytoscape connection failed for cyto_vis (HA1E): ", e\$message)
    })
    
    tryCatch({
      KEGG_lincs(pathway_id, cell_line_1, refine_by_cell_line = FALSE)
    }, error = function(e) {
      message("Cytoscape connection failed for KEGG_lincs (PC3): ", e\$message)
    })
    
    tryCatch({
      KEGG_lincs(pathway_id, cell_line_2, refine_by_cell_line = FALSE)
    }, error = function(e) {
      message("Cytoscape connection failed for KEGG_lincs (HA1E): ", e\$message)
    })
    
    # Write meaningful results to output files
    write.csv(p53_KEGG_mappings, "p53_KEGG_mappings.csv", row.names = FALSE)
    write.csv(p53_edges, "p53_edges.csv", row.names = FALSE)
    write.csv(p53_L1000_summary, "p53_L1000_summary.csv", row.names = FALSE)
    write.csv(p53_PC3_data, "p53_PC3_data.csv", row.names = FALSE)
    write.csv(p53_HA1E_data, "p53_HA1E_data.csv", row.names = FALSE)
    write.csv(p53_PC3_data_with_gene_lists, "p53_PC3_data_with_gene_lists.csv", row.names = FALSE)
    write.csv(p53_PC3_edges, "p53_PC3_edges.csv", row.names = FALSE)
    write.csv(p53_HA1E_edges, "p53_HA1E_edges.csv", row.names = FALSE)
    write.csv(p53_node_map, "p53_node_map.csv", row.names = FALSE)
    write.csv(p53_edge_map_PC3, "p53_edge_map_PC3.csv", row.names = FALSE)
    write.csv(p53_edge_map_HA1E, "p53_edge_map_HA1E.csv", row.names = FALSE)
    
    saveRDS(PC3_GO, "PC3_GO.rds")
    saveRDS(HA1E_GO, "HA1E_GO.rds")
    
    message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_KEGGLINCS_OVERLAY_EXPERIMENTAL_EDGE_DATA":',
        paste0('    KEGGlincs: ', as.character(packageVersion('KEGGlincs')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_overlay_experimental_edge_data.csv versions.yml
    """
}

workflow BIOC_KEGGLINCS_OVERLAY_EXPERIMENTAL_EDGE_DATA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ hsa04115, PC3, HA1E ] ]

    main:
    BIOC_KEGGLINCS_OVERLAY_EXPERIMENTAL_EDGE_DATA(ch_input)

    emit:
    tables   = BIOC_KEGGLINCS_OVERLAY_EXPERIMENTAL_EDGE_DATA.out.tables
    plots    = BIOC_KEGGLINCS_OVERLAY_EXPERIMENTAL_EDGE_DATA.out.plots
    objects  = BIOC_KEGGLINCS_OVERLAY_EXPERIMENTAL_EDGE_DATA.out.objects
    versions = BIOC_KEGGLINCS_OVERLAY_EXPERIMENTAL_EDGE_DATA.out.versions
}
