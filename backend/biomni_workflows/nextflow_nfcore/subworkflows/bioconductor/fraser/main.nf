#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: FRASER — aberrant_splicing_from_bam
// Detect rare aberrant splicing events starting from raw RNA-seq BAM files.
// Input: sampleTable.tsv, *.bam
// Container: quay.io/biocontainers/bioconductor-fraser:2.6.0--r45ha27e39d_0
// R packages: TxDb.Hsapiens.UCSC.hg19.knownGene, BiocParallel, data.table, FRASER, org.Hs.eg.db
// Bioconductor: 3.20 | R: 4.4
// Requires: BiocParallel, FRASER, TxDb.Hsapiens.UCSC.hg19.knownGene, data.table, org.Hs.eg.db
// Visualizations: volcano plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Create a FraserDataSet settings object from the sample
//  * 2. [Visualization & Output] Count split and non-split reads from BAM files using
//  * 3. [Visualization & Output] Calculate Percent Spliced In (PSI) and Jaccard values
//  * 4. [Visualization & Output] Filter out lowly expressed and low-variability junctions
//  * 5. [Visualization & Output] Annotate genomic ranges with gene symbols using
//  * 6. [Visualization & Output] Fit the splicing autoencoder model and calculate p-values
//  * 7. [Visualization & Output] Extract significant splicing outliers using results
//  * 8. [Visualization & Output] Visualize results using plotVolcano

nextflow.enable.dsl = 2

process BIOC_FRASER_ABERRANT_SPLICING_FROM_BAM {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

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
    .bm_deps <- c("TxDb.Hsapiens.UCSC.hg19.knownGene", "BiocParallel", "data.table", "FRASER", "org.Hs.eg.db", "SummarizedExperiment")
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
     
    library(SummarizedExperiment)
   
    library(FRASER)
    library(data.table)
    library(BiocParallel)
    library(TxDb.Hsapiens.UCSC.hg19.knownGene)
    library(org.Hs.eg.db)
    
    # Set parallel backend to serial for stability
    register(SerialParam())
    
    # --- Create a FraserDataSet settings object from the sample ---
    # Read the user-provided sample table
    sampleTable <- fread("sampleTable.tsv")
    
    # Verify that the BAM files specified in the sample table exist in the working directory
    missing_bams <- sampleTable[!file.exists(bamFile), bamFile]
    if(length(missing_bams) > 0) {
      stop("The following BAM files specified in sampleTable.tsv were not found: ", 
           paste(missing_bams, collapse=", "))
    }
    
    # Create FRASER object
    fds <- FraserDataSet(colData=sampleTable, workingDir="FRASER_output")
    
    # --- Count split and non-split reads from BAM files using ---
    fds <- countRNAData(fds)
    
    # --- Calculate Percent Spliced In (PSI) and Jaccard values ---
    fds <- calculatePSIValues(fds)
    
    # --- Filter out lowly expressed and low-variability junctions ---
    fds <- filterExpressionAndVariability(fds, minExpressionInOneSample=20,
           minDeltaPsi=0.0, filter=TRUE)
    
    # --- Annotate genomic ranges with gene symbols using ---
    txdb <- TxDb.Hsapiens.UCSC.hg19.knownGene
    orgDb <- org.Hs.eg.db
    fds <- annotateRangesWithTxDb(fds, txdb=txdb, orgDb=orgDb)
    
    # --- Fit the splicing autoencoder model and calculate p-values ---
    fds <- FRASER(fds, q=c(jaccard=2))
    
    # --- Extract significant splicing outliers using results ---
    res <- results(fds, all=TRUE)
    
    # Save results table to a TSV file
    write.table(as.data.frame(res), file="fraser_results.tsv", sep="\t", quote=FALSE, row.names=FALSE)
    
    # --- Visualize results using plotVolcano ---
    # Dynamically select the first sample ID from the dataset to avoid hardcoding
    sample_id <- as.character(colData(fds)\$sampleID[1])
    
    pdf("volcano_plot.pdf", width=7, height=7)
    plotVolcano(fds, sampleID=sample_id, type="jaccard", aggregate=TRUE)
    dev.off()
    
    # Save the FraserDataSet object for downstream analysis
    saveFraserDataSet(fds, dir="FRASER_output", name="SplicingAnalysis")

    writeLines(c(
        '"BIOC_FRASER_ABERRANT_SPLICING_FROM_BAM":',
        paste0('    FRASER: ', as.character(packageVersion('FRASER')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_aberrant_splicing_from_bam.csv versions.yml
    """
}

workflow BIOC_FRASER_ABERRANT_SPLICING_FROM_BAM_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sampleTable.tsv, *.bam ] ]

    main:
    BIOC_FRASER_ABERRANT_SPLICING_FROM_BAM(ch_input)

    emit:
    tables   = BIOC_FRASER_ABERRANT_SPLICING_FROM_BAM.out.tables
    plots    = BIOC_FRASER_ABERRANT_SPLICING_FROM_BAM.out.plots
    objects  = BIOC_FRASER_ABERRANT_SPLICING_FROM_BAM.out.objects
    versions = BIOC_FRASER_ABERRANT_SPLICING_FROM_BAM.out.versions
}
