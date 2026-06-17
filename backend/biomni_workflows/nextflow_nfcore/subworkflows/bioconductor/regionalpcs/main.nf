#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: regionalpcs — regional_pc_summarization
// Summarize CpG-level DNA methylation data into regional principal components using genomic region annotations.
// Input: MsetEx.sub, TxDb.Hsapiens.UCSC.hg19.knownGene
// Container: quay.io/biocontainers/bioconductor-regionalpcs:1.8.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: AnnotationDbi, GenomicFeatures, GenomicRanges, dplyr, minfi, regionalpcs, tibble, tidyr
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the user-provided input files
//  * 2. [Input & Preparation] Extract methylation M-values from the MethylSet object
//  * 3. [Input & Preparation] Map methylation data to genomic coordinates and convert
//  * 4. [Input & Preparation] Extract target genomic regions (promoters) from the
//  * 5. [Input & Preparation] Create a region map associating CpG sites with the target
//  * 6. [Input & Preparation] Compute regional principal components using the
//  * 7. [Input & Preparation] Compute regional principal components using the
//  * 8. [Input & Preparation] Save meaningful results to output files

nextflow.enable.dsl = 2

process BIOC_REGIONALPCS_REGIONAL_PC_SUMMARIZATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-epigenomics:3.20-slim"

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
    .bm_deps <- c("regionalpcs", "GenomicRanges", "tidyr", "tibble", "dplyr", "minfi", "GenomicFeatures", "AnnotationDbi")
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
    library(regionalpcs)
    library(GenomicRanges)
    library(tidyr)
    library(tibble)
    library(dplyr)
    library(minfi)
    library(GenomicFeatures)
    library(AnnotationDbi)
    
    # Helper function to robustly load input files from the working directory
    load_input <- function(file_path) {
      if (!file.exists(file_path)) {
        stop(paste("Required input file missing:", file_path))
      }
      
      # Attempt to read as RDS first, then fallback to loadDb if it's a TxDb SQLite database
      obj <- tryCatch({
        readRDS(file_path)
      }, error = function(e) {
        tryCatch({
          AnnotationDbi::loadDb(file_path)
        }, error = function(e2) {
          stop(paste("Failed to load", file_path, "as RDS or TxDb database. Error:", e2\$message))
        })
      })
      return(obj)
    }
    
    # --- Load the user-provided input files ---
    MsetEx.sub <- load_input("MsetEx.sub")
    txdb <- load_input("TxDb.Hsapiens.UCSC.hg19.knownGene")
    
    # --- Extract methylation M-values from the MethylSet object ---
    mvals <- getM(MsetEx.sub)
    
    # --- Map methylation data to genomic coordinates and convert ---
    gset <- mapToGenome(MsetEx.sub)
    cpg_gr <- granges(gset)
    
    # --- Extract target genomic regions (promoters) from the ---
    promoters_gr <- suppressMessages(promoters(genes(txdb), 
                                               upstream=1000, 
                                               downstream=0))
    
    # --- Create a region map associating CpG sites with the target ---
    region_map <- regionalpcs::create_region_map(cpg_gr=cpg_gr, 
                                                 genes_gr=promoters_gr)
    
    # --- Compute regional principal components using the ---
    res <- compute_regional_pcs(meth=mvals, region_map=region_map, pc_method="gd")
    names(res)
    regional_pcs <- res\$regional_pcs
    
    # --- Compute regional principal components using the ---
    mp_res <- compute_regional_pcs(mvals, region_map, pc_method = "mp")
    mp_regional_pcs <- mp_res\$regional_pcs
    
    # --- Save meaningful results to output files ---
    # Save region map
    write.csv(region_map, "region_map.csv", row.names = FALSE)
    
    # Save Gavish-Donoho results
    write.csv(regional_pcs, "regional_pcs_gd.csv", row.names = TRUE)
    saveRDS(res, "regional_pcs_gd_results.rds")
    
    # Save Marcenko-Pasteur results
    write.csv(mp_regional_pcs, "regional_pcs_mp.csv", row.names = TRUE)
    saveRDS(mp_res, "regional_pcs_mp_results.rds")
    
    # Generate diagnostic plots of the first two regional PCs across samples
    pdf("regional_pcs_visualization.pdf", width = 12, height = 6)
    par(mfrow = c(1, 2))
    
    if (nrow(regional_pcs) >= 2) {
      plot(t(regional_pcs[1:2, ]), 
           main = "GD Regional PCs (First 2 Regions)", 
           xlab = rownames(regional_pcs)[1], 
           ylab = rownames(regional_pcs)[2],
           pch = 19, col = "blue")
      text(t(regional_pcs[1:2, ]), labels = colnames(regional_pcs), pos = 3, cex = 0.8)
    }
    
    if (nrow(mp_regional_pcs) >= 2) {
      plot(t(mp_regional_pcs[1:2, ]), 
           main = "MP Regional PCs (First 2 Regions)", 
           xlab = rownames(mp_regional_pcs)[1], 
           ylab = rownames(mp_regional_pcs)[2],
           pch = 19, col = "darkgreen")
      text(t(mp_regional_pcs[1:2, ]), labels = colnames(mp_regional_pcs), pos = 3, cex = 0.8)
    }
    
    dev.off()
    
    cat("Pipeline completed successfully. Outputs written to working directory.\n")

    writeLines(c(
        '"BIOC_REGIONALPCS_REGIONAL_PC_SUMMARIZATION":',
        paste0('    regionalpcs: ', as.character(packageVersion('regionalpcs')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_regional_pc_summarization.csv versions.yml
    """
}

workflow BIOC_REGIONALPCS_REGIONAL_PC_SUMMARIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ MsetEx.sub, TxDb.Hsapiens.UCSC.hg19.knownGene ] ]

    main:
    BIOC_REGIONALPCS_REGIONAL_PC_SUMMARIZATION(ch_input)

    emit:
    tables   = BIOC_REGIONALPCS_REGIONAL_PC_SUMMARIZATION.out.tables
    plots    = BIOC_REGIONALPCS_REGIONAL_PC_SUMMARIZATION.out.plots
    objects  = BIOC_REGIONALPCS_REGIONAL_PC_SUMMARIZATION.out.objects
    versions = BIOC_REGIONALPCS_REGIONAL_PC_SUMMARIZATION.out.versions
}
