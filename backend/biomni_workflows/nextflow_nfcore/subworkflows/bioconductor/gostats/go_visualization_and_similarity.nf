#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: GOstats — go_visualization_and_similarity
// Visualize phenotype expression patterns on an induced GO graph and calculate semantic similarity distances between genes based on GO annotations.
// Input: expression_data.RData, selected_genes.txt
// Container: quay.io/biocontainers/bioconductor-gostats:2.76.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, GO.db, GOstats, Rgraphviz, annotate, graph
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] READ USER INPUTS
//  * 2. [Visualization & Output] PREPARATION & GRAPH SETUP
//  * 3. [Visualization & Output] FAITHFUL REPRODUCTION OF DOCUMENTED CODE
//  * 4. [Visualization & Output] WRITE OUTPUT FILES

nextflow.enable.dsl = 2

process BIOC_GOSTATS_GO_VISUALIZATION_AND_SIMILARITY {
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
    .bm_deps <- c("Biobase", "GOstats", "GO.db", "annotate", "Rgraphviz", "RBGL", "graph", "annot_pkg_db")
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
        
        # Load required Bioconductor and CRAN libraries
        library(Biobase)
        library(GOstats)
        library(GO.db)
        library(annotate)
        library(Rgraphviz)
        library(RBGL)
        library(graph)
        
        # ==========================================
        # --- READ USER INPUTS ---
        # ==========================================
        
        # Read selected genes (Entrez Gene IDs)
        if (!file.exists("selected_genes.txt")) {
          stop("Error: 'selected_genes.txt' not found in the working directory.")
        }
        selected_genes <- readLines("selected_genes.txt")
        selected_genes <- unique(trimws(selected_genes))
        selected_genes <- selected_genes[selected_genes != ""]
        
        # Load ExpressionSet object
        if (!file.exists("expression_data.RData")) {
          stop("Error: 'expression_data.RData' not found in the working directory.")
        }
        load_env <- new.env()
        load("expression_data.RData", envir = load_env)
        
        # Find the ExpressionSet object within the loaded environment
        es_names <- names(which(sapply(load_env, function(x) is(x, "ExpressionSet"))))
        if (length(es_names) > 0) {
          eS <- load_env[[es_names[1]]]
        } else {
          stop("Error: No ExpressionSet object found in 'expression_data.RData'.")
        }
        
        # Extract annotation package dynamically from the ExpressionSet
        annot_pkg <- annotation(eS)
        if (length(annot_pkg) == 0 || annot_pkg == "") {
          stop("Error: ExpressionSet does not have an annotation package specified.")
        }
        if (!grepl("\\\\.db\$", annot_pkg)) {
          annot_pkg_db <- paste0(annot_pkg, ".db")
        } else {
          annot_pkg_db <- annot_pkg
          annot_pkg <- sub("\\\\.db\$", "", annot_pkg)
        }
        
        # Load the annotation package
        if (!require(annot_pkg_db, character.only = TRUE)) {
          stop(paste("Error: Annotation package", annot_pkg_db, "is not installed."))
        }
        
        # Get the environment mappings dynamically
        env_ENTREZID <- get(paste0(annot_pkg, "ENTREZID"))
        env_GO2ALLPROBES <- get(paste0(annot_pkg, "GO2ALLPROBES"))
        env_GO <- get(paste0(annot_pkg, "GO"))
        
        # Extract or define the phenotype group variable (MB)
        if ("mol.biol" %in% colnames(pData(eS))) {
          MB <- eS\$mol.biol
        } else if ("mol" %in% colnames(pData(eS))) {
          MB <- eS\$mol
        } else {
          # Fallback to the first factor/character column or default to a factor
          factor_cols <- sapply(pData(eS), function(x) is.factor(x) || is.character(x))
          if (any(factor_cols)) {
            MB <- pData(eS)[[which(factor_cols)[1]]]
          } else {
            MB <- pData(eS)[[1]]
          }
        }
        MB <- as.factor(MB)
        
        # ==========================================
        # --- PREPARATION & GRAPH SETUP ---
        # ==========================================
        
        # Construct the induced GO graph for Cellular Component (CC) ontology
        gCC <- makeGOGraph(selected_genes, "CC", chip = annot_pkg_db)
        
        # Layout the graph using Rgraphviz to create gCClo
        gCClo <- agopen(gCC, name = "gCC", layout = TRUE)
        
        # Define the plotPieChart function dynamically based on the number of groups
        plotPieChart <- function(curPlot, counts, main) {
          num_groups <- ncol(counts)
          colors_to_use <- rainbow(num_groups)
          
          renderNode <- function(x) {
            force(x)
            y <- x * 100 + 1
            function(node, ur, attrs = list(), radConv = 1) {
              nodeCenter <- getNodeCenter(node)
              pieGlyph(y, xpos = getX(nodeCenter), ypos = getY(nodeCenter), radius = getNodeRW(node), col = colors_to_use )
            }
          }
          drawing <- vector(mode = "list", length = nrow(counts))
          for (i in 1:length(drawing)) {
            drawing[[i]] <- renderNode(counts[i, ])
          }
          if (missing(main)) {
            main <- "Example Pie Chart Plot"
          }
          plot(curPlot, drawNode = drawing, main = main)
          legend(
            x = "bottomleft",
            legend = colnames(counts),
            fill = colors_to_use
          )
        }
        
        # Map selected Entrez IDs to probe IDs to define gN
        gN <- unlist(mget(selected_genes, revmap(env_ENTREZID), ifnotfound = NA))
        gN <- gN[!is.na(gN)]
        
        # ==========================================
        # --- FAITHFUL REPRODUCTION OF DOCUMENTED CODE ---
        # ==========================================
        
        mns <- apply(exprs(eS), 1, function(x) sapply(split(x, MB), mean))
        whismax <- apply(mns, 2, function(x) match(max(x), x))
        maxNames <- names(mns[, 1])[whismax]
        names(maxNames) <- names(whismax)
        CCnodes <- nodes(gCC)
        nodes2affy <- mget(CCnodes, env_GO2ALLPROBES, ifnotfound = NA)
        cts <- sapply(nodes2affy, function(x) { wh <- names(whismax) %in% x; table(maxNames[wh]) })
        
        # Dynamically compute counts for all phenotype levels
        pheno_levels <- levels(MB)
        if (length(cts) == 0) {
          ctmat <- matrix(0, nrow = 0, ncol = length(pheno_levels))
          colnames(ctmat) <- pheno_levels
        } else {
          ctmat <- sapply(pheno_levels, function(pheno) {
            counts <- sapply(cts, function(x) x[pheno])
            ifelse(is.na(counts), 0, counts)
          })
          if (is.vector(ctmat)) {
            ctmat <- matrix(ctmat, nrow = length(cts), ncol = length(pheno_levels))
            colnames(ctmat) <- pheno_levels
          }
          rownames(ctmat) <- names(cts)
        }
        
        # Render the induced GO graph with nodes represented as pie charts to a PDF
        pdf("go_induced_pie_charts.pdf", width = 12, height = 12)
        plotPieChart(gCClo, ctmat)
        dev.off()
        
        gN_subset <- gN[1:min(10, length(gN))]
        igenes <- unlist(mget(gN_subset, env_ENTREZID))
        igenes <- igenes[!is.na(igenes)]
        igenes <- as.character(igenes)
        psets <- mget(igenes, revmap(env_ENTREZID))
        psets <- sapply(psets, function(x) x[1])
        GOs <- mget(psets, env_GO, ifnotfound = NA)
        gBP <- sapply(GOs, getOntology, "BP")
        hasBP <- sapply(gBP, function(x) length(x) > 0 && !is.na(x[1]))
        gBP <- gBP[hasBP]
        ggs <- lapply(igenes[hasBP], makeGOGraph, "BP", chip = annot_pkg_db)
        
        # Compute semantic similarity matrices safely handling cases where sum(hasBP) is 0
        n_hasBP <- sum(hasBP)
        if (n_hasBP > 0) {
          simatM1 <- matrix(1, nr = n_hasBP, nc = n_hasBP)
          for (i in 1:n_hasBP) { 
            for (j in 1:n_hasBP) { 
              if (i == j) { 
                next 
              } else { 
                simatM1[i, j] <- simUI(ggs[[i]], ggs[[j]]) 
              } 
            } 
          }
          
          simatM2 <- matrix(1, nr = n_hasBP, nc = n_hasBP)
          for (i in 1:n_hasBP) { 
            for (j in 1:n_hasBP) { 
              if (i == j) { 
                next 
              } else { 
                simatM2[i, j] <- simLP(ggs[[i]], ggs[[j]]) 
              } 
            } 
          }
          
          # Assign names to similarity matrices for readability
          rownames(simatM1) <- colnames(simatM1) <- igenes[hasBP]
          rownames(simatM2) <- colnames(simatM2) <- igenes[hasBP]
        } else {
          simatM1 <- matrix(1, nr = 0, nc = 0)
          simatM2 <- matrix(1, nr = 0, nc = 0)
        }
        
        gCC.leaves <- leaves(gCC, "in")
        
        # ==========================================
        # --- WRITE OUTPUT FILES ---
        # ==========================================
        
        # Save the phenotype count matrix per GO term
        write.csv(ctmat, "go_phenotype_counts.csv", row.names = TRUE)
        
        # Save the semantic similarity matrices
        write.csv(simatM1, "similarity_matrix_UI.csv", row.names = TRUE)
        write.csv(simatM2, "similarity_matrix_LP.csv", row.names = TRUE)
        
        # Save the identified leaf nodes of the CC GO graph
        writeLines(gCC.leaves, "gCC_leaves.txt")
        
        # Save the similarity matrices as an RDS object for downstream analysis
        saveRDS(list(simUI = simatM1, simLP = simatM2), "semantic_similarity_results.rds")
        
        message("Pipeline completed successfully. Outputs written to working directory.")

    writeLines(c(
        '"BIOC_GOSTATS_GO_VISUALIZATION_AND_SIMILARITY":',
        paste0('    GOstats: ', as.character(packageVersion('GOstats')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_go_visualization_and_similarity.csv versions.yml
    """
}

workflow BIOC_GOSTATS_GO_VISUALIZATION_AND_SIMILARITY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ expression_data.RData, selected_genes.txt ] ]

    main:
    BIOC_GOSTATS_GO_VISUALIZATION_AND_SIMILARITY(ch_input)

    emit:
    tables   = BIOC_GOSTATS_GO_VISUALIZATION_AND_SIMILARITY.out.tables
    plots    = BIOC_GOSTATS_GO_VISUALIZATION_AND_SIMILARITY.out.plots
    objects  = BIOC_GOSTATS_GO_VISUALIZATION_AND_SIMILARITY.out.objects
    versions = BIOC_GOSTATS_GO_VISUALIZATION_AND_SIMILARITY.out.versions
}
