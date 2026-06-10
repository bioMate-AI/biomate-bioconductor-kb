#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: PCAN — network_consensus
// Assess the relevance of a candidate gene to a set of phenotypes based on the consensus of its interacting neighbors in a protein-protein interaction network.
// Input: genId, hqStrNw, hpMatByGene, resnSss
// Container: quay.io/biocontainers/bioconductor-pcan:1.38.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: PCAN
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Identify the direct neighbors of the candidate gene in the interaction network. 2. Compare the neighbor gene list against the phen

nextflow.enable.dsl = 2

process BIOC_PCAN_NETWORK_CONSENSUS {
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
    # 1. Read User Input Files
    # -----------------------------------------------------------------------------
    
    # Load genId (Entrez ID of the candidate gene)
    genId <- if (file.exists("genId.rds")) {
      readRDS("genId.rds")
    } else if (file.exists("genId")) {
      tryCatch(readRDS("genId"), error = function(e) readLines("genId", warn = FALSE)[1])
    } else if (file.exists("genId.txt")) {
      readLines("genId.txt", warn = FALSE)[1]
    } else {
      stop("Required input file 'genId' not found in the working directory.")
    }
    genId <- as.character(genId)
    
    # Load hqStrNw (data frame of high-quality STRING network interactions)
    hqStrNw <- if (file.exists("hqStrNw.rds")) {
      readRDS("hqStrNw.rds")
    } else if (file.exists("hqStrNw.csv")) {
      read.csv("hqStrNw.csv", stringsAsFactors = FALSE)
    } else if (file.exists("hqStrNw")) {
      tryCatch(readRDS("hqStrNw"), error = function(e) read.csv("hqStrNw", stringsAsFactors = FALSE))
    } else {
      stop("Required input file 'hqStrNw' not found in the working directory.")
    }
    
    # Load hpMatByGene (list of semantic similarity matrices per gene)
    hpMatByGene <- if (file.exists("hpMatByGene.rds")) {
      readRDS("hpMatByGene.rds")
    } else if (file.exists("hpMatByGene")) {
      readRDS("hpMatByGene")
    } else {
      stop("Required input file 'hpMatByGene' not found in the working directory.")
    }
    
    # Load resnSss (vector of similarity scores for all genes)
    resnSss <- if (file.exists("resnSss.rds")) {
      readRDS("resnSss.rds")
    } else if (file.exists("resnSss")) {
      tryCatch(readRDS("resnSss"), error = function(e) {
        df <- read.csv("resnSss", stringsAsFactors = FALSE)
        vec <- df[[2]]
        names(vec) <- df[[1]]
        vec
      })
    } else if (file.exists("resnSss.csv")) {
      df <- read.csv("resnSss.csv", stringsAsFactors = FALSE)
      vec <- df[[2]]
      names(vec) <- df[[1]]
      vec
    } else {
      stop("Required input file 'resnSss' not found in the working directory.")
    }
    
    # -----------------------------------------------------------------------------
    # 2. Execute Documented Workflow
    # -----------------------------------------------------------------------------
    
    # Stage 1: Identify the direct neighbors of the candidate gene in the interaction network
    neighbors <- unique(c(
        hqStrNw\$gene1[which(hqStrNw\$gene2==genId)],
        hqStrNw\$gene2[which(hqStrNw\$gene1==genId)],
        genId
    ))
    
    # Stage 2: Compare the neighbor gene list against the phenotypes of interest using hpGeneListComp
    neighRes <- hpGeneListComp(
        geneList=neighbors,
        ssMatByGene = hpMatByGene,
        geneSSScore = resnSss
    )
    
    # -----------------------------------------------------------------------------
    # 3. Save Outputs
    # -----------------------------------------------------------------------------
    
    # Save the complete results object
    saveRDS(neighRes, "neighRes.rds")
    
    # Save neighbor scores as a CSV table
    scores_df <- data.frame(
      entrez = names(neighRes\$scores),
      score = neighRes\$scores,
      stringsAsFactors = FALSE
    )
    write.csv(scores_df, "neighbor_scores.csv", row.names = FALSE)
    
    # Save the comparison p-value
    writeLines(as.character(neighRes\$p.value), "neighbor_p_value.txt")

    writeLines(c(
        '"BIOC_PCAN_NETWORK_CONSENSUS":',
        paste0('    PCAN: ', as.character(packageVersion('PCAN')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_network_consensus.csv versions.yml
    """
}

workflow BIOC_PCAN_NETWORK_CONSENSUS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ genId, hqStrNw, hpMatByGene, resnSss ] ]

    main:
    BIOC_PCAN_NETWORK_CONSENSUS(ch_input)

    emit:
    tables   = BIOC_PCAN_NETWORK_CONSENSUS.out.tables
    plots    = BIOC_PCAN_NETWORK_CONSENSUS.out.plots
    objects  = BIOC_PCAN_NETWORK_CONSENSUS.out.objects
    versions = BIOC_PCAN_NETWORK_CONSENSUS.out.versions
}
