#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: bbcanalyzer — complete_base_analysis
// Run the complete pipeline to analyze BAM files at target regions, output frequency and calling text files, and generate visual barplots.
// Input: SampleNames.txt, targetRegions.txt, [Sample].bam and [Sample].bai, [Sample].vcf, dbsnp_138.part.vcf.gz
// Container: quay.io/biocontainers/bioconductor-bbcanalyzer:1.40.0--r45hdfd78af_0
// R packages: BSgenome.Hsapiens.UCSC.hg19, BBCAnalyzer
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BBCANALYZER_COMPLETE_BASE_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-bbcanalyzer:1.40.0--r45hdfd78af_0"

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
    .bm_deps <- c("BSgenome.Hsapiens.UCSC.hg19", "BBCAnalyzer")
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
    library(BBCAnalyzer)
    library(BSgenome.Hsapiens.UCSC.hg19)
    
    # Define input file paths in the working directory
    sample_file <- "SampleNames.txt"
    target_file <- "targetRegions.txt"
    bam_folder <- "."
    output_folder <- "."
    output_pics_folder <- "."
    known_polymorphisms <- "dbsnp_138.part.vcf.gz"
    
    # Validate mandatory inputs
    if (!file.exists(sample_file)) {
      stop(paste("Required sample names file missing:", sample_file))
    }
    if (!file.exists(target_file)) {
      stop(paste("Required target regions file missing:", target_file))
    }
    
    # Determine if optional VCF files are present in the working directory
    vcf_folder <- ""
    vcf_files <- list.files(path = ".", pattern = "\\\\.vcf\$", full.names = TRUE)
    if (length(vcf_files) > 0) {
      vcf_folder <- "."
    }
    
    # Determine if optional known polymorphisms file is present
    known_file_path <- ""
    if (file.exists(known_polymorphisms)) {
      known_file_path <- known_polymorphisms
    }
    
    # 1. Load reference genome
    ref_genome <- BSgenome.Hsapiens.UCSC.hg19
    
    # 2. Run analyzeBases to determine target positions, analyze reads, sum up frequencies,
    # report variants, and generate plots.
    output1 <- analyzeBases(
      sample_names = sample_file,
      bam_input = bam_folder,
      target_regions = target_file,
      vcf_input = vcf_folder,
      output = output_folder,
      output_pictures = output_pics_folder,
      known_file = known_file_path,
      genome = ref_genome,
      MQ_threshold = 60,
      BQ_threshold = 50,
      frequency_threshold = 0.01,
      qual_lower_bound = 58,
      qual_upper_bound = 63,
      marks = c(0.01),
      relative = TRUE,
      per_sample = TRUE
    )
    
    # Save the returned list of lists as an RDS object for downstream analysis
    saveRDS(output1, file = "BBCAnalyzer_output.rds")
    
    message("BBCAnalyzer pipeline completed successfully. Output files and plots generated in the working directory.")

    writeLines(c(
        '"BIOC_BBCANALYZER_COMPLETE_BASE_ANALYSIS":',
        paste0('        bbcanalyzer: ', as.character(packageVersion("bbcanalyzer")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_complete_base_analysis.csv versions.yml
    """
}

workflow BIOC_BBCANALYZER_COMPLETE_BASE_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ SampleNames.txt, targetRegions.txt, [Sample].bam and [Sample].bai, [Sample].vcf, dbsnp_138.part.vcf.gz ] ]

    main:
    BIOC_BBCANALYZER_COMPLETE_BASE_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_BBCANALYZER_COMPLETE_BASE_ANALYSIS.out.tables
    plots    = BIOC_BBCANALYZER_COMPLETE_BASE_ANALYSIS.out.plots
    objects  = BIOC_BBCANALYZER_COMPLETE_BASE_ANALYSIS.out.objects
    versions = BIOC_BBCANALYZER_COMPLETE_BASE_ANALYSIS.out.versions
}
