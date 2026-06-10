#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: chipseeker — multi_dataset_comparison
// Compare genomic annotations, TSS distance distributions, and binding profiles across multiple ChIP-seq datasets.
// Input: files, txdb
// Container: quay.io/biocontainers/bioconductor-chipseeker:1.46.1--r45hdfd78af_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CHIPSEEKER_MULTI_DATASET_COMPARISON {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-chipseeker:1.46.1--r45hdfd78af_0"

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
    .bm_deps <- c("ChIPseeker", "GenomicFeatures", "TxDb.Hsapiens.UCSC.hg19.knownGene", "clusterProfiler")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    # Load required libraries
    library(ChIPseeker)
    library(GenomicFeatures)
    library(clusterProfiler)
    
    # ==========================================
    # 1. Read User Inputs from Working Directory
    # ==========================================
    
    # Read BED files from the working directory to construct the 'files' named list
    bed_files <- list.files(pattern = "\\.(bed|bed\\.gz)\$", ignore.case = TRUE, full.names = TRUE)
    if (length(bed_files) == 0) {
      stop("Error: No BED files (*.bed or *.bed.gz) found in the working directory.")
    }
    
    files <- as.list(bed_files)
    names(files) <- tools::file_path_sans_ext(basename(bed_files))
    # Clean up double extensions if present (e.g., sample.bed.gz -> sample)
    names(files) <- sub("\\.bed\$", "", names(files), ignore.case = TRUE)
    
    # Read the TxDb object from the working directory
    if (file.exists("txdb.rds")) {
      message("Loading TxDb object from txdb.rds...")
      txdb <- readRDS("txdb.rds")
    } else {
      message("txdb.rds not found in working directory. Attempting to load TxDb.Hsapiens.UCSC.hg19.knownGene as fallback...")
      if (!requireNamespace("TxDb.Hsapiens.UCSC.hg19.knownGene", quietly = TRUE)) {
        stop("Error: txdb.rds is missing and TxDb.Hsapiens.UCSC.hg19.knownGene fallback is not installed.")
      }
      library(TxDb.Hsapiens.UCSC.hg19.knownGene)
      txdb <- TxDb.Hsapiens.UCSC.hg19.knownGene
    }
    
    # ==========================================
    # 2. Construct tagMatrixList (Replacing Demo Data)
    # ==========================================
    message("Constructing tagMatrixList from input files and TxDb...")
    promoter <- getPromoters(TxDb=txdb, upstream=3000, downstream=3000)
    tagMatrixList <- lapply(files, getTagMatrix, windows=promoter)
    names(tagMatrixList) <- names(files)
    
    # Save tagMatrixList for downstream reference
    saveRDS(tagMatrixList, "tagMatrixList.rds")
    
    # ==========================================
    # 3. Run Documented Workflow & Save Outputs
    # ==========================================
    
    # Stage 1: Plot comparative average profiles
    message("Plotting comparative average profiles...")
    pdf("plotAvgProf_comparison.pdf", width=8, height=6)
    plotAvgProf(tagMatrixList, xlim=c(-3000, 3000))
    dev.off()
    
    # Stage 2: Plot comparative heatmaps
    message("Plotting comparative heatmaps...")
    pdf("tagHeatmap_comparison.pdf", width=12, height=8)
    tagHeatmap(tagMatrixList)
    dev.off()
    
    # Stage 3: Annotate multiple peak files
    message("Annotating peak files...")
    peakAnnoList <- lapply(files, annotatePeak, TxDb=txdb, tssRegion=c(-3000, 3000), verbose=FALSE)
    saveRDS(peakAnnoList, "peakAnnoList.rds")
    
    # Export individual annotations as CSV tables
    for (name in names(peakAnnoList)) {
      write.csv(as.data.frame(peakAnnoList[[name]]), file = paste0("peakAnno_", name, ".csv"), row.names = FALSE)
    }
    
    # Stage 4: Compare genomic annotations
    message("Comparing genomic annotations...")
    pdf("plotAnnoBar_comparison.pdf", width=10, height=6)
    print(plotAnnoBar(peakAnnoList))
    dev.off()
    
    # Stage 5: Compare TSS distance distributions
    message("Comparing TSS distance distributions...")
    pdf("plotDistToTSS_comparison.pdf", width=10, height=6)
    print(plotDistToTSS(peakAnnoList))
    dev.off()
    
    # Stage 6: Compare functional profiles
    message("Comparing functional profiles...")
    genes = lapply(peakAnnoList, function(i) as.data.frame(i)\$geneId)
    names(genes) = sub("_", "\n", names(genes))
    
    # Wrap compareCluster in tryCatch to handle potential KEGG API connection issues gracefully
    tryCatch({
      compKEGG <- compareCluster(geneCluster   = genes, fun           = "enrichKEGG", pvalueCutoff  = 0.05, pAdjustMethod = "BH")
      saveRDS(compKEGG, "compKEGG.rds")
      write.csv(as.data.frame(compKEGG), "compKEGG_results.csv", row.names = FALSE)
      
      pdf("dotplot_compKEGG.pdf", width=10, height=8)
      print(dotplot(compKEGG, showCategory = 15, title = "KEGG Pathway Enrichment Analysis"))
      dev.off()
    }, error = function(e) {
      warning("compareCluster or dotplot failed. This is common if there is no internet connection or if gene IDs do not match KEGG organism database. Error: ", e\$message)
    })
    
    # Stage 7: Visualize overlap of annotated genes
    message("Visualizing overlap of annotated genes...")
    pdf("vennplot_genes.pdf", width=8, height=8)
    vennplot(genes)
    dev.off()
    
    message("Pipeline completed successfully! All outputs have been saved to the working directory.")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_CHIPSEEKER_MULTI_DATASET_COMPARISON":
        chipseeker: \$(Rscript -e 'cat(as.character(packageVersion("chipseeker")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_multi_dataset_comparison.csv versions.yml
    """
}

workflow BIOC_CHIPSEEKER_MULTI_DATASET_COMPARISON_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ files, txdb ] ]

    main:
    BIOC_CHIPSEEKER_MULTI_DATASET_COMPARISON(ch_input)

    emit:
    tables   = BIOC_CHIPSEEKER_MULTI_DATASET_COMPARISON.out.tables
    plots    = BIOC_CHIPSEEKER_MULTI_DATASET_COMPARISON.out.plots
    objects  = BIOC_CHIPSEEKER_MULTI_DATASET_COMPARISON.out.objects
    versions = BIOC_CHIPSEEKER_MULTI_DATASET_COMPARISON.out.versions
}
