#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: mobileRNA — srna_mobilome_analysis
// Identify, quantify, and characterize mobile small RNAs (sRNAs) and population-scale changes across graft junctions or chimeric systems.
// Input: genomeA.fa.gz, genomeB.fa.gz, annotationA.gff.gz, annotationB.gff.gz, sRNAseq_dir
// Container: quay.io/biocontainers/bioconductor-mobilerna:1.6.1--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: bioseq, dplyr, mobileRNA
// Visualizations: PCA plot, heatmap
// QC: missing-value handling
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Merge genome assemblies using RNAmergeGenomes
//  * 2. [Core Analysis] Merge genome annotations using RNAmergeAnnotations
//  * 3. [Core Analysis] Align reads and detect/quantify sRNA clusters using mapRNA
//  * 4. [Input & Preparation] Import pre-processed data into R using RNAimport
//  * 5. [Core Analysis] Identify potential mobile sRNA clusters using RNAmobile
//  * 6. [Visualization & Output] Perform quality control and plot sRNA class distributions using RNAdistribution, plotSamplePCA, and plotSampleDistance
//  * 7. [Input & Preparation] Define consensus dicercall using RNAdicercall and subset populations using RNAsubset
//  * 8. [Core Analysis] Reorder data and perform differential expression analysis using RNAreorder and RNAdifferentialAnalysis
//  * 9. [Core Analysis] Identify gained and lost RNA populations using RNApopulation
//  * 10. [Visualization & Output] Perform functional analysis (extract sequences, match attributes, summarize features) using RNAsequences, RNAattributes, RNAfeatur

nextflow.enable.dsl = 2

process BIOC_MOBILERNA_SRNA_MOBILOME_ANALYSIS {
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
    .bm_deps <- c("mobileRNA", "dplyr", "bioseq")
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
    library("mobileRNA")
    library("dplyr")
    
    # ==========================================
    # 1. Merge Genome Assemblies
    # ==========================================
    fasta_1 <- "genomeA.fa.gz"
    fasta_2 <- "genomeB.fa.gz"
    output_assembly_file <- "merged_assembly.fa"
    
    merged_reference <- RNAmergeGenomes(genomeA = fasta_1,
                                        genomeB = fasta_2,
                                        output_file = output_assembly_file)
    
    # ==========================================
    # 2. Merge Genome Annotations
    # ==========================================
    anno1 <- "annotationA.gff.gz"
    anno2 <- "annotationB.gff.gz"
    output_annotation_file <- "merged_annotation.gff3"
    
    merged_annotation <- RNAmergeAnnotations(annotationA = anno1,
                                             annotationB = anno2,
                                             output_file = output_annotation_file)
    
    # ==========================================
    # 3. Align Reads and Detect/Quantify sRNA Clusters
    # ==========================================
    samples_dir <- "sRNAseq_dir"
    output_location <- "mapRNA_output"
    dir.create(output_location, showWarnings = FALSE, recursive = TRUE)
    
    # Determine conda environment (allow override via environment variable)
    conda_env <- Sys.getenv("SHORTSTACK_CONDA_ENV", "/Users/user-name/miniconda3/envs/ShortStack4")
    
    mapRNA(input = "sRNA",
           input_files_dir = samples_dir,
           output_dir = output_location,
           genomefile = output_assembly_file,
           condaenv = conda_env,
           mmap = "n")
    
    # ==========================================
    # 4. Import Pre-Processed Data into R
    # ==========================================
    results_dir <- file.path(output_location, "2_sRNA_results")
    
    # Dynamically detect sample names from the results directory
    sample_dirs <- list.dirs(results_dir, fullNames = FALSE, recursive = FALSE)
    if (length(sample_dirs) == 0) {
      # Fallback to input files if results directory is empty
      fastq_files <- list.files(samples_dir, pattern = "\\\\.f(ast)?q(\\\\.gz)?\$")
      sample_names <- gsub("\\\\.f(ast)?q(\\\\.gz)?\$", "", fastq_files)
    } else {
      sample_names <- sample_dirs
    }
    
    sRNA_data <- RNAimport(input = "sRNA",
                           directory = results_dir,
                           samples = sample_names)
    
    saveRDS(sRNA_data, "sRNA_data_imported.rds")
    
    # Define control samples dynamically (assuming "selfgraft" in name, fallback to first half)
    controls <- sample_names[grep("selfgraft", sample_names, ignore.case = TRUE)]
    if (length(controls) == 0) {
      controls <- sample_names[1:max(1, floor(length(sample_names) / 2))]
    }
    
    # ==========================================
    # 5. Identify Potential Mobile sRNA Clusters (Initial)
    # ==========================================
    mobile_sRNA <- RNAmobile(input = "sRNA",
                             data = sRNA_data, 
                             controls = controls,
                             genome.ID = "B",
                             task = "keep")
    
    write.table(mobile_sRNA, "./sRNA_mobile_output.txt", sep = "\t", quote = FALSE)
    
    # ==========================================
    # 6. Quality Control and Plot sRNA Class Distributions
    # ==========================================
    pdf("sample_distribution_line.pdf", width = 11, height = 8)
    sample_distribution_line <- RNAdistribution(sRNA_data,
                                                style = "line",
                                                overlap = FALSE, 
                                                facet = TRUE,
                                                colour = "darkgreen")
    if (!is.null(sample_distribution_line\$plot)) {
      print(sample_distribution_line\$plot)
    }
    dev.off()
    
    pdf("sample_distribution_bar.pdf", width = 11, height = 8)
    sample_distribution_bar <- RNAdistribution(sRNA_data,
                                               style = "bar",
                                               facet = TRUE,
                                               colour = "lightblue")
    if (!is.null(sample_distribution_bar\$plot)) {
      print(sample_distribution_bar\$plot)
    }
    dev.off()
    
    # PCA and Distance plots
    groups <- ifelse(sample_names %in% controls, "Selfgraft", "Heterograft")
    
    pdf("sample_pca.pdf", width = 8, height = 6)
    tryCatch({
      plotSamplePCA(data = sRNA_data, group = groups, size.ratio = 2)
    }, error = function(e) warning("PCA plot failed: ", e\$message))
    dev.off()
    
    pdf("sample_distance.pdf", width = 8, height = 8)
    tryCatch({
      plotSampleDistance(sRNA_data)
    }, error = function(e) warning("Distance plot failed: ", e\$message))
    dev.off()
    
    # ==========================================
    # 7. Define Consensus Dicercall and Subset Populations
    # ==========================================
    sRNA_data_dicercall <- RNAdicercall(data = sRNA_data, 
                                         chimeric = TRUE, 
                                         genome.ID = "B_", 
                                         controls = controls)
    
    sRNA_24 <- RNAsubset(sRNA_data_dicercall, class = 24)
    sRNA_2122 <- RNAsubset(sRNA_data_dicercall, class = c(21, 22))
    
    saveRDS(sRNA_24, "sRNA_24.rds")
    saveRDS(sRNA_2122, "sRNA_2122.rds")
    
    pdf("consensus_distribution.pdf", width = 10, height = 7)
    consensus_plot <- RNAdistribution(data = sRNA_data_dicercall,
                                      style = "bar",
                                      data.type = "consensus")
    if (!is.null(consensus_plot\$plot)) {
      print(consensus_plot\$plot)
    }
    dev.off()
    
    # ==========================================
    # 8. Reorder Data and Perform Differential Expression Analysis
    # ==========================================
    reorder_df <- RNAreorder(sRNA_data_dicercall, controls)
    
    # Align groups vector with the reordered columns
    count_cols <- colnames(reorder_df)[grep("^Count_", colnames(reorder_df))]
    reordered_samples <- gsub("^Count_", "", count_cols)
    groups_reordered <- ifelse(reordered_samples %in% controls, "Selfgraft", "Heterograft")
    
    sRNA_DESeq2 <- RNAdifferentialAnalysis(data = reorder_df,
                                           group = groups_reordered,
                                           method = "DESeq2")
    
    # Save summaries
    sink("deseq2_summary.txt")
    cat("=== DESeq2 Summary (alpha = 0.1) ===\n")
    tryCatch(RNAsummary(sRNA_DESeq2), error = function(e) cat("Error: ", e\$message, "\n"))
    cat("\n=== DESeq2 Summary (alpha = 0.05) ===\n")
    tryCatch(RNAsummary(sRNA_DESeq2, alpha = 0.05), error = function(e) cat("Error: ", e\$message, "\n"))
    sink()
    
    write.table(sRNA_DESeq2, "./sRNA_core_dataset.txt", sep = "\t", quote = FALSE)
    
    # Heatmap of significant sRNAs
    significant_sRNAs <- sRNA_DESeq2[sRNA_DESeq2\$padjusted < 0.05 & !is.na(sRNA_DESeq2\$padjusted), ]
    if (nrow(significant_sRNAs) > 0) {
      pdf("significant_sRNAs_heatmap.pdf", width = 8, height = 10)
      p1 <- plotHeatmap(significant_sRNAs, value = "RPM", row.names = FALSE,
                        title = "Heatmap of log-transformed FPKM")
      if (!is.null(p1\$plot)) {
        print(p1\$plot)
      }
      dev.off()
    }
    
    # ==========================================
    # 9. Identify Gained and Lost RNA Populations
    # ==========================================
    conditions <- sample_names[!sample_names %in% controls]
    
    gained_sRNA <- RNApopulation(data = sRNA_DESeq2, 
                                 conditions = conditions,
                                 chimeric = TRUE, 
                                 genome.ID = "B_", 
                                 controls = controls)
    
    lost_sRNA <- RNApopulation(data = sRNA_DESeq2, 
                               conditions = controls, 
                               chimeric = TRUE, 
                               genome.ID = "B_", 
                               controls = controls)
    
    saveRDS(gained_sRNA, "gained_sRNA.rds")
    saveRDS(lost_sRNA, "lost_sRNA.rds")
    
    # ==========================================
    # 10. Functional Analysis of Gained sRNA Populations
    # ==========================================
    if (nrow(gained_sRNA) > 0) {
      gained_sRNA_sequences <- RNAsequences(gained_sRNA, method = "consensus")
      write.table(gained_sRNA_sequences, "gained_sRNA_sequences.txt", sep = "\t", quote = FALSE)
    
      gained_sRNA_attributes <- RNAattributes(data = gained_sRNA, 
                                              match = "genes",
                                              annotation = output_annotation_file)
      saveRDS(gained_sRNA_attributes, "gained_sRNA_attributes.rds")
    }
    
    # ==========================================
    # 11. Mobile sRNA Analysis (Advanced)
    # ==========================================
    mobile_sRNA_adv <- RNAmobile(input = "sRNA",
                                 data = sRNA_DESeq2, 
                                 controls = controls,
                                 genome.ID = "B_",
                                 task = "keep", 
                                 statistical = FALSE)
    
    write.table(mobile_sRNA_adv, "./candidate_mobile_sRNAs.txt", sep = "\t", quote = FALSE)
    
    if (nrow(mobile_sRNA_adv) > 0) {
      pdf("mobile_sRNAs_heatmap.pdf", width = 8, height = 10)
      p2 <- plotHeatmap(mobile_sRNA_adv, row.names = FALSE)
      if (!is.null(p2\$plot)) {
        print(p2\$plot)
      }
      dev.off()
    
      mobile_attributes <- RNAattributes(data = mobile_sRNA_adv, 
                                         match = "genes",
                                         annotation = output_annotation_file)
      saveRDS(mobile_attributes, "mobile_attributes.rds")
    
      mobile_features <- RNAfeatures(data = mobile_sRNA_adv, 
                                     annotation = output_annotation_file)
      write.table(mobile_features, "mobile_features_summary.txt", sep = "\t", quote = FALSE)
    
      pdf("mobile_features_plot.pdf", width = 8, height = 6)
      features_plot <- plotRNAfeatures(data = mobile_sRNA_adv,  
                                       annotation = output_annotation_file)
      if (!is.null(features_plot)) {
        plot(features_plot)
      }
      dev.off()
    
      mobile_sequences <- RNAsequences(mobile_sRNA_adv, method = "consensus") 
      write.table(mobile_sequences, "./candidate_mobile_sRNA_sequences.txt", sep = "\t", quote = FALSE)
    
      # Format sequences for target prediction tools
      sequences <- mobile_sequences %>% select(Cluster, Sequence)
      prefix <- ">"
      sequences\$Cluster <- paste0(prefix, sequences\$Cluster)
      sequences <- na.omit(sequences)
    
      if (nrow(sequences) > 0) {
        res <- do.call(rbind, lapply(seq(nrow(sequences)), 
                                     function(i) t(sequences[i, ])))
        write.table(res, file = "./mobile_sRNA_sequences.txt",
                    row.names = FALSE, col.names = FALSE, quote = FALSE)
      }
    
      # Consensus sequence analysis using bioseq
      if (requireNamespace("bioseq", quietly = TRUE)) {
        library(bioseq)
        tryCatch({
          mobileRNA_seq <- bioseq::rna(mobile_sequences\$Sequence)
          consensus_seq <- bioseq::seq_consensus(mobileRNA_seq)
          writeLines(as.character(consensus_seq), "bioseq_consensus_sequence.txt")
        }, error = function(e) warning("bioseq analysis failed: ", e\$message))
      }
    }

    writeLines(c(
        '"BIOC_MOBILERNA_SRNA_MOBILOME_ANALYSIS":',
        paste0('    mobileRNA: ', as.character(packageVersion('mobileRNA')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_srna_mobilome_analysis.csv versions.yml
    """
}

workflow BIOC_MOBILERNA_SRNA_MOBILOME_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ genomeA.fa.gz, genomeB.fa.gz, annotationA.gff.gz, annotationB.gff.gz, sRNAseq_dir ] ]

    main:
    BIOC_MOBILERNA_SRNA_MOBILOME_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_MOBILERNA_SRNA_MOBILOME_ANALYSIS.out.tables
    plots    = BIOC_MOBILERNA_SRNA_MOBILOME_ANALYSIS.out.plots
    objects  = BIOC_MOBILERNA_SRNA_MOBILOME_ANALYSIS.out.objects
    versions = BIOC_MOBILERNA_SRNA_MOBILOME_ANALYSIS.out.versions
}
