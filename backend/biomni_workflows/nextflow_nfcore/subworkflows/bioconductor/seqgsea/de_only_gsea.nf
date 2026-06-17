#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: seqgsea — de_only_gsea
// Run gene set enrichment analysis using only differential expression scores from gene-level RNA-Seq count data.
// Input: count.file, geneset.file
// Container: quay.io/biocontainers/bioconductor-seqgsea:1.50.0--r45hdfd78af_0
// R packages: SeqGSEA, doParallel
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SEQGSEA_DE_ONLY_GSEA {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-seqgsea:1.50.0--r45hdfd78af_0"

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
    .bm_deps <- c("SeqGSEA", "doParallel")
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
    
    library(SeqGSEA)
    library(doParallel)
    
    # --- Register parallel backend ---
    cl <- makeCluster(2)
    registerDoParallel(cl)
    perm.times <- 20
    
    count.file <- "count.file"
    geneset.file <- "geneset.file"
    
    # --- Load gene read count data ---
    geneCounts <- read.table(count.file, header=TRUE, row.names=1, sep="\t")
    
    # Determine labels dynamically based on the number of samples in the input file
    n_samples <- ncol(geneCounts)
    label <- as.factor(c(rep(1, n_samples/2), rep(0, n_samples - n_samples/2)))
    
    # --- Calculate DE NB statistics on real and permuted datasets ---
    dds <- runDESeq(geneCounts, label)
    DEGres <- DENBStat4GSEA(dds)
    permuteMat <- genpermuteMat(label, times=perm.times)
    DEpermNBstat <- DENBStatPermut4GSEA(dds, permuteMat)
    
    # --- Normalize DE scores ---
    DEscore.normFac <- normFactor(DEpermNBstat)
    DEscore <- scoreNormalization(DEGres\$NBstat, DEscore.normFac)
    DEscore.perm <- scoreNormalization(DEpermNBstat, DEscore.normFac)
    
    # --- Integrate scores with DEweight=1 ---
    gene.score <- geneScore(DEscore, DEweight=1)
    gene.score.perm <- genePermuteScore(DEscore.perm, DEweight=1)
    
    # --- Load gene sets ---
    geneIDs <- rownames(geneCounts)
    gene.set <- loadGenesets(geneset.file, geneIDs, geneID.type="ensembl", genesetsize.min = 5, genesetsize.max = 1000)
    
    # --- Run GSEA and format results ---
    gene.set <- GSEnrichAnalyze(gene.set, gene.score, gene.score.perm, weighted.type=1)
    GSEAres <- GSEAresultTable(gene.set, TRUE)
    
    # Write output tables and RDS objects
    write.table(GSEAres, "SeqGSEA_de_only_results.txt", sep="\t", quote=FALSE, row.names=FALSE)
    saveRDS(gene.set, "SeqGSEA_geneset_analyzed.rds")
    saveRDS(GSEAres, "SeqGSEA_results_table.rds")
    
    # Generate and save diagnostic and results plots
    plotGeneScore(DEscore, DEscore.perm, pdf="SeqGSEA_DEScore.pdf", main="Expression")
    plotGeneScore(gene.score, gene.score.perm, pdf="SeqGSEA_GeneScore.pdf")
    plotES(gene.set, pdf="SeqGSEA_ES_plot.pdf")
    plotSig(gene.set, pdf="SeqGSEA_FDR_plot.pdf")
    
    # Clean up parallel backend
    stopCluster(cl)

    writeLines(c(
        '"BIOC_SEQGSEA_DE_ONLY_GSEA":',
        paste0('        seqgsea: ', as.character(packageVersion("seqgsea")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_de_only_gsea.csv versions.yml
    """
}

workflow BIOC_SEQGSEA_DE_ONLY_GSEA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ count.file, geneset.file ] ]

    main:
    BIOC_SEQGSEA_DE_ONLY_GSEA(ch_input)

    emit:
    tables   = BIOC_SEQGSEA_DE_ONLY_GSEA.out.tables
    plots    = BIOC_SEQGSEA_DE_ONLY_GSEA.out.plots
    objects  = BIOC_SEQGSEA_DE_ONLY_GSEA.out.objects
    versions = BIOC_SEQGSEA_DE_ONLY_GSEA.out.versions
}
