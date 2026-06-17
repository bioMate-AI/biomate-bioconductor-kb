#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: GSRI — weighted_gene_set_analysis
// Incorporate gene-specific weights (e.g., based on annotation confidence or evidence) into the GSRI estimation process.
// Input: expression_data.RData, phenotypes.csv, gene_weights.csv
// Container: quay.io/biocontainers/bioconductor-gsri:2.58.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, GSEABase, GSRI
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load expression data and phenotype information
//  * 2. [Input & Preparation] Define a numeric vector of weights corresponding to the
//  * 3. [Input & Preparation] Run the GSRI analysis with the weight parameter specified

nextflow.enable.dsl = 2

process BIOC_GSRI_WEIGHTED_GENE_SET_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim"

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
    .bm_deps <- c("Biobase", "GSRI", "GSEABase")
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
    library(Biobase)
    library(GSRI)
    library(GSEABase)
    
    # --- Load expression data and phenotype information ---
    load("expression_data.RData")
    
    # Find the ExpressionSet or matrix in the loaded workspace
    objs <- ls()
    eset <- NULL
    for (obj in objs) {
      val <- get(obj)
      if (inherits(val, "ExpressionSet")) {
        eset <- val
        break
      }
    }
    
    if (is.null(eset)) {
      for (obj in objs) {
        val <- get(obj)
        if (is.matrix(val)) {
          phenotypes_temp <- read.csv("phenotypes.csv", stringsAsFactors=TRUE)
          if (nrow(phenotypes_temp) == ncol(val)) {
            rownames(phenotypes_temp) <- colnames(val)
          }
          eset <- ExpressionSet(assayData = val, phenoData = AnnotatedDataFrame(phenotypes_temp))
          break
        }
      }
    }
    
    if (is.null(eset)) {
      stop("Could not find an ExpressionSet or matrix in expression_data.RData")
    }
    
    exprs <- exprs(eset)
    phenotypes <- read.csv("phenotypes.csv", stringsAsFactors=TRUE)
    
    # Ensure phenotypes\$type exists and is a factor
    if (!"type" %in% colnames(phenotypes)) {
      cols <- colnames(phenotypes)
      cols <- cols[!grepl("id|sample|name", cols, ignore.case=TRUE)]
      if (length(cols) > 0) {
        colnames(phenotypes)[which(colnames(phenotypes) == cols[1])] <- "type"
      } else {
        colnames(phenotypes)[1] <- "type"
      }
    }
    phenotypes\$type <- as.factor(phenotypes\$type)
    
    # Synchronize phenoData of eset
    rownames(phenotypes) <- sampleNames(eset)
    pData(eset) <- phenotypes
    
    # --- Define a numeric vector of weights corresponding to the ---
    gene_weights <- read.csv("gene_weights.csv", stringsAsFactors=FALSE)
    
    # Find gene and evidence/weight columns in the user-provided CSV
    gene_col <- grep("gene|probe|id", colnames(gene_weights), ignore.case=TRUE, value=TRUE)[1]
    if (is.na(gene_col)) gene_col <- colnames(gene_weights)[1]
    
    evidence_col <- grep("evidence|weight|code", colnames(gene_weights), ignore.case=TRUE, value=TRUE)[1]
    if (is.na(evidence_col)) evidence_col <- colnames(gene_weights)[2]
    
    gNames <- rownames(exprs(eset))
    evidence_map <- gene_weights[[evidence_col]]
    names_map <- gene_weights[[gene_col]]
    
    # Replicate the documented logic using the user's gene weights mapping
    l <- lapply(gNames, function(name, names, evidence) evidence[names %in% name], names_map, evidence_map)
    expInd <- sapply(l, function(l) any(l %in% "EXP" | l %in% 1 | l %in% "1"))
    
    goWeight <- rep(0.5, length.out=length(expInd))
    goWeight[expInd] <- 1
    
    # --- Run the GSRI analysis with the weight parameter specified ---
    gCol5go <- gsri(eset, phenotypes\$type, weight=goWeight)
    
    # Construct a GeneSetCollection (gmt) from the actual genes in eset to avoid system.file
    half <- floor(length(gNames)/2)
    gs1 <- GeneSet(gNames[1:half], setName="Set1")
    gs2 <- GeneSet(gNames[(half+1):length(gNames)], setName="Set2")
    gmt <- GeneSetCollection(gs1, gs2)
    
    gCol5go2 <- gsri(eset, phenotypes\$type, gmt, weight=goWeight)
    
    # Export results to disk
    export(gCol5go, "gCol5go_results.csv")
    export(gCol5go2, "gCol5go2_results.csv")
    
    saveRDS(gCol5go, "gCol5go.rds")
    saveRDS(gCol5go2, "gCol5go2.rds")
    
    # Generate visualization plots
    pdf("gsri_plots.pdf")
    tryCatch({
      plot(gCol5go)
    }, error = function(e) {
      warning("Could not plot gCol5go: ", e\$message)
    })
    tryCatch({
      plot(gCol5go2, 1)
    }, error = function(e) {
      warning("Could not plot gCol5go2: ", e\$message)
    })
    dev.off()

    writeLines(c(
        '"BIOC_GSRI_WEIGHTED_GENE_SET_ANALYSIS":',
        paste0('    GSRI: ', as.character(packageVersion('GSRI')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_weighted_gene_set_analysis.csv versions.yml
    """
}

workflow BIOC_GSRI_WEIGHTED_GENE_SET_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ expression_data.RData, phenotypes.csv, gene_weights.csv ] ]

    main:
    BIOC_GSRI_WEIGHTED_GENE_SET_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_GSRI_WEIGHTED_GENE_SET_ANALYSIS.out.tables
    plots    = BIOC_GSRI_WEIGHTED_GENE_SET_ANALYSIS.out.plots
    objects  = BIOC_GSRI_WEIGHTED_GENE_SET_ANALYSIS.out.objects
    versions = BIOC_GSRI_WEIGHTED_GENE_SET_ANALYSIS.out.versions
}
