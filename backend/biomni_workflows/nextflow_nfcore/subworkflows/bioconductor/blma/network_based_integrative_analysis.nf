#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: BLMA — network_based_integrative_analysis
// Calculate gene statistics across multiple studies and perform downstream network-based pathway analysis.
// Input: dataList, groupList
// Container: quay.io/biocontainers/bioconductor-blma:1.34.0--r45hdfd78af_0
// R packages: BLMA, ROntoTools
// Bioconductor: 3.20 | R: 4.4
// Requires: BLMA, ROntoTools
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Identify common genes across all datasets
//  * 2. [Core Analysis] Calculate effect sizes and p-values across all studies using getStatistics
//  * 3. [Core Analysis] Identify differentially expressed genes
//  * 4. [Core Analysis] Perform pathway analysis with ORA and Pathway-Express (ROntoTools)

nextflow.enable.dsl = 2

process BIOC_BLMA_NETWORK_BASED_INTEGRATIVE_ANALYSIS {
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
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("BLMA", "ROntoTools")
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
    library(BLMA)
    library(ROntoTools)
    
    # 1. Read user input files from the working directory
    if (!file.exists("dataList.rds") || !file.exists("groupList.rds")) {
      stop("Error: 'dataList.rds' and 'groupList.rds' must be present in the working directory.")
    }
    
    dataList <- readRDS("dataList.rds")
    groupList <- readRDS("groupList.rds")
    
    # 2. Identify common genes across all datasets
    allGenes <- Reduce(intersect, lapply(dataList, rownames))
    
    # 3. Calculate effect sizes and p-values across all studies using getStatistics
    geneStat <- getStatistics(allGenes, dataList = dataList, groupList = groupList)
    
    # Save gene statistics
    write.csv(geneStat, "geneStat.csv", row.names = TRUE)
    
    # 4. Load KEGG pathways and prepare gene sets
    kpg <- loadKEGGPathways()\$kpg
    kpn <- loadKEGGPathways()\$kpn
    gslist <- lapply(kpg, function(y) nodes(y))
    
    # 5. Identify differentially expressed genes
    DEGenes.Left <- rownames(geneStat)[geneStat\$pLeft < 0.05 & geneStat\$ES.pLeft < 0.05]
    DEGenes.Right <- rownames(geneStat)[geneStat\$pRight < 0.05 & geneStat\$ES.pRight < 0.05]
    DEGenes <- union(DEGenes.Left, DEGenes.Right)
    
    # 6. Perform pathway analysis with ORA
    oraRes <- lapply(gslist, function(gs){
      pORACalc(geneSet = gs, DEGenes = DEGenes, measuredGenes = rownames(geneStat))
    })
    oraRes <- data.frame(p.value = unlist(oraRes), pathway = names(oraRes))
    rownames(oraRes)  <- kpn[rownames(oraRes)]
    
    # Print and save ORA results
    print("Head of ORA Results:")
    print(head(oraRes))
    write.csv(oraRes, "ora_results.csv", row.names = TRUE)
    
    # 7. Perform pathway analysis with Pathway-Express (ROntoTools)
    ES <- geneStat[DEGenes, "ES"]
    names(ES) <- DEGenes
    
    peRes <- pe(x = ES, graphs = kpg, ref = allGenes, nboot = 1000, seed = 1, verbose = FALSE)
    
    peRes.Summary <- Summary(peRes, comb.pv.func = fisherMethod)
    peRes.Summary[, ncol(peRes.Summary) + 1] <- rownames(peRes.Summary)
    rownames(peRes.Summary) <- kpn[rownames(peRes.Summary)]
    colnames(peRes.Summary)[ncol(peRes.Summary)] <- "pathway"
    
    # Print and save Pathway-Express results
    print("Head of Pathway-Express Results:")
    print(head(peRes.Summary))
    write.csv(peRes.Summary, "pe_results_summary.csv", row.names = TRUE)
    saveRDS(peRes, "pe_results_object.rds")

    writeLines(c(
        '"BIOC_BLMA_NETWORK_BASED_INTEGRATIVE_ANALYSIS":',
        paste0('    BLMA: ', as.character(packageVersion('BLMA')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_network_based_integrative_analysis.csv versions.yml
    """
}

workflow BIOC_BLMA_NETWORK_BASED_INTEGRATIVE_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ dataList, groupList ] ]

    main:
    BIOC_BLMA_NETWORK_BASED_INTEGRATIVE_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_BLMA_NETWORK_BASED_INTEGRATIVE_ANALYSIS.out.tables
    plots    = BIOC_BLMA_NETWORK_BASED_INTEGRATIVE_ANALYSIS.out.plots
    objects  = BIOC_BLMA_NETWORK_BASED_INTEGRATIVE_ANALYSIS.out.objects
    versions = BIOC_BLMA_NETWORK_BASED_INTEGRATIVE_ANALYSIS.out.versions
}
