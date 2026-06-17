#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: fastqcleaner — fastq_preprocessing_and_filtering
// Filter, trim, and clean FASTQ reads using a sequence of quality, length, adapter, and complexity filters.
// Input: example_fastq.gz
// Container: quay.io/biocontainers/bioconductor-fastqcleaner:1.28.0--r45ha27e39d_0
// R packages: Biostrings, FastqCleaner, ShortRead
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_FASTQCLEANER_FASTQ_PREPROCESSING_AND_FILTERING {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-fastqcleaner:1.28.0--r45ha27e39d_0"

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
    .bm_deps <- c("Biostrings", "FastqCleaner", "ShortRead")
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
    library(ShortRead)
    library(Biostrings)
    library(FastqCleaner)
    
    # ==========================================
    # --- Load FASTQ data into a ShortReadQ object ---
    # ==========================================
    input_file <- "example_fastq.gz"
    
    if (!file.exists(input_file)) {
      stop(paste("Required input file missing:", input_file))
    }
    
    # Read the raw FASTQ file
    raw_read <- readFastq(input_file)
    my_read <- raw_read
    
    # Initialize a data frame to track read counts at each stage
    stats <- data.frame(
      Stage = "Raw Reads",
      Reads = length(my_read),
      Average_Length = mean(width(sread(my_read))),
      stringsAsFactors = FALSE
    )
    
    # ==========================================
    # --- Filter adapters using adapter_filter ---
    # ==========================================
    # Trim 5' adapter (Lpattern) and 3' adapter (Rpattern)
    adapter_seq <- "ATCGACT"
    
    my_read <- adapter_filter(my_read, Lpattern = adapter_seq)
    my_read <- adapter_filter(my_read, Rpattern = adapter_seq)
    
    stats <- rbind(stats, data.frame(
      Stage = "Adapter Filter",
      Reads = length(my_read),
      Average_Length = mean(width(sread(my_read)))
    ))
    
    # ==========================================
    # --- Filter low complexity sequences using complex_filter ---
    # ==========================================
    my_read <- complex_filter(my_read)
    
    stats <- rbind(stats, data.frame(
      Stage = "Complexity Filter",
      Reads = length(my_read),
      Average_Length = mean(width(sread(my_read)))
    ))
    
    # ==========================================
    # --- Trim fixed bases using fixed_filter ---
    # ==========================================
    # Trim 5 bases from 5' end and 10 bases from 3' end
    my_read <- fixed_filter(my_read, trim3 = 10, trim5 = 5)
    
    stats <- rbind(stats, data.frame(
      Stage = "Fixed Trimming (5' & 3')",
      Reads = length(my_read),
      Average_Length = mean(width(sread(my_read)))
    ))
    
    # ==========================================
    # --- Filter by length using length_filter ---
    # ==========================================
    # Remove sequences with length < 10 or length > 150
    my_read <- length_filter(my_read, rm.min = 10, rm.max = 150)
    
    stats <- rbind(stats, data.frame(
      Stage = "Length Filter",
      Reads = length(my_read),
      Average_Length = mean(width(sread(my_read)))
    ))
    
    # ==========================================
    # --- Filter by Ns using n_filter ---
    # ==========================================
    # Remove sequences with more than 3 Ns
    my_read <- n_filter(my_read, rm.N = 3)
    
    stats <- rbind(stats, data.frame(
      Stage = "N Filter",
      Reads = length(my_read),
      Average_Length = mean(width(sread(my_read)))
    ))
    
    # ==========================================
    # --- Filter by average quality using qmean_filter ---
    # ==========================================
    # Remove sequences with average Phred quality < 20
    my_read <- qmean_filter(my_read, minq = 20)
    
    stats <- rbind(stats, data.frame(
      Stage = "Quality Mean Filter",
      Reads = length(my_read),
      Average_Length = mean(width(sread(my_read)))
    ))
    
    # ==========================================
    # --- Filter specific matching sequences using seq_filter ---
    # ==========================================
    # Remove sequences containing specific unwanted patterns
    unwanted_patterns <- c("TGGTC", "CGGT", "GTTCT", "ATA")
    my_read <- seq_filter(my_read, rm.seq = unwanted_patterns)
    
    stats <- rbind(stats, data.frame(
      Stage = "Sequence Pattern Filter",
      Reads = length(my_read),
      Average_Length = mean(width(sread(my_read)))
    ))
    
    # ==========================================
    # --- Trim low quality 3' tails using trim3q_filter ---
    # ==========================================
    # Trim 3' nucleotides with quality score < 20
    my_read <- trim3q_filter(my_read, rm.3qual = 20)
    
    stats <- rbind(stats, data.frame(
      Stage = "3' Quality Tail Trimming",
      Reads = length(my_read),
      Average_Length = mean(width(sread(my_read)))
    ))
    
    # ==========================================
    # --- Remove duplicate sequences using unique_filter ---
    # ==========================================
    my_read <- unique_filter(my_read)
    
    stats <- rbind(stats, data.frame(
      Stage = "Duplicate Filter (Unique)",
      Reads = length(my_read),
      Average_Length = mean(width(sread(my_read)))
    ))
    
    # ==========================================
    # Write Outputs
    # ==========================================
    
    # 1. Write the final cleaned FASTQ file
    writeFastq(my_read, "cleaned_fastq.gz", compress = TRUE)
    
    # 2. Write the preprocessing summary table
    write.csv(stats, "preprocessing_summary.csv", row.names = FALSE)
    
    # 3. Generate diagnostic plots
    pdf("preprocessing_diagnostics.pdf", width = 10, height = 8)
    par(mfrow = c(2, 2))
    
    # Plot 1: Read length distribution before filtering
    hist(width(sread(raw_read)), 
         main = "Read Lengths (Before)", 
         xlab = "Length (bp)", 
         col = "skyblue", 
         border = "white")
    
    # Plot 2: Read length distribution after filtering
    hist(width(sread(my_read)), 
         main = "Read Lengths (After)", 
         xlab = "Length (bp)", 
         col = "palegreen", 
         border = "white")
    
    # Plot 3: Mean quality score distribution before filtering
    hist(alphabetScore(quality(raw_read)) / width(raw_read), 
         main = "Mean Quality (Before)", 
         xlab = "Phred Score", 
         col = "skyblue", 
         border = "white")
    
    # Plot 4: Mean quality score distribution after filtering
    hist(alphabetScore(quality(my_read)) / width(my_read), 
         main = "Mean Quality (After)", 
         xlab = "Phred Score", 
         col = "palegreen", 
         border = "white")
    
    dev.off()

    writeLines(c(
        '"BIOC_FASTQCLEANER_FASTQ_PREPROCESSING_AND_FILTERING":',
        paste0('        fastqcleaner: ', as.character(packageVersion("fastqcleaner")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_fastq_preprocessing_and_filtering.csv versions.yml
    """
}

workflow BIOC_FASTQCLEANER_FASTQ_PREPROCESSING_AND_FILTERING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ example_fastq.gz ] ]

    main:
    BIOC_FASTQCLEANER_FASTQ_PREPROCESSING_AND_FILTERING(ch_input)

    emit:
    tables   = BIOC_FASTQCLEANER_FASTQ_PREPROCESSING_AND_FILTERING.out.tables
    plots    = BIOC_FASTQCLEANER_FASTQ_PREPROCESSING_AND_FILTERING.out.plots
    objects  = BIOC_FASTQCLEANER_FASTQ_PREPROCESSING_AND_FILTERING.out.objects
    versions = BIOC_FASTQCLEANER_FASTQ_PREPROCESSING_AND_FILTERING.out.versions
}
