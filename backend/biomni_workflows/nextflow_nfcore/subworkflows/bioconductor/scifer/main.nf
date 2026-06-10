#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: scifer — bcr_tcr_flow_sanger_integration
// Process flow cytometry index sorting data, perform quality control on Sanger sequencing files, integrate both datasets to assign specificity, and run IgBlast an
// Input: .fcs files, .ab1 files, IgBlast database folder
// Container: quay.io/biocontainers/bioconductor-scifer:1.12.0--r45hdfd78af_0
// R packages: ggplot2, sangerseqR, scifer
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SCIFER_BCR_TCR_FLOW_SANGER_INTEGRATION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-scifer:1.12.0--r45hdfd78af_0"

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
    .bm_deps <- c("ggplot2", "sangerseqR", "scifer")
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
    library(ggplot2)
    library(scifer)
    library(sangerseqR)
    
    # ==========================================
    # 1. AUTOMATED INPUT FILE DISCOVERY
    # ==========================================
    
    message("Searching for input files in the working directory...")
    
    # Discover FCS files and determine the appropriate folder path
    fcs_files <- list.files(pattern = "\\\\.fcs\$", recursive = TRUE, full.names = TRUE)
    if (length(fcs_files) == 0) {
        stop("Error: No .fcs files found in the working directory or its subdirectories.")
    }
    # Extract the top-level directory containing the FCS files
    fcs_parts <- strsplit(fcs_files[1], "/")[[1]]
    fcs_parts <- fcs_parts[fcs_parts != "."]
    if (length(fcs_parts) > 2) {
        fcs_folder <- fcs_parts[1]
    } else {
        fcs_folder <- dirname(fcs_files[1])
    }
    message("Using FCS folder: ", fcs_folder)
    
    # Discover AB1 files and determine the appropriate folder path
    ab1_files <- list.files(pattern = "\\\\.ab1\$", recursive = TRUE, full.names = TRUE)
    if (length(ab1_files) == 0) {
        stop("Error: No .ab1 files found in the working directory or its subdirectories.")
    }
    # Extract the top-level directory containing the AB1 files
    ab1_parts <- strsplit(ab1_files[1], "/")[[1]]
    ab1_parts <- ab1_parts[ab1_parts != "."]
    if (length(ab1_parts) > 2) {
        ab1_folder <- ab1_parts[1]
    } else {
        ab1_folder <- dirname(ab1_files[1])
    }
    message("Using Sanger sequences folder: ", ab1_folder)
    
    # Discover IgBlast database folder containing V.fasta, D.fasta, and J.fasta
    db_dirs <- list.dirs(".", recursive = TRUE, full.names = TRUE)
    igblast_db <- NULL
    for (d in db_dirs) {
        files <- list.files(d)
        if (all(c("V.fasta", "D.fasta", "J.fasta") %in% files)) {
            igblast_db <- d
            break
        }
    }
    if (is.null(igblast_db)) {
        stop("Error: IgBlast database folder containing V.fasta, D.fasta, and J.fasta not found.")
    }
    message("Using IgBlast database folder: ", igblast_db)
    
    
    # ==========================================
    # 2. FLOW CYTOMETRY INDEX SORTING PROCESSING
    # ==========================================
    
    message("Processing flow cytometry index sorting data...")
    fcs_data <- fcs_processing(
        folder_path = fcs_folder,
        compensation = TRUE, plate_wells = 96,
        probe1 = "Pre.F", probe2 = "Post.F",
        posvalue_probe1 = 600, posvalue_probe2 = 400
    )
    
    # Generate and save the flow cytometry plot
    message("Generating flow cytometry plot...")
    p_fcs <- fcs_plot(fcs_data)
    ggsave("fcs_index_sorting_plot.pdf", plot = p_fcs, width = 8, height = 6)
    
    # Display metadata and unique specificities
    message("FCS Data Columns:")
    print(colnames(fcs_data))
    
    message("Unique Specificities Assigned:")
    print(unique(fcs_data\$specificity))
    
    # Save processed FCS data
    saveRDS(fcs_data, "fcs_data_processed.rds")
    
    
    # ==========================================
    # 3. SANGER SEQUENCING QUALITY CONTROL
    # ==========================================
    
    message("Processing a single Sanger sequence for quality control...")
    abi_seq <- sangerseqR::read.abif(ab1_files[1])
    
    summarised <- summarise_abi_file(abi_seq)
    message("Single sequence summary:")
    print(head(summarised[["summary"]]))
    message("Single sequence quality scores:")
    print(head(summarised[["quality_score"]]))
    
    # Save single sequence QC results
    write.csv(summarised[["summary"]], "single_sequence_summary.csv", row.names = FALSE)
    write.csv(summarised[["quality_score"]], "single_sequence_quality_scores.csv", row.names = FALSE)
    
    message("Processing all Sanger sequences in the folder...")
    sf <- summarise_quality(
        folder_sequences = ab1_folder,
        secondary.peak.ratio = 0.33, trim.cutoff = 0.01, processor = 1
    )
    
    message("Summarised Sanger sequence columns:")
    print(colnames(sf[["summaries"]]))
    
    message("Sanger sequence quality summaries (head):")
    print(head(sf[["summaries"]][4:10]))
    
    # Save batch quality summaries
    write.csv(sf[["summaries"]], "sanger_batch_quality_summaries.csv", row.names = FALSE)
    
    
    # ==========================================
    # 4. DATA INTEGRATION & QUALITY REPORT
    # ==========================================
    
    message("Integrating flow cytometry and Sanger sequencing data...")
    output_dir <- "QC_Report_Output"
    if (!dir.exists(output_dir)) {
        dir.create(output_dir, recursive = TRUE)
    }
    
    quality_report(
        folder_sequences = ab1_folder,
        outputfile = "QC_report.html", 
        output_dir = output_dir,
        folder_path_fcs = fcs_folder,
        probe1 = "Pre.F", probe2 = "Post.F",
        posvalue_probe1 = 600, posvalue_probe2 = 400
    )
    
    message("Quality report and integrated outputs generated in: ", output_dir)
    
    
    # ==========================================
    # 5. IGBLAST ANALYSIS
    # ==========================================
    
    message("Running IgBlast analysis...")
    
    # Locate the generated fasta file from the quality report output directory
    fasta_path <- file.path(output_dir, "sequences.fasta")
    if (!file.exists(fasta_path)) {
        # Fallback: search for any generated fasta file in the output directory
        fasta_files <- list.files(output_dir, pattern = "\\\\.(fasta|txt)\$", full.names = TRUE)
        if (length(fasta_files) > 0) {
            fasta_path <- fasta_files[1]
        } else {
            warning("No fasta file found in the quality report output directory. Skipping IgBlast.")
            fasta_path <- NULL
        }
    }
    
    if (!is.null(fasta_path)) {
        # Wrap in tryCatch to handle potential system-level conda/basilisk dependencies gracefully
        tryCatch({
            ighv_res <- igblast(
                database = igblast_db,
                fasta = fasta_path,
                threads = 1
            )
            
            message("IgBlast analysis completed successfully. Preview of results:")
            print(head(ighv_res, 2))
            
            # Save IgBlast results
            write.csv(ighv_res, "igblast_analysis_results.csv", row.names = FALSE)
        }, error = function(e) {
            warning("IgBlast analysis failed or was skipped due to environment constraints: ", e\$message)
        })
    }
    
    message("Pipeline execution completed successfully.")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_SCIFER_BCR_TCR_FLOW_SANGER_INTEGRATION":
        scifer: \$(Rscript -e 'cat(as.character(packageVersion("scifer")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_bcr_tcr_flow_sanger_integration.csv versions.yml
    """
}

workflow BIOC_SCIFER_BCR_TCR_FLOW_SANGER_INTEGRATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ .fcs files, .ab1 files, IgBlast database folder ] ]

    main:
    BIOC_SCIFER_BCR_TCR_FLOW_SANGER_INTEGRATION(ch_input)

    emit:
    tables   = BIOC_SCIFER_BCR_TCR_FLOW_SANGER_INTEGRATION.out.tables
    plots    = BIOC_SCIFER_BCR_TCR_FLOW_SANGER_INTEGRATION.out.plots
    objects  = BIOC_SCIFER_BCR_TCR_FLOW_SANGER_INTEGRATION.out.objects
    versions = BIOC_SCIFER_BCR_TCR_FLOW_SANGER_INTEGRATION.out.versions
}
