#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: RITAN — induced_subnetwork_extraction
// Extract and visualize known physical or regulatory interactions among a set of genes of interest (and optionally their first-degree neighbors) from network reso
// Input: my_genes.txt, BIOGRID-ORGANISM-Mus_musculus-3.4.136.symbols.sif.gz
// Container: quay.io/biocontainers/bioconductor-ritan:1.34.0--r45hdfd78af_0
// R packages: RITAN, RITANdata, igraph
// Bioconductor: 3.20 | R: 4.4
// Requires: RITAN, RITANdata, igraph
// Visualizations: network plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Read User Input
//  * 2. [Visualization & Output] Check input gene symbol coverage
//  * 3. [Visualization & Output] Extract induced subnetworks
//  * 4. [Visualization & Output] Convert to igraph and visualize
//  * 5. [Visualization & Output] Export network and attributes

nextflow.enable.dsl = 2

process BIOC_RITAN_INDUCED_SUBNETWORK_EXTRACTION {
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
    .bm_deps <- c("RITAN", "RITANdata", "igraph")
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
            library(RITAN)
            library(RITANdata)
            library(igraph)
            
            # --- Read User Input ---
            if (!file.exists("my_genes.txt")) {
              stop("Required input file 'my_genes.txt' is missing.")
            }
            my_genes <- readLines("my_genes.txt")
            my_genes <- unique(trimws(my_genes))
            my_genes <- my_genes[my_genes != ""]
            
            # Optional user-defined network SIF file
            sif_file <- "BIOGRID-ORGANISM-Mus_musculus-3.4.136.symbols.sif.gz"
            if (file.exists(sif_file)) {
              network_list[['BioGRID_Mouse']] <- readSIF(sif_file, header = TRUE)
            }
            
            # --- Check input gene symbol coverage ---
            i <- check_any_net_input ( my_genes )
            table (i)
            
            # --- Extract induced subnetworks ---
            net <- network_overlap ( my_genes, resources = 'CCSB' )
            net2 <- network_overlap ( my_genes, resources = c ( 'CCSB' , 'STRING' ), minStringScore = 700 )
            net3.3 <- network_overlap ( my_genes, resources = 'PID' , include_neighbors = TRUE , dedup = TRUE )
            
            # Define net3.1, net4, and net5 to ensure subsequent documented code runs successfully
            net3.1 <- network_overlap ( my_genes, resources = 'PID' , include_neighbors = FALSE , dedup = TRUE )
            net4 <- network_overlap ( my_genes, resources = c ( 'PID' , 'dPPI' , 'TFe' ), include_neighbors = FALSE , dedup = TRUE )
            
            if ("BioGRID_Mouse" %in% names(network_list)) {
              net5 <- network_overlap ( my_genes, resources = 'BioGRID_Mouse' )
            } else {
              net5 <- network_overlap ( my_genes )
            }
            
            # Define tab for write_simple_table
            g <- unique ( c ( net3.1\$p1, net3.1\$p2 ) )
            tab <- data.frame (
              gene = g,
              initial = g %in% my_genes
            )
            
            # --- Convert to igraph and visualize ---
            tryCatch({
              edges <- as.matrix ( net4[, c ( 1 , 3 )] )
              G <- igraph :: make_undirected_graph ( c ( t (edges)) )
              pdf("network_plot.pdf")
              plot (G, vertex.size = 20 , vertex.frame.color = 'white' )
              dev.off()
            }, error = function(e) {
              message("Visualization failed: ", e\$message)
            })
            
            # --- Export network and attributes ---
            write_simple_table (net3.1 , 'net_example.sif' )
            write_simple_table (tab, 'net_example.tab' )
            
            # Save RDS outputs for downstream analysis
            saveRDS(net, "net.rds")
            saveRDS(net2, "net2.rds")
            saveRDS(net3.3, "net3.3.rds")
            saveRDS(net4, "net4.rds")

    writeLines(c(
        '"BIOC_RITAN_INDUCED_SUBNETWORK_EXTRACTION":',
        paste0('    RITAN: ', as.character(packageVersion('RITAN')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_induced_subnetwork_extraction.csv versions.yml
    """
}

workflow BIOC_RITAN_INDUCED_SUBNETWORK_EXTRACTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ my_genes.txt, BIOGRID-ORGANISM-Mus_musculus-3.4.136.symbols.sif.gz ] ]

    main:
    BIOC_RITAN_INDUCED_SUBNETWORK_EXTRACTION(ch_input)

    emit:
    tables   = BIOC_RITAN_INDUCED_SUBNETWORK_EXTRACTION.out.tables
    plots    = BIOC_RITAN_INDUCED_SUBNETWORK_EXTRACTION.out.plots
    objects  = BIOC_RITAN_INDUCED_SUBNETWORK_EXTRACTION.out.objects
    versions = BIOC_RITAN_INDUCED_SUBNETWORK_EXTRACTION.out.versions
}
