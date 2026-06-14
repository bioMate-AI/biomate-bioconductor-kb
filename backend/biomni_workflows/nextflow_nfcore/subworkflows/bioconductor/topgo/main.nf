#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: topGO — predefined_gene_list_enrichment
// Perform GO enrichment analysis using a predefined list of interesting genes and custom gene-to-GO annotations.
// Input: geneid2go.map, myInterestingGenes
// Container: quay.io/biocontainers/bioconductor-topgo:2.62.0--r45hdfd78af_0
// R packages: ALL, genefilter, lattice, topGO, xtable
// Bioconductor: 3.20 | R: 4.4
// Requires: topGO
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Read custom gene-to-GO mappings from a file
//  * 2. [Visualization & Output] Define the gene universe and create a named factor vector
//  * 3. [Visualization & Output] Initialize the topGOdata object using the custom mapping
//  * 4. [Visualization & Output] Run a count-based enrichment test (Fisher's exact test)
//  * 5. [Visualization & Output] Generate a summary table of the top significant GO terms

nextflow.enable.dsl = 2

process BIOC_TOPGO_PREDEFINED_GENE_LIST_ENRICHMENT {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20"

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
    .bm_deps <- c("ALL", "genefilter", "lattice", "topGO", "xtable")
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
    library(topGO)
    
    # --- Read custom gene-to-GO mappings from a file ---
    if (!file.exists("geneid2go.map")) {
      stop("Error: 'geneid2go.map' file not found in the working directory.")
    }
    geneID2GO <- readMappings(file = "geneid2go.map")
    
    # --- Define the gene universe and create a named factor vector ---
    GO2geneID <- inverseList(geneID2GO)
    geneNames <- names(geneID2GO)
    
    if (!file.exists("myInterestingGenes")) {
      stop("Error: 'myInterestingGenes' file not found in the working directory.")
    }
    myInterestingGenes <- readLines("myInterestingGenes")
    myInterestingGenes <- trimws(myInterestingGenes)
    myInterestingGenes <- myInterestingGenes[myInterestingGenes != ""]
    
    geneList <- factor(as.integer(geneNames %in% myInterestingGenes))
    names(geneList) <- geneNames
    
    # --- Initialize the topGOdata object using the custom mapping ---
    GOdata <- new("topGOdata", ontology = "MF", allGenes = geneList, annot = annFUN.gene2GO, gene2GO = geneID2GO)
    
    # --- Run a count-based enrichment test (Fisher's exact test) ---
    resultFis <- runTest(GOdata, algorithm = "classic", statistic = "fisher")
    
    # --- Generate a summary table of the top significant GO terms ---
    allRes <- GenTable(GOdata, classic = resultFis, orderBy = "classic", topNodes = 20)
    
    # Write named output files
    write.csv(allRes, file = "topGO_enrichment_results.csv", row.names = FALSE)
    saveRDS(GOdata, file = "topGO_data_object.rds")
    saveRDS(resultFis, file = "topGO_result_fisher.rds")
    
    # Generate a PDF plot of the GO structure
    tryCatch({
      printGraph(GOdata, resultFis, firstSigNodes = 5, fn.prefix = "tGO_classic", useInfo = "all", pdfSW = TRUE)
    }, error = function(e) {
      warning("Could not generate GO graph PDF: ", e\$message)
    })

    writeLines(c(
        '"BIOC_TOPGO_PREDEFINED_GENE_LIST_ENRICHMENT":',
        paste0('    topGO: ', as.character(packageVersion('topGO')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_predefined_gene_list_enrichment.csv versions.yml
    """
}

workflow BIOC_TOPGO_PREDEFINED_GENE_LIST_ENRICHMENT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ geneid2go.map, myInterestingGenes ] ]

    main:
    BIOC_TOPGO_PREDEFINED_GENE_LIST_ENRICHMENT(ch_input)

    emit:
    tables   = BIOC_TOPGO_PREDEFINED_GENE_LIST_ENRICHMENT.out.tables
    plots    = BIOC_TOPGO_PREDEFINED_GENE_LIST_ENRICHMENT.out.plots
    objects  = BIOC_TOPGO_PREDEFINED_GENE_LIST_ENRICHMENT.out.objects
    versions = BIOC_TOPGO_PREDEFINED_GENE_LIST_ENRICHMENT.out.versions
}
