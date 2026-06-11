#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: bbcanalyzer — plot_only_analysis
// Regenerate or customize barplots using the pre-calculated analysis list from analyzeBases without re-running the BAM parsing.
// Input: SampleNames.txt, output_list, [Sample].vcf, dbsnp_138.part.vcf.gz
// Container: quay.io/biocontainers/bioconductor-bbcanalyzer:1.40.0--r45hdfd78af_0
// R packages: BBCAnalyzer
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BBCANALYZER_PLOT_ONLY_ANALYSIS {
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
    
    # Load required libraries
    library(BBCAnalyzer)
    
    # Define input file paths based on user-provided files in the working directory
    sample_file <- "SampleNames.txt"
    output_list_rds <- "output_list.rds"
    known_file <- "dbsnp_138.part.vcf.gz"
    vcf_input_dir <- "."
    
    # Validate required inputs
    if (!file.exists(sample_file)) {
      stop(paste("Required input file missing:", sample_file))
    }
    
    if (!file.exists(output_list_rds)) {
      stop(paste("Required pre-calculated output list RDS file missing:", output_list_rds))
    }
    
    # Load the pre-calculated analysis list from the previous analyzeBases run
    output_list <- readRDS(output_list_rds)
    
    # Check for optional known polymorphisms file
    if (!file.exists(known_file)) {
      warning("Optional known polymorphisms file 'dbsnp_138.part.vcf.gz' not found. Proceeding without it.")
      known_file <- ""
    }
    
    # Execute the plot-only analysis using the exact documented function and arguments
    message("Generating customized barplots using analyzeBasesPlotOnly...")
    analyzeBasesPlotOnly(sample_names=sample_file,
                vcf_input=vcf_input_dir,
                output="",
                known_file=known_file,            
                output_list=output_list,
                qual_lower_bound=58,
                qual_upper_bound=63,
                marks=c(0.2,0.4,0.6,0.8,1),
                relative=FALSE,
                per_sample=FALSE)
    
    message("Plotting completed successfully. Output plots have been saved to the working directory.")

    writeLines(c(
        '"BIOC_BBCANALYZER_PLOT_ONLY_ANALYSIS":',
        paste0('        bbcanalyzer: ', as.character(packageVersion("bbcanalyzer")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_plot_only_analysis.csv versions.yml
    """
}

workflow BIOC_BBCANALYZER_PLOT_ONLY_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ SampleNames.txt, output_list, [Sample].vcf, dbsnp_138.part.vcf.gz ] ]

    main:
    BIOC_BBCANALYZER_PLOT_ONLY_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_BBCANALYZER_PLOT_ONLY_ANALYSIS.out.tables
    plots    = BIOC_BBCANALYZER_PLOT_ONLY_ANALYSIS.out.plots
    objects  = BIOC_BBCANALYZER_PLOT_ONLY_ANALYSIS.out.objects
    versions = BIOC_BBCANALYZER_PLOT_ONLY_ANALYSIS.out.versions
}
