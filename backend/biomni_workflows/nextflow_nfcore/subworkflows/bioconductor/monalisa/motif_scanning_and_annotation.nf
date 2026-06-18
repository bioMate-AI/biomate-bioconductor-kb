#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: monaLisa — motif_scanning_and_annotation
// Scan genomic sequences to predict and annotate transcription factor motif hits.
// Input: TxDb.Mmusculus.UCSC.mm10.knownGene, BSgenome.Mmusculus.UCSC.mm10, JASPAR2020
// Container: quay.io/biocontainers/bioconductor-monalisa:1.16.0--r45hdfd78af_0
// R packages: BSgenome.Mmusculus.UCSC.mm10, BiocParallel, GenomicFeatures, GenomicRanges, JASPAR2020, TFBSTools, TxDb.Mmusculus.UCSC.mm10.knownGene, monaLisa
// Bioconductor: 3.20 | R: 4.4
// Requires: BSgenome.Mmusculus.UCSC.mm10, BiocParallel, GenomicFeatures, GenomicRanges, TFBSTools, TxDb.Mmusculus.UCSC.mm10.knownGene, monaLisa
// Visualizations: heatmap
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Extract promoter sequences using getSeq()
//  * 2. [Core Analysis] Predict motif hits in sequences using findMotifHits()
//  * 3. [Input & Preparation] Create a motif hit matrix (counts of each motif per sequence) using table()

nextflow.enable.dsl = 2

process BIOC_MONALISA_MOTIF_SCANNING_AND_ANNOTATION {
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
    .bm_deps <- c("BSgenome.Mmusculus.UCSC.mm10", "BiocParallel", "GenomicFeatures", "GenomicRanges", "JASPAR2020", "TFBSTools", "TxDb.Mmusculus.UCSC.mm10.knownGene", "monaLisa")
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
    library(TxDb.Mmusculus.UCSC.mm10.knownGene)
    library(BSgenome.Mmusculus.UCSC.mm10)
    library(JASPAR2020)
    library(TFBSTools)
    library(monaLisa)
    library(BiocParallel)
    library(GenomicFeatures)
    library(GenomicRanges)
    
    # 1. Extract promoter coordinates and prepare GRanges object
    # We use the TxDb object to get promoter regions for a subset of genes
    gr <- trim(promoters(TxDb.Mmusculus.UCSC.mm10.knownGene, upstream = 1000, downstream = 500)[c(1, 4, 5, 10)])
    
    # 2. Prepare the motif PWMs from JASPAR2020
    # We select a representative set of vertebrate motifs
    pfms <- getMatrixByID(JASPAR2020, c("MA0885.1", "MA0099.3", "MA0033.2", "MA0037.3", "MA0158.1"))
    pwms <- toPWM(pfms)
    
    # 3. Extract promoter sequences (Documented Stage 1)
    seqs <- getSeq(BSgenome.Mmusculus.UCSC.mm10, gr)
    
    # 4. Predict motif hits in sequences (Documented Stage 2)
    res <- findMotifHits(query = pwms,
                         subject = seqs,
                         min.score = 6.0,
                         method = "matchPWM",
                         BPPARAM = BiocParallel::SerialParam())
    
    # 5. Create a motif hit matrix (Documented Stage 3)
    m <- table(factor(seqnames(res), levels = names(seqs)),
               factor(res\$pwmname, levels = name(pwms)))
    
    # 6. Write outputs to files
    # Save the raw motif hits GRanges object
    saveRDS(res, "motif_hits.rds")
    
    # Save the motif hit matrix as a CSV table
    write.csv(as.data.frame.matrix(m), "motif_hit_matrix.csv", row.names = TRUE)
    
    # Generate a PDF heatmap of the motif hit matrix
    pdf("motif_hit_heatmap.pdf", width = 8, height = 6)
    heatmap(as.matrix(m), 
            Colv = NA, 
            Rowv = NA, 
            scale = "none",
            col = hcl.colors(12, "YlOrRd", rev = TRUE), 
            margins = c(10, 10),
            main = "Motif Hits per Promoter Sequence",
            xlab = "Motifs",
            ylab = "Promoter Sequences")
    dev.off()

    writeLines(c(
        '"BIOC_MONALISA_MOTIF_SCANNING_AND_ANNOTATION":',
        paste0('    monaLisa: ', as.character(packageVersion('monaLisa')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_motif_scanning_and_annotation.csv versions.yml
    """
}

workflow BIOC_MONALISA_MOTIF_SCANNING_AND_ANNOTATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ TxDb.Mmusculus.UCSC.mm10.knownGene, BSgenome.Mmusculus.UCSC.mm10, JASPAR2020 ] ]

    main:
    BIOC_MONALISA_MOTIF_SCANNING_AND_ANNOTATION(ch_input)

    emit:
    tables   = BIOC_MONALISA_MOTIF_SCANNING_AND_ANNOTATION.out.tables
    plots    = BIOC_MONALISA_MOTIF_SCANNING_AND_ANNOTATION.out.plots
    objects  = BIOC_MONALISA_MOTIF_SCANNING_AND_ANNOTATION.out.objects
    versions = BIOC_MONALISA_MOTIF_SCANNING_AND_ANNOTATION.out.versions
}
