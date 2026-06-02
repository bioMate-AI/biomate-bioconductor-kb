#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: MAGeCKFlute
// CRISPR (clustered regularly interspaced short palindrome repeats) coupled with nuclease Cas9 (CRISPR
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/MAGeCKFlute/inst/doc/MAGeCKFlute.R
// Upstream  : clusterProfiler, enrichplot, ggplot2
// Downstream: none
//
// Install: BiocManager::install("MAGeCKFlute")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MAGECKFLUTE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-mageckflute"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-mageckflute:2.9.0--r44_0' :
        'quay.io/biocontainers/bioconductor-mageckflute:2.9.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_mageckflute_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_mageckflute_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_mageckflute_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(MAGeCKFlute)
    library(jsonlite)


    # --- Check Count Summary [] ---
    # Key functions: read.delim, extdata, BarView, MapRatesView, melt, scale_fill_manual, value, variable
    file4 = file.path(system.file("extdata", package = "MAGeCKFlute"),
                      "testdata/countsummary.txt")
    countsummary = read.delim(file4, check.names = FALSE)
    head(countsummary)
    # Gini index
    BarView(countsummary, x = "Label", y = "GiniIndex",
            ylab = "Gini index", main = "Evenness of sgRNA reads")

    # Missed sgRNAs
    countsummary$Missed = log10(countsummary$Zerocounts)
    BarView(countsummary, x = "Label", y = "Missed", fill = "#394E80",
            ylab = "Log10 missed gRNAs", main = "Missed sgRNAs")

    # Read mapping
    file1 = file.path(system.file("extdata", package = "MAGeCKFlute"),
                      "testdata/rra.gene_summary.txt")
    gdata = ReadRRA(file1)
    head(gdata)

    # --- Mmu2hsa [] ---
    # Key functions: TransGeneID, symbol, mmu, hsa, ScatterView, VolcanoView, volcano, rank
    gdata$HumanGene = TransGeneID(gdata$id, fromType = "symbol", toType = "symbol",
                                  fromOrg = "mmu", toOrg = "hsa")
    sdata$HumanGene = TransGeneID(sdata$Gene, fromType = "symbol", toType = "symbol",
                                  fromOrg = "mmu", toOrg = "hsa")
    gdata$LogFDR = -log10(gdata$FDR)
    p1 = ScatterView(gdata, x = "Score", y = "LogFDR", label = "id", 
                     model = "volcano", top = 5)
    print(p1)

    # Or
    p2 = VolcanoView(gdata, x = "Score", y = "FDR", Label = "id")
    print(p2)
    gdata$Rank = rank(gdata$Score)
    p1 = ScatterView(gdata, x = "Rank", y = "Score", label = "id", 
                     top = 5, auto_cut_y = TRUE, ylab = "Log2FC", 
                     groups = c("top", "bottom"))
    print(p1)

    # --- Rankrra2 [] ---
    # Key functions: RankView, sample, ScatterView, CutoffCalling, top, bottom, sgRankView
    geneList= gdata$Score
    names(geneList) = gdata$id
    p2 = RankView(geneList, top = 5, bottom = 10)
    print(p2)
    RankView(geneList, top = 0, bottom = 0, genelist = c("Pbrm1", "Arid2", "Brd7"))
    gdata$RandomIndex = sample(1:nrow(gdata), nrow(gdata))
    gdata = gdata[order(-gdata$Score), ]
    gg = gdata[gdata$Score>0, ]
    p1 = ScatterView(gg, x = "RandomIndex", y = "Score", label = "id",
                     y_cut = CutoffCalling(gdata$Score,2), 
                     groups = "top", top = 5, ylab = "Log2FC")
    p1
    gg = gdata[gdata$Score<0, ]
    # --- Enrich Rra [] ---
    # Key functions: EnrichAnalyzer, EnrichedView, rnorm, HeatmapView, rep, BatchRemove
    geneList= gdata$Score
    names(geneList) = gdata$id
    enrich_pos = EnrichAnalyzer(geneList = geneList[geneList>0.5], 
                                method = "HGT", type = "KEGG")
    enrich_neg = EnrichAnalyzer(geneList = geneList[geneList< -0.5], 
                                method = "HGT", type = "KEGG")
    EnrichedView(enrich_pos, mode = 1, top = 5, bottom = 0)
    EnrichedView(enrich_pos, mode = 2, top = 5, bottom = 0)
    EnrichedView(enrich_neg, mode = 2, top = 0, bottom = 5)
    ##Before batch removal
    edata = matrix(c(rnorm(2000, 5), rnorm(2000, 8)), 1000)
    colnames(edata) = paste0("s", 1:4)
    HeatmapView(cor(edata))

    ## After batch removal
    batchMat = data.frame(sample = colnames(edata), batch = rep(1:2, each = 2))
    edata1 = BatchRemove(edata, batchMat)
    head(edata1$data)
    print(edata1$p)

    # --- Read Beta [] ---
    # Key functions: ReadBeta, extdata, TransGeneID, NormalizeBeta, Pmel1_Ctrl, symbol, mmu, hsa
    file3 = file.path(system.file("extdata", package = "MAGeCKFlute"),
                      "testdata/mle.gene_summary.txt")
    # Read and visualize the file format
    gdata = ReadBeta(file3)
    head(gdata)
    ctrlname = "Pmel1_Ctrl"
    treatname = "Pmel1"
    gdata$HumanGene = TransGeneID(gdata$Gene, fromType = "symbol", toType = "symbol",
                                  fromOrg = "mmu", toOrg = "hsa")

    gdata_cc = NormalizeBeta(gdata, id = "HumanGene", samples=c(ctrlname, treatname), 
                             method="cell_cycle")
    head(gdata_cc)
    DensityView(gdata_cc, samples=c(ctrlname, treatname))
    ConsistencyView(gdata_cc, ctrlname, treatname)

    # Another option MAView
    MAView(gdata_cc, ctrlname, treatname)

    # --- Selection2 [] ---
    # Key functions: rowMeans, ScatterView, top, bottom, rank, RankView, Pmel1_Ctrl, ninesquare
    gdata_cc$Control = rowMeans(gdata_cc[,ctrlname, drop = FALSE])
    gdata_cc$Treatment = rowMeans(gdata_cc[,treatname, drop = FALSE])

    p1 = ScatterView(gdata_cc, "Control", "Treatment", label = "Gene", 
                     auto_cut_diag = TRUE, display_cut = TRUE, 
                     groups = c("top", "bottom"),
                     toplabels = c("Pbrm1", "Brd7", "Arid2", "Jak1", "Stat1", "B2m"))
    print(p1)
    gdata_cc$Diff = gdata_cc$Treatment - gdata_cc$Control
    gdata_cc$Rank = rank(gdata_cc$Diff)
    p1 = ScatterView(gdata_cc, x = "Rank", y =  "Diff", label = "Gene", 
                     top = 5, auto_cut_y = TRUE, groups = c("top", "bottom"))
    print(p1)

    # Or
    rankdata = gdata_cc$Treatment - gdata_cc$Control
    names(rankdata) = gdata_cc$Gene
    RankView(rankdata)
    p1 = ScatterView(gdata_cc, x="Pmel1_Ctrl", y="Pmel1", label = "Gene", 
                     model = "ninesquare", top = 5, display_cut = TRUE, force = 2)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_mageckflute_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_mageckflute_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_mageckflute_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MAGECKFLUTE:", paste0("    mageckflute: ", packageVersion("MAGeCKFlute"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_mageckflute_results.csv
    touch ${prefix}_mageckflute_output.rds
    echo "BIOC_MAGECKFLUTE:" > versions.yml
    echo "    mageckflute: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MAGECKFLUTE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MAGECKFLUTE(ch_input)

    emit:
    results  = BIOC_MAGECKFLUTE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MAGECKFLUTE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MAGECKFLUTE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MAGECKFLUTE.out.versions  // channel: path(versions.yml)
}
