#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: loci2path — pathway_enrichment_analysis
// Perform pathway enrichment analysis on genomic intervals using tissue-specific eQTL sets and gene set collections.
// Input: query/Psoriasis.BED, eqtl/brain.gtex.txt, eqtl/skin.gtex.txt, eqtl/blood.gtex.txt, geneSet/biocarta.txt, geneSet/biocarta.set.txt
// Container: quay.io/biocontainers/bioconductor-loci2path:1.30.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: GenomicRanges, loci2path
// Visualizations: heatmap
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load query regions as GenomicRanges
//  * 2. [Input & Preparation] Construct eQTL sets and list
//  * 3. [Input & Preparation] Prepare gene set collection
//  * 4. [Core Analysis] Perform query (single or multiple tissues, optionally in parallel)
//  * 5. [Visualization & Output] Explore results (extract tables, covered genes, tissue degrees, and generate visualizations like heatmaps, word clouds, and p-valu

nextflow.enable.dsl = 2

process BIOC_LOCI2PATH_PATHWAY_ENRICHMENT_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim"

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
    .bm_deps <- c("GenomicRanges", "loci2path")
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
        library(GenomicRanges)
        library(loci2path)
        
        # 1. Load query regions as GenomicRanges
        bed.file <- "query/Psoriasis.BED"
        query.bed <- read.table(bed.file, header=FALSE)
        colnames(query.bed) <- c("chr","start","end")
        query.gr <- makeGRangesFromDataFrame(query.bed)
        
        # 2. Construct eQTL sets and list
        brain.file <- "eqtl/brain.gtex.txt"
        tab <- read.table(brain.file, stringsAsFactors=FALSE, header=TRUE)
        snp.gr <- GRanges(seqnames=Rle(tab\$snp.chr), ranges=IRanges(start=tab\$snp.pos, width=1))
        brain.eset <- eqtlSet(tissue="brain", eqtlId=tab\$snp.id, eqtlRange=snp.gr, gene=as.character(tab\$gene.entrez.id))
        
        skin.file <- "eqtl/skin.gtex.txt"
        tab <- read.table(skin.file, stringsAsFactors=FALSE, header=TRUE)
        snp.gr <- GRanges(seqnames=Rle(tab\$snp.chr), ranges=IRanges(start=tab\$snp.pos, width=1))
        skin.eset <- eqtlSet(tissue="skin", eqtlId=tab\$snp.id, eqtlRange=snp.gr, gene=as.character(tab\$gene.entrez.id))
        
        blood.file <- "eqtl/blood.gtex.txt"
        tab <- read.table(blood.file, stringsAsFactors=FALSE, header=TRUE)
        snp.gr <- GRanges(seqnames=Rle(tab\$snp.chr), ranges=IRanges(start=tab\$snp.pos, width=1))
        blood.eset <- eqtlSet(tissue="blood", eqtlId=tab\$snp.id, eqtlRange=snp.gr, gene=as.character(tab\$gene.entrez.id))
        
        eset.list <- list(Brain=brain.eset, Skin=skin.eset, Blood=blood.eset)
        
        # 3. Prepare gene set collection
        biocarta.link.file <- "geneSet/biocarta.txt"
        biocarta.set.file <- "geneSet/biocarta.set.txt"
        
        biocarta.link <- read.delim(biocarta.link.file, header=FALSE, stringsAsFactors=FALSE)
        set.geneid <- read.table(biocarta.set.file, stringsAsFactors=FALSE)
        set.geneid <- strsplit(set.geneid[,1], split=",")
        names(set.geneid) <- biocarta.link[,1]
        
        biocarta <- geneSet(numGene=31847, description=biocarta.link[,2], geneSetList=set.geneid)
        
        # 4. Perform query (single, multiple, and parallel)
        res.one <- query(query.gr=query.gr, loci=skin.eset, path=biocarta)
        
        res.esetlist <- query(query.gr=query.gr, loci=eset.list, path=biocarta)
        
        res.paral <- query(query.gr=query.gr, loci=eset.list, path=biocarta, parallel=TRUE)
        
        # 5. Explore results
        resultTable(res.esetlist)
        coveredGene(res.esetlist)
        
        tissue.degree <- getTissueDegree(res.esetlist, eset.list)
        res.tissue <- data.frame(resultTable(res.esetlist), t.degree=tissue.degree\$mean.tissue.degree)
        
        gr.tissue <- query(query.gr, loci=eset.list)
        
        mat <- getMat(res.esetlist, test.method="gene")
        
        # Generate and save visualizations safely
        tryCatch({
          pdf("heatmap.pdf")
          heatmap.para <- getHeatmap(res.esetlist)
          dev.off()
        }, error = function(e) {
          message("Could not generate heatmap: ", e\$message)
        })
        
        tryCatch({
          pdf("wordcloud.pdf")
          wc <- getWordcloud(res.esetlist)
          dev.off()
        }, error = function(e) {
          message("Could not generate wordcloud: ", e\$message)
        })
        
        tryCatch({
          pdf("pval_plot.pdf")
          pval <- getPval(res.esetlist, test.method="gene")
          dev.off()
        }, error = function(e) {
          message("Could not generate p-value plot: ", e\$message)
        })
        
        description <- getPathDescription(res.esetlist, biocarta)
        
        # Write output files
        write.csv(res.one\$result.table, "res_one_result_table.csv", row.names=FALSE)
        write.csv(resultTable(res.esetlist), "res_esetlist_result_table.csv", row.names=FALSE)
        write.csv(res.tissue, "res_tissue_table.csv", row.names=FALSE)
        write.csv(gr.tissue, "gr_tissue_table.csv", row.names=TRUE)
        write.csv(mat, "tissue_pathway_matrix.csv")
        writeLines(description, "pathway_descriptions.txt")
        saveRDS(res.esetlist, "res_esetlist.rds")

    writeLines(c(
        '"BIOC_LOCI2PATH_PATHWAY_ENRICHMENT_ANALYSIS":',
        paste0('    loci2path: ', as.character(packageVersion('loci2path')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_pathway_enrichment_analysis.csv versions.yml
    """
}

workflow BIOC_LOCI2PATH_PATHWAY_ENRICHMENT_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ query/Psoriasis.BED, eqtl/brain.gtex.txt, eqtl/skin.gtex.txt, eqtl/blood.gtex.txt, geneSet/biocarta.txt, geneSet/biocarta.set.txt ] ]

    main:
    BIOC_LOCI2PATH_PATHWAY_ENRICHMENT_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_LOCI2PATH_PATHWAY_ENRICHMENT_ANALYSIS.out.tables
    plots    = BIOC_LOCI2PATH_PATHWAY_ENRICHMENT_ANALYSIS.out.plots
    objects  = BIOC_LOCI2PATH_PATHWAY_ENRICHMENT_ANALYSIS.out.objects
    versions = BIOC_LOCI2PATH_PATHWAY_ENRICHMENT_ANALYSIS.out.versions
}
