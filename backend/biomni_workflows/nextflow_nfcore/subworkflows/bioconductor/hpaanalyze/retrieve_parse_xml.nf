#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: HPAanalyze — retrieve_parse_xml
// Download detailed XML data for a specific Ensembl gene ID, extract protein classes, tissue expression summaries, antibody details, and individual sample IHC dat
// Input: ensembl_id
// Container: quay.io/biocontainers/bioconductor-hpaanalyze:1.28.0--r45hdfd78af_0
// R packages: HPAanalyze
// Bioconductor: 3.20 | R: 4.4
// Requires: HPAanalyze
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Download and import the XML file using hpaXmlGet()
//  * 2. [Core Analysis] Extract protein classes using hpaXmlProtClass()
//  * 3. [Visualization & Output] Extract tissue expression summary and download representative images using hpaXmlTissueExprSum()
//  * 4. [Core Analysis] Extract antibody details using hpaXmlAntibody()
//  * 5. [Core Analysis] Extract individual sample IHC details using hpaXmlTissueExpr()
//  * 6. [Input & Preparation] Parse all XML data at once using the umbrella function hpaXml()

nextflow.enable.dsl = 2

process BIOC_HPAANALYZE_RETRIEVE_PARSE_XML {
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
    .bm_deps <- c("HPAanalyze")
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
        library(HPAanalyze)
        
        # Read user input
        if (!file.exists("ensembl_id")) {
          stop("Error: Input file 'ensembl_id' not found in the working directory.")
        }
        
        ensembl_id_val <- trimws(readLines("ensembl_id", n = 1, warn = FALSE))
        if (ensembl_id_val == "" || !startsWith(ensembl_id_val, "ENSG")) {
          stop("Error: Invalid Ensembl ID in 'ensembl_id' file. Must start with 'ENSG'.")
        }
        
        # 1. Download and import the XML file
        EGFRxml <- hpaXmlGet ( ensembl_id_val )
        
        # 2. Extract protein classes
        prot_class <- hpaXmlProtClass (EGFRxml)
        
        # 3. Extract tissue expression summary
        tissue_expr_sum <- hpaXmlTissueExprSum (EGFRxml, downloadImg = TRUE)
        
        # 4. Extract antibody details
        antibody_details <- hpaXmlAntibody (EGFRxml)
        
        # 5. Extract individual sample IHC details
        tissueExpression <- hpaXmlTissueExpr (EGFRxml)
        
        # 6. Parse all XML data at once using the umbrella function
        EGFR <- hpaXml ( inputXml= ensembl_id_val )
        
        # Write outputs to files
        if (!is.null(prot_class)) {
          write.csv(prot_class, "protein_classes.csv", row.names = FALSE)
        }
        
        if (!is.null(tissue_expr_sum)) {
          if (!is.null(tissue_expr_sum\$summary)) {
            writeLines(tissue_expr_sum\$summary, "tissue_expression_summary.txt")
          }
          if (!is.null(tissue_expr_sum\$img)) {
            write.csv(tissue_expr_sum\$img, "tissue_expression_images.csv", row.names = FALSE)
          }
        }
        
        if (!is.null(antibody_details)) {
          write.csv(antibody_details, "antibodies.csv", row.names = FALSE)
        }
        
        if (!is.null(tissueExpression)) {
          saveRDS(tissueExpression, "tissue_expression_details.rds")
        }
        
        if (!is.null(EGFR)) {
          saveRDS(EGFR, "parsed_xml_data.rds")
        }

    writeLines(c(
        '"BIOC_HPAANALYZE_RETRIEVE_PARSE_XML":',
        paste0('    HPAanalyze: ', as.character(packageVersion('HPAanalyze')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_retrieve_parse_xml.csv versions.yml
    """
}

workflow BIOC_HPAANALYZE_RETRIEVE_PARSE_XML_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ ensembl_id ] ]

    main:
    BIOC_HPAANALYZE_RETRIEVE_PARSE_XML(ch_input)

    emit:
    tables   = BIOC_HPAANALYZE_RETRIEVE_PARSE_XML.out.tables
    plots    = BIOC_HPAANALYZE_RETRIEVE_PARSE_XML.out.plots
    objects  = BIOC_HPAANALYZE_RETRIEVE_PARSE_XML.out.objects
    versions = BIOC_HPAANALYZE_RETRIEVE_PARSE_XML.out.versions
}
