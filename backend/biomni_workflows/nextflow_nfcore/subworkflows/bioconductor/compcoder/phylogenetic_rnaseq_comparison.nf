#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: compcodeR — phylogenetic_rnaseq_comparison
// Format user's count matrix, sample annotations, phylogenetic tree, and gene length matrix into a phyloCompData object, run phylogenetic/length-normalized DE met
// Input: count.matrix, sample.annotations, tree, length.matrix
// Container: quay.io/biocontainers/bioconductor-compcoder:1.46.0--r45hdfd78af_0
// R packages: ape, compcodeR
// Bioconductor: 3.20 | R: 4.4
// Requires: ape, compcodeR
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Create a phyloCompData object using the phyloCompData constructor. 2. Validate the object using check_phyloCompData. 3. Run differ

nextflow.enable.dsl = 2

process BIOC_COMPCODER_PHYLOGENETIC_RNASEQ_COMPARISON {
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
    .bm_deps <- c("ape", "compcodeR")
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
    
    library(compcodeR)
    library(ape)
    
    # Helper to read matrix from RDS or text formats
    read_matrix <- function(path) {
      if (file.exists(path)) {
        res <- tryCatch(readRDS(path), error = function(e) NULL)
        if (is.matrix(res)) return(res)
        res <- tryCatch(as.matrix(read.table(path, header = TRUE, row.names = 1, check.names = FALSE)), error = function(e) NULL)
        if (is.matrix(res)) return(res)
        res <- tryCatch(as.matrix(read.csv(path, row.names = 1, check.names = FALSE)), error = function(e) NULL)
        if (is.matrix(res)) return(res)
      }
      stop(paste("Could not read matrix from", path))
    }
    
    # Helper to read data frame from RDS or text formats
    read_df <- function(path) {
      if (file.exists(path)) {
        res <- tryCatch(readRDS(path), error = function(e) NULL)
        if (is.data.frame(res)) return(res)
        res <- tryCatch(read.table(path, header = TRUE, row.names = 1, check.names = FALSE), error = function(e) NULL)
        if (is.data.frame(res)) return(res)
        res <- tryCatch(read.csv(path, row.names = 1, check.names = FALSE), error = function(e) NULL)
        if (is.data.frame(res)) return(res)
      }
      stop(paste("Could not read data frame from", path))
    }
    
    # Helper to read tree from RDS or Newick format
    read_tree_file <- function(path) {
      if (file.exists(path)) {
        res <- tryCatch(readRDS(path), error = function(e) NULL)
        if (inherits(res, "phylo")) return(res)
        res <- tryCatch(read.tree(path), error = function(e) NULL)
        if (inherits(res, "phylo")) return(res)
      }
      stop(paste("Could not read tree from", path))
    }
    
    # Load user inputs
    count.matrix <- read_matrix("count.matrix")
    sample.annotations <- read_df("sample.annotations")
    tree <- read_tree_file("tree")
    length.matrix <- read_matrix("length.matrix")
    
    # Align names as in documented code
    colnames(count.matrix) <- colnames(length.matrix) <- rownames(sample.annotations) <- tree\$tip.label
    
    # Create phyloCompData object
    info.parameters <- list(dataset = "mydata", uID = "123456")
    cpd <- phyloCompData(count.matrix = count.matrix,
                         sample.annotations = sample.annotations,
                         info.parameters = info.parameters,
                         tree = tree,
                         length.matrix = length.matrix)
    
    # Validate
    check_phyloCompData(cpd)
    
    # Save to the expected filename for runDiffExp
    saveRDS(cpd, "alt_BM_repl1.rds")
    
    # Run differential expression analyses
    runDiffExp(data.file = "alt_BM_repl1.rds", result.extent = "DESeq2", Rmdfunction = "DESeq2.createRmd", output.directory = ".", fit.type = "parametric", test = "Wald")
    runDiffExp(data.file = "alt_BM_repl1.rds", result.extent = "lengthNorm.limma", Rmdfunction = "lengthNorm.limma.createRmd", output.directory = ".", norm.method = "TMM", length.normalization = "TPM", data.transformation = "log2", trend = FALSE, block.factor = "id.species")
    runDiffExp(data.file = "alt_BM_repl1.rds", result.extent = "phylolm", Rmdfunction = "phylolm.createRmd", output.directory = ".", norm.method = "TMM", model = "BM", measurement_error = TRUE, extra.design.covariates = NULL, length.normalization = "TPM", data.transformation = "log2")
    
    # Export results to CSV
    if (file.exists("alt_BM_repl1_DESeq2.rds")) {
      res_deseq2 <- readRDS("alt_BM_repl1_DESeq2.rds")
      write.csv(res_deseq2@result.table, "DESeq2_results.csv", row.names = TRUE)
    }
    if (file.exists("alt_BM_repl1_lengthNorm.limma.rds")) {
      res_limma <- readRDS("alt_BM_repl1_lengthNorm.limma.rds")
      write.csv(res_limma@result.table, "lengthNorm_limma_results.csv", row.names = TRUE)
    }
    if (file.exists("alt_BM_repl1_phylolm.rds")) {
      res_phylolm <- readRDS("alt_BM_repl1_phylolm.rds")
      write.csv(res_phylolm@result.table, "phylolm_results.csv", row.names = TRUE)
    }

    writeLines(c(
        '"BIOC_COMPCODER_PHYLOGENETIC_RNASEQ_COMPARISON":',
        paste0('    compcodeR: ', as.character(packageVersion('compcodeR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_phylogenetic_rnaseq_comparison.csv versions.yml
    """
}

workflow BIOC_COMPCODER_PHYLOGENETIC_RNASEQ_COMPARISON_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ count.matrix, sample.annotations, tree, length.matrix ] ]

    main:
    BIOC_COMPCODER_PHYLOGENETIC_RNASEQ_COMPARISON(ch_input)

    emit:
    tables   = BIOC_COMPCODER_PHYLOGENETIC_RNASEQ_COMPARISON.out.tables
    plots    = BIOC_COMPCODER_PHYLOGENETIC_RNASEQ_COMPARISON.out.plots
    objects  = BIOC_COMPCODER_PHYLOGENETIC_RNASEQ_COMPARISON.out.objects
    versions = BIOC_COMPCODER_PHYLOGENETIC_RNASEQ_COMPARISON.out.versions
}
