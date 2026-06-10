#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: shortread — fastq_filtering_and_trimming
// Iterate through a FASTQ file in chunks to filter out low-quality reads and trim low-quality ends.
// Input: a.fastq.gz
// Container: quay.io/biocontainers/bioconductor-shortread:1.68.0--r45ha27e39d_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SHORTREAD_FASTQ_FILTERING_AND_TRIMMING {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-shortread:1.68.0--r45ha27e39d_0"

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
    .bm_deps <- c("shortread")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    library(ShortRead)
    
    # Define input and output file paths
    input_file <- "a.fastq.gz"
    output_file <- "a_subset.fastq.gz"
    
    # Clean up any pre-existing output file to prevent appending to old results
    if (file.exists(output_file)) {
        file.remove(output_file)
    }
    
    # Documented filtering and trimming function (reproduced exactly)
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
    
    # Execute the workflow on the user-provided input file
    myFilterAndTrim(input_file, output_file)
    
    # Generate downstream analysis and summary outputs
    # 1. Compare read and nucleotide counts before and after filtering
    counts_in <- countFastq(input_file)
    counts_out <- countFastq(output_file)
    
    counts_df <- rbind(
        Input = counts_in,
        Output = counts_out
    )
    write.csv(counts_df, "fastq_filtering_counts.csv", row.names = TRUE)
    
    # 2. Read the processed FASTQ file to summarize sequence occurrences
    fq_out <- readFastq(output_file)
    tbls <- tables(fq_out)
    
    # Save top sequences
    top_seqs <- data.frame(
        Sequence = names(tbls\$top),
        Count = as.vector(tbls\$top)
    )
    write.csv(head(top_seqs, 100), "top_filtered_sequences.csv", row.names = FALSE)
    
    # Save sequence occurrence distribution
    write.csv(tbls\$distribution, "sequence_distribution.csv", row.names = FALSE)
    
    # 3. Perform Quality Assessment (QA) on the filtered file
    qa_summary <- qa(output_file, type = "fastq")
    saveRDS(qa_summary, "qa_summary_filtered.rds")
    
    # Extract and save specific QA tables
    write.csv(qa_summary[["readCounts"]], "qa_read_counts.csv", row.names = TRUE)
    write.csv(qa_summary[["baseCalls"]], "qa_base_calls.csv", row.names = TRUE)

    cat <<-END_VERSIONS > versions.yml
    "BIOC_SHORTREAD_FASTQ_FILTERING_AND_TRIMMING":
        shortread: \$(Rscript -e 'cat(as.character(packageVersion("shortread")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_fastq_filtering_and_trimming.csv versions.yml
    """
}

workflow BIOC_SHORTREAD_FASTQ_FILTERING_AND_TRIMMING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ a.fastq.gz ] ]

    main:
    BIOC_SHORTREAD_FASTQ_FILTERING_AND_TRIMMING(ch_input)

    emit:
    tables   = BIOC_SHORTREAD_FASTQ_FILTERING_AND_TRIMMING.out.tables
    plots    = BIOC_SHORTREAD_FASTQ_FILTERING_AND_TRIMMING.out.plots
    objects  = BIOC_SHORTREAD_FASTQ_FILTERING_AND_TRIMMING.out.objects
    versions = BIOC_SHORTREAD_FASTQ_FILTERING_AND_TRIMMING.out.versions
}
