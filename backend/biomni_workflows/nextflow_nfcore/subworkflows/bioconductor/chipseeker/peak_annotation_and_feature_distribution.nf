#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ChIPseeker — peak_annotation_and_feature_distribution
// Annotate peaks with nearest genes and genomic features (promoter, exon, intron, etc.) and visualize their distributions.
// Input: files[[4]]
// Container: quay.io/biocontainers/bioconductor-chipseeker:1.46.1--r45hdfd78af_0
// R packages: ChIPseeker, TxDb.Hsapiens.UCSC.hg19.knownGene, org.Hs.eg.db
// Bioconductor: 3.20 | R: 4.4
// Requires: ChIPseeker, TxDb.Hsapiens.UCSC.hg19.knownGene, org.Hs.eg.db
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Annotate peaks using annotatePeak with a TxDb object
//  * 2. [Core Analysis] Convert annotation to a data frame or GRanges object
//  * 3. [Visualization & Output] Visualize genomic annotations using plotAnnoPie, plotAnnoBar, or vennpie
//  * 4. [Visualization & Output] Visualize distribution relative to TSS using plotDistToTSS
//  * 5. [Core Analysis] Link genomic regions to genes using seq2gene

nextflow.enable.dsl = 2

process BIOC_CHIPSEEKER_PEAK_ANNOTATION_AND_FEATURE_DISTRIBUTION {
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
    .bm_deps <- c("ChIPseeker", "TxDb.Hsapiens.UCSC.hg19.knownGene", "org.Hs.eg.db")
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
    library(TxDb.Hsapiens.UCSC.hg19.knownGene)
    library(org.Hs.eg.db)
    
    # Set up TxDb object
    txdb <- TxDb.Hsapiens.UCSC.hg19.knownGene
    
    # Identify the BED file in the working directory
    bed_files <- list.files(pattern = "\\\\.(bed|bed\\\\.gz)\$", ignore.case = TRUE)
    if (length(bed_files) == 0) {
      stop("Error: No BED file found in the working directory.")
    }
    
    # Construct the files list such that files[[4]] contains the BED file path
    files <- vector("list", 4)
    files[[4]] <- bed_files[1]
    
    # Read the peak file
    peak <- readPeakFile(files[[4]])
    
    # Stage 1: Annotate peaks using annotatePeak with a TxDb object
    peakAnno <- annotatePeak(files[[4]], tssRegion=c(-3000, 3000),
                             TxDb=txdb, annoDb="org.Hs.eg.db")
    
    # Stage 2: Convert annotation to a data frame and GRanges object, and save them
    peakAnno_df <- as.data.frame(peakAnno)
    write.csv(peakAnno_df, "peak_annotation_results.csv", row.names = FALSE)
    
    peakAnno_gr <- as.GRanges(peakAnno)
    saveRDS(peakAnno_gr, "peak_annotation_granges.rds")
    
    # Stage 3: Visualize genomic annotations using plotAnnoPie, plotAnnoBar, and vennpie
    pdf("genomic_annotation_plots.pdf", width = 10, height = 8)
    plotAnnoPie(peakAnno)
    print(plotAnnoBar(peakAnno))
    vennpie(peakAnno)
    dev.off()
    
    # Stage 4: Visualize distribution relative to TSS using plotDistToTSS
    pdf("distribution_to_tss_plot.pdf", width = 8, height = 4)
    print(plotDistToTSS(peakAnno,
                  title="Distribution of transcription factor-binding loci\nrelative to TSS"))
    dev.off()
    
    # Stage 5: Link genomic regions to genes using seq2gene
    gene <- seq2gene(peak, tssRegion = c(-1000, 1000), flankDistance = 3000, TxDb=txdb)
    
    # Save the linked genes output
    write.table(gene, "linked_genes.txt", row.names = FALSE, col.names = FALSE, quote = FALSE)

    writeLines(c(
        '"BIOC_CHIPSEEKER_PEAK_ANNOTATION_AND_FEATURE_DISTRIBUTION":',
        paste0('    ChIPseeker: ', as.character(packageVersion('ChIPseeker')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_peak_annotation_and_feature_distribution.csv versions.yml
    """
}

workflow BIOC_CHIPSEEKER_PEAK_ANNOTATION_AND_FEATURE_DISTRIBUTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ files[[4]] ] ]

    main:
    BIOC_CHIPSEEKER_PEAK_ANNOTATION_AND_FEATURE_DISTRIBUTION(ch_input)

    emit:
    tables   = BIOC_CHIPSEEKER_PEAK_ANNOTATION_AND_FEATURE_DISTRIBUTION.out.tables
    plots    = BIOC_CHIPSEEKER_PEAK_ANNOTATION_AND_FEATURE_DISTRIBUTION.out.plots
    objects  = BIOC_CHIPSEEKER_PEAK_ANNOTATION_AND_FEATURE_DISTRIBUTION.out.objects
    versions = BIOC_CHIPSEEKER_PEAK_ANNOTATION_AND_FEATURE_DISTRIBUTION.out.versions
}
