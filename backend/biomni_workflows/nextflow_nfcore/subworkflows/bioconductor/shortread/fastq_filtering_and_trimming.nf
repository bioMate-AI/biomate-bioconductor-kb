#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ShortRead — fastq_filtering_and_trimming
// Stream through a large FASTQ file, apply quality and composition filters, trim low-quality ends, and write the processed reads to a new file.
// Input: file.fastq
// Container: quay.io/biocontainers/bioconductor-shortread:1.68.0--r45ha27e39d_0
// R packages: ShortRead
// Bioconductor: 3.20 | R: 4.4
// Requires: ShortRead
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Open the input FASTQ file stream using FastqStreamer and open
//  * 2. [Core Analysis] Iterate through the file in chunks using yield
//  * 3. [Core Analysis] Filter out reads containing Ns using nFilter
//  * 4. [Core Analysis] Trim low-quality tails using trimTailw
//  * 5. [Core Analysis] Filter reads by minimum width
//  * 6. [Visualization & Output] Append the processed reads to the destination file using writeFastq
//  * 7. [Core Analysis] Close the stream using close

nextflow.enable.dsl = 2

process BIOC_SHORTREAD_FASTQ_FILTERING_AND_TRIMMING {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20-slim"

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
    .bm_deps <- c("ShortRead")
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
            
    library(ShortRead)
    
    # Define input and output files
    input_file <- "file.fastq"
    output_file <- "file_filtered.fastq"
    
    # Ensure input file exists
    if (!file.exists(input_file)) {
        stop(paste("Input file", input_file, "does not exist in the working directory."))
    }
    
    # If output file exists, remove it to avoid appending to an old run
    if (file.exists(output_file)) {
        file.remove(output_file)
    }
    
    # Get initial counts
    initial_stats <- countFastq(input_file)
    
    # Define the documented function EXACTLY as requested
    myFilterAndTrim <-
        function(fl, destination=sprintf("%s_subset", fl))
    {
        ## open input stream
        stream <- open(FastqStreamer(fl))
        on.exit(close(stream))
        repeat {
            ## input chunk
            fq <- yield(stream)
            if (length(fq) == 0)
                break
            ## trim and filter, e.g., reads cannot contain 'N'...
            fq <- fq[nFilter()(fq)]  # see ?srFilter for pre-defined filters
            ## trim as soon as 2 of 5 nucleotides has quality encoding less
            ## than "4" (phred score 20)
            fq <- trimTailw(fq, 2, "4", 2)
            ## drop reads that are less than 36nt
            fq <- fq[width(fq) >= 36]
            ## append to destination
            writeFastq(fq, destination, "a")
        }
    }
    
    # Run the filtering and trimming workflow
    myFilterAndTrim(fl = input_file, destination = output_file)
    
    # Get final counts
    final_stats <- countFastq(output_file)
    
    # Create a summary data frame of the filtering process
    summary_df <- data.frame(
        Stage = c("Before_Filtering", "After_Filtering"),
        Reads = c(initial_stats\$records, final_stats\$records),
        Nucleotides = c(initial_stats\$nucleotides, final_stats\$nucleotides)
    )
    
    # Write summary to CSV
    write.csv(summary_df, "filtering_summary.csv", row.names = FALSE)
    
    # Sample the filtered fastq to generate downstream summaries memory-efficiently
    sampler <- FastqSampler(output_file)
    filtered_fq <- yield(sampler)
    tbls <- tables(filtered_fq)
    
    # Save top sequences to CSV
    top_seqs <- data.frame(
        Sequence = names(tbls\$top),
        Count = as.integer(tbls\$top)
    )
    write.csv(head(top_seqs, 100), "top_filtered_sequences.csv", row.names = FALSE)
    
    # Save sequence occurrence distribution to CSV
    write.csv(tbls\$distribution, "sequence_occurrence_distribution.csv", row.names = FALSE)
    
    # Save the filtered ShortReadQ object as RDS for downstream analysis
    saveRDS(filtered_fq, "filtered_reads.rds")

    writeLines(c(
        '"BIOC_SHORTREAD_FASTQ_FILTERING_AND_TRIMMING":',
        paste0('    ShortRead: ', as.character(packageVersion('ShortRead')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_fastq_filtering_and_trimming.csv versions.yml
    """
}

workflow BIOC_SHORTREAD_FASTQ_FILTERING_AND_TRIMMING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ file.fastq ] ]

    main:
    BIOC_SHORTREAD_FASTQ_FILTERING_AND_TRIMMING(ch_input)

    emit:
    tables   = BIOC_SHORTREAD_FASTQ_FILTERING_AND_TRIMMING.out.tables
    plots    = BIOC_SHORTREAD_FASTQ_FILTERING_AND_TRIMMING.out.plots
    objects  = BIOC_SHORTREAD_FASTQ_FILTERING_AND_TRIMMING.out.objects
    versions = BIOC_SHORTREAD_FASTQ_FILTERING_AND_TRIMMING.out.versions
}
