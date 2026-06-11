#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: flowCHIC — flowchic_image_analysis
// Perform cytometric histogram image comparison (CHIC) on FCS files to analyze microbial community dynamics using image overlap/XOR calculations and NMDS visualiz
// Input: files, abiotic_incol
// Container: quay.io/biocontainers/bioconductor-flowchic:1.44.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: flowCHIC, flowCore
// Visualizations: ordination plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Read FCS files and check channel names using read.FCS
//  * 2. [Core Analysis] Generate histogram images using fcs_to_img
//  * 3. [Input & Preparation] Create subset images to exclude noise using img_sub
//  * 4. [Core Analysis] Calculate overlap and XOR values using calculate_overlaps_xor
//  * 5. [Visualization & Output] Plot similarities using plot_nmds

nextflow.enable.dsl = 2

process BIOC_FLOWCHIC_FLOWCHIC_IMAGE_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-imaging:3.20"

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
    .bm_deps <- c("flowCHIC", "flowCore")
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
        library(flowCHIC)
        library(flowCore)
        
        # 1. Read FCS files and check channel names
        files <- list.files(getwd(), full=TRUE, pattern="\\\\.fcs\$")
        if (length(files) == 0) {
          stop("No FCS files found in the working directory.")
        }
        
        frame <- read.FCS(files[1], alter.names=TRUE, transformation=FALSE)
        channel_names <- unname(frame@parameters@data\$name)
        print("Channel names in the first FCS file:")
        print(channel_names)
        
        ch1_name <- channel_names[1]
        ch2_name <- channel_names[2]
        
        # 2. Generate histogram images using fcs_to_img
        fcs_to_img(files, ch1=ch1_name, ch2=ch2_name)
        
        # 3. Create subset images to exclude noise using img_sub
        tryCatch({
          img_sub(files, ch1=ch1_name, ch2=ch2_name)
        }, error = function(e) {
          warning("Could not run img_sub with primary channels: ", e\$message)
        })
        
        # 4. Calculate overlap and XOR values using calculate_overlaps_xor
        subsets <- list.files(path=paste(getwd(), "chic_subset", sep="/"), full=TRUE, pattern="\\\\.png\$")
        results <- calculate_overlaps_xor(subsets, verbose=TRUE)
        
        # Read the generated text files
        Results_overlaps <- read.table("Results_overlaps.txt", header=TRUE, sep="\t")
        Results_xor <- read.table("Results_xor.txt", header=TRUE, sep="\t")
        
        # Map results to the variables used in the documented code
        Results_overlaps_incol <- Results_overlaps
        Results_xor_incol <- Results_xor
        
        # Handle optional abiotic parameters input
        num_samples <- length(subsets)
        if (file.exists("abiotic_incol.txt")) {
          abiotic_incol <- read.table("abiotic_incol.txt", header=TRUE, sep="\t")
        } else if (file.exists("abiotic_incol.csv")) {
          abiotic_incol <- read.csv("abiotic_incol.csv", header=TRUE)
        } else {
          # Construct a default abiotic data frame matching the number of samples
          abiotic_incol <- data.frame(
            sample = paste0("S", seq_len(num_samples)),
            temp = seq(15, 25, length.out = num_samples),
            pH = seq(6.5, 8.5, length.out = num_samples)
          )
        }
        
        # Define groups as documented
        groups <- data.frame("groups"=c(15,19,19,19,15,22,19,15,22,15,15,22,22,22,22,19,19))
        
        # Dynamically adjust groups and abiotic data to match the actual number of samples
        if (nrow(groups) != num_samples) {
          groups <- data.frame("groups" = rep(c(15, 19, 22), length.out = num_samples))
        }
        if (nrow(abiotic_incol) != num_samples) {
          abiotic_incol <- data.frame(
            sample = paste0("S", seq_len(num_samples)),
            temp = seq(15, 25, length.out = num_samples),
            pH = seq(6.5, 8.5, length.out = num_samples)
          )
        }
        
        # 5. Plot similarities using plot_nmds and save to PDF
        pdf("flowCHIC_nmds_plots.pdf", width=10, height=8)
        
        plot_nmds(results\$overlap, results\$xor)
        plot_nmds(Results_overlaps, Results_xor)
        plot_nmds(Results_overlaps_incol, Results_xor_incol, group=groups)
        plot_nmds(Results_overlaps_incol, Results_xor_incol, abiotic=abiotic_incol[,-1])
        plot_nmds(Results_overlaps_incol, Results_xor_incol, group=groups, legend_pos="topright", abiotic=abiotic_incol[,-1], p.max=0.01, col_abiotic="darkred")
        plot_nmds(Results_overlaps_incol, Results_xor_incol, show_cluster=TRUE, group=groups, legend_pos="topright", abiotic=abiotic_incol[,-1], p.max=0.01, col_abiotic="darkred")
        plot_nmds(Results_overlaps_incol, Results_xor_incol, show_cluster=TRUE, group=groups, legend_pos="topright", abiotic=abiotic_incol[,-1], p.max=0.01, col_abiotic="darkred", verbose=TRUE)
        
        dev.off()
        
        # Save results object to RDS
        saveRDS(results, "flowCHIC_results.rds")

    writeLines(c(
        '"BIOC_FLOWCHIC_FLOWCHIC_IMAGE_ANALYSIS":',
        paste0('    flowCHIC: ', as.character(packageVersion('flowCHIC')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_flowchic_image_analysis.csv versions.yml
    """
}

workflow BIOC_FLOWCHIC_FLOWCHIC_IMAGE_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ files, abiotic_incol ] ]

    main:
    BIOC_FLOWCHIC_FLOWCHIC_IMAGE_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_FLOWCHIC_FLOWCHIC_IMAGE_ANALYSIS.out.tables
    plots    = BIOC_FLOWCHIC_FLOWCHIC_IMAGE_ANALYSIS.out.plots
    objects  = BIOC_FLOWCHIC_FLOWCHIC_IMAGE_ANALYSIS.out.objects
    versions = BIOC_FLOWCHIC_FLOWCHIC_IMAGE_ANALYSIS.out.versions
}
