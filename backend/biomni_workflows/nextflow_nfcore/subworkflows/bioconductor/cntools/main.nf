#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: CNTools — segmented_copy_number_analysis
// Convert segmented DNA copy number data into a matrix format by region or gene, filter out low-variance features, and perform hierarchical clustering.
// Input: sampleData, geneInfo
// Container: quay.io/biocontainers/bioconductor-cntools:1.66.0--r45h01b2380_0
// R packages: CNTools, genefilter
// Bioconductor: 3.20 | R: 4.4
// Requires: CNTools, genefilter
// Visualizations: cluster plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Instantiate a CNSeg object from the segment data using CNSeg. 2. Convert segments to a reduced segment matrix by region or gene us

nextflow.enable.dsl = 2

process BIOC_CNTOOLS_SEGMENTED_COPY_NUMBER_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20"

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
    .bm_deps <- c("CNTools", "genefilter")
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
    library(CNTools)
    library(genefilter)
    
    # Helper function to find and read input files from the working directory
    find_and_read <- function(base_name) {
      possible_files <- c(
        base_name,
        paste0(base_name, ".csv"),
        paste0(base_name, ".tsv"),
        paste0(base_name, ".txt")
      )
      for (f in possible_files) {
        if (file.exists(f)) {
          if (grepl("\\\\.csv\$", f)) {
            return(read.csv(f, header = TRUE, stringsAsFactors = FALSE))
          } else if (grepl("\\\\.(tsv|txt)\$", f)) {
            return(read.delim(f, header = TRUE, stringsAsFactors = FALSE))
          } else {
            try_read <- try(read.table(f, header = TRUE, stringsAsFactors = FALSE), silent = TRUE)
            if (!inherits(try_read, "try-error")) return(try_read)
          }
        }
      }
      stop(paste("Required input file not found in working directory:", base_name))
    }
    
    # Read user inputs
    sampleData <- find_and_read("sampleData")
    geneInfo <- find_and_read("geneInfo")
    
    # Ensure geneInfo is a matrix as required by CNTools
    geneInfo <- as.matrix(geneInfo)
    
    # 1. Instantiate a CNSeg object from the segment data using CNSeg
    # Robust sampling to handle cases where there are fewer than 20 unique IDs
    unique_ids <- unique(sampleData[, "ID"])
    sampled_ids <- sample(unique_ids, min(20, length(unique_ids)))
    cnseg <- CNSeg(sampleData[which(is.element(sampleData[, "ID"], sampled_ids)), ])
    
    # 2. Convert segments to a reduced segment matrix by region or gene using getRS
    rdseg <- getRS(cnseg, by = "region", imput = FALSE, XY = FALSE, what = "mean")
    
    # Robust sampling for geneInfo to handle cases where there are fewer than 2000 genes
    geneInfo <- geneInfo[sample(1:nrow(geneInfo), min(2000, nrow(geneInfo))), , drop = FALSE]
    rdByGene <- getRS(cnseg, by = "gene", imput = FALSE, XY = FALSE, geneMap = geneInfo, what = "median")
    
    # 3. Extract the reduced segment matrix using rs
    reducedseg <- rs(rdseg)
    reducedseg_gene <- rs(rdByGene)
    
    # Save extracted matrices
    write.csv(reducedseg, "reduced_segment_region.csv", row.names = TRUE)
    write.csv(reducedseg_gene, "reduced_segment_gene.csv", row.names = TRUE)
    
    # 4. Filter features using genefilter or madFilter
    f1 <- kOverA(5, 1)
    ffun <- filterfun(f1)
    filteredrs_gf <- genefilter(rdseg, ffun)
    
    # Save genefilter result
    write.csv(rs(filteredrs_gf), "filtered_segment_genefilter.csv", row.names = TRUE)
    
    filteredrs <- madFilter(rdseg, 0.8)
    
    # Save madFilter result
    write.csv(rs(filteredrs), "filtered_segment_madfilter.csv", row.names = TRUE)
    
    # 5. Calculate sample distances and perform hierarchical clustering using getDist and hclust
    hc <- hclust(getDist(filteredrs, method = "euclidian"), method = "complete") 
    
    # Save clustering object
    saveRDS(hc, "hierarchical_clustering.rds")
    
    # Plot and save dendrogram
    pdf("hierarchical_clustering_dendrogram.pdf", width = 10, height = 7)
    plot(hc, hang = -1, cex = 0.8, main = "Hierarchical Clustering of Samples", xlab = "")
    dev.off()

    writeLines(c(
        '"BIOC_CNTOOLS_SEGMENTED_COPY_NUMBER_ANALYSIS":',
        paste0('    CNTools: ', as.character(packageVersion('CNTools')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_segmented_copy_number_analysis.csv versions.yml
    """
}

workflow BIOC_CNTOOLS_SEGMENTED_COPY_NUMBER_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sampleData, geneInfo ] ]

    main:
    BIOC_CNTOOLS_SEGMENTED_COPY_NUMBER_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_CNTOOLS_SEGMENTED_COPY_NUMBER_ANALYSIS.out.tables
    plots    = BIOC_CNTOOLS_SEGMENTED_COPY_NUMBER_ANALYSIS.out.plots
    objects  = BIOC_CNTOOLS_SEGMENTED_COPY_NUMBER_ANALYSIS.out.objects
    versions = BIOC_CNTOOLS_SEGMENTED_COPY_NUMBER_ANALYSIS.out.versions
}
