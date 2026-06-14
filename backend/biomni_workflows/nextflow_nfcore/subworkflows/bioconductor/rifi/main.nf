#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: rifi — rifi_wrapper_workflow
// Run the entire rifi analysis pipeline automatically using a single wrapper function.
// Input: example_input_e_coli, gff_e_coli.gff3.gz
// Container: quay.io/biocontainers/bioconductor-rifi:1.14.0--r45hdfd78af_0
// R packages: rifi, SummarizedExperiment
// Bioconductor: 3.20 | R: 4.4
// Requires: SummarizedExperiment, rifi
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load input data and GFF3 annotation file
//  * 2. [Visualization & Output] Run the wrapper function rifi_wrapper to execute preprocessing, fitting, penalty estimation, fragmentation, statistics, summary, a

nextflow.enable.dsl = 2

process BIOC_RIFI_RIFI_WRAPPER_WORKFLOW {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

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
    .bm_deps <- c("rifi", "SummarizedExperiment")
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
    
    library(rifi)
    
    
    library(SummarizedExperiment)
    # 1. Load input data and GFF3 annotation file from the working directory
    if (file.exists("example_input_e_coli")) {
      example_input_e_coli <- tryCatch({
        readRDS("example_input_e_coli")
      }, error = function(e) {
        env <- new.env()
        load("example_input_e_coli", envir = env)
        if (length(ls(env)) > 0) {
          env[[ls(env)[1]]]
        } else {
          stop("Failed to load example_input_e_coli")
        }
      })
    } else {
      stop("Required input file 'example_input_e_coli' not found in the working directory.")
    }
    
    if (!file.exists("gff_e_coli.gff3.gz")) {
      stop("Required input file 'gff_e_coli.gff3.gz' not found in the working directory.")
    }
    
    Path = gzfile("gff_e_coli.gff3.gz")
    
    # 2. Run the wrapper function rifi_wrapper to execute the entire pipeline
    wrapper_minimal <-
      rifi_wrapper(
        inp = example_input_e_coli,
        cores = 2,
        path = Path,
        bg = 0,
        restr = 0.01
      )
    
    # 3. Write named output files for the meaningful results
    saveRDS(wrapper_minimal, "rifi_wrapper_output.rds")
    
    if (length(wrapper_minimal) > 0) {
      final_se <- wrapper_minimal[[length(wrapper_minimal)]]
      saveRDS(final_se, "rifi_final_summary_se.rds")
      
      meta_data <- metadata(final_se)
      
      if ("dataframe_summary_1" %in% names(meta_data)) {
        write.csv(meta_data\$dataframe_summary_1, file = "dataframe_summary_1.csv", row.names = FALSE)
      }
      if ("dataframe_summary_2" %in% names(meta_data)) {
        write.csv(meta_data\$dataframe_summary_2, file = "dataframe_summary_2.csv", row.names = FALSE)
      }
      if ("dataframe_summary_events" %in% names(meta_data)) {
        write.csv(meta_data\$dataframe_summary_events, file = "dataframe_summary_events.csv", row.names = FALSE)
      }
      if ("dataframe_summary_TI" %in% names(meta_data)) {
        write.csv(meta_data\$dataframe_summary_TI, file = "dataframe_summary_TI.csv", row.names = FALSE)
      }
      
      tryCatch({
        rr <- rowRanges(final_se)
        if (!is.null(rr)) {
          write.csv(as.data.frame(rr), file = "rowRanges_summary.csv", row.names = FALSE)
        }
      }, error = function(e) {
        message("Could not export rowRanges: ", e\$message)
      })
    }

    writeLines(c(
        '"BIOC_RIFI_RIFI_WRAPPER_WORKFLOW":',
        paste0('    rifi: ', as.character(packageVersion('rifi')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rifi_wrapper_workflow.csv versions.yml
    """
}

workflow BIOC_RIFI_RIFI_WRAPPER_WORKFLOW_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ example_input_e_coli, gff_e_coli.gff3.gz ] ]

    main:
    BIOC_RIFI_RIFI_WRAPPER_WORKFLOW(ch_input)

    emit:
    tables   = BIOC_RIFI_RIFI_WRAPPER_WORKFLOW.out.tables
    plots    = BIOC_RIFI_RIFI_WRAPPER_WORKFLOW.out.plots
    objects  = BIOC_RIFI_RIFI_WRAPPER_WORKFLOW.out.objects
    versions = BIOC_RIFI_RIFI_WRAPPER_WORKFLOW.out.versions
}
