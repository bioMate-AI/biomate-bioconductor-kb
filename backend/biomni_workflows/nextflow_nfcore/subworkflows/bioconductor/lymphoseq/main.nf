#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: LymphoSeq — tcr_bcr_repertoire_analysis
// Import, clean, and analyze T and B cell receptor sequencing data to characterize repertoire diversity, compare samples, and track clones.
// Input: sample_folder/, metadata.csv
// Container: quay.io/biocontainers/bioconductor-lymphoseq:1.38.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: LymphoSeq, RColorBrewer, ggplot2, pheatmap, reshape, wordcloud
// Visualizations: heatmap, bar plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Import ImmunoSEQ files using readImmunoSeq
//  * 2. [Visualization & Output] Subset samples using metadata if necessary
//  * 3. [Visualization & Output] Extract productive sequences and aggregate
//  * 4. [Visualization & Output] Calculate repertoire diversity metrics and visualize
//  * 5. [Visualization & Output] Calculate clonal relatedness and visualize sequence
//  * 6. [Visualization & Output] Perform multiple sequence alignment
//  * 7. [Visualization & Output] Search for specific sequences
//  * 8. [Visualization & Output] Compare samples pairwise
//  * 9. [Visualization & Output] Identify differentially abundant sequences
//  * 10. [Visualization & Output] Find recurring sequences
//  * 11. [Visualization & Output] Track sequences across samples
//  * 12. [Visualization & Output] Analyze V(D)J gene usage and visualize
//  * 13. [Visualization & Output] Remove contamination sequences
//  * 14. [Visualization & Output] Merge samples

nextflow.enable.dsl = 2

process BIOC_LYMPHOSEQ_TCR_BCR_REPERTOIRE_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20"

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
    .bm_deps <- c("LymphoSeq", "RColorBrewer", "wordcloud", "reshape", "pheatmap", "ggplot2")
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
            library(LymphoSeq)
            library(RColorBrewer)
            library(grDevices)
            library(wordcloud)
            library(reshape)
            library(pheatmap)
            library(ggplot2)
            
            # -----------------------------------------------------------------------------
            # --- Import ImmunoSEQ files using readImmunoSeq ---
            # -----------------------------------------------------------------------------
            TCRB.path <- "sample_folder"
            
            if (!dir.exists(TCRB.path)) {
              stop("Error: 'sample_folder' directory does not exist in the working directory.")
            }
            
            tsv_files <- list.files(TCRB.path, pattern = "\\\\.tsv\$", ignore.case = TRUE)
            if (length(tsv_files) == 0) {
              stop("Error: No .tsv files found in 'sample_folder'. Please ensure ImmunoSEQ v2 files are present.")
            }
            
            # Read the ImmunoSEQ files
            TCRB.list <- readImmunoSeq(path = TCRB.path)
            
            # Dynamically assign sample names based on the user's data
            sample_names <- names(TCRB.list)
            sample1 <- sample_names[1]
            sample2 <- if(length(sample_names) > 1) sample_names[2] else sample_names[1]
            sample3 <- if(length(sample_names) > 2) sample_names[3] else sample_names[1]
            
            names(TCRB.list)
            
            lapply(TCRB.list, dim)
            
            head(TCRB.list[[sample1]])
            
            # -----------------------------------------------------------------------------
            # --- Subset samples using metadata if necessary ---
            # -----------------------------------------------------------------------------
            if (file.exists("metadata.csv")) {
              TCRB.metadata <- read.csv("metadata.csv")
              # Ensure required columns exist for the vignette code to run
              if (!all(c("phenotype", "day", "samples") %in% colnames(TCRB.metadata))) {
                TCRB.metadata <- data.frame(
                  samples = names(TCRB.list),
                  phenotype = "Unsorted",
                  day = 365,
                  stringsAsFactors = FALSE
                )
              }
            } else {
              TCRB.metadata <- data.frame(
                samples = names(TCRB.list),
                phenotype = "Unsorted",
                day = 365,
                stringsAsFactors = FALSE
              )
            }
            
            TCRB.metadata
            selected <- as.character(TCRB.metadata[TCRB.metadata\$phenotype == "Unsorted" & 
                                             TCRB.metadata\$day > 300, "samples"])
            if (length(selected) == 0) selected <- names(TCRB.list)
            TCRB.list.selected <- TCRB.list[selected]
            names(TCRB.list.selected)
            
            # Update sample names based on the selected subset
            sample_names <- names(TCRB.list.selected)
            sample1 <- sample_names[1]
            sample2 <- if(length(sample_names) > 1) sample_names[2] else sample_names[1]
            sample3 <- if(length(sample_names) > 2) sample_names[3] else sample_names[1]
            
            # -----------------------------------------------------------------------------
            # --- Extract productive sequences and aggregate ---
            # -----------------------------------------------------------------------------
            productive.TRB.aa <- productiveSeq(file.list = TCRB.list.selected, aggregate = "aminoAcid", 
                                           prevalence = FALSE)
            
            productive.TRB.nt <- productiveSeq(file.list = TCRB.list.selected, aggregate = "nucleotide", 
                                           prevalence = FALSE)
            
            head(TCRB.list.selected[[sample1]])
            
            head(productive.TRB.aa[[sample1]])
            
            head(productive.TRB.nt[[sample1]])
            
            # -----------------------------------------------------------------------------
            # --- Calculate repertoire diversity metrics and visualize ---
            # -----------------------------------------------------------------------------
            clonality_results <- clonality(file.list = TCRB.list.selected)
            write.csv(clonality_results, "clonality_report.csv", row.names = FALSE)
            
            pdf("lorenz_curve.pdf", width = 7, height = 7)
            print(lorenzCurve(samples = names(productive.TRB.aa), list = productive.TRB.aa))
            dev.off()
            
            pdf("top_seqs_plot.pdf", width = 7, height = 5)
            print(topSeqsPlot(list = productive.TRB.aa, top = 10))
            dev.off()
            
            # -----------------------------------------------------------------------------
            # --- Calculate clonal relatedness and visualize sequence ---
            # -----------------------------------------------------------------------------
            relatedness_results <- clonalRelatedness(list = TCRB.list.selected, editDistance = 10)
            write.csv(relatedness_results, "clonal_relatedness.csv", row.names = FALSE)
            
            pdf("phylo_tree.pdf", width = 7, height = 8)
            print(phyloTree(list = productive.TRB.nt, sample = sample1, type = "nucleotide", 
                     layout = "rectangular"))
            dev.off()
            
            # -----------------------------------------------------------------------------
            # --- Perform multiple sequence alignment ---
            # -----------------------------------------------------------------------------
            alignment_output <- capture.output({
              alignSeq(list = productive.TRB.nt, sample = sample1, type = "aminoAcid", 
                       method = "ClustalW", output = "consule")
            })
            writeLines(alignment_output, "alignment_output.txt")
            
            # -----------------------------------------------------------------------------
            # --- Search for specific sequences ---
            # -----------------------------------------------------------------------------
            # Dynamically select a sequence from the user's data
            top_seq <- productive.TRB.aa[[sample1]]\$aminoAcid[1]
            
            searchSeq(list = productive.TRB.aa, sequence = top_seq, type = "aminoAcid", 
                      match = "global", editDistance = 0)
            
            published <- searchPublished(list = productive.TRB.aa)
            write.csv(published, "published_matches.csv", row.names = FALSE)
            head(published)
            
            # -----------------------------------------------------------------------------
            # --- Compare samples pairwise ---
            # -----------------------------------------------------------------------------
            bhattacharyya.matrix <- bhattacharyyaMatrix(productive.seqs = productive.TRB.aa)
            write.csv(bhattacharyya.matrix, "bhattacharyya_matrix.csv")
            bhattacharyya.matrix
            
            similarity.matrix <- similarityMatrix(productive.seqs = productive.TRB.aa)
            write.csv(similarity.matrix, "similarity_matrix.csv")
            similarity.matrix
            
            pdf("pairwise_plot.pdf", width = 6.5, height = 5)
            print(pairwisePlot(matrix = bhattacharyya.matrix))
            dev.off()
            
            if (length(unique(c(sample1, sample2))) >= 2) {
              common <- commonSeqs(samples = c(sample1, sample2), 
                                  productive.aa = productive.TRB.aa)
              write.csv(common, "common_sequences.csv", row.names = FALSE)
              head(common)
              
              pdf("common_seqs_venn_2way.pdf", width = 4, height = 4)
              commonSeqsVenn(samples = c(sample1, sample2), 
                             productive.seqs = productive.TRB.aa)
              dev.off()
              
              pdf("common_seqs_plot.pdf", width = 4, height = 4)
              print(commonSeqsPlot(sample1, sample2, 
                             productive.aa = productive.TRB.aa, show = "common"))
              dev.off()
            }
            
            if (length(unique(c(sample1, sample2, sample3))) >= 3) {
              pdf("common_seqs_venn_3way.pdf", width = 4, height = 4)
              commonSeqsVenn(samples = c(sample1, sample2, sample3), 
                             productive.seqs = productive.TRB.aa)
              dev.off()
            }
            
            pdf("common_seqs_bar.pdf", width = 7, height = 5)
            print(commonSeqsBar(productive.aa = productive.TRB.aa, 
                          samples = sample_names, 
                          color.sample = sample1,
                          labels = "no"))
            dev.off()
            
            # -----------------------------------------------------------------------------
            # --- Identify differentially abundant sequences ---
            # -----------------------------------------------------------------------------
            if (length(unique(c(sample1, sample2))) >= 2) {
              diff_abundance <- differentialAbundance(list = productive.TRB.aa, 
                                    sample1 = sample1, 
                                    sample2 = sample2, 
                                    type = "aminoAcid", q = 0.01)
              write.csv(diff_abundance, "differential_abundance.csv", row.names = FALSE)
            }
            
            # -----------------------------------------------------------------------------
            # --- Find recurring sequences ---
            # -----------------------------------------------------------------------------
            unique.seqs <- uniqueSeqs(productive.aa = productive.TRB.aa)
            write.csv(unique.seqs, "unique_sequences.csv", row.names = FALSE)
            head(unique.seqs)
            
            sequence.matrix <- seqMatrix(productive.aa = productive.TRB.aa, sequences = unique.seqs\$aminoAcid)
            write.csv(sequence.matrix, "sequence_matrix.csv", row.names = FALSE)
            head(sequence.matrix)
            
            top.freq <- topFreq(productive.aa = productive.TRB.aa, percent = 0.1)
            head(top.freq)
            
            top.freq <- topFreq(productive.aa = productive.TRB.aa, percent = 0)
            top.freq.matrix <- merge(top.freq, sequence.matrix)
            write.csv(top.freq.matrix, "top_freq_matrix.csv", row.names = FALSE)
            head(top.freq.matrix)
            
            # -----------------------------------------------------------------------------
            # --- Track sequences across samples ---
            # -----------------------------------------------------------------------------
            pdf("clone_track_plot.pdf", width = 7, height = 5)
            print(cloneTrack(sequence.matrix = sequence.matrix, 
                       productive.aa = productive.TRB.aa, 
                       map = unique(c(sample1, sample2)), 
                       label = unique(c(sample1, sample2)), 
                       track = top_seq, 
                       unassigned = FALSE))
            dev.off()
            
            # -----------------------------------------------------------------------------
            # --- Analyze V(D)J gene usage and visualize ---
            # -----------------------------------------------------------------------------
            vGenes <- geneFreq(productive.nt = productive.TRB.nt, locus = "V", family = TRUE)
            write.csv(vGenes, "v_genes_frequency.csv", row.names = FALSE)
            head(vGenes)
            
            top.seqs <- topSeqs(productive.seqs = productive.TRB.nt, top = 1)
            pdf("chord_diagram_vdj.pdf", width = 4, height = 4)
            chordDiagramVDJ(sample = top.seqs, 
                            association = "VJ", 
                            colors = c("darkred", "navyblue"))
            dev.off()
            
            RedBlue <- grDevices::colorRampPalette(rev(RColorBrewer::brewer.pal(11, "RdBu")))(256)
            
            pdf("vgenes_wordcloud.pdf", width = 4, height = 4)
            wordcloud::wordcloud(words = vGenes[vGenes\$samples == sample1, "familyName"], 
                                 freq = vGenes[vGenes\$samples == sample1, "frequencyGene"], 
                                 colors = RedBlue)
            dev.off()
            
            vGenes <- reshape::cast(vGenes, familyName ~ samples, value = "frequencyGene", sum)
            rownames(vGenes) = as.character(vGenes\$familyName)
            vGenes\$familyName = NULL
            
            pdf("vgenes_heatmap.pdf", width = 5, height = 7)
            pheatmap::pheatmap(vGenes, color = RedBlue, scale = "row")
            dev.off()
            
            vGenes <- geneFreq(productive.nt = productive.TRB.nt, locus = "V", family = TRUE)
            multicolors <- grDevices::colorRampPalette(rev(RColorBrewer::brewer.pal(9, "Set1")))(28)
            
            pdf("vgenes_barplot.pdf", width = 7, height = 5.6)
            print(ggplot2::ggplot(vGenes, aes(x = samples, y = frequencyGene, fill = familyName)) +
              geom_bar(stat = "identity") +
              theme_minimal() + 
              scale_y_continuous(expand = c(0, 0)) + 
              guides(fill = guide_legend(ncol = 2)) +
              scale_fill_manual(values = multicolors) + 
              labs(y = "Frequency (%)", x = "", fill = "") +
              theme(axis.text.x = element_text(angle = 90, vjust = 0.5, hjust = 1)))
            dev.off()
            
            # -----------------------------------------------------------------------------
            # --- Remove contamination sequences ---
            # -----------------------------------------------------------------------------
            searchSeq(list = productive.TRB.aa, sequence = top_seq)
            cleansed <- removeSeq(file.list = productive.TRB.aa, sequence = top_seq)
            saveRDS(cleansed, "cleansed_productive_trb.rds")
            searchSeq(list = cleansed, sequence = top_seq)
            
            # -----------------------------------------------------------------------------
            # --- Merge samples ---
            # -----------------------------------------------------------------------------
            if (length(unique(c(sample1, sample2))) >= 2) {
              merged_samples <- mergeFiles(samples = c(sample1, sample2), 
                                              file.list = TCRB.list.selected)
              write.csv(merged_samples, "merged_samples.csv", row.names = FALSE)
            }
            
            # Print session info
            sessionInfo()

    writeLines(c(
        '"BIOC_LYMPHOSEQ_TCR_BCR_REPERTOIRE_ANALYSIS":',
        paste0('    LymphoSeq: ', as.character(packageVersion('LymphoSeq')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_tcr_bcr_repertoire_analysis.csv versions.yml
    """
}

workflow BIOC_LYMPHOSEQ_TCR_BCR_REPERTOIRE_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sample_folder/, metadata.csv ] ]

    main:
    BIOC_LYMPHOSEQ_TCR_BCR_REPERTOIRE_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_LYMPHOSEQ_TCR_BCR_REPERTOIRE_ANALYSIS.out.tables
    plots    = BIOC_LYMPHOSEQ_TCR_BCR_REPERTOIRE_ANALYSIS.out.plots
    objects  = BIOC_LYMPHOSEQ_TCR_BCR_REPERTOIRE_ANALYSIS.out.objects
    versions = BIOC_LYMPHOSEQ_TCR_BCR_REPERTOIRE_ANALYSIS.out.versions
}
