#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: apalyzer — paired_end_3most_extraction
// Extract the 3'-most alignment from paired-end BAM files to prepare them for accurate APA analysis.
// Input: Bamfile, Outdir
// Container: quay.io/biocontainers/bioconductor-apalyzer:1.20.0--r44hdfd78af_0
// R packages: APAlyzer
// Bioconductor: 3.20 | R: 4.4
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_APALYZER_PAIRED_END_3MOST_EXTRACTION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-apalyzer:1.20.0--r44hdfd78af_0"

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
    .bm_deps <- c("APAlyzer")
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
    library(APAlyzer)
    
    # USER INPUTS — Read from environment variables or use defaults
    Bamfile <- Sys.getenv("BAM_FILE", unset = "input.bam")
    Outdir <- Sys.getenv("OUT_DIR", unset = "output_dir")
    
    # Ensure output directory exists
    if (!dir.exists(Outdir)) {
      dir.create(Outdir, recursive = TRUE)
    }
    
    # Verify input BAM file exists
    if (!file.exists(Bamfile)) {
      stop(paste("Input BAM file not found at:", Bamfile))
    }
    
    # Load genomic reference (dfIPA and dfLE) from official repository
    message("Loading genomic reference...")
    ref_url <- "https://github.com/RJWANGbioinfo/PAS_reference_RData/blob/master/mm9_REF.RData?raw=True"
    con <- url(ref_url)
    load(con)
    close(con)
    
    # --- Extract 3'-most alignments using ThreeMostPairBam ---
    message("Extracting 3'-most alignments...")
    ThreeMostPairBam (BamfilePath=Bamfile,
    					OutDirPath=Outdir,
    					StrandType='forward-reverse')
    
    # Determine the path of the extracted BAM file
    # ThreeMostPairBam saves the output as [input_base].3most.bam in OutDirPath
    bam_base <- basename(Bamfile)
    expected_name <- gsub("\\\\.bam\$", ".3most.bam", bam_base)
    ThreemostBamfile <- file.path(Outdir, expected_name)
    
    # Verify the extracted BAM file exists
    if (!file.exists(ThreemostBamfile)) {
      # Fallback search in case of naming variations
      found_files <- list.files(Outdir, pattern = "\\\\.3most\\\\.bam\$", full.names = TRUE)
      if (length(found_files) > 0) {
        ThreemostBamfile <- found_files[1]
      } else {
        stop("Extracted 3'-most BAM file could not be found in the output directory.")
      }
    }
    
    # --- Use the extracted BAM file in PASEXP_IPA with SeqType set ---
    message("Calculating relative expression of IPAs...")
    IPA_OUTraw=PASEXP_IPA(dfIPA, dfLE, ThreemostBamfile, Strandtype="forward", SeqType="ThreeMostPairEnd")
    
    # Write named output files
    message("Saving results...")
    write.csv(IPA_OUTraw, file = file.path(Outdir, "IPA_OUTraw.csv"), row.names = FALSE)
    saveRDS(IPA_OUTraw, file = file.path(Outdir, "IPA_OUTraw.rds"))
    
    message("Pipeline completed successfully!")

    writeLines(c(
        '"BIOC_APALYZER_PAIRED_END_3MOST_EXTRACTION":',
        paste0('        apalyzer: ', as.character(packageVersion("apalyzer")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_paired_end_3most_extraction.csv versions.yml
    """
}

workflow BIOC_APALYZER_PAIRED_END_3MOST_EXTRACTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ Bamfile, Outdir ] ]

    main:
    BIOC_APALYZER_PAIRED_END_3MOST_EXTRACTION(ch_input)

    emit:
    tables   = BIOC_APALYZER_PAIRED_END_3MOST_EXTRACTION.out.tables
    plots    = BIOC_APALYZER_PAIRED_END_3MOST_EXTRACTION.out.plots
    objects  = BIOC_APALYZER_PAIRED_END_3MOST_EXTRACTION.out.objects
    versions = BIOC_APALYZER_PAIRED_END_3MOST_EXTRACTION.out.versions
}
