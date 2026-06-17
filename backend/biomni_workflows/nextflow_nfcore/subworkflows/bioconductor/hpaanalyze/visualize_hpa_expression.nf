#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: HPAanalyze — visualize_hpa_expression
// Generate exploratory plots (heatmaps, bar charts, tile charts) for a list of target genes across tissues, cancers, and subcellular compartments.
// Input: geneList, tissueList, cancerList
// Container: quay.io/biocontainers/bioconductor-hpaanalyze:1.28.0--r45hdfd78af_0
// R packages: HPAanalyze, dplyr, ggplot2
// Bioconductor: 3.20 | R: 4.4
// Requires: HPAanalyze, dplyr, ggplot2
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Download HPA datasets using hpaDownload()
//  * 2. [Visualization & Output] Visualize tissue expression using hpaVisTissue()
//  * 3. [Visualization & Output] Visualize cancer pathology expression using hpaVisPatho()
//  * 4. [Visualization & Output] Visualize subcellular localization using hpaVisSubcell()

nextflow.enable.dsl = 2

process BIOC_HPAANALYZE_VISUALIZE_HPA_EXPRESSION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-proteomics:3.20-slim"

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
    .bm_deps <- c("HPAanalyze", "dplyr", "ggplot2")
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
        library(HPAanalyze)
        library(ggplot2)
        library(dplyr)
        
        # Helper function to robustly read user input files from the working directory
        read_input_vector <- function(filepath) {
          if (!file.exists(filepath)) {
            stop(paste("Required input file missing:", filepath))
          }
          tryCatch({
            return(readRDS(filepath))
          }, error = function(e) {
            lines <- readLines(filepath, warn = FALSE)
            lines <- trimws(lines)
            lines <- lines[lines != ""]
            if (length(lines) == 1 && grepl(",", lines)) {
              lines <- strsplit(lines, ",")[[1]]
              lines <- trimws(gsub('["\']', '', lines))
            }
            return(lines)
          })
        }
        
        # 1. Read user input files from the working directory
        geneList <- read_input_vector("geneList")
        tissueList <- read_input_vector("tissueList")
        cancerList <- read_input_vector("cancerList")
        
        # 2. Download HPA datasets using hpaDownload()
        downloadedData <- hpaDownload ( downloadList= 'histology' )
        
        # 3. Visualize tissue expression using hpaVisTissue()
        p_tissue <- hpaVisTissue (downloadedData, targetGene= geneList, targetTissue= tissueList)
        ggplot2::ggsave("hpa_vis_tissue.pdf", plot = p_tissue, width = 10, height = 8)
        saveRDS(p_tissue, "hpa_vis_tissue.rds")
        
        # 4. Visualize cancer pathology expression using hpaVisPatho()
        colorGray <- c ( 'slategray1' , 'slategray2' , 'slategray3' , 'slategray4' )
        p_patho <- hpaVisPatho (downloadedData, targetGene= geneList, targetCancer= cancerList, color= colorGray)
        ggplot2::ggsave("hpa_vis_patho.pdf", plot = p_patho, width = 10, height = 8)
        saveRDS(p_patho, "hpa_vis_patho.rds")
        
        # 5. Visualize subcellular localization using hpaVisSubcell()
        p_subcell <- hpaVisSubcell (downloadedData, targetGene= geneList, customTheme= TRUE ) + 
          ggplot2 :: theme_minimal () + 
          ggplot2 :: ylab ( 'Subcellular locations' ) + 
          ggplot2 :: xlab ( 'Protein' ) + 
          ggplot2 :: theme ( axis.text.x= element_text ( angle= 45 , hjust= 1 )) + 
          ggplot2 :: theme ( legend.position= "none" ) + 
          ggplot2 :: coord_equal ()
        ggplot2::ggsave("hpa_vis_subcell.pdf", plot = p_subcell, width = 10, height = 8)
        saveRDS(p_subcell, "hpa_vis_subcell.rds")
        
        # 6. Subset and export tabular data for meaningful results
        subsetData <- hpaSubset(data = downloadedData,
                                targetGene = geneList,
                                targetTissue = tissueList,
                                targetCancer = cancerList)
        
        if (!is.null(subsetData\$normal_tissue)) {
          write.csv(subsetData\$normal_tissue, "subset_normal_tissue.csv", row.names = FALSE)
        }
        if (!is.null(subsetData\$pathology)) {
          write.csv(subsetData\$pathology, "subset_pathology.csv", row.names = FALSE)
        }
        if (!is.null(subsetData\$subcellular_location)) {
          write.csv(subsetData\$subcellular_location, "subset_subcellular_location.csv", row.names = FALSE)
        }

    writeLines(c(
        '"BIOC_HPAANALYZE_VISUALIZE_HPA_EXPRESSION":',
        paste0('    HPAanalyze: ', as.character(packageVersion('HPAanalyze')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_visualize_hpa_expression.csv versions.yml
    """
}

workflow BIOC_HPAANALYZE_VISUALIZE_HPA_EXPRESSION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ geneList, tissueList, cancerList ] ]

    main:
    BIOC_HPAANALYZE_VISUALIZE_HPA_EXPRESSION(ch_input)

    emit:
    tables   = BIOC_HPAANALYZE_VISUALIZE_HPA_EXPRESSION.out.tables
    plots    = BIOC_HPAANALYZE_VISUALIZE_HPA_EXPRESSION.out.plots
    objects  = BIOC_HPAANALYZE_VISUALIZE_HPA_EXPRESSION.out.objects
    versions = BIOC_HPAANALYZE_VISUALIZE_HPA_EXPRESSION.out.versions
}
