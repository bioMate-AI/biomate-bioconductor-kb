#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: MGFM — marker_gene_detection
// Identify tissue- or cell-type-specific marker genes from normalized microarray expression data, with optional gene annotation.
// Input: expression_matrix.csv
// Container: quay.io/biocontainers/bioconductor-mgfm:1.44.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: MGFM, hgu133a.db
// Visualizations: cluster plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the MGFM package and the appropriate chip annotation database package
//  * 2. [Input & Preparation] Load the normalized gene expression matrix
//  * 3. [Core Analysis] Run getMarkerGenes() to identify marker genes, specifying whether to annotate probe sets and setting a specificity score cutoff
//  * 4. [Core Analysis] Inspect the resulting marker list for each sample type

nextflow.enable.dsl = 2

process BIOC_MGFM_MARKER_GENE_DETECTION {
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
    .bm_deps <- c("MGFM", "hgu133a.db")
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
    
    # 1. Load the MGFM package and the appropriate chip annotation database package.
    library("MGFM")
    require(hgu133a.db)
    
    # 2. Load the normalized gene expression matrix.
    # Read the user-provided expression matrix. Replicate samples must have the exact same column label.
    # check.names = FALSE is critical to preserve identical column names for replicates.
    expression_matrix <- read.csv("expression_matrix.csv", row.names = 1, check.names = FALSE)
    ds2.mat <- as.matrix(expression_matrix)
    
    # Optional: Generate hierarchical clustering plot of the samples as described in the vignette
    tryCatch({
      sample_dist <- dist(t(ds2.mat))
      sample_hc <- hclust(sample_dist, method = "average")
      pdf("sample_clustering_dendrogram.pdf", width = 8, height = 6)
      plot(sample_hc, main = "Hierarchical Clustering of Samples", xlab = "Samples", sub = "Method: Average Linkage, Distance: Euclidean")
      dev.off()
    }, error = function(e) {
      message("Could not generate clustering plot: ", e\$message)
    })
    
    # 3. Run getMarkerGenes() to identify marker genes, specifying whether to annotate probe sets and setting a specificity score cutoff.
    
    # Run 1: With annotation (using hgu133a chip mapping)
    # Wrapped in tryCatch in case the input probe IDs do not match the hgu133a platform.
    marker.list2 <- tryCatch({
      getMarkerGenes(ds2.mat, samples2compare="all", annotate=TRUE, chip="hgu133a", score.cutoff=1)
    }, error = function(e) {
      message("Annotated marker gene detection failed (likely due to probe ID mismatch with hgu133a): ", e\$message)
      NULL
    })
    
    # 4. Inspect the resulting marker list for each sample type and save outputs.
    if (!is.null(marker.list2)) {
      print("Names of annotated marker lists:")
      print(names(marker.list2))
      
      # Inspect the first 20 markers of liver (or the first available sample type)
      if ("liver_markers" %in% names(marker.list2)) {
        print("First 20 annotated liver markers:")
        print(marker.list2[["liver_markers"]][1:min(20, length(marker.list2[["liver_markers"]]))])
      } else if (length(marker.list2) > 0) {
        first_type <- names(marker.list2)[1]
        print(paste("First 20 annotated markers for", first_type, ":"))
        print(marker.list2[[first_type]][1:min(20, length(marker.list2[[first_type]]))])
      }
      
      # Save annotated results
      saveRDS(marker.list2, "marker_list_annotated.rds")
      
      # Export to CSV format
      max_len <- max(sapply(marker.list2, length))
      if (max_len > 0) {
        padded_list <- lapply(marker.list2, function(x) { length(x) <- max_len; x })
        write.csv(as.data.frame(padded_list, check.names = FALSE), "marker_list_annotated.csv", row.names = FALSE)
      }
    }
    
    # Run 2: Without annotation
    marker.list2 <- getMarkerGenes(ds2.mat, samples2compare="all", annotate=FALSE, score.cutoff=1)
    
    print("Names of unannotated marker lists:")
    print(names(marker.list2))
    
    # Inspect the first 20 markers of lung (or the first available sample type)
    if ("lung_markers" %in% names(marker.list2)) {
      print("First 20 unannotated lung markers:")
      print(marker.list2[["lung_markers"]][1:min(20, length(marker.list2[["lung_markers"]]))])
    } else if (length(marker.list2) > 0) {
      first_type <- names(marker.list2)[1]
      print(paste("First 20 unannotated markers for", first_type, ":"))
      print(marker.list2[[first_type]][1:min(20, length(marker.list2[[first_type]]))])
    }
    
    # Save unannotated results
    saveRDS(marker.list2, "marker_list_unannotated.rds")
    
    # Export to CSV format
    max_len_unannot <- max(sapply(marker.list2, length))
    if (max_len_unannot > 0) {
      padded_list_unannot <- lapply(marker.list2, function(x) { length(x) <- max_len_unannot; x })
      write.csv(as.data.frame(padded_list_unannot, check.names = FALSE), "marker_list_unannotated.csv", row.names = FALSE)
    }

    writeLines(c(
        '"BIOC_MGFM_MARKER_GENE_DETECTION":',
        paste0('    MGFM: ', as.character(packageVersion('MGFM')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_marker_gene_detection.csv versions.yml
    """
}

workflow BIOC_MGFM_MARKER_GENE_DETECTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ expression_matrix.csv ] ]

    main:
    BIOC_MGFM_MARKER_GENE_DETECTION(ch_input)

    emit:
    tables   = BIOC_MGFM_MARKER_GENE_DETECTION.out.tables
    plots    = BIOC_MGFM_MARKER_GENE_DETECTION.out.plots
    objects  = BIOC_MGFM_MARKER_GENE_DETECTION.out.objects
    versions = BIOC_MGFM_MARKER_GENE_DETECTION.out.versions
}
