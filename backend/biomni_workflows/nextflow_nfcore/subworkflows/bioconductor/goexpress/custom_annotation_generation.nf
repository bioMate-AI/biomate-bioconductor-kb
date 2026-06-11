#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: GOexpress — custom_annotation_generation
// Download and prepare custom Ensembl annotations via biomaRt for offline, fast, and reproducible GOexpress analyses.
// Input: ensembl_host_metadata
// Container: quay.io/biocontainers/bioconductor-goexpress:1.44.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: GOexpress, biomaRt
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Connect to the Ensembl BioMart database using biomaRt. 2. Download gene annotations (IDs, symbols, descriptions). 3. Download GO t

nextflow.enable.dsl = 2

process BIOC_GOEXPRESS_CUSTOM_ANNOTATION_GENERATION {
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
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
        
    # Load required libraries
    library(biomaRt)
    library(GOexpress)
    
    # 1. Read user input: ensembl_host_metadata
    host_url <- NULL
    dataset_name <- NULL
    
    if (file.exists("ensembl_host_metadata")) {
      # Try reading as CSV first
      tryCatch({
        metadata <- read.csv("ensembl_host_metadata", stringsAsFactors = FALSE)
        if ("host" %in% colnames(metadata)) {
          host_url <- trimws(metadata\$host[1])
        }
        if ("dataset" %in% colnames(metadata)) {
          dataset_name <- trimws(metadata\$dataset[1])
        }
      }, error = function(e) {})
      
      # If CSV parsing didn't yield both, try parsing as key-value lines
      if (is.null(host_url) || is.null(dataset_name)) {
        lines <- readLines("ensembl_host_metadata", warn = FALSE)
        for (line in lines) {
          if (grepl("host", line, ignore.case = TRUE)) {
            val <- gsub(".*[:=, ]", "", line)
            host_url <- trimws(val)
          }
          if (grepl("dataset", line, ignore.case = TRUE)) {
            val <- gsub(".*[:=, ]", "", line)
            dataset_name <- trimws(val)
          }
        }
      }
    }
    
    # Fallback defaults if input parsing failed or file is missing
    if (is.null(host_url) || host_url == "") {
      host_url <- "feb2014.archive.ensembl.org"
    }
    if (is.null(dataset_name) || dataset_name == "") {
      dataset_name <- "btaurus_gene_ensembl"
    }
    
    # 2. Connect to the Ensembl BioMart database
    listMarts(host = host_url)
    ensembl75 <- useMart(
      host = host_url,
      biomart = "ENSEMBL_MART_ENSEMBL", 
      dataset = dataset_name
    )
    
    # 3. Download gene annotations (IDs, symbols, descriptions)
    allgenes.Ensembl <- getBM(
      attributes = c("ensembl_gene_id", "external_gene_id", "description"),
      mart = ensembl75
    )
    colnames(allgenes.Ensembl)[1] <- "gene_id"
    
    # 4. Download GO term annotations (IDs, names, namespaces)
    allGO.Ensembl <- getBM(
      attributes = c("go_id", "name_1006", "namespace_1003"),
      mart = ensembl75
    )
    
    # 5. Download the mapping between gene IDs and GO IDs
    GOgenes.Ensembl <- getBM(
      attributes = c("ensembl_gene_id", "go_id"),
      mart = ensembl75
    )
    colnames(GOgenes.Ensembl)[1] <- "gene_id"
    
    # 6. Clean and format the downloaded data frames
    GOgenes.Ensembl <- GOgenes.Ensembl[GOgenes.Ensembl\$go_id != "", ]
    GOgenes.Ensembl <- GOgenes.Ensembl[GOgenes.Ensembl\$gene_id != "", ]
    
    # 7. Save the custom annotations to local R data files (.rda)
    save(GOgenes.Ensembl, file = "GOgenes.Ensembl75.rda")
    save(allGO.Ensembl, file = "allGO.Ensembl75.rda")
    save(allgenes.Ensembl, file = "allgenes.Ensembl75.rda")
    
    # Also save as CSV tables for standard downstream interoperability
    write.csv(allgenes.Ensembl, file = "allgenes_Ensembl.csv", row.names = FALSE)
    write.csv(allGO.Ensembl, file = "allGO_Ensembl.csv", row.names = FALSE)
    write.csv(GOgenes.Ensembl, file = "GOgenes_Ensembl.csv", row.names = FALSE)

    writeLines(c(
        '"BIOC_GOEXPRESS_CUSTOM_ANNOTATION_GENERATION":',
        paste0('    GOexpress: ', as.character(packageVersion('GOexpress')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_custom_annotation_generation.csv versions.yml
    """
}

workflow BIOC_GOEXPRESS_CUSTOM_ANNOTATION_GENERATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ ensembl_host_metadata ] ]

    main:
    BIOC_GOEXPRESS_CUSTOM_ANNOTATION_GENERATION(ch_input)

    emit:
    tables   = BIOC_GOEXPRESS_CUSTOM_ANNOTATION_GENERATION.out.tables
    plots    = BIOC_GOEXPRESS_CUSTOM_ANNOTATION_GENERATION.out.plots
    objects  = BIOC_GOEXPRESS_CUSTOM_ANNOTATION_GENERATION.out.objects
    versions = BIOC_GOEXPRESS_CUSTOM_ANNOTATION_GENERATION.out.versions
}
