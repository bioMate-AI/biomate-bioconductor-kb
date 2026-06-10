#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: BBCAnalyzer — visualization_only
// Generate or customize plots using pre-calculated base analysis results without re-parsing the BAM files.
// Input: SampleNames.txt, output_list, [Sample].vcf, dbsnp_138.part.vcf.gz
// Container: quay.io/biocontainers/bioconductor-bbcanalyzer:1.40.0--r45hdfd78af_0
// R packages: BBCAnalyzer
// Bioconductor: 3.20 | R: 4.4
// Requires: BBCAnalyzer
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Run analyzeBasesPlotOnly using the output list from a previous analyzeBases run to generate customized plots

nextflow.enable.dsl = 2

process BIOC_BBCANALYZER_VISUALIZATION_ONLY {
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
    .bm_deps <- c("BBCAnalyzer")
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
        
        # Load the required Bioconductor package
        library(BBCAnalyzer)
        
        # 1. Declare and verify USER INPUT files from the working directory
        sample_file <- "SampleNames.txt"
        if (!file.exists(sample_file)) {
          stop("Error: Required input file 'SampleNames.txt' not found in the working directory.")
        }
        
        # Load the pre-calculated base analysis results (output_list)
        output_list_path <- "output_list"
        if (!file.exists(output_list_path)) {
          if (file.exists("output_list.rds")) {
            output_list_path <- "output_list.rds"
          } else {
            stop("Error: Required input 'output_list' (RDS file) not found in the working directory.")
          }
        }
        output_list <- readRDS(output_list_path)
        
        # Check for optional VCF files in the working directory
        vcf_files <- list.files(pattern = "\\\\.vcf\$")
        if (length(vcf_files) > 0) {
          vcf_input_dir <- "."
        } else {
          vcf_input_dir <- ""
        }
        
        # Check for optional known polymorphisms tabix file
        known_file_path <- "dbsnp_138.part.vcf.gz"
        if (!file.exists(known_file_path)) {
          known_file_path <- ""
        }
        
        # 2. Run the visualization pipeline
        analyzeBasesPlotOnly(sample_names=sample_file,
                    vcf_input=vcf_input_dir,
                    output="",
                    known_file=known_file_path,            
                    output_list=output_list,
                    qual_lower_bound=58,
                    qual_upper_bound=63,
                    marks=c(0.2,0.4,0.6,0.8,1),
                    relative=FALSE,
                    per_sample=FALSE)
        
        cat("Pipeline completed successfully. Plots saved as PNG files.\n")

    writeLines(c(
        '"BIOC_BBCANALYZER_VISUALIZATION_ONLY":',
        paste0('    BBCAnalyzer: ', as.character(packageVersion('BBCAnalyzer')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_visualization_only.csv versions.yml
    """
}

workflow BIOC_BBCANALYZER_VISUALIZATION_ONLY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ SampleNames.txt, output_list, [Sample].vcf, dbsnp_138.part.vcf.gz ] ]

    main:
    BIOC_BBCANALYZER_VISUALIZATION_ONLY(ch_input)

    emit:
    tables   = BIOC_BBCANALYZER_VISUALIZATION_ONLY.out.tables
    plots    = BIOC_BBCANALYZER_VISUALIZATION_ONLY.out.plots
    objects  = BIOC_BBCANALYZER_VISUALIZATION_ONLY.out.objects
    versions = BIOC_BBCANALYZER_VISUALIZATION_ONLY.out.versions
}
