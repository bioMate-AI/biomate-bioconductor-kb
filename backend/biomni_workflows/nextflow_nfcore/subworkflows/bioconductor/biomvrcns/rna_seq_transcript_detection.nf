#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: biomvRCNS — rna_seq_transcript_detection
// Detect expressed transcripts (exons, introns, and intergenic regions) from RNA-seq read count data using gene annotations as priors.
// Input: encodeTP53.RData, TxDb.Hsapiens.UCSC.hg19.knownGene
// Container: quay.io/biocontainers/bioconductor-biomvrcns:1.50.0--r45h01b2380_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: TxDb.Hsapiens.UCSC.hg19.knownGene, biomvRCNS
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load and pool replicate read counts for different cell types
//  * 2. [Core Analysis] Run biomvRhsmm with a TxDb annotation object to automatically estimate state number and sojourn parameters
//  * 3. [Core Analysis] Extract detected exon segments
//  * 4. [Visualization & Output] Plot the expression and estimated segments against gene annotations using biomvRGviz
//  * 5. [Core Analysis] Identify novel transcribed regions by overlapping results with annotations

nextflow.enable.dsl = 2

process BIOC_BIOMVRCNS_RNA_SEQ_TRANSCRIPT_DETECTION {
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
    .bm_deps <- c("biomvRCNS", "TxDb.Hsapiens.UCSC.hg19.knownGene")
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
    library(biomvRCNS)
    library(TxDb.Hsapiens.UCSC.hg19.knownGene)
    
    # 1. Load and pool replicate read counts for different cell types
    # Read the pre-compiled GRanges object from the working directory
    load("encodeTP53.RData")
    cgr <- encodeTP53\$cgr
    gmgr <- encodeTP53\$gmgr
    
    mcols(cgr) <- DataFrame(
    	Gm12878=1+rowSums(as.matrix(mcols(cgr)[,1:2])), 
    	K562=1+rowSums(as.matrix(mcols(cgr)[,3:4])) )
    
    # 2. Run biomvRhsmm with a TxDb annotation object to automatically estimate state number and sojourn parameters
    txdb <- TxDb.Hsapiens.UCSC.hg19.knownGene	
    rhsmm <- biomvRhsmm(x=cgr, xAnno=txdb, maxbp=1E3, soj.type='gamma', 
    	emis.type='pois', prior.m='quantile', q.alpha=0.01)
    
    # Save the fitted model object
    saveRDS(rhsmm, "rhsmm_model.rds")
    
    # 3. Extract detected exon segments
    detected_exons <- rhsmm@res[mcols(rhsmm@res)[,'STATE']=='exon']
    write.csv(as.data.frame(detected_exons), "detected_exons.csv", row.names=FALSE)
    
    # 4. Plot the expression and estimated segments against gene annotations using biomvRGviz
    g <- mcols(rhsmm@res)[,'STATE']=='exon' & mcols(rhsmm@res)[,'SAMPLE']=='Gm12878'
    pdf("plot_Gm12878.pdf", width=10, height=8)
    obj <- biomvRGviz(exprgr=cgr[,'Gm12878'], gmgr=gmgr, 
    	seggr=rhsmm@res[g], plotstrand='-', regionID='TP53', tofile=FALSE)
    dev.off()
    
    k <- mcols(rhsmm@res)[,'STATE']=='exon' & mcols(rhsmm@res)[,'SAMPLE']=='K562'
    pdf("plot_K562.pdf", width=10, height=8)
    obj <- biomvRGviz(exprgr=cgr[,'K562'], gmgr=gmgr, 
      seggr=rhsmm@res[k], plotstrand='-', regionID='TP53', tofile=FALSE)
    dev.off()
    
    # 5. Identify novel transcribed regions by overlapping results with annotations
    nK2gm <- queryHits(findOverlaps(rhsmm@res[k], gmgr))
    nK2G <- queryHits(findOverlaps(rhsmm@res[k], rhsmm@res[g]))
    novel_regions <- rhsmm@res[k][setdiff(seq_len(sum(k)), unique(c(nK2G, nK2gm)))]
    write.csv(as.data.frame(novel_regions), "novel_regions_K562.csv", row.names=FALSE)
    
    # 6. Run alternative segmentation methods
    rseg <- biomvRseg(x=cgr, maxbp=1E3, maxseg=20, family='pois')
    saveRDS(rseg, "rseg_model.rds")
    write.csv(as.data.frame(rseg@res), "rseg_segments.csv", row.names=FALSE)
    
    rmgmr <- biomvRmgmr(x=cgr, q=0.99, maxgap=50, minrun=100)
    saveRDS(rmgmr, "rmgmr_model.rds")
    write.csv(as.data.frame(rmgmr@res), "rmgmr_segments.csv", row.names=FALSE)

    writeLines(c(
        '"BIOC_BIOMVRCNS_RNA_SEQ_TRANSCRIPT_DETECTION":',
        paste0('    biomvRCNS: ', as.character(packageVersion('biomvRCNS')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rna_seq_transcript_detection.csv versions.yml
    """
}

workflow BIOC_BIOMVRCNS_RNA_SEQ_TRANSCRIPT_DETECTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ encodeTP53.RData, TxDb.Hsapiens.UCSC.hg19.knownGene ] ]

    main:
    BIOC_BIOMVRCNS_RNA_SEQ_TRANSCRIPT_DETECTION(ch_input)

    emit:
    tables   = BIOC_BIOMVRCNS_RNA_SEQ_TRANSCRIPT_DETECTION.out.tables
    plots    = BIOC_BIOMVRCNS_RNA_SEQ_TRANSCRIPT_DETECTION.out.plots
    objects  = BIOC_BIOMVRCNS_RNA_SEQ_TRANSCRIPT_DETECTION.out.objects
    versions = BIOC_BIOMVRCNS_RNA_SEQ_TRANSCRIPT_DETECTION.out.versions
}
