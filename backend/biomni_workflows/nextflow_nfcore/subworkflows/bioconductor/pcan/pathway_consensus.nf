#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: PCAN — pathway_consensus
// Assess the relevance of a candidate gene to a set of phenotypes based on the consensus of genes belonging to the same biological pathway.
// Input: genId, hsEntrezByRPath, rPath, hpMatByGene, resnSss
// Container: quay.io/biocontainers/bioconductor-pcan:1.38.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: PCAN
// Visualizations: bar plot, pathway diagram, heatmap
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] READ USER INPUTS
//  * 2. [Visualization & Output] PIPELINE EXECUTION (Faithful to Documented Code)
//  * 3. [Visualization & Output] WRITE OUTPUT FILES

nextflow.enable.dsl = 2

process BIOC_PCAN_PATHWAY_CONSENSUS {
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
    .bm_deps <- c("PCAN")
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
    library(PCAN)
    
    # -----------------------------------------------------------------------------
    # --- READ USER INPUTS ---
    # -----------------------------------------------------------------------------
    
    # Read genId (Entrez ID of the candidate gene)
    if (file.exists("genId.rds")) {
      genId <- readRDS("genId.rds")
    } else if (file.exists("genId.txt")) {
      genId <- trimws(readLines("genId.txt", n = 1))
    } else {
      stop("Error: genId file (genId.rds or genId.txt) not found in the working directory.")
    }
    
    # Read hsEntrezByRPath (list of genes per Reactome pathway)
    if (file.exists("hsEntrezByRPath.rds")) {
      hsEntrezByRPath <- readRDS("hsEntrezByRPath.rds")
    } else {
      stop("Error: hsEntrezByRPath.rds not found in the working directory.")
    }
    
    # Read rPath (pathway definitions)
    if (file.exists("rPath.rds")) {
      rPath <- readRDS("rPath.rds")
    } else if (file.exists("rPath.csv")) {
      rPath <- read.csv("rPath.csv", stringsAsFactors = FALSE)
    } else {
      stop("Error: rPath file (rPath.rds or rPath.csv) not found in the working directory.")
    }
    
    # Read hpMatByGene (list of semantic similarity matrices per gene)
    if (file.exists("hpMatByGene.rds")) {
      hpMatByGene <- readRDS("hpMatByGene.rds")
    } else {
      stop("Error: hpMatByGene.rds not found in the working directory.")
    }
    
    # Read resnSss (vector of similarity scores for all genes)
    if (file.exists("resnSss.rds")) {
      resnSss <- readRDS("resnSss.rds")
    } else {
      stop("Error: resnSss.rds not found in the working directory.")
    }
    
    # Load geneDef and hpDef metadata (read from working directory if available, otherwise use package defaults)
    geneDef <- if (file.exists("geneDef.rds")) {
      readRDS("geneDef.rds")
    } else if (file.exists("geneDef.csv")) {
      read.csv("geneDef.csv", stringsAsFactors = FALSE)
    } else {
      PCAN::geneDef
    }
    
    hpDef <- if (file.exists("hpDef.rds")) {
      readRDS("hpDef.rds")
    } else if (file.exists("hpDef.csv")) {
      read.csv("hpDef.csv", stringsAsFactors = FALSE)
    } else {
      PCAN::hpDef
    }
    
    
    # -----------------------------------------------------------------------------
    # --- PIPELINE EXECUTION (Faithful to Documented Code) ---
    # -----------------------------------------------------------------------------
    
    # Identify the pathway(s) containing the candidate gene
    candPath <- names(hsEntrezByRPath)[which(unlist(lapply(
        hsEntrezByRPath,
        function(x) genId %in% x
    )))]
    
    if (length(candPath) == 0) {
      stop("Candidate gene was not found in any of the provided pathways.")
    }
    
    # If the candidate gene belongs to multiple pathways, select the first one
    candPath <- candPath[1]
    
    # Compare the pathway gene list against the phenotypes of interest
    rPathRes <- hpGeneListComp(
        geneList=hsEntrezByRPath[[candPath]],
        ssMatByGene = hpMatByGene,
        geneSSScore = resnSss
    )
    
    # Extract and map scores
    pathSss <- rPathRes\$scores[which(!is.na(rPathRes\$scores))]
    names(pathSss) <- geneDef[match(names(pathSss), geneDef\$entrez), "symbol"]
    
    # Plot the distribution of scores (Barplot)
    pdf("pathway_consensus_barplot.pdf", width = 10, height = 7)
    par(mar = c(7.1, 4.1, 4.1, 2.1))
    barplot(
        sort(pathSss),
        las=2,
        ylab=expression(Sim[sym]),
        main=rPath[which(rPath\$Pathway %in% candPath),"Pathway_name"]
    )
    dev.off()
    
    # Prepare labels for the heatmap
    geneLabels <- geneDef\$symbol[which(!duplicated(geneDef\$entrez))]
    names(geneLabels) <- geneDef\$entrez[which(!duplicated(geneDef\$entrez))]
    hpLabels <- hpDef\$name
    names(hpLabels) <- hpDef\$id
    
    # Generate a heatmap of gene-phenotype matches
    pdf("pathway_consensus_heatmap.pdf", width = 10, height = 10)
    hpGeneHeatmap(
        rPathRes,
        genesOfInterest=genId,
        geneLabels=geneLabels,
        hpLabels=hpLabels,
        clustByGene=TRUE,
        clustByHp=TRUE,
        palFun=colorRampPalette(c("white", "red")),
        goiCol="blue",
        main=rPath[which(rPath\$Pathway %in% candPath),"Pathway_name"]
    )
    dev.off()
    
    
    # -----------------------------------------------------------------------------
    # --- WRITE OUTPUT FILES ---
    # -----------------------------------------------------------------------------
    
    # Save the main comparison result object
    saveRDS(rPathRes, "rPathRes.rds")
    
    # Save the pathway gene scores to a CSV file
    pathway_scores_df <- data.frame(
      Entrez_ID = names(rPathRes\$scores),
      Symbol = geneDef[match(names(rPathRes\$scores), geneDef\$entrez), "symbol"],
      Score = rPathRes\$scores,
      stringsAsFactors = FALSE
    )
    write.csv(pathway_scores_df, "pathway_gene_scores.csv", row.names = FALSE)
    
    # Save a summary of the pathway consensus analysis
    summary_df <- data.frame(
      Candidate_Gene_ID = genId,
      Candidate_Gene_Symbol = geneDef[match(genId, geneDef\$entrez), "symbol"],
      Pathway_ID = candPath,
      Pathway_Name = rPath[which(rPath\$Pathway %in% candPath), "Pathway_name"],
      P_Value = rPathRes\$p.value,
      stringsAsFactors = FALSE
    )
    write.csv(summary_df, "pathway_consensus_summary.csv", row.names = FALSE)

    writeLines(c(
        '"BIOC_PCAN_PATHWAY_CONSENSUS":',
        paste0('    PCAN: ', as.character(packageVersion('PCAN')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_pathway_consensus.csv versions.yml
    """
}

workflow BIOC_PCAN_PATHWAY_CONSENSUS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ genId, hsEntrezByRPath, rPath, hpMatByGene, resnSss ] ]

    main:
    BIOC_PCAN_PATHWAY_CONSENSUS(ch_input)

    emit:
    tables   = BIOC_PCAN_PATHWAY_CONSENSUS.out.tables
    plots    = BIOC_PCAN_PATHWAY_CONSENSUS.out.plots
    objects  = BIOC_PCAN_PATHWAY_CONSENSUS.out.objects
    versions = BIOC_PCAN_PATHWAY_CONSENSUS.out.versions
}
