#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: Moonlight2R
// The understanding of cancer mechanism requires the identification of genes playing a role in the dev
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/Moonlight2R/inst/doc/Moonlight2R.R
// Upstream  : dplyr, magrittr
// Downstream: none
//
// Install: BiocManager::install("Moonlight2R")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MOONLIGHT2R {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-moonlight2r"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-moonlight2r:1.4.0--r44_0' :
        'quay.io/biocontainers/bioconductor-moonlight2r:1.4.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_moonlight2r_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_moonlight2r_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_moonlight2r_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(Moonlight2R)
    library(jsonlite)


    # --- Eval = True [] ---
    # Key functions: getDataGEO
    data(DEGsmatrix)
    data(dataFilt)
    data(dataMAF)
    data(GEO_TCGAtab)
    data(LOC_transcription)
    data(LOC_translation)
    data(LOC_protein)
    data(Oncogenic_mediators_mutation_summary)
    data(DEG_Mutations_Annotations)
    data(dataMethyl)
    knitr::kable(GEO_TCGAtab, digits = 2,
           caption = "Table with GEO data set matched to one
           of the 18 given TCGA cancer types ",
           row.names = TRUE)
    dataFilt_GEO <- getDataGEO(GEOobject = "GSE20347", platform = "GPL571")

    # --- Eval = True [] ---
    # Key functions: getDataGEO, FEA, plotFEA
    dataFilt_GEO <- getDataGEO(TCGAtumor = "ESCA")
    data(DEGsmatrix)
    data(DiseaseList)
    data(EAGenes)
    dataFEA <- FEA(DEGsmatrix = DEGsmatrix)
    plotFEA(dataFEA = dataFEA, additionalFilename = "_exampleVignette", height = 10, width = 20)

    # --- Eval = True [] ---
    # Key functions: GRN, sample, FEA, URA, PRA, apoptosis
    data(DEGsmatrix)
    data(dataFilt)
    dataGRN <- GRN(DEGsmatrix = DEGsmatrix, TFs = sample(rownames(DEGsmatrix), 100), normCounts = dataFilt,
    	               nGenesPerm = 5, kNearest = 3, nBoot = 5, DiffGenes = TRUE)
    data(dataGRN)
    data(DEGsmatrix)
    data(DiseaseList)
    data(EAGenes)

    dataFEA <- FEA(DEGsmatrix = DEGsmatrix)

    BPselected <- dataFEA$Diseases.or.Functions.Annotation[1:5]
    # --- Eval = True [] ---
    # Key functions: GMA, dataMethyl, dataFilt, dataPRA, LUAD_sample_anno, GLS, plotNetworkHive
    data("dataMethyl")
    data("dataFilt")
    data("dataPRA")
    data("DEGsmatrix")
    data("LUAD_sample_anno")
    data("NCG")
    data("EncodePromoters")
    data("MetEvidenceDriver")

    # Subset column names (sample names) in expression data to patient level
    genes_query <- "BRCA1"
    dataGLS <- GLS(genes = genes_query, 
    	       query_string = "AND cancer AND driver",
    	       max_records = 20)
    head(dataGLS)

    ## -----------------------------------------------------------------------------
    knitr::kable(LOC_transcription)

    ## -----------------------------------------------------------------------------

    # --- Eval = True [] ---
    # Key functions: plotDMA, plotMoonlight, drivers, plotGMA, DEG_Methylation_Annotations, Oncogenic_mediators_methylation_summary, genelist
    data(dataDMA)
    data(DEG_Mutations_Annotations)
    data(Oncogenic_mediators_mutation_summary)
    plotDMA(DEG_Mutations_Annotations, 
            Oncogenic_mediators_mutation_summary, 
            type = 'complete', additionalFilename = "")
    data(DEG_Mutations_Annotations)
    data(Oncogenic_mediators_mutation_summary)
    data(dataURA_plot)
    plotMoonlight(DEG_Mutations_Annotations,
            Oncogenic_mediators_mutation_summary, 
            dataURA_plot, gene_type = "drivers", n = 50)
    data("DEG_Methylation_Annotations")
    data("Oncogenic_mediators_methylation_summary")
    genes <- c("ACAN", "ACE2", "ADAM19", "AFAP1L1")
    plotGMA(DEG_Methylation_Annotations = DEG_Methylation_Annotations,
            Oncogenic_mediators_methylation_summary = Oncogenic_mediators_methylation_summary,
            type = "genelist", genelist = genes,
            additionalFilename = "./GMAresults/")

    # --- Eval = True [] ---
    # Key functions: plotMoonlightMet, DEG_Methylation_Annotations, Oncogenic_mediators_methylation_summary, dataURA_plot, plotMetExp, EpiMix_Results_Regular, dataMethyl, dataFilt
    data("DEG_Methylation_Annotations")
    data("Oncogenic_mediators_methylation_summary")
    data("dataURA_plot")
    genes <- c("ACAN", "ACE2", "ADAM19", "AFAP1L1")
    plotMoonlightMet(DEG_Methylation_Annotations = DEG_Methylation_Annotations,
                     Oncogenic_mediators_methylation_summary = Oncogenic_mediators_methylation_summary,
                     dataURA = dataURA_plot,
                     genes = genes,
                     additionalFilename = "./GMAresults/")
    data("EpiMix_Results_Regular")
    data("dataMethyl")
    data("dataFilt")

    # Subset column names (sample names) in expression data to patient level
    pattern <- "^(.{4}-.{2}-.{4}-.{2}).*"
    colnames(dataFilt) <- sub(pattern, "\\1", colnames(dataFilt))


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_moonlight2r_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_moonlight2r_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_moonlight2r_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MOONLIGHT2R:", paste0("    moonlight2r: ", packageVersion("Moonlight2R"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_moonlight2r_results.csv
    touch ${prefix}_moonlight2r_output.rds
    echo "BIOC_MOONLIGHT2R:" > versions.yml
    echo "    moonlight2r: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MOONLIGHT2R_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MOONLIGHT2R(ch_input)

    emit:
    results  = BIOC_MOONLIGHT2R.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MOONLIGHT2R.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MOONLIGHT2R.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MOONLIGHT2R.out.versions  // channel: path(versions.yml)
}
