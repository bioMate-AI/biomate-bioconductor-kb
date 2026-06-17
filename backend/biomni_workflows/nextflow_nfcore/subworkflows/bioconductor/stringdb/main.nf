#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: STRINGdb — protein_interaction_and_enrichment_analysis
// Map differentially expressed genes to the STRING database, visualize their interaction network with fold-change color coding, perform background-corrected funct
// Input: gene_expression_data.csv
// Container: quay.io/biocontainers/bioconductor-stringdb:2.22.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: STRINGdb
// Visualizations: network plot, enrichment plot, cluster plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Initialize STRINGdb object with species and score threshold using STRINGdb$new
//  * 2. [Core Analysis] Map gene symbols to STRING identifiers using string_db$map
//  * 3. [Core Analysis] Filter mapped genes by p-value and select top hits
//  * 4. [Visualization & Output] Plot the protein-protein interaction network using string_db$plot_network
//  * 5. [Core Analysis] Add differential expression colors based on log fold change using string_db$add_diff_exp_color
//  * 6. [Visualization & Output] Post payload to the STRING server using string_db$post_payload and plot the halo network
//  * 7. [Core Analysis] Set custom background gene list using string_db$set_background
//  * 8. [Core Analysis] Compute background-corrected functional enrichment using string_db$get_enrichment
//  * 9. [Visualization & Output] Generate and display enrichment figure using string_db$get_enrichment_figure
//  * 10. [Core Analysis] Retrieve functional annotations using string_db$get_annotations
//  * 11. [Visualization & Output] Partition network into clusters using string_db$get_clusters and plot individual clusters
//  * 12. [Core Analysis] Query specific protein interactions, partners, and homologs using string_db$mp, string_db$get_interactions, string_db$get_interact

nextflow.enable.dsl = 2

process BIOC_STRINGDB_PROTEIN_INTERACTION_AND_ENRICHMENT_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-proteomics:3.20-slim"

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
    .bm_deps <- c("STRINGdb")
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
    
    # Load required libraries
    library(STRINGdb)
    library(grid)
    
    # 1. Initialize STRINGdb object
    string_db <- STRINGdb\$new(
      version = "12.0",
      species = 9606, 
      score_threshold = 400,
      network_type = "full",
      link_data = "detailed",
      input_directory = ""
    )
    
    # 2. Read user input file
    # The pipeline expects 'gene_expression_data.csv' in the working directory.
    # This file must contain columns: 'gene' (symbols), 'pvalue', and 'logFC'.
    diff_exp_data <- read.csv("gene_expression_data.csv", stringsAsFactors = FALSE)
    
    # 3. Map gene symbols to STRING identifiers
    example1_mapped <- string_db\$map(diff_exp_data, "gene", removeUnmappedRows = TRUE)
    write.csv(example1_mapped, "mapped_genes.csv", row.names = FALSE)
    
    # 4. Filter mapped genes by p-value and select top hits
    example1_mapped_pval05 <- subset(example1_mapped, pvalue < 0.05)
    example1_mapped_pval05 <- example1_mapped_pval05[order(example1_mapped_pval05\$pvalue), ]
    
    # Select top hits (up to 200) safely
    num_hits <- min(200, nrow(example1_mapped_pval05))
    if (num_hits > 0) {
      hits <- example1_mapped_pval05\$STRING_id[1:num_hits]
    } else {
      stop("No genes found with pvalue < 0.05. Cannot proceed with network analysis.")
    }
    
    # 5. Plot the initial protein-protein interaction network
    pdf("network_initial.pdf", width = 10, height = 10)
    string_db\$plot_network(hits)
    dev.off()
    
    # 6. Add differential expression colors based on log fold change
    example1_mapped_pval05 <- string_db\$add_diff_exp_color(
      subset(example1_mapped, pvalue < 0.05), 
      logFcColStr = "logFC"
    )    
    
    # 7. Post payload to the STRING server and plot the halo network
    payload_id <- string_db\$post_payload(
      example1_mapped_pval05\$STRING_id, 
      colors = example1_mapped_pval05\$color
    )
    
    pdf("network_halo.pdf", width = 10, height = 10)
    string_db\$plot_network(hits, payload_id = payload_id)
    dev.off()
    
    # 8. Compute uncorrected functional enrichment
    enrichment <- string_db\$get_enrichment(hits)
    write.csv(enrichment, "enrichment_uncorrected.csv", row.names = FALSE)
    
    # 9. Generate and display enrichment figure
    tryCatch({
      enrichment_img <- string_db\$get_enrichment_figure(
        hits,
        category = "Component",
        group_by_similarity = 0.8,
        color_palette = "yellow_pink",
        x_axis = "signal"
      )
      pdf("enrichment_figure.pdf", width = 8, height = 6)
      grid::grid.newpage()
      grid::grid.raster(enrichment_img, interpolate = FALSE)
      dev.off()
    }, error = function(e) {
      warning("Could not generate enrichment figure: ", e\$message)
    })
    
    # 10. Set custom background gene list and compute background-corrected enrichment
    backgroundV <- example1_mapped\$STRING_id
    string_db\$set_background(backgroundV)
    
    enrichment_background_corrected <- string_db\$get_enrichment(hits)
    write.csv(enrichment_background_corrected, "enrichment_background_corrected.csv", row.names = FALSE)
    
    # 11. Retrieve functional annotations
    annotations <- string_db\$get_annotations(hits)
    write.csv(annotations, "annotations.csv", row.names = FALSE)
    
    # 12. Partition network into clusters and plot individual clusters
    num_cluster_genes <- min(600, nrow(example1_mapped_pval05))
    clustersList <- string_db\$get_clusters(example1_mapped_pval05\$STRING_id[1:num_cluster_genes])
    saveRDS(clustersList, "network_clusters.rds")
    
    pdf("network_clusters.pdf", width = 8, height = 8)
    for (i in seq_along(clustersList)) {
      if (i > 4) break  # Plot up to the first 4 clusters
      par(mar = c(0, 0, 0.5, 0))
      string_db\$plot_network(clustersList[[i]], add_summary = FALSE)
    }
    dev.off()
    
    # 13. Query specific protein interactions, partners, and homologs
    string_proteins <- string_db\$get_proteins()
    write.csv(head(string_proteins, 100), "string_proteins_head100.csv", row.names = FALSE)
    
    tp53 <- string_db\$mp("tp53")
    atm <- string_db\$mp("atm")
    
    # Get interactions between TP53 and ATM
    interactions <- string_db\$get_interactions(c(tp53, atm))
    write.csv(interactions, "tp53_atm_interactions.csv", row.names = FALSE)
    
    # Get interaction partners
    partners <- string_db\$get_interaction_partners(c(tp53, atm), limit = 5)[, c("from", "to", "combined_score", "experimental", "from_name", "to_name")]
    write.csv(partners, "tp53_atm_partners.csv", row.names = FALSE)
    
    # Get paralogs of TP53
    paralogs <- string_db\$get_paralogs(tp53)
    write.csv(paralogs, "tp53_paralogs.csv", row.names = FALSE)
    
    # Get best homolog hits for TP53 across species
    tp53_besthits <- string_db\$get_homologs_besthits(tp53)
    write.csv(tp53_besthits, "tp53_homologs_besthits.csv", row.names = FALSE)
    
    # Get homologs in Mouse (species 10090)
    mouse_homologs <- string_db\$get_homologs_besthits(c(tp53, atm), target_species_id = 10090)
    write.csv(mouse_homologs, "tp53_atm_mouse_homologs.csv", row.names = FALSE)

    writeLines(c(
        '"BIOC_STRINGDB_PROTEIN_INTERACTION_AND_ENRICHMENT_ANALYSIS":',
        paste0('    STRINGdb: ', as.character(packageVersion('STRINGdb')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_protein_interaction_and_enrichment_analysis.csv versions.yml
    """
}

workflow BIOC_STRINGDB_PROTEIN_INTERACTION_AND_ENRICHMENT_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ gene_expression_data.csv ] ]

    main:
    BIOC_STRINGDB_PROTEIN_INTERACTION_AND_ENRICHMENT_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_STRINGDB_PROTEIN_INTERACTION_AND_ENRICHMENT_ANALYSIS.out.tables
    plots    = BIOC_STRINGDB_PROTEIN_INTERACTION_AND_ENRICHMENT_ANALYSIS.out.plots
    objects  = BIOC_STRINGDB_PROTEIN_INTERACTION_AND_ENRICHMENT_ANALYSIS.out.objects
    versions = BIOC_STRINGDB_PROTEIN_INTERACTION_AND_ENRICHMENT_ANALYSIS.out.versions
}
