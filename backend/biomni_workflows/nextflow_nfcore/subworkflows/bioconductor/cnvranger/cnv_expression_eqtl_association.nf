#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: CNVRanger — cnv_expression_eqtl_association
// Perform association testing between CNV regions and RNA-seq expression levels to identify dosage and neighborhood effects.
// Input: Silva16_PONE_CNV_calls.csv, counts_cleaned.txt
// Container: quay.io/biocontainers/bioconductor-cnvranger:1.26.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: AnnotationHub, CNVRanger, GenomeInfoDb, GenomicRanges, S4Vectors, SummarizedExperiment, ensembldb
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Prepare CNV calls as a GRangesList and summarize them
//  * 2. [Visualization & Output] Prepare RNA-seq counts as a RangedSummarizedExperiment
//  * 3. [Visualization & Output] Run cnvEQTL to test for expression differences
//  * 4. [Visualization & Output] Plot eQTL results

nextflow.enable.dsl = 2

process BIOC_CNVRANGER_CNV_EXPRESSION_EQTL_ASSOCIATION {
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
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
    
    # Load required libraries
    library(CNVRanger)
    library(GenomicRanges)
    library(AnnotationHub)
    library(ensembldb)
    
    # Define working directory as data directory
    data.dir <- "."
    
    # ----------------------------------------------------------------------
    # --- Prepare CNV calls as a GRangesList and summarize them ---
    # ----------------------------------------------------------------------
    
    # Read the user-provided CNV calls
    call.file <- file.path(data.dir, "Silva16_PONE_CNV_calls.csv")
    calls <- read.csv(call.file, as.is=TRUE)
    
    # Convert to GRangesList grouped by sample ID (NE_id)
    grl <- GenomicRanges::makeGRangesListFromDataFrame(
        calls, 
        split.field="NE_id", 
        keep.extra.columns=TRUE
    )
    grl <- GenomicRanges::sort(grl)
    
    # Summarize individual CNV calls into population-level CNV regions
    cnvrs <- populationRanges(grl, density=0.1)
    
    # Save summarized CNV regions
    write.csv(as.data.frame(cnvrs), "cnv_regions.csv", row.names=FALSE)
    
    
    # ----------------------------------------------------------------------
    # --- Prepare RNA-seq counts as a RangedSummarizedExperiment ---
    # ----------------------------------------------------------------------
    
    # Retrieve Bos taurus gene annotations from AnnotationHub
    ah <- AnnotationHub::AnnotationHub()
    ahDb <- AnnotationHub::query(ah, pattern = c("Bos taurus", "EnsDb"))
    
    # Safely fetch Ensembl 92 (AH60948) or fallback to the first available Bos taurus EnsDb
    ahEdb <- tryCatch({
        ahDb[["AH60948"]]
    }, error = function(e) {
        ens_idx <- grep("EnsDb", ahDb\$rdataclass)
        if (length(ens_idx) > 0) {
            ahDb[[names(ahDb)[ens_idx[1]]]]
        } else {
            stop("No EnsDb found for Bos taurus in AnnotationHub")
        }
    })
    
    bt.genes <- ensembldb::genes(ahEdb)
    GenomeInfoDb::seqlevelsStyle(bt.genes) <- "UCSC"
    
    # Restrict to chromosomes 1 and 2 and protein-coding genes
    sel.genes <- subset(bt.genes, seqnames %in% paste0("chr", 1:2))
    sel.genes <- subset(sel.genes, gene_biotype == "protein_coding")
    
    # Read RNA-seq read counts
    rseq.file <- file.path(data.dir, "counts_cleaned.txt")
    rcounts <- read.delim(rseq.file, row.names=1, stringsAsFactors=FALSE)
    rcounts <- as.matrix(rcounts)
    
    # Align rcounts with the selected genes to avoid subscript out of bounds
    common.genes <- intersect(rownames(rcounts), names(GenomicRanges::granges(sel.genes)))
    rcounts <- rcounts[common.genes, , drop=FALSE]
    
    # Construct the RangedSummarizedExperiment exactly as documented
    rranges <- GenomicRanges::granges(sel.genes)[rownames(rcounts)]
    rse <- SummarizedExperiment(assays=list(rcounts=rcounts), rowRanges=rranges)
    
    
    # ----------------------------------------------------------------------
    # --- Run cnvEQTL to test for expression differences ---
    # ----------------------------------------------------------------------
    
    # Run the association testing exactly as documented
    res <- cnvEQTL(cnvrs, grl, rse, window = "1Mbp", verbose = TRUE)
    
    # Save the eQTL results
    saveRDS(res, "eqtl_results.rds")
    
    # Save a flattened summary table of the eQTL results
    res_df <- as.data.frame(res)
    write.csv(res_df, "eqtl_results_summary.csv", row.names=FALSE)
    
    
    # ----------------------------------------------------------------------
    # --- Plot eQTL results ---
    # ----------------------------------------------------------------------
    
    # Find the first tested region with results to plot
    valid_idx <- which(S4Vectors::elementNROWS(res) > 0)
    if (length(valid_idx) > 0) {
        idx <- valid_idx[1]
        r_name <- names(res)[idx]
        r <- GenomicRanges::GRanges(r_name)
        
        pdf("eqtl_plot.pdf")
        tryCatch({
            # Plot using the Bos taurus assembly (bosTau6)
            plotEQTL(cnvr=r, genes=res[[idx]], genome="bosTau6", cn="CN1")
        }, error = function(e) {
            warning("Could not plot EQTL: ", e\$message)
        })
        dev.off()
    }

    writeLines(c(
        '"BIOC_CNVRANGER_CNV_EXPRESSION_EQTL_ASSOCIATION":',
        paste0('    CNVRanger: ', as.character(packageVersion('CNVRanger')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cnv_expression_eqtl_association.csv versions.yml
    """
}

workflow BIOC_CNVRANGER_CNV_EXPRESSION_EQTL_ASSOCIATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ Silva16_PONE_CNV_calls.csv, counts_cleaned.txt ] ]

    main:
    BIOC_CNVRANGER_CNV_EXPRESSION_EQTL_ASSOCIATION(ch_input)

    emit:
    tables   = BIOC_CNVRANGER_CNV_EXPRESSION_EQTL_ASSOCIATION.out.tables
    plots    = BIOC_CNVRANGER_CNV_EXPRESSION_EQTL_ASSOCIATION.out.plots
    objects  = BIOC_CNVRANGER_CNV_EXPRESSION_EQTL_ASSOCIATION.out.objects
    versions = BIOC_CNVRANGER_CNV_EXPRESSION_EQTL_ASSOCIATION.out.versions
}
