#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: a4 — pathway_enrichment_mlp
// Perform pathway enrichment analysis using the Mean Log P (MLP) method.
// Input: ExpressionSet
// Container: quay.io/biocontainers/bioconductor-a4:1.58.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: GOstats, Rgraphviz, a4
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Generate p-values using limmaTwoLevels
//  * 2. [Core Analysis] Map probe IDs to Entrez IDs
//  * 3. [Core Analysis] Retrieve gene sets
//  * 4. [Core Analysis] Run MLP analysis
//  * 5. [Visualization & Output] Plot the MLP results as a GO graph

nextflow.enable.dsl = 2

process BIOC_A4_PATHWAY_ENRICHMENT_MLP {
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
    library(a4)
    library(MLP)
    
    # 1. Read the input ExpressionSet
    input_file <- "expression_set.rds"
    if (!file.exists(input_file)) {
      stop("Required input file 'expression_set.rds' not found in the working directory.")
    }
    ALL <- readRDS(input_file)
    
    # Ensure the ExpressionSet has the required group column "BT2"
    if (!"BT2" %in% colnames(pData(ALL))) {
      if ("BT" %in% colnames(pData(ALL))) {
        labels <- as.factor(ifelse(regexpr("^B", as.character(pData(ALL)\$BT)) == 1, "B", "T"))
        pData(ALL)\$BT2 <- labels
      } else {
        # Fallback: use the first column of pData as the grouping variable
        pData(ALL)\$BT2 <- as.factor(pData(ALL)[[1]])
      }
    }
    
    # Ensure ENTREZID is present in fData
    if (!"ENTREZID" %in% colnames(fData(ALL))) {
      ann <- annotation(ALL)
      if (length(ann) > 0 && ann != "") {
        db_pack <- paste0(ann, ".db")
        if (requireNamespace(db_pack, quietly = TRUE)) {
          library(db_pack, character.only = TRUE)
          ALL <- addGeneInfo(ALL)
        }
      }
      # If still not present, fallback to using rownames
      if (!"ENTREZID" %in% colnames(fData(ALL))) {
        fData(ALL)\$ENTREZID <- rownames(ALL)
      }
    }
    
    # 2. Generate p-values using limmaTwoLevels and map probe IDs to Entrez IDs
    limmaResult <- limmaTwoLevels(object =  ALL, group = "BT2")
    pValues <- limmaResult@MArrayLM\$p.value
    pValueNames <- fData(ALL)[rownames(pValues), 'ENTREZID']
    pValues <- pValues[,2]
    names(pValues) <- pValueNames
    pValues <- pValues[!is.na(pValueNames)]
    
    # 3. Retrieve gene sets
    geneSet <- getGeneSets(species = "Human", geneSetSource = "GOBP", entrezIdentifiers = names(pValues))
    
    # 4. Run MLP analysis
    mlpOut <- MLP(geneSet = geneSet, geneStatistic = pValues, minGenes = 5, maxGenes = 100, rowPermutations = TRUE, nPermutations = 50, smoothPValues = TRUE, probabilityVector = c(0.5, 0.9, 0.95, 0.99, 0.999, 0.9999, 0.99999), df = 9)
    
    # Save MLP results object
    saveRDS(mlpOut, "mlp_results.rds")
    
    # Save MLP results as a CSV table
    tryCatch({
      mlp_df <- as.data.frame(mlpOut)
      write.csv(mlp_df, "mlp_results.csv", row.names = TRUE)
    }, error = function(e) {
      warning("Could not export MLP results to CSV: ", e\$message)
    })
    
    # 5. Plot the MLP results as a GO graph
    if (requireNamespace("Rgraphviz", quietly = TRUE) && requireNamespace("GOstats", quietly = TRUE)) {
      library(Rgraphviz)
      library(GOstats)
    }
    
    pdf(file = "GOgraph.pdf")
    plot(mlpOut, type = "GOgraph", nRow = 25)
    dev.off()

    writeLines(c(
        '"BIOC_A4_PATHWAY_ENRICHMENT_MLP":',
        paste0('    a4: ', as.character(packageVersion('a4')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_pathway_enrichment_mlp.csv versions.yml
    """
}

workflow BIOC_A4_PATHWAY_ENRICHMENT_MLP_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ ExpressionSet ] ]

    main:
    BIOC_A4_PATHWAY_ENRICHMENT_MLP(ch_input)

    emit:
    tables   = BIOC_A4_PATHWAY_ENRICHMENT_MLP.out.tables
    plots    = BIOC_A4_PATHWAY_ENRICHMENT_MLP.out.plots
    objects  = BIOC_A4_PATHWAY_ENRICHMENT_MLP.out.objects
    versions = BIOC_A4_PATHWAY_ENRICHMENT_MLP.out.versions
}
