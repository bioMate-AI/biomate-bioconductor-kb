#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: splinter — alternative_splicing_validation
// Analyze alternative splicing events, simulate coding sequence changes, design PCR primers for validation, and visualize splicing coverage.
// Input: skipped_exons.txt, Mus_musculus.Ensembl.NCBIM37.65.partial.gtf, wt_chr14.bam, mt_chr14.bam
// Container: quay.io/biocontainers/bioconductor-splinter:1.36.0--r45hdfd78af_0
// R packages: BSgenome.Mmusculus.UCSC.mm9, GenomicFeatures, SPLINTER, txdbmaker
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SPLINTER_ALTERNATIVE_SPLICING_VALIDATION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-splinter:1.36.0--r45hdfd78af_0"

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
    .bm_deps <- c("BSgenome.Mmusculus.UCSC.mm9", "GenomicFeatures", "SPLINTER", "txdbmaker")
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
    library(SPLINTER)
    library(BSgenome.Mmusculus.UCSC.mm9)
    library(GenomicFeatures)
    library(txdbmaker)
    
    # Set up genome
    bsgenome <- BSgenome.Mmusculus.UCSC.mm9
    
    # Define input file paths (reading directly from the working directory)
    gtf_file <- "Mus_musculus.Ensembl.NCBIM37.65.partial.gtf"
    mats_file <- "skipped_exons.txt"
    wt <- "wt_chr14.bam"
    mt <- "mt_chr14.bam"
    
    # 1. Build TxDb from GTF and extract CDS and exon information
    txdb <- makeTxDbFromGFF(file=gtf_file, chrominfo = Seqinfo(genome="mm9"))
    thecds <- cdsBy(txdb, by="tx", use.names=TRUE)
    theexons <- exonsBy(txdb, by="tx", use.names=TRUE)
    
    # 2. Extract splicing events from MATS output
    typeofAS <- "SE"
    splice_data <- extractSpliceEvents(data=mats_file, filetype='mats', splicetype=typeofAS)
    
    # 3. Add Ensembl annotation to the splicing data
    splice_data <- addEnsemblAnnotation(data=splice_data, species="mmusculus")
    
    # Optional sorting as shown in the vignette
    splice_data\$data <- splice_data\$data[with(splice_data\$data, order(FDR, -IncLevelDifference)), ]
    
    # Save annotated splice events to CSV
    write.csv(splice_data\$data, "annotated_splice_events.csv", row.names=FALSE)
    
    # 4. Find valid transcripts and coding sequences for a target gene
    single_id <- 'Prmt5'
    pp <- which(grepl(single_id, splice_data\$data\$Symbol))
    single_record <- splice_data\$data[pp[1], ]
    
    valid_tx <- findTX(id=single_record\$ID, tx=theexons, db=txdb)
    valid_cds <- findTX(id=single_record\$ID, tx=thecds, db=txdb)
    
    # 5. Construct the Region of Interest (ROI)
    roi <- makeROI(single_record, type="SE")
    
    # 6. Find compatible transcripts containing the ROI
    compatible_tx <- findCompatibleEvents(valid_tx, roi=roi, verbose=TRUE)
    compatible_cds <- findCompatibleEvents(valid_cds, valid_tx, roi=roi, verbose=TRUE)
    
    # 7. Simulate splicing outcomes by removing or inserting regions
    region_minus_exon <- removeRegion(compatible_cds\$hits[[1]], roi)
    region_plus_exon <- insertRegion(region_minus_exon, roi)
    
    # 8. Compare sequence outcomes and predict translation changes
    event <- eventOutcomeCompare(seq1=compatible_cds\$hits[[1]], seq2=region_minus_exon,
                                 genome=bsgenome, direction=TRUE, fullseq=FALSE)
    
    # Save event outcome comparison
    saveRDS(event, "event_outcome_comparison.rds")
    
    # 9. Extract DNA sequence for the ROI
    aa <- getRegionDNA(roi, bsgenome)
    
    # 10. Design primers and check their genomic coverage
    primers <- data.frame(PRIMER_LEFT_SEQUENCE="ACTTTCGGACTCTGTGTGACT",
                          PRIMER_RIGHT_SEQUENCE="TCATAGGCATTGGGTGGAGG",
                          stringsAsFactors=FALSE)
    
    cp <- checkPrimer(primers[1,], bsgenome, roi)
    
    # 11. Predict PCR product sizes for the splicing isoforms
    pcr_result1 <- getPCRsizes(cp, theexons)
    tx_minus_exon <- removeRegion(compatible_tx\$hits[[1]], roi)
    pcr_result2 <- getPCRsizes(cp, tx_minus_exon)
    
    relevant_pcr_bands <- splitPCRhit(pcr_result1, compatible_tx)
    
    # Save PCR results
    write.csv(pcr_result1, "pcr_result_with_exon.csv", row.names=FALSE)
    write.csv(pcr_result2, "pcr_result_without_exon.csv", row.names=FALSE)
    saveRDS(relevant_pcr_bands, "relevant_pcr_bands.rds")
    
    # 12. Plot genomic coverage and PSI values
    pdf("splicing_validation_plots.pdf", width=10, height=8)
    eventPlot(transcripts=theexons, roi_plot=roi, bams=c(wt, mt), names=c('wt', 'mt'),
              annoLabel=single_id, rspan=2000)
    psiPlot(single_record)
    dev.off()

    writeLines(c(
        '"BIOC_SPLINTER_ALTERNATIVE_SPLICING_VALIDATION":',
        paste0('        splinter: ', as.character(packageVersion("splinter")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_alternative_splicing_validation.csv versions.yml
    """
}

workflow BIOC_SPLINTER_ALTERNATIVE_SPLICING_VALIDATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ skipped_exons.txt, Mus_musculus.Ensembl.NCBIM37.65.partial.gtf, wt_chr14.bam, mt_chr14.bam ] ]

    main:
    BIOC_SPLINTER_ALTERNATIVE_SPLICING_VALIDATION(ch_input)

    emit:
    tables   = BIOC_SPLINTER_ALTERNATIVE_SPLICING_VALIDATION.out.tables
    plots    = BIOC_SPLINTER_ALTERNATIVE_SPLICING_VALIDATION.out.plots
    objects  = BIOC_SPLINTER_ALTERNATIVE_SPLICING_VALIDATION.out.objects
    versions = BIOC_SPLINTER_ALTERNATIVE_SPLICING_VALIDATION.out.versions
}
