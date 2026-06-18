#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: Rbowtie2 — adapter_trimming_and_alignment
// Preprocess raw paired-end sequencing reads by identifying and removing adapters, building a Bowtie2 index, and aligning the trimmed reads to the reference genom
// Input: reads_1.fq, reads_2.fq, refs
// Container: quay.io/biocontainers/bioconductor-rbowtie2:2.16.0--r45ha27e39d_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Rbowtie2
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Identify adapter sequences from raw paired-end reads using identify_adapters
//  * 2. [Core Analysis] Trim identified adapters from reads using remove_adapters
//  * 3. [Input & Preparation] Build a Bowtie2 index from reference FASTA files using bowtie2_build
//  * 4. [Core Analysis] Align the trimmed reads to the reference index using bowtie2_samtools to generate a SAM file

nextflow.enable.dsl = 2

process BIOC_RBOWTIE2_ADAPTER_TRIMMING_AND_ALIGNMENT {
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
    .bm_deps <- c("Rbowtie2")
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
    
    # Load required library
    library(Rbowtie2)
    
    # Define input file paths from the working directory
    input_reads_1 <- "reads_1.fq"
    input_reads_2 <- "reads_2.fq"
    
    # Verify that input FASTQ files exist
    if (!file.exists(input_reads_1) || !file.exists(input_reads_2)) {
        stop("Required input files 'reads_1.fq' and/or 'reads_2.fq' are missing from the working directory.")
    }
    
    # Resolve reference genome files
    if (dir.exists("refs")) {
        refs_files <- list.files("refs", full.names = TRUE)
        if (length(refs_files) == 0) {
            stop("The 'refs' directory is empty.")
        }
    } else if (file.exists("refs")) {
        refs_files <- "refs"
    } else {
        # Fallback: search for files starting with 'refs' in the working directory
        refs_files <- list.files(pattern = "^refs")
        if (length(refs_files) == 0) {
            stop("Reference genome files ('refs') not found in the working directory.")
        }
    }
    
    # Create a temporary directory for intermediate processing
    td <- tempdir()
    
    # 1. Identify adapter sequences from raw paired-end reads
    adapters <- identify_adapters(
        file1 = input_reads_1,
        file2 = input_reads_2,
        basename = file.path(td, "reads"),
        "--threads 3",
        overwrite = TRUE
    )
    
    # Save identified adapters to a CSV file
    write.csv(
        data.frame(Read = c("Read1", "Read2"), Adapter = adapters),
        file = "identified_adapters.csv",
        row.names = FALSE
    )
    
    # Define paths for trimmed output files
    trimmed_1 <- file.path(td, "reads_1.trimmed.fq")
    trimmed_2 <- file.path(td, "reads_2.trimmed.fq")
    
    # 2. Trim identified adapters from reads
    cmdout_trim <- remove_adapters(
        file1 = input_reads_1,
        file2 = input_reads_2,
        adapter1 = adapters[1], 
        adapter2 = adapters[2],
        output1 = trimmed_1,
        output2 = trimmed_2,
        basename = file.path(td, "reads.base"),
        overwrite = TRUE,
        "--threads 3"
    )
    
    # Copy trimmed FASTQ files to the working directory as output
    file.copy(trimmed_1, "reads_1.trimmed.fq", overwrite = TRUE)
    file.copy(trimmed_2, "reads_2.trimmed.fq", overwrite = TRUE)
    
    # 3. Build a Bowtie2 index from reference FASTA files
    cmdout_build <- bowtie2_build(
        references = refs_files, 
        bt2Index = file.path(td, "lambda_virus"), 
        "--threads 4 --quiet",
        overwrite = TRUE
    )
    
    # 4. Align the trimmed reads to the reference index using bowtie2_samtools
    cmdout_align <- NULL
    if (file.exists(file.path(td, "lambda_virus.1.bt2")) || file.exists(file.path(td, "lambda_virus.1.bt2l"))) {
        cmdout_align <- bowtie2_samtools(
            bt2Index = file.path(td, "lambda_virus"),
            output = file.path(td, "result"),
            outputType = "sam",
            seq1 = trimmed_1,
            seq2 = trimmed_2,
            overwrite = TRUE,
            bamFile = NULL,
            "--threads 3"
        )
        
        # Copy the resulting SAM file to the working directory
        file.copy(file.path(td, "result.sam"), "alignment_result.sam", overwrite = TRUE)
        
        # Print the first few lines of the SAM file to console
        cat("--- SAM File Header Preview ---\n")
        print(head(readLines("alignment_result.sam")))
    } else {
        stop("Bowtie2 index generation failed; alignment step skipped.")
    }
    
    # Save a summary log of the pipeline execution
    writeLines(
        c(
            "=== Rbowtie2 Pipeline Execution Summary ===",
            paste("Date:", Sys.time()),
            "\n--- Adapter Identification ---",
            paste("Adapter 1:", adapters[1]),
            paste("Adapter 2:", adapters[2]),
            "\n--- Adapter Removal Output ---",
            cmdout_trim,
            "\n--- Bowtie2 Build Output ---",
            paste(cmdout_build, collapse = "\n"),
            "\n--- Bowtie2 Alignment Output ---",
            paste(cmdout_align, collapse = "\n")
        ),
        con = "pipeline_summary.log"
    )

    writeLines(c(
        '"BIOC_RBOWTIE2_ADAPTER_TRIMMING_AND_ALIGNMENT":',
        paste0('    Rbowtie2: ', as.character(packageVersion('Rbowtie2')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_adapter_trimming_and_alignment.csv versions.yml
    """
}

workflow BIOC_RBOWTIE2_ADAPTER_TRIMMING_AND_ALIGNMENT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ reads_1.fq, reads_2.fq, refs ] ]

    main:
    BIOC_RBOWTIE2_ADAPTER_TRIMMING_AND_ALIGNMENT(ch_input)

    emit:
    tables   = BIOC_RBOWTIE2_ADAPTER_TRIMMING_AND_ALIGNMENT.out.tables
    plots    = BIOC_RBOWTIE2_ADAPTER_TRIMMING_AND_ALIGNMENT.out.plots
    objects  = BIOC_RBOWTIE2_ADAPTER_TRIMMING_AND_ALIGNMENT.out.objects
    versions = BIOC_RBOWTIE2_ADAPTER_TRIMMING_AND_ALIGNMENT.out.versions
}
