#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: RCy3 — import_attribute_data
// Import external node attribute data (such as gene expression data) from a data frame into an existing Cytoscape network.
// Input: network_file.sif, expression_data.csv
// Container: quay.io/biocontainers/bioconductor-rcy3:2.30.1--r45hdfd78af_0
// R packages: RCy3
// Bioconductor: 3.20 | R: 4.4
// Requires: RCy3
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Verify Cytoscape connection
//  * 2. [Input & Preparation] Import network from file
//  * 3. [Input & Preparation] Read external attribute data
//  * 4. [Input & Preparation] Load table data into Cytoscape matching on key columns

nextflow.enable.dsl = 2

process BIOC_RCY3_IMPORT_ATTRIBUTE_DATA {
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
    .bm_deps <- c("RCy3")
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
    library(RCy3)
    
    # 1. Verify Cytoscape connection
    cytoscapePing()
    
    # 2. Import network from file
    # Replacing demo-data setup with the user-specified input file
    sif <- "network_file.sif"
    importNetworkFromFile(sif)
    
    # 3. Read external attribute data
    # Replacing demo-data setup with the user-specified input file
    csv <- "expression_data.csv"
    data <- read.csv(csv, stringsAsFactors = FALSE)
    
    # 4. Load table data into Cytoscape matching on key columns
    loadTableData(data, data.key.column="name")
    
    # 5. Write named output files for the meaningful results
    # Retrieve the updated node table from Cytoscape and save it to a CSV file
    node_table <- getTableColumns(table = "node")
    write.csv(node_table, "updated_node_table.csv", row.names = FALSE)
    
    # Export the network visualization as a PNG image
    exportImage("network_visualization", "PNG")

    writeLines(c(
        '"BIOC_RCY3_IMPORT_ATTRIBUTE_DATA":',
        paste0('    RCy3: ', as.character(packageVersion('RCy3')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_import_attribute_data.csv versions.yml
    """
}

workflow BIOC_RCY3_IMPORT_ATTRIBUTE_DATA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ network_file.sif, expression_data.csv ] ]

    main:
    BIOC_RCY3_IMPORT_ATTRIBUTE_DATA(ch_input)

    emit:
    tables   = BIOC_RCY3_IMPORT_ATTRIBUTE_DATA.out.tables
    plots    = BIOC_RCY3_IMPORT_ATTRIBUTE_DATA.out.plots
    objects  = BIOC_RCY3_IMPORT_ATTRIBUTE_DATA.out.objects
    versions = BIOC_RCY3_IMPORT_ATTRIBUTE_DATA.out.versions
}
