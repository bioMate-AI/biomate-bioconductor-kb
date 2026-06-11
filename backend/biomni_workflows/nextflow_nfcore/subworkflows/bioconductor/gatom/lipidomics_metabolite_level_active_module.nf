#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: gatom — lipidomics_metabolite_level_active_module
// Identify an active metabolic module from lipidomics data using metabolite-level topology and abbreviate lipid labels for readability.
// Input: met.de.lipids
// Container: quay.io/biocontainers/bioconductor-gatom:1.8.4--r45hdfd78af_0
// R packages: data.table, gatom, igraph, mwcsr
// Bioconductor: 3.20 | R: 4.4
// Requires: data.table, gatom, igraph, mwcsr
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Read the declared user input file from the working
//  * 2. [Visualization & Output] Download/load the required network and annotation
//  * 3. [Visualization & Output] Construct the metabolic graph with metabolite-level
//  * 4. [Visualization & Output] Score the graph
//  * 5. [Visualization & Output] Solve the maximum weight connected subgraph problem
//  * 6. [Visualization & Output] Abbreviate metabolite labels for improved readability
//  * 7. [Visualization & Output] Visualize the resulting module (creates the widget object)
//  * 8. [Visualization & Output] Save meaningful results to output files

nextflow.enable.dsl = 2

process BIOC_GATOM_LIPIDOMICS_METABOLITE_LEVEL_ACTIVE_MODULE {
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
    .bm_deps <- c("data.table", "gatom", "igraph", "mwcsr")
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
    library(gatom)
    library(data.table)
    library(igraph)
    library(mwcsr)
    
    # --- Read the declared user input file from the working ---
    input_file <- "met.de.lipids"
    if (!file.exists(input_file)) {
      if (file.exists("met.de.lipids.csv")) {
        input_file <- "met.de.lipids.csv"
      } else if (file.exists("met.de.lipids.tsv")) {
        input_file <- "met.de.lipids.tsv"
      } else {
        stop("Required input file 'met.de.lipids' (or .csv/.tsv) not found in the working directory.")
      }
    }
    
    message("Reading user input: ", input_file)
    met.de.lipids <- data.table::fread(input_file)
    
    # --- Download/load the required network and annotation ---
    message("Downloading Rhea lipid subnetwork and annotations...")
    network.lipids <- readRDS(url("http://artyomovlab.wustl.edu/publications/supp_materials/GATOM/network.rhea.lipids.rds"))
    met.lipids.db <- readRDS(url("http://artyomovlab.wustl.edu/publications/supp_materials/GATOM/met.lipids.db.rds"))
    org.Mm.eg.gatom.anno <- readRDS(url("http://artyomovlab.wustl.edu/publications/supp_materials/GATOM/org.Mm.eg.gatom.anno.rds"))
    gene2reaction.extra <- data.table::fread("http://artyomovlab.wustl.edu/publications/supp_materials/GATOM/gene2reaction.rhea.mmu.eg.tsv", colClasses="character")
    
    # --- Construct the metabolic graph with metabolite-level ---
    message("Constructing metabolic graph...")
    lg <- makeMetabolicGraph(network=network.lipids,
                             topology="metabolites",
                             org.gatom.anno=org.Mm.eg.gatom.anno,
                             gene.de=NULL,
                             met.db=met.lipids.db,
                             met.de=met.de.lipids,
                             gene2reaction.extra=gene2reaction.extra)
    
    # --- Score the graph ---
    message("Scoring graph...")
    lgs <- scoreGraph(lg, k.gene = NULL, k.met = 50)
    
    # --- Solve the maximum weight connected subgraph problem ---
    message("Solving MWCS problem...")
    solver <- rnc_solver()
    set.seed(42)
    sol <- solve_mwcsp(solver, lgs)
    lm <- sol\$graph
    
    # --- Abbreviate metabolite labels for improved readability ---
    message("Abbreviating labels...")
    lm1 <- abbreviateLabels(lm, orig.names = TRUE, abbrev.names = TRUE)
    
    # --- Visualize the resulting module (creates the widget object) ---
    message("Creating visualization widget...")
    widget <- createShinyCyJSWidget(lm1)
    
    # --- Save meaningful results to output files ---
    message("Saving output files...")
    
    # Save the igraph object
    saveRDS(lm1, "active_lipid_module.rds")
    
    # Save as GraphML
    igraph::write_graph(lm1, file = "active_lipid_module.graphml", format = "graphml")
    
    # Save as interactive HTML widget
    tryCatch({
      saveModuleToHtml(module = lm1, file = "active_lipid_module.html", name = "Active_Lipid_Module")
    }, error = function(e) {
      warning("Could not save HTML widget: ", e\$message)
    })
    
    # Save as PDF plot
    tryCatch({
      set.seed(42)
      saveModuleToPdf(lm1, file = "active_lipid_module.pdf", name = "Active_Lipid_Module", n_iter = 100, force = 1e-5)
    }, error = function(e) {
      warning("Could not save PDF plot: ", e\$message)
    })
    
    # Export node and edge attributes as CSV tables
    tryCatch({
      nodes_dt <- data.table::as.data.table(igraph::as_data_frame(lm1, what = "vertices"))
      edges_dt <- data.table::as.data.table(igraph::as_data_frame(lm1, what = "edges"))
      data.table::fwrite(nodes_dt, "active_lipid_module_nodes.csv")
      data.table::fwrite(edges_dt, "active_lipid_module_edges.csv")
    }, error = function(e) {
      warning("Could not export CSV tables: ", e\$message)
    })
    
    message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_GATOM_LIPIDOMICS_METABOLITE_LEVEL_ACTIVE_MODULE":',
        paste0('    gatom: ', as.character(packageVersion('gatom')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_lipidomics_metabolite_level_active_module.csv versions.yml
    """
}

workflow BIOC_GATOM_LIPIDOMICS_METABOLITE_LEVEL_ACTIVE_MODULE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ met.de.lipids ] ]

    main:
    BIOC_GATOM_LIPIDOMICS_METABOLITE_LEVEL_ACTIVE_MODULE(ch_input)

    emit:
    tables   = BIOC_GATOM_LIPIDOMICS_METABOLITE_LEVEL_ACTIVE_MODULE.out.tables
    plots    = BIOC_GATOM_LIPIDOMICS_METABOLITE_LEVEL_ACTIVE_MODULE.out.plots
    objects  = BIOC_GATOM_LIPIDOMICS_METABOLITE_LEVEL_ACTIVE_MODULE.out.objects
    versions = BIOC_GATOM_LIPIDOMICS_METABOLITE_LEVEL_ACTIVE_MODULE.out.versions
}
