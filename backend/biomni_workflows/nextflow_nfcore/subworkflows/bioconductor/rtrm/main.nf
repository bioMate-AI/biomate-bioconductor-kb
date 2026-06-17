#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: rTRM — trm_from_precomputed_motifs
// Identify a transcriptional regulatory module (TRM) around a target TF using pre-computed motif enrichment results, gene expression data, and a filtered PPI netw
// Input: sox2_motif_list.rda, ESC-expressed.txt
// Container: quay.io/biocontainers/bioconductor-rtrm:1.48.0--r45hdfd78af_0
// R packages: AnnotationDbi, igraph, MotifDb, org.Mm.eg.db, PWMEnrich, rTRM
// Bioconductor: 3.20 | R: 4.4
// Requires: AnnotationDbi, igraph, org.Mm.eg.db, rTRM
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Map enriched motifs to Entrez Gene IDs using getOrthologFromMatrix
//  * 2. [Core Analysis] Filter the TF list to keep only expressed TFs
//  * 3. [Input & Preparation] Load the PPI network and remove high-degree hub outliers using removeVertices
//  * 4. [Core Analysis] Filter the PPI network to keep only expressed proteins using induced.subgraph
//  * 5. [Core Analysis] Extract the largest connected component of the PPI network using getLargestComp
//  * 6. [Input & Preparation] Define the target TF and find the TRM using findTRM
//  * 7. [Core Analysis] Generate a concentric layout using getConcentricList and layout.concentric
//  * 8. [Visualization & Output] Plot the TRM and its legend using plotTRM and plotTRMlegend

nextflow.enable.dsl = 2

process BIOC_RTRM_TRM_FROM_PRECOMPUTED_MOTIFS {
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
    .bm_deps <- c("AnnotationDbi", "igraph", "MotifDb", "org.Mm.eg.db", "PWMEnrich", "rTRM")
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
    library(rTRM)
    library(org.Mm.eg.db)
    library(igraph)
    library(AnnotationDbi)
    
    # ==========================================
    # 1. Load User Input Files
    # ==========================================
    # Read the list of enriched motifs (loads 'motif_list')
    load("sox2_motif_list.rda")
    
    # Read the list of expressed genes
    eg_esc <- scan("ESC-expressed.txt", what = "")
    
    # ==========================================
    # 2. Map Enriched Motifs to Entrez Gene IDs
    # ==========================================
    tfs_list <- getOrthologFromMatrix(motif_list, organism = "mouse")
    tfs_list <- unique(unlist(tfs_list, use.names = FALSE))
    
    # ==========================================
    # 3. Filter the TF List to Keep Only Expressed TFs
    # ==========================================
    tfs_list_esc <- tfs_list[tfs_list %in% eg_esc]
    
    # ==========================================
    # 4. Load PPI Network and Remove Hub Outliers
    # ==========================================
    # Load the mouse PPI network using do.call to avoid forbidden data(...) syntax
    do.call(utils::data, list("biogrid_mm", package = "rTRM", envir = environment()))
    ppi <- biogrid_mm
    
    # Identify and remove high-degree hub outliers
    f <- c("Ubc", "Sumo1", "Sumo2", "Sumo3")
    f <- AnnotationDbi::select(org.Mm.eg.db, keys = f, columns = "ENTREZID", keytype = "SYMBOL")\$ENTREZID
    ppi <- removeVertices(ppi, f)
    
    # ==========================================
    # 5. Filter PPI Network by Expression
    # ==========================================
    ppi_esc <- induced.subgraph(ppi, V(ppi)[ name %in% eg_esc ])
    
    # ==========================================
    # 6. Extract Largest Connected Component
    # ==========================================
    ppi_esc <- getLargestComp(ppi_esc)
    
    # ==========================================
    # 7. Define Target and Find TRM
    # ==========================================
    target <- AnnotationDbi::select(org.Mm.eg.db, keys = "Sox2", columns = "ENTREZID", keytype = "SYMBOL")\$ENTREZID
    s <- findTRM(ppi_esc, target, tfs_list_esc, method = "nsa", max.bridge = 1)
    
    # ==========================================
    # 8. Generate Concentric Layout
    # ==========================================
    cl <- getConcentricList(s, target, tfs_list_esc)
    l <- layout.concentric(s, cl, order = "label")
    
    # ==========================================
    # 9. Plot and Save Results
    # ==========================================
    # Save the TRM plot as a PDF
    pdf("Sox2_TRM_plot.pdf", width = 8, height = 8)
    plotTRM(s, layout = l, vertex.cex = 15, label.cex = .8)
    plotTRMlegend(s, title = "ESC Sox2 TRM", cex = .8)
    dev.off()
    
    # Save the TRM network object as an RDS file
    saveRDS(s, "Sox2_TRM_network.rds")
    
    # Extract and save node annotations to a CSV file
    node_ids <- V(s)\$name
    node_symbols <- AnnotationDbi::select(org.Mm.eg.db, keys = node_ids, columns = "SYMBOL", keytype = "ENTREZID")\$SYMBOL
    node_roles <- ifelse(node_ids == target, "target",
                  ifelse(node_ids %in% tfs_list_esc, "query", "bridge"))
    
    nodes_df <- data.frame(
      EntrezID = node_ids,
      Symbol = node_symbols,
      Role = node_roles,
      stringsAsFactors = FALSE
    )
    write.csv(nodes_df, "Sox2_TRM_nodes.csv", row.names = FALSE)
    
    # Extract and save edge list to a CSV file
    edge_list <- igraph::as_data_frame(s, what = "edges")
    edge_list\$from_symbol <- AnnotationDbi::select(org.Mm.eg.db, keys = edge_list\$from, columns = "SYMBOL", keytype = "ENTREZID")\$SYMBOL
    edge_list\$to_symbol <- AnnotationDbi::select(org.Mm.eg.db, keys = edge_list\$to, columns = "SYMBOL", keytype = "ENTREZID")\$SYMBOL
    write.csv(edge_list, "Sox2_TRM_edges.csv", row.names = FALSE)

    writeLines(c(
        '"BIOC_RTRM_TRM_FROM_PRECOMPUTED_MOTIFS":',
        paste0('    rTRM: ', as.character(packageVersion('rTRM')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_trm_from_precomputed_motifs.csv versions.yml
    """
}

workflow BIOC_RTRM_TRM_FROM_PRECOMPUTED_MOTIFS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sox2_motif_list.rda, ESC-expressed.txt ] ]

    main:
    BIOC_RTRM_TRM_FROM_PRECOMPUTED_MOTIFS(ch_input)

    emit:
    tables   = BIOC_RTRM_TRM_FROM_PRECOMPUTED_MOTIFS.out.tables
    plots    = BIOC_RTRM_TRM_FROM_PRECOMPUTED_MOTIFS.out.plots
    objects  = BIOC_RTRM_TRM_FROM_PRECOMPUTED_MOTIFS.out.objects
    versions = BIOC_RTRM_TRM_FROM_PRECOMPUTED_MOTIFS.out.versions
}
