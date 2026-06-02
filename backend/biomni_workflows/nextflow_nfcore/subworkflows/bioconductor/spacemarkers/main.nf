#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: SpaceMarkers
// Spatial transcriptomic technologies have helped to resolve the connection between gene expression an
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/SpaceMarkers/inst/doc/SpaceMarkers_vignette.R
// Upstream  : Matrix, RColorBrewer, cowplot, dplyr, ggplot2
// Downstream: none
//
// Install: BiocManager::install("SpaceMarkers")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SPACEMARKERS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-spacemarkers"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-spacemarkers:1.2.1--r44_0' :
        'quay.io/biocontainers/bioconductor-spacemarkers:1.2.1--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_spacemarkers_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_spacemarkers_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_spacemarkers_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(SpaceMarkers)
    library(jsonlite)

    # --- set [] ---
    # Key functions: set
    --------------------------------------
    knitr::opts_knit$set(
        collapse = TRUE,
        comment = "#>",
        fig.align   = 'center'
    # --- Unlink [] ---
    # Key functions: unlink, files
    ---------------------------------------------------------------------
    unlink(basename(sp_url))
    files <- list.files(".")[grepl(counts_file,list.files("."))]
    unlink(files)
    unlink("spatial", recursive = TRUE)
    # --- Readrds [] ---
    # Key functions: intersect, slot
    ---------------------------------------------------------------------
    cogaps_result <- readRDS(system.file("extdata","CoGAPS_result.rds",
        package="SpaceMarkers",mustWork = TRUE))
    features <- intersect(rownames(counts_matrix),rownames(
        slot(cogaps_result,"featureLoadings")))
    # --- Data [] ---
    # Key functions: data
    ---------------------------------------------------------------------
    data("curated_genes")
    spPatterns<-spPatterns[c("barcode","y","x","Pattern_1","Pattern_5")]
    counts_matrix <- counts_matrix[curated_genes,]
    cogaps_matrix <- cogaps_matrix[curated_genes, ]
    # --- Getinteractinggenes [] ---
    # Key functions: getInteractingGenes
    ---------------------------------------------------------------------
    SpaceMarkers <- getInteractingGenes(data = counts_matrix,
                                        reconstruction = cogaps_matrix,
                                        optParams = optParams,
                                        spPatterns = spPatterns,
    # --- Function [] ---
    # Key functions: frame
    ---------------------------------------------------------------------
    compare_genes <- function(ref_list, list2,ref_name = "mode1",
                                list2_name = "mode2", sub_slice = NULL){
        ref_rank <- seq(1,length(ref_list),1)
        list2_ref_rank <- which(list2 %in% ref_list)
    # --- Compare Genes [] ---
    # Key functions: compare_genes
    ---------------------------------------------------------------------
    res_to_DE <- compare_genes(head(residual_p1_p5$Gene, n = 20),DE_p1_p5$Gene,
                                ref_name="residual",list2_name="DE")
    DE_to_res <- compare_genes(head(DE_p1_p5$Gene, n = 20),residual_p1_p5$Gene,
                                ref_name = "DE",list2_name = "residual")
    # --- Getinteractinggenes [] ---
    # Key functions: getInteractingGenes
    ---------------------------------------------------------------------
    SpaceMarkers_enrich <- getInteractingGenes(data = counts_matrix,
                                        reconstruction = cogaps_matrix,
                                        optParams = optParams,
                                        spPatterns = spPatterns,
    # --- Compare Genes [] ---
    # Key functions: compare_genes
    ---------------------------------------------------------------------
    enrich_res_to_de<-compare_genes(
        head(DE_p1_p5_enrichment, 20),
        residual_p1_p5_enrichment,
        ref_name="DE_Enrich",list2_name = "res_Enrich")
    # --- Function [] ---
    # Key functions: ggproto, ggproto_parent, setup_data, viewport, editGrob, ggname
    ---------------------------------------------------------------------
    geom_spatial <-  function(mapping = NULL,
        data = NULL,
        stat = "identity",
        position = "identity",
    # --- List [] ---
    # Key functions: csv, factor
    ---------------------------------------------------------------------
    bcs <- list()
    for (i in 1:length(sample_names)) {
        bcs[[i]] <- read.csv(tissue_paths[i],col.names=c(
            "barcode","tissue","row","col","imagerow","imagecol"), header = FALSE)
    # --- List [] ---
    # Key functions: frame, rowSums
    ---------------------------------------------------------------------
    matrix <- list()
    for (i in 1:length(sample_names)) {
        matrix[[i]] <- as.data.frame(t(as.matrix(counts_matrix)))
    }
    # --- Function [] ---
    # Key functions: colorRampPalette
    ---------------------------------------------------------------------
    myPalette <- function(numLevels) {
        return(colorRampPalette(c("blue","yellow"))(numLevels))}
    # --- Ifelse [] ---
    # Key functions: ifelse, na, factor, frame
    ---------------------------------------------------------------------
    region <- SpaceMarkers$hotspots[,1]
    region <- ifelse(!is.na(region)&!is.na(SpaceMarkers$hotspots[,2]),
                        "Interacting",ifelse(!is.na(region),region,
                                                SpaceMarkers$hotspots[,2]))
    # --- Head [] ---
    # Key functions: filter
    ---------------------------------------------------------------------
    head(residual_p1_p5 %>% dplyr::filter(
        sp_genes$`Pattern_1 x Pattern_5` == "vsBoth"),n_genes)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_spacemarkers_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_spacemarkers_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_spacemarkers_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SPACEMARKERS:", paste0("    spacemarkers: ", packageVersion("SpaceMarkers"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_spacemarkers_results.csv
    touch ${prefix}_spacemarkers_output.rds
    echo "BIOC_SPACEMARKERS:" > versions.yml
    echo "    spacemarkers: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SPACEMARKERS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SPACEMARKERS(ch_input)

    emit:
    results  = BIOC_SPACEMARKERS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SPACEMARKERS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SPACEMARKERS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SPACEMARKERS.out.versions  // channel: path(versions.yml)
}
