#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: MultiRNAflow
// Our R package MultiRNAflow provides an easy to use unified framework allowing to automatically make 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/MultiRNAflow/inst/doc/MultiRNAflow_vignette-knitr.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("MultiRNAflow")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MULTIRNAFLOW {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-multirnaflow"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-multirnaflow:1.4.0--r44_0' :
        'quay.io/biocontainers/bioconductor-multirnaflow:1.4.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_multirnaflow_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_multirnaflow_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_multirnaflow_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(MultiRNAflow)
    library(jsonlite)


    # --- Style Sweave [] ---
    # Key functions: latex, set, reshape2, ggplot2, ggrepel, ggalluvial, factoextra, plot3D
    BiocStyle::latex(use.unsrturl=FALSE)
    library(knitr)
    opts_chunk$set(
    concordance=TRUE
    )
    Cran.pck <- c("reshape2", "ggplot2", "ggrepel", "ggalluvial",
                  "FactoMineR", "factoextra",
                  "plot3D", "plot3Drgl", "ggplotify", "UpSetR", "gprofiler2")
    Bioconductor.pck <- c("SummarizedExperiment", "S4Vectors", "DESeq2",
                          "Mfuzz", "ComplexHeatmap")
    data("RawCounts_Antoszewski2022_MOUSEsub500")
    data("RawCounts_Leong2014_FISSIONsub500wt")
    data("RawCounts_Schleiss2021_CLLsub500")
    data("RawCounts_Weger2021_MOUSEsub500")
    data("RawCounts_Leong2014_FISSIONsub500wt")
    colnames(RawCounts_Leong2014_FISSIONsub500wt)
    data("RawCounts_Leong2014_FISSIONsub500wt")
    # --- Pcaleukemia [] ---
    # Key functions: PCAanalysis, metadata, str, black, red, HCPCanalysis, MFUZZanalysis, hcpc
    SEresPCALeuk500 <- PCAanalysis(SEresNorm=SEresNORMleuk500,
                                   gene.deletion=NULL,
                                   sample.deletion=NULL,
                                   Plot.PCA=FALSE,
                                   Mean.Accross.Time=FALSE,
                                   Color.Group=NULL,
                                   Cex.label=0.9, Cex.point=0.8, epsilon=0.2,
                                   Phi=25, Theta=140,
                                   motion3D=FALSE,
                                   path.result=NULL, Name.folder.pca=NULL)
    ## Save 'Results' of the metadata in an object
    resleuk500 <- S4Vectors::metadata(SEresPCALeuk500)$Results

    ## Save the results of normalization in an object
    resPCALeuk500 <- resleuk500[[1]][[2]]
    ###
    names(S4Vectors::metadata(SEresPCALeuk500))
    str(resleuk500, max.level=3, give.attr=FALSE)
    names(resPCALeuk500)
    print(resPCALeuk500$PCA_2DtemporalLinks)

    # --- Profile Cllcolor [] ---
    # Key functions: black, red, DEanalysisGlobal, Results_DEanalysis_sub500, rowData, metadata, DEplotVolcanoMA, str
    colorLeuk <- data.frame(Name=c("NP", "P"), Col=c("black", "red"))
    SEresDELeuk500 <- DEanalysisGlobal(SEres=SEresEVOleuk500,
                                       pval.min=0.05,
                                       pval.vect.t=NULL,
                                       log.FC.min=1,
                                       LRT.supp.info=FALSE,
                                       Plot.DE.graph=FALSE,
                                       path.result=NULL,
                                       Name.folder.DE=NULL)

    ## data("Results_DEanalysis_sub500")
    DEsummaryLeuk <- SummarizedExperiment::rowData(SEresDELeuk500)
    resDELeuk500 <- S4Vectors::metadata(SEresDELeuk500)$Results[[2]][[2]]
    resGlossaryLeuk <- resDELeuk500$Glossary
    print(resDELeuk500$DEplots_TimePerGroup$Alluvial.graph.Group_P)
    print(resDELeuk500$DEplots_TimePerGroup$NumberDEgenes.acrossTime.perTemporalGroup.Group_P)
    print(resDELeuk500$DEplots_TimePerGroup$NumberDEgenes_UpDownRegulated_perTimeperGroup)
    print(resDELeuk500$DEplots_TimePerGroup$VennBarplot.withNumberUpRegulated.Group_P)
    print(resDELeuk500$DEplots_TimePerGroup$AlluvialGraph_DE.1tmin_perGroup)
    print(resDELeuk500$DEplots_GroupPerTime$NumberSpecificGenes_UpDownRegulated_perBiologicalCondition)

    # --- Heatmapleukemia Res [] ---
    # Key functions: metadata, str, GSEAQuickAnalysis, hsapiens, GSEApreprocessing, DATAprepSE, DATAnormalization, rle
    ## Save 'Results' of the metadata in an object
    resleuk500 <- S4Vectors::metadata(SEresHeatmapLeuk)$Results

    ## Save the results of DEplotHeatmaps in an object
    resHeatmapLeuk <- resleuk500[[2]][[4]]
    ###
    names(S4Vectors::metadata(SEresHeatmapLeuk))
    str(resleuk500, max.level=3, give.attr=FALSE)
    names(resHeatmapLeuk)
    print(resHeatmapLeuk$Heatmap_Correlation)
    print(resHeatmapLeuk$Heatmap_Zscore)
    # --- Volcano Mamus1 [] ---
    # Key functions: DEplotVolcanoMA, DEplotHeatmaps, GSEAQuickAnalysis, metadata, mmusculus, GSEApreprocessing, DATAprepSE, DATAnormalization
    SEresVolcanoMAMus1 <- DEplotVolcanoMA(SEresDE=SEresDEMus1,
                                          NbGene.plotted=2,
                                          SizeLabel=3,
                                          Display.plots=FALSE,
                                          Save.plots=FALSE)
    SEresVolcanoMAMus1 <- DEplotHeatmaps(SEresDE=SEresDEMus1,
                                         ColumnsCriteria=2,#c(2,4),
                                         Set.Operation="union",
                                         NbGene.analysis=20,
                                         SizeLabelRows=5,
                                         SizeLabelCols=5,
                                         Display.plots=FALSE,
                                         Save.plots=FALSE)
    # --- Normalization Mouse2 [] ---
    # Key functions: DATAnormalization, vst, red, blue, orange, darkgreen, PCAanalysis, HCPCanalysis
    SEresNormMus2 <- DATAnormalization(SEres=SEresPrepMus2,
                                       Normalization="vst",
                                       Blind.rlog.vst=FALSE,
                                       Plot.Boxplot=FALSE,
                                       Colored.By.Factors=TRUE,
                                       Color.Group=NULL,
                                       path.result=NULL)
    colMus2 <- data.frame(Name=c("BmKo", "BmWt" ,"CrKo", "CrWt"),
                          Col=c("red", "blue", "orange", "darkgreen"))
    SEresPCAmus2 <- PCAanalysis(SEresNorm=SEresNormMus2,
                                gene.deletion=NULL,
                                sample.deletion=NULL,
                                Plot.PCA=FALSE, motion3D=FALSE,
                                Mean.Accross.Time=FALSE,
                                Color.Group=NULL,
                                Cex.label=0.6, Cex.point=0.7, epsilon=0.2,
                                Phi=25, Theta=140,
                                path.result=NULL,
                                Name.folder.pca=NULL)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_multirnaflow_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_multirnaflow_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_multirnaflow_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MULTIRNAFLOW:", paste0("    multirnaflow: ", packageVersion("MultiRNAflow"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_multirnaflow_results.csv
    touch ${prefix}_multirnaflow_output.rds
    echo "BIOC_MULTIRNAFLOW:" > versions.yml
    echo "    multirnaflow: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MULTIRNAFLOW_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MULTIRNAFLOW(ch_input)

    emit:
    results  = BIOC_MULTIRNAFLOW.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MULTIRNAFLOW.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MULTIRNAFLOW.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MULTIRNAFLOW.out.versions  // channel: path(versions.yml)
}
