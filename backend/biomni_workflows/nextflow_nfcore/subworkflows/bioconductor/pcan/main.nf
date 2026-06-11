#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: PCAN — direct_phenotype_comparison
// Compare a candidate gene's associated phenotypes directly to a set of phenotypes of interest to calculate a relative relevance rank.
// Input: hpOfInterest, genId, geneByTrait, hpByTrait
// Container: quay.io/biocontainers/bioconductor-pcan:1.38.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: BiocParallel, PCAN
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] READ USER INPUT FILES
//  * 2. [Visualization & Output] RUN WORKFLOW (DIRECT PHENOTYPE COMPARISON)
//  * 3. [Visualization & Output] WRITE OUTPUTS

nextflow.enable.dsl = 2

process BIOC_PCAN_DIRECT_PHENOTYPE_COMPARISON {
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
    library(BiocParallel)
    
    # Retrieve standard database objects from the PCAN package namespace
    # to avoid using the forbidden data(...) function.
    hpDef <- PCAN::hpDef
    hp_descendants <- PCAN::hp_descendants
    hp_ancestors <- PCAN::hp_ancestors
    
    # ==========================================
    # --- READ USER INPUT FILES ---
    # ==========================================
    
    # Read hpOfInterest
    if (file.exists("hpOfInterest.rds")) {
      hpOfInterest <- readRDS("hpOfInterest.rds")
    } else if (file.exists("hpOfInterest.txt")) {
      hpOfInterest <- readLines("hpOfInterest.txt")
    } else {
      stop("Error: hpOfInterest file (hpOfInterest.rds or hpOfInterest.txt) not found in the working directory.")
    }
    
    # Read genId
    if (file.exists("genId.rds")) {
      genId <- readRDS("genId.rds")
    } else if (file.exists("genId.txt")) {
      genId <- trimws(readLines("genId.txt")[1])
    } else {
      stop("Error: genId file (genId.rds or genId.txt) not found in the working directory.")
    }
    
    # Read geneByTrait
    if (file.exists("geneByTrait.rds")) {
      geneByTrait <- readRDS("geneByTrait.rds")
    } else if (file.exists("geneByTrait.csv")) {
      geneByTrait <- read.csv("geneByTrait.csv", stringsAsFactors = FALSE)
    } else {
      stop("Error: geneByTrait file (geneByTrait.rds or geneByTrait.csv) not found in the working directory.")
    }
    
    # Read hpByTrait
    if (file.exists("hpByTrait.rds")) {
      hpByTrait <- readRDS("hpByTrait.rds")
    } else if (file.exists("hpByTrait.csv")) {
      hpByTrait <- read.csv("hpByTrait.csv", stringsAsFactors = FALSE)
    } else {
      stop("Error: hpByTrait file (hpByTrait.rds or hpByTrait.csv) not found in the working directory.")
    }
    
    # Infer or read disId (disease ID) to simulate the discovery use-case
    if (file.exists("disId.txt")) {
      disId <- trimws(readLines("disId.txt")[1])
    } else if (file.exists("disId.rds")) {
      disId <- readRDS("disId.rds")
    } else {
      # Infer disId from hpByTrait and hpOfInterest
      matching_traits <- hpByTrait\$id[hpByTrait\$hp %in% hpOfInterest]
      if (length(matching_traits) > 0) {
        disId <- names(sort(table(matching_traits), decreasing = TRUE))[1]
      } else {
        disId <- "612285" # Default fallback
      }
    }
    
    # ==========================================
    # --- RUN WORKFLOW (DIRECT PHENOTYPE COMPARISON) ---
    # ==========================================
    
    # Filter out the known association to simulate discovery
    geneByTrait <- geneByTrait[
        which(geneByTrait\$id!=disId | geneByTrait\$entrez!=genId),
    ]
    
    # Rebuild geneByHp mapping
    geneByHp <- unique(merge(
        geneByTrait,
        hpByTrait,
        by="id"
    )[,c("entrez", "hp")])
    
    # Map candidate gene to its associated HPO terms
    genHpDef <- hpDef[
        match(
            geneByHp[which(geneByHp\$entrez==genId), "hp"],
            hpDef\$id
        ),
    ]
    genHp <- genHpDef\$id
    
    if (length(genHp) == 0 || all(is.na(genHp))) {
      stop("Error: No HPO terms found associated with the candidate gene: ", genId)
    }
    
    # Compute Information Content (IC) for all HPO terms
    info <- unstack(geneByHp, entrez~hp)
    ic <- computeHpIC(info, hp_descendants)
    
    # Compute semantic similarity matrix between candidate gene HPs and HPs of interest
    compMat <- compareHPSets(
        hpSet1=genHp, hpSet2=hpOfInterest,
        IC=ic,
        ancestors=hp_ancestors,
        method="Resnik",
        BPPARAM=SerialParam()
    )
    
    # Summarize the similarity matrix into a single score
    direct_score <- hpSetCompSummary(compMat, method="bma", direction="symSim")
    
    # Compute similarity scores for all genes to rank the candidate gene
    hpGeneResnik <- compareHPSets(
        hpSet1=names(ic), hpSet2=hpOfInterest,
        IC=ic,
        ancestors=hp_ancestors,
        method="Resnik",
        BPPARAM=SerialParam()
    )
    
    hpByGene <- unstack(geneByHp, hp~entrez)
    hpMatByGene <- lapply(
        hpByGene,
        function(x){
            hpGeneResnik[x, , drop=FALSE]
        }
    )
    
    resnSss <- unlist(lapply(
        hpMatByGene,
        hpSetCompSummary,
        method="bma", direction="symSim"
    ))
    
    # Extract candidate score and calculate ranks
    if (!genId %in% names(resnSss)) {
      stop("Error: Candidate gene ", genId, " not found in the computed similarity scores.")
    }
    
    candScore <- resnSss[genId]
    candRank <- sum(resnSss >= candScore)
    candRelRank <- candRank/length(resnSss)
    
    # ==========================================
    # --- WRITE OUTPUTS ---
    # ==========================================
    
    # Save similarity matrix
    write.csv(compMat, "candidate_vs_interest_similarity_matrix.csv", row.names = TRUE)
    saveRDS(compMat, "candidate_vs_interest_similarity_matrix.rds")
    
    # Save all gene scores
    all_scores_df <- data.frame(
      Entrez = names(resnSss),
      Score = as.numeric(resnSss),
      stringsAsFactors = FALSE
    )
    write.csv(all_scores_df, "all_genes_scores.csv", row.names = FALSE)
    saveRDS(resnSss, "all_genes_scores.rds")
    
    # Save summary metrics
    summary_df <- data.frame(
      Metric = c("Candidate_Gene_ID", "Candidate_Score", "Rank", "Total_Genes", "Relative_Rank_Percent"),
      Value = c(as.character(genId), as.character(candScore), as.character(candRank), as.character(length(resnSss)), as.character(candRelRank * 100)),
      stringsAsFactors = FALSE
    )
    write.csv(summary_df, "candidate_relevance_summary.csv", row.names = FALSE)
    
    # Generate and save distribution plot
    h <- hist(resnSss, breaks = 100, plot = FALSE)
    max_y <- max(h\$counts) * 1.2
    
    pdf("symmetric_semantic_similarity_distribution.pdf", width = 8, height = 6)
    hist(
        resnSss,
        breaks = 100, col = "grey",
        ylim = c(0, max_y),
        xlab = expression(Sim[sym]),
        ylab = "Number of genes",
        main = paste(
            "Distribution of symmetric semantic similarity scores\nfor all the",
            length(resnSss), "genes"
        )
    )
    abline(v = candScore, col = "#BE0000", lwd = 3, lty = 2)
    text(
        x = candScore, y = max_y * 0.5,
        paste0(
            "Candidate Gene (", genId, ")\n",
            "Score: ", round(candScore, 4), "\n",
            "Rank: ", candRank, " / ", length(resnSss), "\n",
            "Relative Rank: ", round(candRelRank * 100, 2), "%"
        ),
        pos = if (candScore > median(resnSss, na.rm = TRUE)) 2 else 4,
        cex = 0.8,
        col = "#BE0000"
    )
    dev.off()

    writeLines(c(
        '"BIOC_PCAN_DIRECT_PHENOTYPE_COMPARISON":',
        paste0('    PCAN: ', as.character(packageVersion('PCAN')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_direct_phenotype_comparison.csv versions.yml
    """
}

workflow BIOC_PCAN_DIRECT_PHENOTYPE_COMPARISON_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ hpOfInterest, genId, geneByTrait, hpByTrait ] ]

    main:
    BIOC_PCAN_DIRECT_PHENOTYPE_COMPARISON(ch_input)

    emit:
    tables   = BIOC_PCAN_DIRECT_PHENOTYPE_COMPARISON.out.tables
    plots    = BIOC_PCAN_DIRECT_PHENOTYPE_COMPARISON.out.plots
    objects  = BIOC_PCAN_DIRECT_PHENOTYPE_COMPARISON.out.objects
    versions = BIOC_PCAN_DIRECT_PHENOTYPE_COMPARISON.out.versions
}
