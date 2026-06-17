#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: chromPlot — idiogram_and_synteny_mapping
// Plot chromosome idiograms (G-banding) and highlight genomic elements or synteny blocks directly on the chromosome body.
// Input: hg_gap, hg_cytoBandIdeo, refGeneHg, sinteny
// Container: quay.io/biocontainers/bioconductor-chromplot:1.38.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: chromPlot
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load coordinate gaps and cytoband data
//  * 2. [Visualization & Output] Plot basic chromosome structures
//  * 3. [Visualization & Output] Plot G-banding patterns
//  * 4. [Core Analysis] Overlay genomic elements or synteny blocks on the chromosome body

nextflow.enable.dsl = 2

process BIOC_CHROMPLOT_IDIOGRAM_AND_SYNTENY_MAPPING {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20-slim"

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
    .bm_deps <- c("chromPlot")
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
    
    # Load required libraries
    library(chromPlot)
    
    # Helper function to read user input files from the working directory
    read_input <- function(base_name) {
      possible_files <- c(
        paste0(base_name, ".rds"),
        paste0(base_name, ".txt"),
        paste0(base_name, ".tsv"),
        paste0(base_name, ".csv"),
        base_name
      )
      
      for (f in possible_files) {
        if (file.exists(f)) {
          message(paste("Reading input file:", f))
          if (grepl("\\\\.rds\$", f)) {
            return(readRDS(f))
          } else if (grepl("\\\\.csv\$", f)) {
            return(read.csv(f, header = TRUE, stringsAsFactors = FALSE))
          } else {
            # Try reading as tab-separated, fallback to whitespace-delimited
            df <- tryCatch(
              read.table(f, sep = "\t", header = TRUE, stringsAsFactors = FALSE),
              error = function(e) read.table(f, header = TRUE, stringsAsFactors = FALSE)
            )
            return(df)
          }
        }
      }
      stop(paste("Error: Required input file not found for:", base_name))
    }
    
    # 1. Load coordinate gaps, cytoband data, genomic elements, and synteny blocks
    message("Loading user input datasets...")
    hg_gap          <- read_input("hg_gap")
    hg_cytoBandIdeo <- read_input("hg_cytoBandIdeo")
    refGeneHg       <- read_input("refGeneHg")
    sinteny         <- read_input("sinteny")
    
    # Ensure refGeneHg has the Colors column set as in the documented workflow
    refGeneHg\$Colors <- "red"
    
    # 2. Plot basic chromosome structures
    message("Generating Plot 1: Basic chromosome structures...")
    pdf("chromplot_basic_gaps.pdf", width = 10, height = 8)
    chromPlot(gaps = hg_gap)
    dev.off()
    
    # 3. Plot G-banding patterns
    message("Generating Plot 2: G-banding patterns...")
    pdf("chromplot_g_banding.pdf", width = 12, height = 8)
    chromPlot(
      bands = hg_cytoBandIdeo, 
      gaps = hg_gap, 
      chr = c("1", "2", "3", "4", "5", "6"), 
      figCols = 6
    )
    dev.off()
    
    # 4. Overlay genomic elements on the chromosome body
    message("Generating Plot 3: Genomic elements overlay...")
    pdf("chromplot_genomic_elements.pdf", width = 10, height = 8)
    chromPlot(
      gaps = hg_gap, 
      bands = refGeneHg, 
      chr = c(19, 20, 21), 
      figCols = 3
    )
    dev.off()
    
    # 5. Overlay synteny blocks on the chromosome body
    message("Generating Plot 4: Synteny mapping...")
    pdf("chromplot_synteny.pdf", width = 10, height = 8)
    chromPlot(
      gaps = hg_gap, 
      bands = sinteny, 
      chr = c(19:21), 
      figCols = 3
    )
    dev.off()
    
    # Save RDS objects of the loaded/processed data for downstream verification
    message("Saving processed data objects...")
    saveRDS(hg_gap, "processed_hg_gap.rds")
    saveRDS(hg_cytoBandIdeo, "processed_hg_cytoBandIdeo.rds")
    saveRDS(refGeneHg, "processed_refGeneHg.rds")
    saveRDS(sinteny, "processed_sinteny.rds")
    
    message("Pipeline completed successfully. Outputs generated:
      - chromplot_basic_gaps.pdf
      - chromplot_g_banding.pdf
      - chromplot_genomic_elements.pdf
      - chromplot_synteny.pdf
      - processed_hg_gap.rds
      - processed_hg_cytoBandIdeo.rds
      - processed_refGeneHg.rds
      - processed_sinteny.rds")

    writeLines(c(
        '"BIOC_CHROMPLOT_IDIOGRAM_AND_SYNTENY_MAPPING":',
        paste0('    chromPlot: ', as.character(packageVersion('chromPlot')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_idiogram_and_synteny_mapping.csv versions.yml
    """
}

workflow BIOC_CHROMPLOT_IDIOGRAM_AND_SYNTENY_MAPPING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ hg_gap, hg_cytoBandIdeo, refGeneHg, sinteny ] ]

    main:
    BIOC_CHROMPLOT_IDIOGRAM_AND_SYNTENY_MAPPING(ch_input)

    emit:
    tables   = BIOC_CHROMPLOT_IDIOGRAM_AND_SYNTENY_MAPPING.out.tables
    plots    = BIOC_CHROMPLOT_IDIOGRAM_AND_SYNTENY_MAPPING.out.plots
    objects  = BIOC_CHROMPLOT_IDIOGRAM_AND_SYNTENY_MAPPING.out.objects
    versions = BIOC_CHROMPLOT_IDIOGRAM_AND_SYNTENY_MAPPING.out.versions
}
