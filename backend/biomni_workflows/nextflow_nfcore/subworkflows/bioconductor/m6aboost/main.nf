#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: m6Aboost — m6a_prediction_from_miclip2
// Predict m6A sites from miCLIP2 peak calling results and signal bigWig files.
// Input: peak_calling_results.rds, truncation_positive.bw, truncation_negative.bw, C2T_positive.bw, C2T_negative.bw, annotation.gff3
// Container: quay.io/biocontainers/bioconductor-m6aboost:1.16.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: BSgenome.Mmusculus.UCSC.mm10, GenomicRanges, m6Aboost
// Visualizations: bar plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Assign truncation events to peaks using truncationAssignment
//  * 2. [Core Analysis] Assign C-to-T transitions to peaks using CtoTAssignment
//  * 3. [Core Analysis] Calculate mean truncation and C-to-T counts across replicates
//  * 4. [Core Analysis] Extract features using preparingData with the GFF3 annotation
//  * 5. [Core Analysis] Predict m6A sites using m6Aboost with a BSgenome package

nextflow.enable.dsl = 2

process BIOC_M6ABOOST_M6A_PREDICTION_FROM_MICLIP2 {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20"

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
        library(m6Aboost)
        library(GenomicRanges)
        library(BSgenome.Mmusculus.UCSC.mm10)
        
        # Define input file paths as specified by the user
        peaks_file <- "peak_calling_results.rds"
        truncation_pos <- "truncation_positive.bw"
        truncation_neg <- "truncation_negative.bw"
        c2t_pos <- "C2T_positive.bw"
        c2t_neg <- "C2T_negative.bw"
        annotation_gff <- "annotation.gff3"
        
        # Verify input files exist
        input_files <- c(peaks_file, truncation_pos, truncation_neg, c2t_pos, c2t_neg, annotation_gff)
        for (f in input_files) {
            if (!file.exists(f)) {
                stop(paste("Required input file missing:", f))
            }
        }
        
        # Read the input peaks (GRanges object)
        test <- readRDS(peaks_file)
        
        # 1. Assign truncation events to peaks using truncationAssignment
        test <- truncationAssignment(test, 
            bw_positive=truncation_pos,
            bw_negative=truncation_neg,
            sampleName = "WT1")
        
        # 2. Assign C-to-T transitions to peaks using CtoTAssignment
        test <- CtoTAssignment(test, 
            bw_positive=c2t_pos,
            bw_negative=c2t_neg,
            sampleName = "CtoT_WT1")
        
        # 3. Calculate mean truncation and C-to-T counts across replicates
        # Since we have a single replicate workflow from the input files,
        # the mean is equal to the single replicate values.
        test\$WTmean <- test\$WT1
        test\$CtoTmean <- test\$CtoT_WT1
        
        # 4. Extract features using preparingData with the GFF3 annotation
        test <- preparingData(test, annotation_gff, colname_reads="WTmean", 
            colname_C2T="CtoTmean")
        
        # 5. Predict m6A sites using m6Aboost with a BSgenome package
        out <- m6Aboost(test, "BSgenome.Mmusculus.UCSC.mm10", normalization = TRUE)
        
        # Save the results
        # Save GRanges object
        saveRDS(out, "m6Aboost_predictions.rds")
        
        # Save as CSV table
        out_df <- as.data.frame(out)
        write.csv(out_df, "m6Aboost_predictions.csv", row.names = FALSE)
        
        # Generate summary plot
        pdf("m6Aboost_prediction_summary.pdf")
        if ("class" %in% colnames(mcols(out))) {
            class_counts <- table(out\$class)
            barplot(class_counts, 
                    main="m6Aboost Prediction Results", 
                    col=c("salmon", "skyblue"), 
                    ylab="Number of Sites",
                    xlab="m6A Class")
        }
        dev.off()
        
        message("m6Aboost pipeline completed successfully. Outputs saved to 'm6Aboost_predictions.rds', 'm6Aboost_predictions.csv', and 'm6Aboost_prediction_summary.pdf'.")

    writeLines(c(
        '"BIOC_M6ABOOST_M6A_PREDICTION_FROM_MICLIP2":',
        paste0('    m6Aboost: ', as.character(packageVersion('m6Aboost')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_m6a_prediction_from_miclip2.csv versions.yml
    """
}

workflow BIOC_M6ABOOST_M6A_PREDICTION_FROM_MICLIP2_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ peak_calling_results.rds, truncation_positive.bw, truncation_negative.bw, C2T_positive.bw, C2T_negative.bw, annotation.gff3 ] ]

    main:
    BIOC_M6ABOOST_M6A_PREDICTION_FROM_MICLIP2(ch_input)

    emit:
    tables   = BIOC_M6ABOOST_M6A_PREDICTION_FROM_MICLIP2.out.tables
    plots    = BIOC_M6ABOOST_M6A_PREDICTION_FROM_MICLIP2.out.plots
    objects  = BIOC_M6ABOOST_M6A_PREDICTION_FROM_MICLIP2.out.objects
    versions = BIOC_M6ABOOST_M6A_PREDICTION_FROM_MICLIP2.out.versions
}
