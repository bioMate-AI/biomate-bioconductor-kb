#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: gage
// GAGE is a published method for gene set (enrichment or GSEA) or pathway analysis. GAGE is generally 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/gage/inst/doc/RNA-seqWorkflow.R
// Upstream  : DESeq, DESeq2, GenomicAlignments, edgeR, gageData
// Downstream: EGSEA
//
// Install: BiocManager::install("gage")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GAGE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-gage"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-gage:2.56.0--r44_0' :
        'quay.io/biocontainers/bioconductor-gage:2.56.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_gage_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_gage_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_gage_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(gage)
    library(BamFileList)
    library(DESeq)
    library(DESeqDataSetFromMatrix)
    library(DGEList)
    library(DataFrame)
    library(ScanBamParam)
    library(jsonlite)

    # --- KEGG Pathway Enrichment ---
    # Key functions: gage
    ref.idx <- 5:8
    samp.idx <- 1:4
    cnts.kegg.p <- gage(
        cnts.norm,
        gsets = kegg.gs,
        ref = ref.idx,
        samp = samp.idx,
        compare = "unpaired"
    )

    # --- Pathway Visualization ---
    # Key functions: pathview
    sel <- cnts.kegg.p$greater[, "q.val"] < 0.1 &
        !is.na(cnts.kegg.p$greater[, "q.val"])
    path.ids <- rownames(cnts.kegg.p$greater)[sel]
    path.ids2 <- substr(path.ids, 1, 8)
    cnts.d <- cnts.norm[, samp.idx] - rowMeans(cnts.norm[, ref.idx])
    pv.out.list <- sapply(
        path.ids2[1:3],
        function(pid) pathview(
            gene.data = cnts.d,
            pathway.id = pid,
            species = "hsa"
        )
    )

    # --- Gene Ontology Enrichment ---
    # Key functions: gage
    ref.idx <- 5:8
    samp.idx <- 1:4
    cnts.mf.p <- gage(
        cnts.norm,
        gsets = go.sets.hs[go.subs.hs$MF],
        ref = ref.idx,
        samp = samp.idx,
        compare = "unpaired"
    )

    # --- Gene-level Visualization ---
    # Key functions: geneData
    ref.idx <- 5:8
    samp.idx <- 1:4
    top.gs <- rownames(cnts.mf.p$less)[1:3]
    for (gs in top.gs) {
        outname <- gsub(" |:|/", "_", substr(gs, 12, 100))
        geneData(
            genes = go.sets.hs[[gs]],
            exprs = cnts.norm,
            ref = ref.idx,
            samp = samp.idx,
            outname = outname,
            txt = TRUE,
            heatmap = TRUE,
            limit = 3,
            scatterplot = TRUE
        )
    }

    # --- Enrichment Analysis with Custom Statistics ---
    # Key functions: gage
    ref.idx <- 5:8
    samp.idx <- 1:4
    cnts.t <- apply(cnts.norm, 1, function(x) {
        t.test(x[samp.idx], x[ref.idx], paired = FALSE)$statistic
    })
    cnts.meanfc <- rowMeans(
        cnts.norm[, samp.idx] - cnts.norm[, ref.idx]
    )
    cnts.t.kegg.p <- gage(
        cnts.t,
        gsets = kegg.gs,
        ref = NULL,
        samp = NULL
    )
    cnts.meanfc.kegg.p <- gage(
        cnts.meanfc,
        gsets = kegg.gs,
        ref = NULL,
        samp = NULL
    )


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_gage_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_gage_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_gage_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GAGE:", paste0("    gage: ", packageVersion("gage"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gage_results.csv
    touch ${prefix}_gage_output.rds
    echo "BIOC_GAGE:" > versions.yml
    echo "    gage: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GAGE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GAGE(ch_input)

    emit:
    results  = BIOC_GAGE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GAGE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GAGE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GAGE.out.versions  // channel: path(versions.yml)
}
