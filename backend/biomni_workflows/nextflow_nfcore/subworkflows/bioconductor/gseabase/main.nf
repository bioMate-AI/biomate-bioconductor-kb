#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: GSEABase
// This package provides classes and methods to support Gene Set Enrichment Analysis (GSEA).
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/GSEABase/inst/doc/GSEABase.R
// Upstream  : ReportingTools, annotate
// Downstream: AGDEX, BicARE, CCPROMISE, Cepo, cpvSNP
//
// Install: BiocManager::install("GSEABase")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GSEABASE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-gseabase"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-gseabase:1.68.0--r44_0' :
        'quay.io/biocontainers/bioconductor-gseabase:1.68.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_gseabase_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_gseabase_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_gseabase_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(GSEABase)
    library(jsonlite)


    # --- Preliminaries [] ---
    # Key functions: suppressPackageStartupMessages, GeneSet
    ## FIXME: <adjMat> adjacency matrix -- color w. +/- 1
    ## FIXME: limma topTable --> GeneColorSet
    ## w. verbose=TRUE
    suppressPackageStartupMessages({
        library(GSEABase)
        library(hgu95av2.db)
        library(GO.db)
    })
    data(sample.ExpressionSet) # from Biobase
    egs <- GeneSet(sample.ExpressionSet[201:250,], setName="Sample")
    egs

    # --- Gene Ids [] ---
    # Key functions: geneIds, details, GeneSet, AnnotationIdentifier, GOCollection, showMethods, hgu95av2
    head(geneIds(egs))
    details(egs)

    ## -----------------------------------------------------------------------------
      ## FIXME: GeneSet(AnnotationIdentifier("hgu95av2")) --> non-empty
      ## FIXME: GeneSet(AnnotationIdentifier("hgu95av2"),
      ## collectionType=GOCollection()) filters on GOCollection (or KEGG)

    ## ----GeneSet-methods----------------------------------------------------------
    showMethods("GeneSet", inherited=FALSE)

    # --- Gene Identifier Types [] ---
    # Key functions: slot, getClass, subclasses, mapIdentifiers, EntrezIdentifier
    names(slot(getClass("GeneIdentifierType"), "subclasses"))
    mapIdentifiers(egs, EntrezIdentifier())

    # --- Gene Set Identifiers [] ---
    # Key functions: getEG, geneIds, GeneSet, EntrezIdentifier, hgu95av2, slot, getClass, subclasses
    library(annotate)                       # getEG
    eids <- unique(getEG(geneIds(egs), "hgu95av2"))
    eids <- eids[!is.na(eids)]
    GeneSet(EntrezIdentifier(), geneIds=as.character(eids))
    names(slot(getClass("CollectionType"), "subclasses"))

    # --- Gocollection [] ---
    # Key functions: GeneSet, GOCollection, EntrezIdentifier, org.Hs.eg.db, BroadCollection, mapIdentifiers, AnnotationIdentifier, extdata
    GeneSet(GOCollection(c("GO:0005488", "GO:0019825"),
                         evidenceCode="IDA"),
            geneIdType=EntrezIdentifier("org.Hs.eg.db"),
            setName="Sample GO Collection")
    fl <- system.file("extdata", "Broad1.xml", package="GSEABase")
    bgs <- GeneSet(BroadCollection(), urls=fl)
    bgs

    ## ----Broad-to-annotation------------------------------------------------------
    bgs1 <- mapIdentifiers(bgs, AnnotationIdentifier("hgu95av2"))
    bgs1

    # --- Subset [] ---
    # Key functions: textConnection, close, unlink, GeneColorSet, EntrezIdentifier, hide, GeneSetCollection, GOCollection
    bgs[1:5]
    bgs[c("GALNS", "LOC646365")]

    ## ----egs-bgs------------------------------------------------------------------
    egs & bgs1

    ## ----subset-ExpressionSet-----------------------------------------------------
    sample.ExpressionSet[bgs,]

    ## ----GeneColorSet-setup, echo=FALSE, results="hide"---------------------------
    gsc <- GeneSetCollection(sample.ExpressionSet[201:250,], setType=GOCollection())
    gsc
    gsc[["GO:0005737"]]

    ## ----GeneSetCollection-GOCollection-------------------------------------------
    GeneSetCollection(sample.ExpressionSet[201:300,],
                      setType=GOCollection(evidenceCode="IMP"))

    ## ----GeneSetCollection-BroadCollection----------------------------------------
       ## FIXME: BroadCollection default to paste("c", 1:4, sep="")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_gseabase_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_gseabase_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_gseabase_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GSEABASE:", paste0("    gseabase: ", packageVersion("GSEABase"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gseabase_results.csv
    touch ${prefix}_gseabase_output.rds
    echo "BIOC_GSEABASE:" > versions.yml
    echo "    gseabase: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GSEABASE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GSEABASE(ch_input)

    emit:
    results  = BIOC_GSEABASE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GSEABASE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GSEABASE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GSEABASE.out.versions  // channel: path(versions.yml)
}
