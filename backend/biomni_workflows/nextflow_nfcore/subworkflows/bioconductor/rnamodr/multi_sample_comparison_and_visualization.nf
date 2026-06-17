#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: RNAmodR — multi_sample_comparison_and_visualization
// Compare modification scores across multiple sample sets and visualize the results using heatmaps, transcript plots, and ROC curves.
// Input: RNAmodR.Data.example.AAS.gff3, RNAmodR.Data.example.AAS.fasta, Multiple BAM files grouped by sample set
// Container: quay.io/biocontainers/bioconductor-rnamodr:1.24.0--r45hdfd78af_0
// R packages: GenomicFeatures, RNAmodR, rtracklayer, txdbmaker
// Bioconductor: 3.20 | R: 4.4
// Requires: GenomicFeatures, RNAmodR, rtracklayer, txdbmaker
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load annotation and sequence files
//  * 2. [Input & Preparation] Define a named list of BAM files representing different sample sets
//  * 3. [Input & Preparation] Create a ModifierSet object (e.g., ModSetInosine)
//  * 4. [Core Analysis] Retrieve modifications and extract unique coordinates
//  * 5. [Core Analysis] Compare scores across sample sets at specific coordinates using compareByCoord()
//  * 6. [Input & Preparation] Create an alias data frame from a TxDb object
//  * 7. [Visualization & Output] Plot comparisons using plotCompareByCoord()
//  * 8. [Visualization & Output] Plot detailed transcript-level scores using plotData()
//  * 9. [Visualization & Output] Evaluate performance using plotROC()
//  * 10. [Input & Preparation] Retrieve read metadata statistics using stats()

nextflow.enable.dsl = 2

process BIOC_RNAMODR_MULTI_SAMPLE_COMPARISON_AND_VISUALIZATION {
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
    .bm_deps <- c("GenomicFeatures", "RNAmodR", "rtracklayer", "txdbmaker")
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
            library(RNAmodR)
            library(rtracklayer)
            library(GenomicFeatures)
            library(txdbmaker)
            
            # 1. Load annotation and sequence files from the working directory
            annotation_file <- "RNAmodR.Data.example.AAS.gff3"
            fasta_file <- "RNAmodR.Data.example.AAS.fasta"
            
            annotation <- GFF3File(annotation_file)
            sequences <- fasta_file
            
            # 2. Define a named list of BAM files representing different sample sets
            files <- list("SampleSet1" = c(treated = "wt_1.bam",
                                           treated = "wt_2.bam",
                                           treated = "wt_3.bam"),
                          "SampleSet2" = c(treated = "bud23_1.bam",
                                           treated = "bud23_2.bam"),
                          "SampleSet3" = c(treated = "trm8_1.bam",
                                           treated = "trm8_2.bam"))
            
            # 3. Create a ModifierSet object (ModSetInosine)
            msi <- ModSetInosine(files, annotation = annotation, sequences = sequences)
            saveRDS(msi, file = "msi_object.rds")
            
            # 4. Retrieve modifications and extract unique coordinates
            mod <- modifications(msi)
            saveRDS(mod, file = "modifications_genomic.rds")
            
            mod_pt <- modifications(msi, perTranscript = TRUE)
            saveRDS(mod_pt, file = "modifications_transcript.rds")
            
            # Reset to genomic coordinates for downstream comparison
            mod <- modifications(msi)
            coord <- unique(unlist(mod))
            coord\$score <- NULL
            coord\$sd <- NULL
            saveRDS(coord, file = "unique_coordinates.rds")
            
            # 5. Compare scores across sample sets at specific coordinates using compareByCoord()
            comparison <- compareByCoord(msi, coord)
            write.csv(as.data.frame(comparison), file = "comparison_by_coordinate.csv", row.names = FALSE)
            
            # 6. Create an alias data frame from a TxDb object
            txdb <- makeTxDbFromGFF(annotation)
            alias <- data.frame(tx_id = names(id2name(txdb)),
                                name = id2name(txdb))
            write.csv(alias, file = "transcript_aliases.csv", row.names = FALSE)
            
            # 7. Plot comparisons using plotCompareByCoord()
            pdf("plot_compare_by_coord.pdf")
            print(plotCompareByCoord(msi, coord, alias = alias))
            dev.off()
            
            pdf("plot_compare_by_coord_normalized.pdf")
            print(plotCompareByCoord(msi[c(3,1,2)], coord, alias = alias, normalize = "SampleSet3",
                               perTranscript = TRUE))
            dev.off()
            
            # 8. Plot detailed transcript-level scores using plotData()
            coord_pt <- unique(unlist(mod_pt))
            target_tx <- as.character(coord_pt\$Parent[1])
            target_pos <- start(coord_pt)[1]
            target_from <- max(1L, target_pos - 15L)
            target_to <- target_pos + 15L
            
            pdf(paste0("plot_data_transcript_", target_tx, ".pdf"))
            print(plotData(msi, target_tx, from = target_from, to = target_to, alias = alias))
            dev.off()
            
            pdf(paste0("plot_data_transcript_", target_tx, "_with_sequence.pdf"))
            print(plotData(msi[1:2], target_tx, from = target_from, to = target_to, showSequenceData = TRUE, alias = alias))
            dev.off()
            
            # 9. Evaluate performance using plotROC()
            pdf("plot_roc_curve.pdf")
            print(plotROC(msi, coord))
            dev.off()
            
            # 10. Retrieve read metadata statistics using stats()
            stats_data <- stats(msi)
            saveRDS(stats_data, file = "msi_statistics.rds")

    writeLines(c(
        '"BIOC_RNAMODR_MULTI_SAMPLE_COMPARISON_AND_VISUALIZATION":',
        paste0('    RNAmodR: ', as.character(packageVersion('RNAmodR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_multi_sample_comparison_and_visualization.csv versions.yml
    """
}

workflow BIOC_RNAMODR_MULTI_SAMPLE_COMPARISON_AND_VISUALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ RNAmodR.Data.example.AAS.gff3, RNAmodR.Data.example.AAS.fasta, Multiple BAM files grouped by sample set ] ]

    main:
    BIOC_RNAMODR_MULTI_SAMPLE_COMPARISON_AND_VISUALIZATION(ch_input)

    emit:
    tables   = BIOC_RNAMODR_MULTI_SAMPLE_COMPARISON_AND_VISUALIZATION.out.tables
    plots    = BIOC_RNAMODR_MULTI_SAMPLE_COMPARISON_AND_VISUALIZATION.out.plots
    objects  = BIOC_RNAMODR_MULTI_SAMPLE_COMPARISON_AND_VISUALIZATION.out.objects
    versions = BIOC_RNAMODR_MULTI_SAMPLE_COMPARISON_AND_VISUALIZATION.out.versions
}
