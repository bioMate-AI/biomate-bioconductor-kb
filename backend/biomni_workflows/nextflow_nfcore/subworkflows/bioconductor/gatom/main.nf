#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: gatom — dual_omics_active_module
// Identify an active metabolic module from paired transcriptomics and metabolomics differential expression data using atom-level topology.
// Input: gene.de.rawEx, met.de.rawEx
// Container: quay.io/biocontainers/bioconductor-gatom:1.8.4--r45hdfd78af_0
// R packages: data.table, fgsea, gatom, igraph, mwcsr
// Bioconductor: 3.20 | R: 4.4
// Requires: data.table, fgsea, gatom, igraph, mwcsr
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Read user input files from the working directory
//  * 2. [Visualization & Output] Download the required network and annotation databases
//  * 3. [Visualization & Output] Construct the metabolic graph with atom-level topology
//  * 4. [Visualization & Output] Score the graph nodes and edges
//  * 5. [Visualization & Output] Initialize the solver
//  * 6. [Visualization & Output] Solve the maximum weight connected subgraph problem
//  * 7. [Visualization & Output] Visualize and save the module
//  * 8. [Visualization & Output] Downstream pathway enrichment analysis

nextflow.enable.dsl = 2

process BIOC_GATOM_DUAL_OMICS_ACTIVE_MODULE {
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
    .bm_deps <- c("data.table", "fgsea", "gatom", "igraph", "mwcsr")
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
    
    # Set timeout for downloading large database files
    options(timeout = 600)
    
    # Load required libraries
    library(gatom)
    library(data.table)
    library(igraph)
    library(mwcsr)
    library(fgsea)
    
    # --- Read user input files from the working directory ---
    gene.de.rawEx <- data.table::fread("gene.de.rawEx")
    met.de.rawEx <- data.table::fread("met.de.rawEx")
    
    # --- Download the required network and annotation databases ---
    networkEx <- readRDS(url("http://artyomovlab.wustl.edu/publications/supp_materials/GATOM/network.kegg.rds"))
    met.kegg.dbEx <- readRDS(url("http://artyomovlab.wustl.edu/publications/supp_materials/GATOM/met.kegg.db.rds"))
    org.Mm.eg.gatom.annoEx <- readRDS(url("http://artyomovlab.wustl.edu/publications/supp_materials/GATOM/org.Mm.eg.gatom.anno.rds"))
    
    # Define aliases to match the exact documented code variables for downstream analysis
    org.Mm.eg.gatom.anno <- org.Mm.eg.gatom.annoEx
    
    # --- Construct the metabolic graph with atom-level topology ---
    g <- makeMetabolicGraph(network=networkEx, 
                            topology="atoms",
                            org.gatom.anno=org.Mm.eg.gatom.annoEx, 
                            gene.de=gene.de.rawEx,
                            met.db=met.kegg.dbEx, 
                            met.de=met.de.rawEx)
    
    kg <- g # Alias for downstream ORA universe
    
    # --- Score the graph nodes and edges ---
    gs <- scoreGraph(g, k.gene = 25, k.met = 25)
    
    # --- Initialize the solver ---
    solver <- rnc_solver()
    
    # --- Solve the maximum weight connected subgraph problem ---
    set.seed(42)
    res <- solve_mwcsp(solver, gs)
    m <- res\$graph
    
    km <- m # Alias for downstream ORA genes
    
    # --- Visualize and save the module ---
    createShinyCyJSWidget(m)
    
    write_graph(m, file = file.path(tempdir(), "M0.vs.M1.graphml"), format = "graphml")
    
    saveModuleToHtml(module = m, file = file.path(tempdir(), "M0.vs.M1.html"), 
                     name="M0.vs.M1")
    
    saveModuleToDot(m, file = file.path(tempdir(), "M0.vs.M1.dot"), name = "M0.vs.M1")
    
    saveModuleToPdf(m, file = file.path(tempdir(), "M0.vs.M1.pdf"), name = "M0.vs.M1", 
                    n_iter=100, force=1e-5)
    
    # Copy the saved files from tempdir to the current working directory
    file.copy(file.path(tempdir(), "M0.vs.M1.graphml"), "./M0.vs.M1.graphml", overwrite = TRUE)
    file.copy(file.path(tempdir(), "M0.vs.M1.html"), "./M0.vs.M1.html", overwrite = TRUE)
    file.copy(file.path(tempdir(), "M0.vs.M1.dot"), "./M0.vs.M1.dot", overwrite = TRUE)
    file.copy(file.path(tempdir(), "M0.vs.M1.pdf"), "./M0.vs.M1.pdf", overwrite = TRUE)
    
    # --- Downstream pathway enrichment analysis ---
    foraRes <- fgsea::fora(pathways=org.Mm.eg.gatom.anno\$pathways,
                           genes=E(km)\$gene,
                           universe=unique(E(kg)\$gene),
                           minSize=5)
    
    mainPathways <- fgsea::collapsePathwaysORA(
      foraRes[padj < 0.05],
      pathways=org.Mm.eg.gatom.anno\$pathways,
      genes=E(km)\$gene,
      universe=unique(E(kg)\$gene))
    
    # Save enrichment results to the working directory
    data.table::fwrite(foraRes, "foraRes.csv")
    saveRDS(mainPathways, "mainPathways.rds")

    writeLines(c(
        '"BIOC_GATOM_DUAL_OMICS_ACTIVE_MODULE":',
        paste0('    gatom: ', as.character(packageVersion('gatom')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_dual_omics_active_module.csv versions.yml
    """
}

workflow BIOC_GATOM_DUAL_OMICS_ACTIVE_MODULE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ gene.de.rawEx, met.de.rawEx ] ]

    main:
    BIOC_GATOM_DUAL_OMICS_ACTIVE_MODULE(ch_input)

    emit:
    tables   = BIOC_GATOM_DUAL_OMICS_ACTIVE_MODULE.out.tables
    plots    = BIOC_GATOM_DUAL_OMICS_ACTIVE_MODULE.out.plots
    objects  = BIOC_GATOM_DUAL_OMICS_ACTIVE_MODULE.out.objects
    versions = BIOC_GATOM_DUAL_OMICS_ACTIVE_MODULE.out.versions
}
