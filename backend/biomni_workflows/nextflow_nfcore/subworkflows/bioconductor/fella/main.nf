#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: FELLA — kegg_network_enrichment
// Build a local KEGG database for a specific organism, map a list of affected metabolites, perform network-based enrichment (diffusion or PageRank), and export/vi
// Input: list_of_compounds.txt
// Container: quay.io/biocontainers/bioconductor-fella:1.30.0--r45hdfd78af_0
// R packages: FELLA, igraph, KEGGREST, magrittr
// Bioconductor: 3.20 | R: 4.4
// Requires: FELLA, igraph, org.Mm.eg.db
// Visualizations: enrichment plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Build the KEGG graph from KEGGREST
//  * 2. [Visualization & Output] Build the local database files
//  * 3. [Visualization & Output] Load the KEGG database
//  * 4. [Visualization & Output] Visualize the enriched subnetwork and save to PDF
//  * 5. [Visualization & Output] Export results as a table
//  * 6. [Visualization & Output] Export results as an igraph object

nextflow.enable.dsl = 2

process BIOC_FELLA_KEGG_NETWORK_ENRICHMENT {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-metabolomics:3.20"

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
    .bm_deps <- c("FELLA", "igraph", "KEGGREST", "magrittr")
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
        library(FELLA)
        library(igraph)
        
        # Set seed for reproducibility
        set.seed(1)
        
        # Check for user input file
        input_file <- "list_of_compounds.txt"
        if (!file.exists(input_file)) {
          stop(paste("Required input file", input_file, "not found in the working directory."))
        }
        
        # Read user input compounds
        cpd.nafld <- readLines(input_file)
        cpd.nafld <- trimws(cpd.nafld)
        cpd.nafld <- cpd.nafld[cpd.nafld != ""]
        
        if (length(cpd.nafld) == 0) {
          stop("The input file 'list_of_compounds.txt' is empty.")
        }
        
        # --- Build the KEGG graph from KEGGREST ---
        message("Building KEGG graph from KEGGREST...")
        graph <- buildGraphFromKEGGREST(
            organism = "mmu", 
            filter.path = c("01100", "01200", "01210", "01212", "01230"))
        
        # --- Build the local database files ---
        tmpdir <- paste0(tempdir(), "/my_database")
        unlink(tmpdir, recursive = TRUE)  
        
        message("Building local database from graph...")
        buildDataFromGraph(
            keggdata.graph = graph, 
            databaseDir = tmpdir, 
            internalDir = FALSE, 
            matrices = "none", 
            normality = "diffusion", 
            niter = 100)
        
        # --- Load the KEGG database ---
        message("Loading KEGG database...")
        fella.data <- loadKEGGdata(
            databaseDir = tmpdir, 
            internalDir = FALSE, 
            loadMatrix = "none"
        )
        
        # 4 & 5. Run enrichment analysis
        message("Running enrichment analysis...")
        analysis.nafld <- enrich(
            compounds = cpd.nafld, 
            data = fella.data, 
            method = "diffusion", 
            approx = "normality")
        
        # --- Visualize the enriched subnetwork and save to PDF ---
        message("Generating enrichment plot...")
        pdf("enrichment_plot.pdf", width = 10, height = 10)
        plot(
            analysis.nafld, 
            method = "diffusion", 
            data = fella.data, 
            nlimit = 250,  
            plotLegend = FALSE)
        dev.off()
        
        # --- Export results as a table ---
        message("Generating results table...")
        tab.all <- generateResultsTable(
            method = "diffusion", 
            nlimit = 100, 
            object = analysis.nafld, 
            data = fella.data)
        
        # Save the table to a CSV file
        write.csv(tab.all, "results_table_summary.csv", row.names = FALSE)
        
        # Export results using exportResults
        exportResults(
            format = "csv", 
            file = "results_table.csv", 
            method = "diffusion", 
            object = analysis.nafld, 
            data = fella.data)
        
        # --- Export results as an igraph object ---
        message("Generating results graph...")
        g.nafld <- generateResultsGraph(
            object = analysis.nafld, 
            data = fella.data, 
            method = "diffusion")
        
        # Save the raw igraph object
        saveRDS(g.nafld, "results_graph.rds")
        
        # 9. (Optional) Annotate the graph with GO terms
        message("Attempting to annotate graph with GO terms...")
        tryCatch({
          if (requireNamespace("org.Mm.eg.db", quietly = TRUE)) {
            g.go <- addGOToGraph(
                graph = g.nafld, 
                GOterm = "GO:0005739", 
                godata.options = list(
                    OrgDb = "org.Mm.eg.db", ont = "CC"), 
                mart.options = list(
                    biomart = "ensembl", dataset = "mmusculus_gene_ensembl"))
            
            saveRDS(g.go, "results_graph_go.rds")
            message("GO annotation successful. Saved to 'results_graph_go.rds'.")
          } else {
            message("Skipping GO annotation: 'org.Mm.eg.db' package is not installed.")
          }
        }, error = function(e) {
          message("GO annotation failed or skipped (requires internet access for BioMart): ", e\$message)
        })
        
        message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_FELLA_KEGG_NETWORK_ENRICHMENT":',
        paste0('    FELLA: ', as.character(packageVersion('FELLA')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_kegg_network_enrichment.csv versions.yml
    """
}

workflow BIOC_FELLA_KEGG_NETWORK_ENRICHMENT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ list_of_compounds.txt ] ]

    main:
    BIOC_FELLA_KEGG_NETWORK_ENRICHMENT(ch_input)

    emit:
    tables   = BIOC_FELLA_KEGG_NETWORK_ENRICHMENT.out.tables
    plots    = BIOC_FELLA_KEGG_NETWORK_ENRICHMENT.out.plots
    objects  = BIOC_FELLA_KEGG_NETWORK_ENRICHMENT.out.objects
    versions = BIOC_FELLA_KEGG_NETWORK_ENRICHMENT.out.versions
}
