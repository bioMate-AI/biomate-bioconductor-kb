#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: graphite — clipper_mixed_metabolomics
// Perform integrated pathway analysis on mixed gene expression and metabolomics data using clipper.
// Input: Terunuma_gene_expr.txt, Terunuma_metabolite_expr.txt
// Container: quay.io/biocontainers/bioconductor-graphite:1.56.0--r45hdfd78af_0
// R packages: Rgraphviz, clipper, graphite, impute, org.Hs.eg.db
// Bioconductor: 3.20 | R: 4.4
// Requires: Rgraphviz, clipper, graphite, impute, org.Hs.eg.db
// Visualizations: plot (ggplot/base)
// QC: missing-value handling
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load and clean gene and metabolite expression matrices
//  * 2. [Core Analysis] Format metabolite rownames with "CAS:" prefix and gene rownames with "ENSEMBL:" prefix
//  * 3. [Core Analysis] Merge matrices and log-transform metabolite levels
//  * 4. [Input & Preparation] Load pathways and convert identifiers to ENSEMBL and CAS
//  * 5. [Core Analysis] Filter pathways based on coverage of measured genes/metabolites
//  * 6. [Input & Preparation] Define sample classes and run clipper with which = "mixed"

nextflow.enable.dsl = 2

process BIOC_GRAPHITE_CLIPPER_MIXED_METABOLOMICS {
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
    .bm_deps <- c("Rgraphviz", "clipper", "graphite", "impute", "org.Hs.eg.db")
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
        library(graphite)
        library(clipper)
        library(impute)
        library(org.Hs.eg.db)
        library(Rgraphviz)
        
        # 1. Load and clean gene and metabolite expression matrices
        gexpr <- read.table("Terunuma_gene_expr.txt", header = TRUE, sep = "\t", row.names = 1,
                            stringsAsFactors = FALSE)
        
        mexpr <- read.table("Terunuma_metabolite_expr.txt", header = TRUE, sep = "\t", row.names = NULL,
                            stringsAsFactors = FALSE)
        
        idcols <- 1:4
        nas_by_row <- rowSums(is.na(data.matrix(mexpr[,-idcols]))) / (ncol(mexpr) - length(idcols))
        
        dexpr <- mexpr[nas_by_row < 0.5,]
        iexpr <- cbind(dexpr[,idcols],
                        impute.knn(data.matrix(dexpr[,-idcols]))\$data,
                        stringsAsFactors = FALSE)
        iexpr\$CAS <- sub("\\\\s*;.*\$", "", iexpr\$CAS)
        iexpr[,idcols][iexpr[,idcols] == ""] <- NA
        valid_cas <- !is.na(iexpr\$CAS)
        cas_col <- which(names(iexpr) == "CAS")
        cexpr <- iexpr[valid_cas, c(cas_col, seq.int(5, ncol(iexpr)))]
        
        # 2. Format metabolite rownames with "CAS:" prefix and gene rownames with "ENSEMBL:" prefix
        mexpr <- data.matrix(cexpr[,-1])
        rownames(mexpr) <- paste("CAS", cexpr\$CAS, sep = ":")
        
        # Ensure gene expression rownames have "ENSEMBL:" prefix to match pathway nodes
        if (!any(grepl("^ENSEMBL:", rownames(gexpr)))) {
          rownames(gexpr) <- paste("ENSEMBL", rownames(gexpr), sep = ":")
        }
        colnames(mexpr) <- colnames(gexpr)
        
        # 3. Merge matrices and log-transform metabolite levels
        fexpr <- rbind(data.matrix(gexpr), log(mexpr))
        
        # 4. Load pathways and convert identifiers to ENSEMBL and CAS
        kpaths <- pathways("hsapiens", "kegg")
        rpaths <- convertIdentifiers(convertIdentifiers(kpaths, "ENSEMBL"), "CAS")
        
        # 5. Filter pathways based on coverage of measured genes/metabolites
        filter_pathways <- function(pathways, expr, min_edge_num) {
          node_names <- rownames(expr)
          pred <- function(p) {
            ns <- nodes(p, "mixed")
                 if (length(ns) == 0) {
                   return(FALSE)
                 }
                 frac <- length(grep("^CAS:", ns)) / length(ns)
                 if (frac < 0.3) {
                   return(FALSE)
                 }
                 es <- edges(p, "mixed")
                 mask <- (paste(es\$src_type, es\$src, sep = ":") %in% node_names) &
                         (paste(es\$dest_type, es\$dest, sep = ":") %in% node_names)
                 sum(mask) >= min_edge_num
             }
             Filter(pred, pathways)
        }
        
        fpaths <- filter_pathways(rpaths, fexpr, 10)
        
        # 6. Define sample classes and run clipper with which = "mixed"
        pos_indices <- grep("^POS", colnames(fexpr))
        neg_indices <- grep("^NEG", colnames(fexpr))
        classes <- numeric(length = ncol(fexpr))
        classes[neg_indices] <- 1
        classes[pos_indices] <- 2
        
        out <- runClipper(fpaths, fexpr, classes, "mean", "mixed",
                          maxNodes = 150, seed = 42)
        
        # Save the main output object
        saveRDS(out, "clipper_output.rds")
        
        # Save a CSV summary of the results
        tryCatch({
          res_list <- out\$results
          if (length(res_list) > 0) {
            res_df_list <- lapply(names(res_list), function(pn) {
              df <- res_list[[pn]]
              if (is.data.frame(df) || is.matrix(df)) {
                df <- as.data.frame(df)
                df\$pathway <- pn
                return(df)
              }
              return(NULL)
            })
            res_df_list <- res_df_list[!sapply(res_df_list, is.null)]
            if (length(res_df_list) > 0) {
              final_res <- do.call(rbind, res_df_list)
              write.csv(final_res, "clipper_results_summary.csv", row.names = FALSE)
            }
          }
        }, error = function(e) {
          message("Could not write CSV summary: ", e\$message)
        })
        
        # Plot altered pathways to PDF
        tryCatch({
          plot_altered_path <- function(result, pathways, node_scale = 2) {
            title <- names(result)
            pathway <- pathways[[title]]
        
            graph <- pathwayGraph(pathway, which = "mixed")
        
            labels <- sapply(nodes(graph), function(n) {
               n2 <- sub("^CAS:", "", n)
               if (n != n2) {
                 n2
               } else {
                 mapIds(org.Hs.eg.db, sub("^ENSEMBL:", "", n), "SYMBOL", "ENSEMBL",
                        multiVals = "first")
               }
            })
            names(labels) <- nodes(graph)
        
            altered <- unlist(strsplit(rownames(result[[1]])[1], "[,;]"))
            selected <- nodes(graph) %in% altered
            node_colors <- ifelse(selected, "red", "black")
            names(node_colors) <- nodes(graph)
        
            base <- 0.75
            heights <- ifelse(selected, base * node_scale, base)
            names(heights) <- nodes(graph)
            widths <- ifelse(selected, base * node_scale, base)
            names(widths) <- nodes(graph)
        
            base <- 14
            fontsizes <- ifelse(selected, base * node_scale, base)
            names(fontsizes) <- nodes(graph)
        
            between_altered <- function(edge_names, altered) {
              sapply(edge_names, function(edge_name) {
                nodes <- unlist(strsplit(edge_name, "~", fixed = TRUE))
                all(nodes %in% altered)
              })
            }
        
            edge_colors <- ifelse(between_altered(edgeNames(graph), altered),
                                  "red", "black")
        
            plot(graph,
                 attrs = list(edge = list(arrowsize = 0.5)),
                 nodeAttrs = list(label = labels, color = node_colors, width = widths,
                                  height = heights, fontsize = fontsizes),
                 edgeAttrs = list(color = edge_colors),
                 recipEdges = "combined", main = title)
          }
        
          pdf("altered_pathways.pdf", width = 10, height = 8)
          for (idx in seq_along(out\$results)) {
            res <- out\$results[idx]
            if (names(res) %in% names(fpaths)) {
              plot_altered_path(res, fpaths)
            }
          }
          dev.off()
        }, error = function(e) {
          message("Could not generate PDF plots: ", e\$message)
        })

    writeLines(c(
        '"BIOC_GRAPHITE_CLIPPER_MIXED_METABOLOMICS":',
        paste0('    graphite: ', as.character(packageVersion('graphite')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_clipper_mixed_metabolomics.csv versions.yml
    """
}

workflow BIOC_GRAPHITE_CLIPPER_MIXED_METABOLOMICS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ Terunuma_gene_expr.txt, Terunuma_metabolite_expr.txt ] ]

    main:
    BIOC_GRAPHITE_CLIPPER_MIXED_METABOLOMICS(ch_input)

    emit:
    tables   = BIOC_GRAPHITE_CLIPPER_MIXED_METABOLOMICS.out.tables
    plots    = BIOC_GRAPHITE_CLIPPER_MIXED_METABOLOMICS.out.plots
    objects  = BIOC_GRAPHITE_CLIPPER_MIXED_METABOLOMICS.out.objects
    versions = BIOC_GRAPHITE_CLIPPER_MIXED_METABOLOMICS.out.versions
}
