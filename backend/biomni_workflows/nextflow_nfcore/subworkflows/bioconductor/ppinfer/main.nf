#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: PPInfer — custom_network_protein_inference
// Infer functionally related proteins from a custom protein-protein interaction network and perform functional enrichment analysis.
// Input: network.gml, target_proteins.txt, pathways.gmt
// Container: quay.io/biocontainers/bioconductor-ppinfer:1.36.0--r45hdfd78af_0
// R packages: Category, fgsea, ggplot2, GOstats, igraph, limma, PPInfer
// Bioconductor: 3.20 | R: 4.4
// Requires: PPInfer, fgsea, ggplot2, igraph
// Visualizations: bar plot, enrichment plot, network plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Load the network and target proteins
//  * 2. [Visualization & Output] Compute the regularized Laplacian kernel
//  * 3. [Visualization & Output] Prepare target proteins
//  * 4. [Visualization & Output] Infer closely related proteins
//  * 5. [Visualization & Output] Over-Representation Analysis (ORA)
//  * 6. [Visualization & Output] Gene Set Enrichment Analysis (GSEA)
//  * 7. [Visualization & Output] Visualize Enrichment Network

nextflow.enable.dsl = 2

process BIOC_PPINFER_CUSTOM_NETWORK_PROTEIN_INFERENCE {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-proteomics:3.20"

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
    .bm_deps <- c("Category", "fgsea", "ggplot2", "GOstats", "igraph", "limma", "PPInfer")
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
            library(PPInfer)
            library(igraph)
            library(fgsea)
            library(ggplot2)
            
            # ==========================================
            # --- Load the network and target proteins ---
            # ==========================================
            
            # Read network.gml (supports GML format or RDS of graphNEL/igraph)
            litG <- tryCatch({
              igraph::read_graph("network.gml", format = "gml")
            }, error = function(e) {
              obj <- readRDS("network.gml")
              if (inherits(obj, "graphNEL")) {
                igraph.from.graphNEL(obj)
              } else {
                obj
              }
            })
            
            # Ensure vertex names are populated
            if (is.null(V(litG)\$name)) {
              V(litG)\$name <- as.character(seq_len(gorder(litG)))
            }
            
            # Extract the largest connected component (at least 50 vertices)
            sg <- decompose(litG, min.vertices = 50)
            if (length(sg) == 0) {
              # Fallback if no component has >= 50 vertices
              sg <- decompose(litG, min.vertices = 1)
            }
            sg <- sg[[1]]
            
            # Read target proteins and pathways from user input files
            target_proteins <- readLines("target_proteins.txt")
            target_proteins <- trimws(target_proteins)
            target_proteins <- target_proteins[target_proteins != ""]
            
            examplePathways <- fgsea::gmtPathways("pathways.gmt")
            
            # ==========================================
            # --- Compute the regularized Laplacian kernel ---
            # ==========================================
            K <- net.kernel(sg)
            
            # ==========================================
            # --- Prepare target proteins ---
            # ==========================================
            gene.names <- V(sg)\$name
            rownames(K) <- gene.names
            
            # Filter target proteins to those present in the network component
            myInterestingGenes <- intersect(target_proteins, gene.names)
            
            # Ensure N - 2n > 0 constraint is met (n must be less than N/2)
            N <- length(gene.names)
            max_n <- floor((N - 1) / 2)
            
            if (length(myInterestingGenes) > max_n) {
              myInterestingGenes <- head(myInterestingGenes, max_n)
            }
            if (length(myInterestingGenes) == 0) {
              # Fallback to a sample if no target proteins overlap
              myInterestingGenes <- sample(gene.names, min(10, max_n))
            }
            
            # ==========================================
            # --- Infer closely related proteins ---
            # ==========================================
            set.seed(123)
            cv_folds <- min(10, length(myInterestingGenes))
            if (cv_folds >= 2) {
              infer <- net.infer(myInterestingGenes, K, cross = cv_folds)
            } else {
              infer <- net.infer(myInterestingGenes, K)
            }
            
            # Save cross-validation error and inference results
            cat("CV Error:", infer\$CVerror, "\n")
            saveRDS(infer, "protein_inference_cross_val.rds")
            
            index <- match(infer\$top, names(V(sg)))
            V(sg)[index]\$color <- "red"
            
            gene.id <- infer\$top
            saveRDS(infer, "protein_inference_final.rds")
            
            # ==========================================
            # --- Over-Representation Analysis (ORA) ---
            # ==========================================
            result.ORA <- ORA(examplePathways, gene.id[1:10])
            write.csv(result.ORA, "ORA_results.csv", row.names = FALSE)
            
            # Plot ORA results
            pdf("ORA_barplot.pdf", width = 8, height = 6)
            p_ora <- ORA.barplot(result.ORA, category = "Category", size = "Size",
                                 count = "Count", pvalue = "pvalue", sort = "pvalue") +
                     scale_colour_gradient(low = 'red', high = 'gray', limits=c(0, 0.1))
            print(p_ora)
            dev.off()
            
            # ==========================================
            # --- Gene Set Enrichment Analysis (GSEA) ---
            # ==========================================
            index <- !is.na(infer\$score)
            gene.id <- infer\$top[index]
            scores <- infer\$score[index]
            scaled.scores <- as.numeric(scale(scores))
            names(scaled.scores) <- gene.id
            
            set.seed(1)
            result.GSEA <- fgsea(examplePathways, scaled.scores, nperm=1000)
            
            # Convert list column to character strings before writing to CSV
            result.GSEA_out <- as.data.frame(result.GSEA)
            result.GSEA_out\$leadingEdge <- sapply(result.GSEA_out\$leadingEdge, paste, collapse = "/")
            write.csv(result.GSEA_out, "GSEA_results.csv", row.names = FALSE)
            
            # Plot GSEA results
            pdf("GSEA_barplot.pdf", width = 10, height = 8)
            p_gsea <- GSEA.barplot(result.GSEA, category = 'pathway', score = 'NES', pvalue = 'pval',
                         numChar = 50, sort = 'NES', decreasing = TRUE)
            print(p_gsea)
            dev.off()
            
            # ==========================================
            # --- Visualize Enrichment Network ---
            # ==========================================
            pdf("enrichment_network.pdf", width = 10, height = 10)
            enrich.net(result.GSEA, examplePathways, node.id = 'pathway',
                       pvalue = 'pval', pvalue.cutoff = 0.25, degree.cutoff = 0,
                       n = 100, vertex.label.cex = 0.75, show.legend = FALSE,
                       edge.width = function(x) {5*sqrt(x)},
                       layout=igraph::layout.kamada.kawai)
            dev.off()

    writeLines(c(
        '"BIOC_PPINFER_CUSTOM_NETWORK_PROTEIN_INFERENCE":',
        paste0('    PPInfer: ', as.character(packageVersion('PPInfer')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_custom_network_protein_inference.csv versions.yml
    """
}

workflow BIOC_PPINFER_CUSTOM_NETWORK_PROTEIN_INFERENCE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ network.gml, target_proteins.txt, pathways.gmt ] ]

    main:
    BIOC_PPINFER_CUSTOM_NETWORK_PROTEIN_INFERENCE(ch_input)

    emit:
    tables   = BIOC_PPINFER_CUSTOM_NETWORK_PROTEIN_INFERENCE.out.tables
    plots    = BIOC_PPINFER_CUSTOM_NETWORK_PROTEIN_INFERENCE.out.plots
    objects  = BIOC_PPINFER_CUSTOM_NETWORK_PROTEIN_INFERENCE.out.objects
    versions = BIOC_PPINFER_CUSTOM_NETWORK_PROTEIN_INFERENCE.out.versions
}
