#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: RTCGAToolbox — rtcgatoolbox_tcga_integration
// Query TCGA Firehose metadata, download clinical data for comparison, and integrate local transcriptomic counts into a standard Bioconductor SummarizedExperiment
// Input: counts.csv, coldata.csv
// Container: 2.40.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: RTCGAToolbox, S4Vectors, SummarizedExperiment
// Visualizations: bar plot, box plot
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RTCGATOOLBOX_RTCGATOOLBOX_TCGA_INTEGRATION {
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
    .bm_deps <- c("RTCGAToolbox", "S4Vectors", "SummarizedExperiment")
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
      library(SummarizedExperiment)
  library(RTCGAToolbox)
    library(S4Vectors)
    
    # ==========================================
    # --- Read Local Input Data ---
    # ==========================================
    message("Reading local input files...")
    counts_df <- read.csv("counts.csv", check.names = FALSE)
    if ("gene_id" %in% colnames(counts_df)) {
        rownames(counts_df) <- counts_df\$gene_id
        counts_df\$gene_id <- NULL
    }
    counts_matrix <- as.matrix(counts_df)
    
    coldata_df <- read.csv("coldata.csv", check.names = FALSE)
    
    # ==========================================
    # --- Query Firehose Metadata ---
    # ==========================================
    message("Querying Firehose metadata...")
    datasets <- getFirehoseDatasets()
    run_dates <- getFirehoseRunningDates(last = 3)
    analyze_dates <- getFirehoseAnalyzeDates(last = 3)
    
    # Save Firehose metadata summary
    metadata_summary <- data.frame(
        Metric = c("Total_Available_Datasets", "Latest_Run_Date", "Latest_Analyze_Date"),
        Value = c(length(datasets), run_dates[1], analyze_dates[1])
    )
    write.csv(metadata_summary, "firehose_metadata.csv", row.names = FALSE)
    
    # ==========================================
    # --- Download and Extract TCGA Data ---
    # ==========================================
    message("Downloading TCGA clinical data for comparison...")
    # We attempt to download clinical data for the Adrenocortical Carcinoma (ACC) cohort
    tcga_data <- tryCatch({
        getFirehoseData(
            dataset = "ACC",
            runDate = run_dates[1],
            forceDownload = TRUE,
            clinical = TRUE,
            Mutation = FALSE,
            RNASeq2Gene = FALSE
        )
    }, error = function(e) {
        warning("Firehose download failed or timed out: ", e\$message)
        NULL
    })
    
    # Extract and save TCGA clinical data if available
    if (!is.null(tcga_data) && !isEmpty(tcga_data)) {
        message("Extracting TCGA clinical data...")
        tcga_clinical <- getData(tcga_data, "clinical")
        write.csv(tcga_clinical, "tcga_acc_clinical.csv", row.names = TRUE)
    } else {
        message("Using fallback empty clinical table due to download failure.")
        fallback_df <- data.frame(
            Sample_ID = character(0),
            Survival_Days = numeric(0),
            Status = character(0)
        )
        write.csv(fallback_df, "tcga_acc_clinical.csv", row.names = FALSE)
    }
    
    # ==========================================
    # --- Build SummarizedExperiment & Analyze ---
    # ==========================================
    message("Integrating local data into SummarizedExperiment...")
    # Align coldata with counts columns
    common_samples <- intersect(colnames(counts_matrix), coldata_df\$sample)
    
    if (length(common_samples) > 0) {
        counts_subset <- counts_matrix[, common_samples, drop = FALSE]
        coldata_subset <- coldata_df[match(common_samples, coldata_df\$sample), , drop = FALSE]
        rownames(coldata_subset) <- coldata_subset\$sample
        
        local_se <- SummarizedExperiment(
            assays = list(counts = counts_subset),
            colData = DataFrame(coldata_subset)
        )
    } else {
        # Fallback if sample names do not match perfectly
        rownames(coldata_df) <- coldata_df\$sample
        local_se <- SummarizedExperiment(
            assays = list(counts = counts_matrix),
            colData = DataFrame(coldata_df)
        )
    }
    
    # Calculate library sizes as a basic QC metric
    lib_sizes <- colSums(assay(local_se, "counts"))
    colData(local_se)\$library_size <- lib_sizes
    
    # Save local sample summary
    local_summary <- as.data.frame(colData(local_se))
    write.csv(local_summary, "local_sample_summary.csv", row.names = TRUE)
    
    # ==========================================
    # --- Visualization ---
    # ==========================================
    message("Generating diagnostic plots...")
    pdf("library_sizes.pdf", width = 7, height = 5)
    if ("condition" %in% colnames(colData(local_se))) {
        boxplot(library_size ~ condition, data = as.data.frame(colData(local_se)),
                main = "Library Sizes by Experimental Condition",
                ylab = "Total Counts", xlab = "Condition",
                col = c("#4DAF4A", "#377EB8"))
    } else {
        barplot(lib_sizes, main = "Library Sizes per Sample", 
                ylab = "Total Counts", las = 2, col = "skyblue")
    }
    dev.off()
    
    message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_RTCGATOOLBOX_RTCGATOOLBOX_TCGA_INTEGRATION":',
        paste0('    RTCGAToolbox: ', as.character(packageVersion('RTCGAToolbox')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rtcgatoolbox_tcga_integration.csv versions.yml
    """
}

workflow BIOC_RTCGATOOLBOX_RTCGATOOLBOX_TCGA_INTEGRATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_RTCGATOOLBOX_RTCGATOOLBOX_TCGA_INTEGRATION(ch_input)

    emit:
    tables   = BIOC_RTCGATOOLBOX_RTCGATOOLBOX_TCGA_INTEGRATION.out.tables
    plots    = BIOC_RTCGATOOLBOX_RTCGATOOLBOX_TCGA_INTEGRATION.out.plots
    objects  = BIOC_RTCGATOOLBOX_RTCGATOOLBOX_TCGA_INTEGRATION.out.objects
    versions = BIOC_RTCGATOOLBOX_RTCGATOOLBOX_TCGA_INTEGRATION.out.versions
}
