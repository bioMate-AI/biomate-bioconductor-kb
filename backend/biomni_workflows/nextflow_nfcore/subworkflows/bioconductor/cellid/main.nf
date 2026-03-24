#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: CelliD
// CelliD is a clustering-free multivariate statistical method for the robust extraction of per-cell ge
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/CelliD/inst/doc/BioconductorVignette.R
// Upstream  : ggpubr, msigdbr, tidyverse
// Downstream: none
//
// Install: BiocManager::install("CelliD")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CELLID {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-cellid"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-cellid:1.14.0--r44_0' :
        'quay.io/biocontainers/bioconductor-cellid:1.14.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_cellid_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_cellid_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_cellid_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(CreateSeuratObject)
    library(DimPlot)
    library(DimPlotMC)
    library(FindVariableFeatures)
    library(GetCellGeneSet)
    library(GetGroupGeneSet)
    library(NormalizeData)
    library(RunCellHGT)
    library(RunMCA)
    library(RunPCA)
    library(jsonlite)

    # --- Create Seurat Object [] ---
    # Key functions: CreateSeuratObject, NormalizeData, ScaleData
    Baron <- CreateSeuratObject(counts = BaronMatrixProt, project = "Baron", min.cells = 5, meta.data = BaronMetaData)
    Seger <- CreateSeuratObject(counts = SegerMatrixProt, project = "Segerstolpe", min.cells = 5, meta.data = SegerMetaData)
    Baron <- NormalizeData(Baron)
    # --- Run M C A [] ---
    # Key functions: RunMCA
    Baron <- RunMCA(Baron)
    # --- Dim Plot M C [] ---
    # Key functions: DimPlotMC
    DimPlotMC(Baron, reduction = "mca", group.by = "cell.type", features = c("CTRL", "INS", "MYZAP", "CDH11"), as.text = TRUE) + ggtitle("MCA with some key gene markers")
    # --- Std Seurat [] ---
    # Key functions: RunPCA, RunUMAP, RunTSNE, DimPlot, ggarrange
    Baron <- RunPCA(Baron, features = rownames(Baron))
    Baron <- RunUMAP(Baron, dims = 1:30)
    Baron <- RunTSNE(Baron, dims = 1:30)
    # --- Read TSV data file [] ---
    # Key functions: read_tsv, group_by, summarise, setNames
    panglao <- read_tsv("https://panglaodb.se/markers/PanglaoDB_markers_27_Mar_2020.tsv.gz")
    panglao_pancreas <- panglao %>% filter(organ == "Pancreas")
    panglao_pancreas <- panglao_pancreas %>%  filter(str_detect(species,"Hs"))
    # --- group_by [] ---
    # Key functions: group_by, summarise, setNames
    panglao_all <- panglao %>%  filter(str_detect(species,"Hs"))
    group_by(`cell type`) %>%
    summarise(geneset = list(`official gene symbol`))
    # --- predictions using pancreas preestablished geneset [] ---
    # Key functions: RunCellHGT, ifelse
    HGT_pancreas_gs <- RunCellHGT(Baron, pathways = pancreas_gs, dims = 1:50, n.features = 200)
    For each cell, assess the signature with the lowest corrected p-value (max -log10 corrected p-value)
    pancreas_gs_prediction <- rownames(HGT_pancreas_gs)[apply(HGT_pancreas_gs, 2, which.max)]
    # --- plottting cell type predictions based on pancreas [] ---
    # Key functions: setNames, DimPlot, scale_color_manual, theme, ggarrange
    color <- c("#F8766D", "#E18A00", "#BE9C00", "#8CAB00", "#24B700", "#00BE70", "#00C1AB", "#00BBDA", "#00ACFC", "#8B93FF", "#D575FE", "#F962DD", "#FF65AC", "grey")
    ggcolor <- setNames(color,c(sort(unique(Baron$cell.type)), "unassigned"))
    OriginalPlot <- DimPlot(Baron, reduction = "tsne", group.by = "cell.type") +
    # --- predictions using all preestablished geneset [] ---
    # Key functions: RunCellHGT, ifelse, setNames, DimPlot, scale_color_manual
    HGT_all_gs <- RunCellHGT(Baron, pathways = all_gs, dims = 1:50)
    all_gs_prediction <- rownames(HGT_all_gs)[apply(HGT_all_gs, 2, which.max)]
    all_gs_prediction_signif <- ifelse(apply(HGT_all_gs, 2, max)>2, yes = all_gs_prediction, "unassigned")
    # --- geneset extraction [] ---
    # Key functions: GetCellGeneSet, GetGroupGeneSet
    Extracting per-cell gene signatures from the Baron dataset with CelliD(c)
    Baron_cell_gs <- GetCellGeneSet(Baron, dims = 1:50, n.features = 200)
    Extracting per-group gene signatures from the Baron dataset with CelliD(g)
    # --- segerstolpe preprocessing [] ---
    # Key functions: NormalizeData, FindVariableFeatures, ScaleData, RunMCA, RunPCA
    Seger <- NormalizeData(Seger)
    Seger <- FindVariableFeatures(Seger)
    Seger <- ScaleData(Seger)
    # --- predictions using extracted geneset cell [] ---
    # Key functions: RunCellHGT, ifelse, setNames, DimPlot, theme
    HGT_baron_cell_gs <- RunCellHGT(Seger, pathways = Baron_cell_gs, dims = 1:50)
    baron_cell_gs_match <- rownames(HGT_baron_cell_gs)[apply(HGT_baron_cell_gs, 2, which.max)]
    baron_cell_gs_prediction_signif <- ifelse(apply(HGT_baron_cell_gs, 2, max)>2, yes = baron_cell_gs_prediction, "unassigned")
    # --- predictions using extracted geneset group [] ---
    # Key functions: RunCellHGT, ifelse, setNames, DimPlot, theme
    HGT_baron_group_gs <- RunCellHGT(Seger, pathways = Baron_group_gs, dims = 1:50)
    baron_group_gs_prediction <- rownames(HGT_baron_group_gs)[apply(HGT_baron_group_gs, 2, which.max)]
    baron_group_gs_prediction_signif <- ifelse(apply(HGT_baron_group_gs, 2, max)>2, yes = baron_group_gs_prediction, "unassigned")
    # --- Functionnal Enrichment [] ---
    # Key functions: msigdbr, group_by, summarise, setNames, RunCellHGT
    library(msigdbr)
    msigdf <- msigdbr::msigdbr(species = "Homo sapiens")
    msigdf_filtered <- msigdf %>% select(gs_cat, gs_subcat, gs_name, gene_symbol, gs_description) %>%

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_cellid_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_cellid_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_cellid_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CELLID:", paste0("    cellid: ", packageVersion("CelliD"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cellid_results.csv
    touch ${prefix}_cellid_output.rds
    echo "BIOC_CELLID:" > versions.yml
    echo "    cellid: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CELLID_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CELLID(ch_input)

    emit:
    results  = BIOC_CELLID.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CELLID.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CELLID.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CELLID.out.versions  // channel: path(versions.yml)
}
