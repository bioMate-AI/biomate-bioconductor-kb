#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ddpcrclust — ddpcr_clustering_and_analysis
// Automatically cluster ddPCR droplet amplitudes, assign targets, and calculate copies per droplet (CPD) using a template.
// Input: csv, csv
// Container: quay.io/biocontainers/bioconductor-ddpcrclust:1.30.0--r45hdfd78af_0
// R packages: ddPCRclust, ggplot2
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DDPCRCLUST_DDPCR_CLUSTERING_AND_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-ddpcrclust:1.30.0--r45hdfd78af_0"

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
    .bm_deps <- c("ddPCRclust", "ggplot2")
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
    library(ddPCRclust)
    library(ggplot2)
    
    # Identify input files in the working directory
    csv_files <- list.files(path = ".", pattern = "\\\\.csv\$", ignore.case = TRUE, full.names = TRUE)
    
    if (length(csv_files) == 0) {
      stop("No CSV files found in the working directory.")
    }
    
    template_file <- NULL
    amplitude_files <- c()
    
    # Distinguish the template file from the raw amplitude files
    for (f in csv_files) {
      header <- tryCatch(colnames(read.csv(f, nrows = 1)), error = function(e) NULL)
      if (!is.null(header)) {
        if (any(grepl("Well|Sample|Marker|No.of.markers", header, ignore.case = TRUE))) {
          template_file <- f
        } else if (any(grepl("Ch1|Ch2|Amplitude", header, ignore.case = TRUE))) {
          amplitude_files <- c(amplitude_files, f)
        }
      }
    }
    
    # Fallback detection based on column count if headers are non-standard
    if (is.null(template_file)) {
      for (f in csv_files) {
        test_df <- tryCatch(read.csv(f, nrows = 2), error = function(e) NULL)
        if (!is.null(test_df)) {
          if (ncol(test_df) > 2) {
            template_file <- f
          } else {
            amplitude_files <- unique(c(amplitude_files, f))
          }
        }
      }
    }
    
    # Ensure we have both template and amplitude files
    if (is.null(template_file)) {
      stop("Could not identify a template CSV file in the working directory.")
    }
    if (length(amplitude_files) == 0) {
      stop("No raw droplet amplitude CSV files identified in the working directory.")
    }
    
    # 1. Read raw ddPCR amplitude files
    files <- readFiles(amplitude_files)
    
    # 2. Read template
    template <- readTemplate(template_file)
    
    # 3. Run ddPCRclust
    result <- ddPCRclust(files, template)
    
    # 4. Plot the results
    # Dynamically select the first available well from the results for plotting
    well_name <- names(result)[1]
    plot_data <- result[[well_name]]\$data
    
    p <- ggplot(data = plot_data,
                mapping = aes(x = Ch2.Amplitude, y = Ch1.Amplitude))
    p <- p + geom_point(aes(color = factor(Cluster)), size = .5, na.rm = TRUE) +
         ggtitle(paste(well_name, 'example')) + theme_bw() + theme(legend.position='none')
    
    # Save the plot
    ggsave(filename = "ddPCRclust_plot.pdf", plot = p, width = 7, height = 6)
    
    # Save the RDS object
    saveRDS(result, file = "ddPCRclust_results.rds")
    
    # Export results to CSV files for each well
    for (well in names(result)) {
      output_filename <- paste0("ddPCRclust_result_", well, ".csv")
      write.csv(result[[well]]\$data, file = output_filename, row.names = FALSE)
    }

    cat <<-END_VERSIONS > versions.yml
    "BIOC_DDPCRCLUST_DDPCR_CLUSTERING_AND_ANALYSIS":
        ddpcrclust: \$(Rscript -e 'cat(as.character(packageVersion("ddpcrclust")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ddpcr_clustering_and_analysis.csv versions.yml
    """
}

workflow BIOC_DDPCRCLUST_DDPCR_CLUSTERING_AND_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ csv, csv ] ]

    main:
    BIOC_DDPCRCLUST_DDPCR_CLUSTERING_AND_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_DDPCRCLUST_DDPCR_CLUSTERING_AND_ANALYSIS.out.tables
    plots    = BIOC_DDPCRCLUST_DDPCR_CLUSTERING_AND_ANALYSIS.out.plots
    objects  = BIOC_DDPCRCLUST_DDPCR_CLUSTERING_AND_ANALYSIS.out.objects
    versions = BIOC_DDPCRCLUST_DDPCR_CLUSTERING_AND_ANALYSIS.out.versions
}
