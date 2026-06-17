#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: chipseeker — peak_annotation_and_enrichment
// Annotate peaks with genomic features and nearest genes, visualize annotation distributions, and perform functional enrichment analysis.
// Input: files[[4]], txdb
// Container: quay.io/biocontainers/bioconductor-chipseeker:1.46.1--r45hdfd78af_0
// R packages: ChIPseeker, GenomicFeatures, ReactomePA, clusterProfiler, org.Hs.eg.db
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CHIPSEEKER_PEAK_ANNOTATION_AND_ENRICHMENT {
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
    .bm_deps <- c("ChIPseeker", "GenomicFeatures", "ReactomePA", "clusterProfiler", "org.Hs.eg.db")
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
    library(ChIPseeker)
    library(GenomicFeatures)
    library(ReactomePA)
    library(org.Hs.eg.db)
    library(clusterProfiler)
    
    # --- Read User Inputs ---
    # The pipeline expects "files_4.bed" (BED file of ChIP-seq peaks)
    # and "txdb.rds" (serialized TxDb object) in the working directory.
    if (!file.exists("files_4.bed")) {
      stop("Error: Input BED file 'files_4.bed' not found in the working directory.")
    }
    if (!file.exists("txdb.rds")) {
      stop("Error: Input TxDb RDS file 'txdb.rds' not found in the working directory.")
    }
    
    files <- list()
    files[[4]] <- "files_4.bed"
    
    txdb <- readRDS("txdb.rds")
    
    # Read peak file for downstream seq2gene analysis
    peak <- readPeakFile(files[[4]])
    
    # --- Annotate peaks with genomic features and nearest genes ---
    message("Annotating peaks...")
    peakAnno <- annotatePeak(files[[4]], tssRegion=c(-3000, 3000), TxDb=txdb, annoDb="org.Hs.eg.db")
    
    # Save annotation results
    saveRDS(peakAnno, "peakAnno.rds")
    write.csv(as.data.frame(peakAnno), "peakAnno.csv", row.names = FALSE)
    
    # --- Visualize genomic annotations ---
    message("Generating genomic annotation plots...")
    pdf("plotAnnoPie.pdf", width = 8, height = 6)
    plotAnnoPie(peakAnno)
    dev.off()
    
    pdf("plotAnnoBar.pdf", width = 8, height = 6)
    plotAnnoBar(peakAnno)
    dev.off()
    
    pdf("vennpie.pdf", width = 8, height = 6)
    vennpie(peakAnno)
    dev.off()
    
    # --- Visualize distance to TSS ---
    message("Generating distance to TSS plot...")
    pdf("plotDistToTSS.pdf", width = 8, height = 6)
    plotDistToTSS(peakAnno, title="Distribution of transcription factor-binding loci\nrelative to TSS")
    dev.off()
    
    # --- Pathway enrichment analysis (Reactome) on nearest genes ---
    message("Performing pathway enrichment on nearest genes...")
    pathway1 <- tryCatch({
      p1 <- enrichPathway(as.data.frame(peakAnno)\$geneId)
      if (!is.null(p1)) {
        write.csv(as.data.frame(p1), "pathway1_enrichment.csv", row.names = FALSE)
        saveRDS(p1, "pathway1.rds")
        print(head(pathway1, 2))
      }
      p1
    }, error = function(e) {
      warning("Pathway 1 enrichment failed or returned no results: ", e\$message)
      NULL
    })
    
    # --- Link genomic regions to genes using seq2gene ---
    message("Linking genomic regions to genes using seq2gene...")
    gene <- seq2gene(peak, tssRegion = c(-1000, 1000), flankDistance = 3000, TxDb=txdb)
    saveRDS(gene, "seq2gene_genes.rds")
    
    # --- Pathway enrichment analysis on seq2gene linked genes ---
    message("Performing pathway enrichment on seq2gene linked genes...")
    pathway2 <- tryCatch({
      p2 <- enrichPathway(gene)
      if (!is.null(p2)) {
        write.csv(as.data.frame(p2), "pathway2_enrichment.csv", row.names = FALSE)
        saveRDS(p2, "pathway2.rds")
        print(head(pathway2, 2))
        
        # Plot dotplot of pathway2
        pdf("dotplot_pathway2.pdf", width = 8, height = 6)
        print(dotplot(p2))
        dev.off()
      }
      p2
    }, error = function(e) {
      warning("Pathway 2 enrichment failed or returned no results: ", e\$message)
      NULL
    })
    
    message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_CHIPSEEKER_PEAK_ANNOTATION_AND_ENRICHMENT":',
        paste0('        chipseeker: ', as.character(packageVersion("chipseeker")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_peak_annotation_and_enrichment.csv versions.yml
    """
}

workflow BIOC_CHIPSEEKER_PEAK_ANNOTATION_AND_ENRICHMENT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ files[[4]], txdb ] ]

    main:
    BIOC_CHIPSEEKER_PEAK_ANNOTATION_AND_ENRICHMENT(ch_input)

    emit:
    tables   = BIOC_CHIPSEEKER_PEAK_ANNOTATION_AND_ENRICHMENT.out.tables
    plots    = BIOC_CHIPSEEKER_PEAK_ANNOTATION_AND_ENRICHMENT.out.plots
    objects  = BIOC_CHIPSEEKER_PEAK_ANNOTATION_AND_ENRICHMENT.out.objects
    versions = BIOC_CHIPSEEKER_PEAK_ANNOTATION_AND_ENRICHMENT.out.versions
}
