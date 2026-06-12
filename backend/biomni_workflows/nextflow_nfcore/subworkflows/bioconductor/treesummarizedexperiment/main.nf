#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: TreeSummarizedExperiment
// TreeSummarizedExperiment has extended SingleCellExperiment to include hierarchical information on th
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/TreeSummarizedExperiment/inst/doc/Introduction_to_treeSummarizedExperiment.R
// Upstream  : ape, ggtree, ggplot2
// Downstream: ExperimentSubset, HoloFoodR, MGnifyR, mia, miaSim
//
// Install: BiocManager::install("TreeSummarizedExperiment")
// ============================================================

nextflow.enable.dsl = 2


process BIOC_TREESUMMARIZEDEXPERIMENT {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-treesummarizedexperiment"
    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-single_cell:3.20"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_treesummarizedexperiment_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_treesummarizedexperiment_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_treesummarizedexperiment_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("TreeSummarizedExperiment", "jsonlite")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
    }
    library(TreeSummarizedExperiment)
    library(jsonlite)

    # --- Object Construction [TreeSummarizedExperiment] ---
    # Key functions: TreeSummarizedExperiment, assays, rowData, colData
    assay_data <- rbind(rep(0, 4), matrix(1:20, nrow = 5))
    colnames(assay_data) <- paste0("sample", 1:4)
    rownames(assay_data) <- paste("entity", seq_len(6), sep = "")
    row_data <- data.frame(Kingdom = "A",
                           Phylum = rep(c("B1", "B2"), c(2, 4)),
                           Class = rep(c("C1", "C2", "C3"), each = 2),
                           OTU = paste0("D", 1:6),
                           row.names = rownames(assay_data),
                           stringsAsFactors = FALSE)
    col_data <- data.frame(gg = c(1, 2, 3, 3),
                           group = rep(LETTERS[1:2], each = 2), 
                           row.names = colnames(assay_data),
                           stringsAsFactors = FALSE)
    row_tree <- ape::rtree(5)
    col_tree <- ape::rtree(4)
    col_tree\$tip.label <- colnames(assay_data)
    col_tree\$node.label <- c("All", "GroupA", "GroupB")
    row_lab <- row_tree\$tip.label[c(1, 1:5)]
    both_tse <- TreeSummarizedExperiment(assays = list(Count = assay_data),
                                         rowData = row_data,
                                         colData = col_data,
                                         rowTree = row_tree,
                                         rowNodeLab = row_lab,
                                         colTree = col_tree)

    # --- Tree Management [TreeSummarizedExperiment] ---
    # Key functions: rowTree, colTree, rowTree<-
    r_tree <- rowTree(both_tse)
    c_tree <- colTree(both_tse)
    new_tree <- ape::rtree(nrow(both_tse))
    new_tree\$tip.label <- rownames(both_tse)
    new_tse <- both_tse
    rowTree(new_tse) <- new_tree

    # --- Link Data and Reference Sequences [TreeSummarizedExperiment] ---
    # Key functions: rowLinks, colLinks, referenceSeq, referenceSeq<-
    r_link <- rowLinks(both_tse)
    c_link <- colLinks(both_tse)
    refSeq <- Biostrings::DNAStringSet(rep("AGCT", nrow(both_tse)))
    referenceSeq(both_tse) <- refSeq
    ref_seq_out <- referenceSeq(both_tse)

    # --- Subsetting and Node Filtering [TreeSummarizedExperiment] ---
    # Key functions: subsetByNode, rowLinks, colLinks
    sub_tse <- both_tse[1:2, 1]
    node_tse <- subsetByNode(x = both_tse, rowNode = "t3")
    node_tse_sub <- subsetByNode(x = both_tse, rowNode = "t3", 
                                 colNode = c("sample1", "sample2"))
    sub_r_link <- rowLinks(node_tse_sub)


    # --- Save outputs ---
    .objs <- setdiff(ls(), c("args", "prefix", ".objs"))
    .cells <- function(v) { x <- tryCatch(get(v), error = function(e) NULL)
                            if (is.data.frame(x) || is.matrix(x)) prod(dim(x)) else -1 }
    .dfs  <- Filter(function(v) is.data.frame(tryCatch(get(v), error = function(e) NULL)), .objs)
    .tabs <- Filter(function(v) { x <- tryCatch(get(v), error = function(e) NULL)
                                  is.data.frame(x) || is.matrix(x) }, .objs)
    .cand <- if (length(.dfs) > 0) .dfs else .tabs
    if (length(.cand) > 0) {
        .main <- get(.cand[[ which.max(sapply(.cand, .cells)) ]])
        write.csv(as.data.frame(.main), "${prefix}_treesummarizedexperiment_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed", n_objects = length(.objs)),
                  "${prefix}_treesummarizedexperiment_results.csv", row.names = FALSE)
    }
    .payload <- tryCatch(mget(.objs, ifnotfound = list(NULL)),
                         error = function(e) list(status = "completed"))
    saveRDS(.payload, "${prefix}_treesummarizedexperiment_output.rds")

    # --- versions.yml ---
    writeLines(
        c("BIOC_TREESUMMARIZEDEXPERIMENT:", paste0("    treesummarizedexperiment: ", as.character(packageVersion("TreeSummarizedExperiment")))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_treesummarizedexperiment_results.csv
    touch ${prefix}_treesummarizedexperiment_output.rds
    echo "BIOC_TREESUMMARIZEDEXPERIMENT:" > versions.yml
    echo "    treesummarizedexperiment: 0.0.0" >> versions.yml
    """
}


workflow BIOC_TREESUMMARIZEDEXPERIMENT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_TREESUMMARIZEDEXPERIMENT(ch_input)

    emit:
    results  = BIOC_TREESUMMARIZEDEXPERIMENT.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_TREESUMMARIZEDEXPERIMENT.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_TREESUMMARIZEDEXPERIMENT.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_TREESUMMARIZEDEXPERIMENT.out.versions  // channel: path(versions.yml)
}
