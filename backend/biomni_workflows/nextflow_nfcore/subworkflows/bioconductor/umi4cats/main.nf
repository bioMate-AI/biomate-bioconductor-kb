#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: UMI4Cats — umi4c_analysis_workflow
// Process raw paired-end UMI-4C FASTQ files, align them to a digested reference genome, call significant interactions, perform differential testing between two co
// Input: R1/R2 FASTQ files, BSgenome object, Bowtie2 index files, Metadata table / colData
// Container: quay.io/biocontainers/bioconductor-umi4cats:1.20.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: BSgenome.Hsapiens.UCSC.hg19, TxDb.Hsapiens.UCSC.hg19.knownGene, UMI4Cats, cowplot, org.Hs.eg.db, tidyr
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Demultiplex multiplexed FASTQ files using demultiplexFastq (optional)
//  * 2. [Core Analysis] Perform in silico digestion of the reference genome using digestGenome
//  * 3. [Core Analysis] Process raw FASTQ files to align reads and count UMIs using contactsUMI4C
//  * 4. [Core Analysis] Generate alignment and filtering statistics using statsUMI4C
//  * 5. [Input & Preparation] Load count files and construct a UMI4C object using makeUMI4C
//  * 6. [Input & Preparation] Define candidate window fragments using makeWindowFragments
//  * 7. [Core Analysis] Call significant interactions with the viewpoint using callInteractions and retrieve them with getSignInteractions
//  * 8. [Core Analysis] Perform differential interaction analysis using waldUMI4C (DESeq2) or fisherUMI4C (Fisher's Exact Test)
//  * 9. [Core Analysis] Retrieve differential results using resultsUMI4C
//  * 10. [Visualization & Output] Visualize contact profiles, domainograms, and differential results using plotUMI4C or plotInteractionsUMI4C

nextflow.enable.dsl = 2

process BIOC_UMI4CATS_UMI4C_ANALYSIS_WORKFLOW {
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
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
            
            # ==============================================================================
            # UMI-4C Analysis Pipeline using UMI4Cats
            # Workflow: umi4c_analysis_workflow
            # ==============================================================================
            
            # Load required libraries
            library(UMI4Cats)
            library(tidyr)
            library(cowplot)
            library(BSgenome.Hsapiens.UCSC.hg19)
            library(TxDb.Hsapiens.UCSC.hg19.knownGene)
            library(org.Hs.eg.db)
            
            # ------------------------------------------------------------------------------
            # USER INPUTS & CONFIGURATION
            # ------------------------------------------------------------------------------
            # Please ensure these files/directories exist in your working directory or update paths.
            fastq_dir <- "fastq"                      # Directory containing raw paired-end FASTQ files
            bowtie_index <- "bowtie2_index/ucsc.hg19" # Bowtie2 index prefix path
            metadata_path <- "metadata.csv"           # Optional user-provided metadata sheet
            bs_genome_package <- "BSgenome.Hsapiens.UCSC.hg19"
            
            # UMI-4C specific parameters (Update these for your experiment)
            bait_seq <- "GGACAAGCTCCCTGCAACTCA"       # Bait sequence
            bait_pad <- "GGACTTGCA"                   # Pad sequence
            res_enz <- "GATC"                         # Restriction enzyme sequence
            cut_pos <- 0                              # Restriction enzyme cut position
            name_RE <- "dpnII"                        # Restriction enzyme name
            
            # Load reference genome
            library(bs_genome_package, character.only = TRUE)
            refgen <- get(bs_genome_package)
            
            # Output directory for UMI4Cats processing
            wk_dir <- "UMI4C_out"
            
            # ------------------------------------------------------------------------------
            # 1. Demultiplex baits inside FastQ file (Optional)
            # ------------------------------------------------------------------------------
            if (file.exists("multiplexed_R1.fastq.gz") && file.exists("barcodes.csv")) {
                message("Running demultiplexFastq...")
                barcodes <- read.csv("barcodes.csv", stringsAsFactors = FALSE)
                demultiplexFastq(
                    fastq = "multiplexed_R1.fastq.gz",
                    barcodes = barcodes,
                    out_path = fastq_dir
                )
            } else {
                message("Skipping optional demultiplexing (multiplexed_R1.fastq.gz or barcodes.csv not found).")
            }
            
            # ------------------------------------------------------------------------------
            # 2. Perform in silico digestion of the reference genome
            # ------------------------------------------------------------------------------
            message("Digesting reference genome...")
            hg19_dpnii <- digestGenome(
                res_enz = res_enz,
                cut_pos = cut_pos,
                name_RE = name_RE,
                ref_gen = refgen,
                out_path = file.path(tempdir(), "digested_genome/")
            )
            
            # ------------------------------------------------------------------------------
            # 3. Process raw FASTQ files to align reads and count UMIs
            # ------------------------------------------------------------------------------
            message("Processing UMI-4C contacts...")
            contactsUMI4C(
                fastq_dir = fastq_dir,
                wk_dir = wk_dir,
                bait_seq = bait_seq,
                bait_pad = bait_pad,
                res_enz = res_enz,
                cut_pos = cut_pos,
                digested_genome = hg19_dpnii,
                bowtie_index = bowtie_index,
                ref_gen = refgen,
                threads = 2,
                numb_reads = 1e6
            )
            
            # ------------------------------------------------------------------------------
            # 4. Generate alignment and filtering statistics
            # ------------------------------------------------------------------------------
            message("Generating alignment and filtering statistics...")
            statsUMI4C(wk_dir = wk_dir)
            
            # Copy stats summary to a permanent output file
            stats_file <- file.path(wk_dir, "logs", "stats_summary.txt")
            if (file.exists(stats_file)) {
                file.copy(stats_file, "stats_summary.txt", overwrite = TRUE)
                message("Saved alignment statistics to 'stats_summary.txt'")
            }
            
            # ------------------------------------------------------------------------------
            # 5. Load count files and construct a UMI4C object
            # ------------------------------------------------------------------------------
            message("Constructing UMI4C object...")
            if (file.exists(metadata_path)) {
                message("Loading user-provided metadata table...")
                colData <- read.csv(metadata_path, stringsAsFactors = FALSE)
            } else {
                message("Constructing colData dynamically from processed count files...")
                files <- list.files(file.path(wk_dir, "count"),
                                    pattern = "*_counts.tsv.gz",
                                    full.names = TRUE
                )
                colData <- data.frame(
                    sampleID = gsub("_counts.tsv.gz", "", basename(files)),
                    file = files,
                    stringsAsFactors = FALSE
                )
                colData <- colData |>
                    separate(sampleID,
                        into = c("condition", "replicate", "viewpoint"),
                        remove = FALSE
                    )
            }
            
            # Generate UMI4C object
            vpt_name <- if ("viewpoint" %in% colnames(colData)) colData\$viewpoint[1] else "Viewpoint"
            
            umi <- makeUMI4C(
                colData = colData,
                viewpoint_name = vpt_name,
                grouping = "condition",
                bait_expansion = 2e6
            )
            
            saveRDS(umi, "umi_object.rds")
            message("Saved UMI4C object to 'umi_object.rds'")
            
            # ------------------------------------------------------------------------------
            # 6. Define candidate window fragments
            # ------------------------------------------------------------------------------
            message("Generating window fragments...")
            win_frags <- makeWindowFragments(umi, n_frags=8)
            
            # ------------------------------------------------------------------------------
            # 7. Call significant interactions with the viewpoint
            # ------------------------------------------------------------------------------
            message("Calling significant interactions...")
            gr <- callInteractions(umi4c = umi, 
                                   design = ~condition, 
                                   query_regions = win_frags, 
                                   padj_threshold = 0.01, 
                                   zscore_threshold=2)
            
            # Plot interactions and save to PDF
            message("Plotting interactions...")
            all_plot <- plotInteractionsUMI4C(umi, gr, grouping = NULL, significant=FALSE)
            sign_plot <- plotInteractionsUMI4C(umi, gr, grouping = NULL, significant=TRUE)
            
            pdf("interactions_plot.pdf", width = 12, height = 7)
            print(cowplot::plot_grid(all_plot, sign_plot, ncol=2, labels=c("All", "Significant")))
            dev.off()
            message("Saved interactions plot to 'interactions_plot.pdf'")
            
            # Obtain unique significant interactions
            inter <- getSignInteractions(gr)
            write.csv(as.data.frame(inter), "significant_interactions.csv", row.names = FALSE)
            message("Saved unique significant interactions to 'significant_interactions.csv'")
            
            # ------------------------------------------------------------------------------
            # 8. Perform differential interaction analysis
            # ------------------------------------------------------------------------------
            message("Performing differential testing (DESeq2 Wald Test)...")
            umi_wald <- tryCatch({
                waldUMI4C(umi,
                          query_regions = inter,
                          design = ~condition)
            }, error = function(e) {
                message("Wald test failed: ", e\$message)
                NULL
            })
            
            message("Performing differential testing (Fisher's Exact Test)...")
            umi_fisher <- fisherUMI4C(umi,
                                      grouping = "condition",
                                      query_regions = inter,
                                      filter_low = 20)
            
            # ------------------------------------------------------------------------------
            # 9. Retrieve and save differential results
            # ------------------------------------------------------------------------------
            message("Retrieving differential analysis results...")
            res_fisher <- resultsUMI4C(umi_fisher, ordered = TRUE, counts = TRUE, format = "data.frame")
            write.csv(res_fisher, "differential_results_fisher.csv", row.names = FALSE)
            message("Saved Fisher's test results to 'differential_results_fisher.csv'")
            
            if (!is.null(umi_wald)) {
                res_wald <- resultsUMI4C(umi_wald, ordered = TRUE, counts = TRUE, format = "data.frame")
                write.csv(res_wald, "differential_results_wald.csv", row.names = FALSE)
                message("Saved Wald test results to 'differential_results_wald.csv'")
            }
            
            # ------------------------------------------------------------------------------
            # 10. Visualize contact profiles, domainograms, and differential results
            # ------------------------------------------------------------------------------
            message("Generating final contact profile plots...")
            
            # Plot replicates without grouping
            pdf("umi_plot_replicates.pdf", width = 10, height = 8)
            print(plotUMI4C(umi,
                grouping = NULL,
                TxDb = TxDb.Hsapiens.UCSC.hg19.knownGene::TxDb.Hsapiens.UCSC.hg19.knownGene,
                OrgDb = "org.Hs.eg.db",
                dgram_plot = FALSE
            ))
            dev.off()
            message("Saved replicate contact profiles to 'umi_plot_replicates.pdf'")
            
            # Plot differential results with grouping
            pdf("umi_plot_differential.pdf", width = 10, height = 8)
            print(plotUMI4C(umi_fisher, grouping = "condition", ylim=c(0,10)))
            dev.off()
            message("Saved differential contact profiles to 'umi_plot_differential.pdf'")
            
            message("Pipeline completed successfully!")

    writeLines(c(
        '"BIOC_UMI4CATS_UMI4C_ANALYSIS_WORKFLOW":',
        paste0('    UMI4Cats: ', as.character(packageVersion('UMI4Cats')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_umi4c_analysis_workflow.csv versions.yml
    """
}

workflow BIOC_UMI4CATS_UMI4C_ANALYSIS_WORKFLOW_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ R1/R2 FASTQ files, BSgenome object, Bowtie2 index files, Metadata table / colData ] ]

    main:
    BIOC_UMI4CATS_UMI4C_ANALYSIS_WORKFLOW(ch_input)

    emit:
    tables   = BIOC_UMI4CATS_UMI4C_ANALYSIS_WORKFLOW.out.tables
    plots    = BIOC_UMI4CATS_UMI4C_ANALYSIS_WORKFLOW.out.plots
    objects  = BIOC_UMI4CATS_UMI4C_ANALYSIS_WORKFLOW.out.objects
    versions = BIOC_UMI4CATS_UMI4C_ANALYSIS_WORKFLOW.out.versions
}
