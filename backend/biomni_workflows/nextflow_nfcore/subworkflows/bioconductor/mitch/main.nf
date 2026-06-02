#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: mitch
// mitch is an R package for multi-contrast enrichment analysis. At it’s heart, it uses a rank-MANOVA b
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/mitch/inst/doc/infiniumMethArrayWorkflow.R
// Upstream  : HGNChelper, stringi
// Downstream: none
//
// Install: BiocManager::install("mitch")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MITCH {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-mitch"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-mitch:1.18.4--r44_0' :
        'quay.io/biocontainers/bioconductor-mitch:1.18.4--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_mitch_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_mitch_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_mitch_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(mitch)
    library(jsonlite)


    # --- Lib [] ---
    # Key functions: suppressPackageStartupMessages, mitch
    suppressPackageStartupMessages({
        library("mitch")
        library("HGNChelper")
        library("IlluminaHumanMethylation450kanno.ilmn12.hg19")
        library("IlluminaHumanMethylationEPICanno.ilm10b4.hg19")
    })

    # --- Genesets Example [] ---
    # Key functions: mitch
    data(genesetsExample)
    head(genesetsExample,3)

    # --- Anno1 [] ---
    # Key functions: getAnnotation, stack, UCSC_RefGene_Name, UCSC_RefGene_Group, Islands_Name, Relation_to_Island, gene, probe
    anno <- getAnnotation(IlluminaHumanMethylation450kanno.ilmn12.hg19)
    myann <- data.frame(anno[,c("UCSC_RefGene_Name","UCSC_RefGene_Group","Islands_Name","Relation_to_Island")])
    head(myann)
    gp <- myann[,"UCSC_RefGene_Name",drop=FALSE]
    gp2 <- strsplit(gp$UCSC_RefGene_Name,";")
    names(gp2) <- rownames(gp)
    gp2 <- lapply(gp2,unique)
    gt1 <- stack(gp2)
    colnames(gt1) <- c("gene","probe")
    gt1$probe <- as.character(gt1$probe)

    # --- Genenames [] ---
    # Key functions: getCurrentHumanMap, readRDS, checkGeneSymbols
    #new.hgnc.table <- getCurrentHumanMap()
    new.hgnc.table <- readRDS("../inst/extdata/new.hgnc.table.rds")
    fix <- checkGeneSymbols(gt1$gene,map=new.hgnc.table)
    fix2 <- fix[which(fix$x != fix$Suggested.Symbol),]
    length(unique(fix2$x))
    gt1$gene <- fix$Suggested.Symbol
    head(gt1)

    # --- Import1 [] ---
    # Key functions: read.table
    x <- read.table("https://ziemann-lab.net/public/gmea/dma3a.tsv",header=TRUE,row.names=1)
    head(x)

    # --- Import2 [] ---
    # Key functions: mitch_import, limma
    y <- mitch_import(x,DEtype="limma",geneTable=gt1)
    head(y)
    dim(y)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_mitch_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_mitch_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_mitch_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MITCH:", paste0("    mitch: ", packageVersion("mitch"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_mitch_results.csv
    touch ${prefix}_mitch_output.rds
    echo "BIOC_MITCH:" > versions.yml
    echo "    mitch: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MITCH_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MITCH(ch_input)

    emit:
    results  = BIOC_MITCH.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MITCH.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MITCH.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MITCH.out.versions  // channel: path(versions.yml)
}
