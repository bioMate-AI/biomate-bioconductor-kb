#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: Rbowtie — spliced_alignment_splicemap
// Perform de novo splice junction discovery and alignment for reads >= 50bp.
// Input: refDir, readsFiles
// Container: quay.io/biocontainers/bioconductor-rbowtie:1.50.0--r45ha27e39d_0
// R packages: Rbowtie
// Bioconductor: 3.20 | R: 4.4
// Requires: Rbowtie
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Define configuration parameters in a named list
//  * 2. [Core Analysis] Run spliced alignment using SpliceMap

nextflow.enable.dsl = 2

process BIOC_RBOWTIE_SPLICED_ALIGNMENT_SPLICEMAP {
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
    .bm_deps <- c("Rbowtie")
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
    
    # Load required library
    library(Rbowtie)
    
    # 1. Define input file paths in the working directory
    refDir <- "chr1.fa"
    readsFiles <- "reads.fastq"
    
    # Robust fallback: search working directory if defaults do not exist
    if (!file.exists(refDir)) {
      fa_files <- list.files(pattern = "\\\\.(fa|fasta|fna)\$", ignore.case = TRUE)
      if (length(fa_files) > 0) {
        refDir <- fa_files[1]
      }
    }
    
    if (!file.exists(readsFiles)) {
      fq_files <- list.files(pattern = "\\\\.(fastq|fq)\$", ignore.case = TRUE)
      if (length(fq_files) > 0) {
        readsFiles <- fq_files[1]
      }
    }
    
    # Determine reference files (handle if refDir is a directory or a single file)
    if (dir.exists(refDir)) {
      refFiles <- list.files(refDir, pattern = "\\\\.(fa|fasta|fna)\$", full.names = TRUE, ignore.case = TRUE)
    } else {
      refFiles <- refDir
    }
    
    # Determine read format dynamically based on input file extension
    read_fmt <- "FASTQ"
    if (any(grepl("\\\\.(fasta|fa|fna)\$", readsFiles, ignore.case = TRUE))) {
      read_fmt <- "FASTA"
    }
    
    # 2. Build the reference index using bowtie_build (required for SpliceMap)
    indexDir <- file.path(getwd(), "refsIndex")
    if (!dir.exists(indexDir)) {
      dir.create(indexDir, recursive = TRUE)
    }
    
    tmp <- bowtie_build(references=refFiles, outdir=indexDir, prefix="index", force=TRUE)
    
    # 3. Define configuration parameters in a named list
    samFiles <- file.path(getwd(), "splicedAlignments.sam")
    
    cfg <- list(genome_dir=refDir,
                reads_list1=readsFiles,
                read_format=read_fmt,
                quality_format="phred-33",
                outfile=samFiles,
                temp_path=tempdir(),
                max_intron=400000,
                min_intron=20000,
                max_multi_hit=10,
                seed_mismatch=1,
                read_mismatch=2,
                num_chromosome_together=2,
                bowtie_base_dir=file.path(indexDir, "index"),
                num_threads=4,
                try_hard="yes",
                selectSingleHit=TRUE)
    
    # 4. Run spliced alignment using SpliceMap
    res <- SpliceMap(cfg)
    
    # 5. Write outputs
    saveRDS(res, "splicemap_result.rds")
    
    # Generate and write summary CSV
    if (file.exists(samFiles)) {
      sam_lines <- readLines(samFiles, n = 100)
      summary_df <- data.frame(
        Metric = c("OutputSAMFile", "TotalLinesRead", "IsSAMHeaderPresent"),
        Value = c(samFiles, length(sam_lines), any(grepl("^@", sam_lines)))
      )
      write.csv(summary_df, "splicemap_summary.csv", row.names = FALSE)
    } else {
      summary_df <- data.frame(
        Metric = c("Status"),
        Value = c("SAM file not found")
      )
      write.csv(summary_df, "splicemap_summary.csv", row.names = FALSE)
    }

    writeLines(c(
        '"BIOC_RBOWTIE_SPLICED_ALIGNMENT_SPLICEMAP":',
        paste0('    Rbowtie: ', as.character(packageVersion('Rbowtie')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_spliced_alignment_splicemap.csv versions.yml
    """
}

workflow BIOC_RBOWTIE_SPLICED_ALIGNMENT_SPLICEMAP_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ refDir, readsFiles ] ]

    main:
    BIOC_RBOWTIE_SPLICED_ALIGNMENT_SPLICEMAP(ch_input)

    emit:
    tables   = BIOC_RBOWTIE_SPLICED_ALIGNMENT_SPLICEMAP.out.tables
    plots    = BIOC_RBOWTIE_SPLICED_ALIGNMENT_SPLICEMAP.out.plots
    objects  = BIOC_RBOWTIE_SPLICED_ALIGNMENT_SPLICEMAP.out.objects
    versions = BIOC_RBOWTIE_SPLICED_ALIGNMENT_SPLICEMAP.out.versions
}
