#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: seqgsea — integrated_de_ds_gsea
// Run an integrated gene set enrichment analysis combining differential expression and differential splicing from exon-level RNA-Seq count data.
// Input: case.files, control.files, geneset.file
// Container: quay.io/biocontainers/bioconductor-seqgsea:1.50.0--r45hdfd78af_0
// R packages: doParallel, SeqGSEA
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SEQGSEA_INTEGRATED_DE_DS_GSEA {
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
    .bm_deps <- c("doParallel", "SeqGSEA")
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
    library(SeqGSEA)
    library(doParallel)
    
    # 1. Register parallel backend
    cl <- makeCluster(2)
    registerDoParallel(cl)
    
    # Define permutation times
    perm.times <- 20
    
    # Helper function to resolve input files robustly
    get_files <- function(meta_file) {
      if (!file.exists(meta_file)) {
        stop(paste("Required input file missing:", meta_file))
      }
      lines <- trimws(readLines(meta_file))
      lines <- lines[lines != ""]
      if (length(lines) > 0 && all(file.exists(lines))) {
        return(lines)
      }
      return(meta_file)
    }
    
    # Resolve user input files from the working directory
    case.files <- get_files("case.files")
    control.files <- get_files("control.files")
    geneset.file <- "geneset.file"
    
    # 2. Load exon count data
    RCS <- loadExonCountData(case.files, control.files)
    
    # 3. Filter low-expression exons and genes
    RCS <- exonTestability(RCS, cutoff=5)
    geneTestable <- geneTestability(RCS)
    RCS <- subsetByGenes(RCS, unique(geneID(RCS))[ geneTestable ])
    geneIDs <- unique(geneID(RCS))
    
    # 4. Calculate DS NB statistics on real and permuted datasets
    RCS <- estiExonNBstat(RCS)
    RCS <- estiGeneNBstat(RCS)
    permuteMat <- genpermuteMat(RCS, times=perm.times)
    RCS <- DSpermute4GSEA(RCS, permuteMat)
    
    # 5. Calculate DE NB statistics on real and permuted datasets
    geneCounts <- getGeneCount(RCS)
    label <- label(RCS)
    dds <- runDESeq(geneCounts, label)
    DEGres <- DENBStat4GSEA(dds)
    DEpermNBstat <- DENBStatPermut4GSEA(dds, permuteMat)
    
    # 6. Normalize DE and DS scores
    DEscore.normFac <- normFactor(DEpermNBstat)
    DEscore <- scoreNormalization(DEGres\$NBstat, DEscore.normFac)
    DEscore.perm <- scoreNormalization(DEpermNBstat, DEscore.normFac)
    
    DSscore.normFac <- normFactor(RCS@permute_NBstat_gene)
    DSscore <- scoreNormalization(RCS@featureData_gene\$NBstat, DSscore.normFac)
    DSscore.perm <- scoreNormalization(RCS@permute_NBstat_gene, DSscore.normFac)
    
    # 7. Integrate DE and DS scores
    gene.score <- geneScore(DEscore, DSscore, DEweight=0.5)
    gene.score.perm <- genePermuteScore(DEscore.perm, DSscore.perm, DEweight=0.5)
    
    # 8. Load gene sets
    gene.set <- loadGenesets(geneset.file, geneIDs, geneID.type="ensembl", genesetsize.min = 5, genesetsize.max = 1000)
    
    # 9. Run GSEA and format results
    gene.set <- GSEnrichAnalyze(gene.set, gene.score, gene.score.perm, weighted.type=1)
    GSEAres <- GSEAresultTable(gene.set, TRUE)
    
    # Write output files
    write.csv(GSEAres, "GSEA_results.csv", row.names=FALSE)
    saveRDS(gene.set, "GSEA_geneset_object.rds")
    saveRDS(RCS, "RCS_object.rds")
    
    # Generate diagnostic and results plots
    plotGeneScore(DEscore, DEscore.perm, pdf="DEScore.pdf", main="Expression")
    plotGeneScore(DSscore, DSscore.perm, pdf="DSScore.pdf", main="Splicing")
    plotGeneScore(gene.score, gene.score.perm, pdf="GeneScore.pdf")
    plotES(gene.set, pdf="GSEA_ES.pdf")
    plotSig(gene.set, pdf="GSEA_FDR.pdf")
    
    # Stop cluster
    stopCluster(cl)

    writeLines(c(
        '"BIOC_SEQGSEA_INTEGRATED_DE_DS_GSEA":',
        paste0('        seqgsea: ', as.character(packageVersion("seqgsea")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_integrated_de_ds_gsea.csv versions.yml
    """
}

workflow BIOC_SEQGSEA_INTEGRATED_DE_DS_GSEA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ case.files, control.files, geneset.file ] ]

    main:
    BIOC_SEQGSEA_INTEGRATED_DE_DS_GSEA(ch_input)

    emit:
    tables   = BIOC_SEQGSEA_INTEGRATED_DE_DS_GSEA.out.tables
    plots    = BIOC_SEQGSEA_INTEGRATED_DE_DS_GSEA.out.plots
    objects  = BIOC_SEQGSEA_INTEGRATED_DE_DS_GSEA.out.objects
    versions = BIOC_SEQGSEA_INTEGRATED_DE_DS_GSEA.out.versions
}
