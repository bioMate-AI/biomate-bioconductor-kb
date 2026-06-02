#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: CNEr
// Large-scale identification and advanced visualization of sets of conserved noncoding elements.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/CNEr/inst/doc/CNEr.R
// Upstream  : GenomeInfoDb, Gviz, biomaRt, rtracklayer
// Downstream: none
//
// Install: BiocManager::install("CNEr")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CNER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-cner"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-cner:1.42.0--r44_0' :
        'quay.io/biocontainers/bioconductor-cner:1.42.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_cner_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_cner_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_cner_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(CNEr)
    library(BiomartGeneRegionTrack)
    library(CNE)
    library(CNE12)
    library(CNE21)
    library(GenomeAxisTrack)
    library(UcscTrack)
    library(jsonlite)

    # --- Alignment Quality Control [] ---
    # Key functions: matchDistribution, syntenicDotplot
    matchDistribution(axtHg38DanRer10)
    fn_chr4 <- system.file("extdata", "chr4.hg19.galGal3.net.axt.gz", package = "CNEr")
    axt_chr4 <- readAxt(
        fn_chr4, 
        tAssemblyFn = system.file("extdata", package = "BSgenome.Hsapiens.UCSC.hg19"),
        qAssemblyFn = system.file("extdata", package = "BSgenome.Ggallus.UCSC.galGal3")
    )
    syntenicDotplot(axt_chr4, firstChrs = "chr4", secondChrs = "chr4", type = "dot")


    # --- Conserved Non-coding Elements Scanning [] ---
    # Key functions: CNE, ceScan, CNE12, CNE21
    cneDanRer10Hg38 <- CNE(
        assembly1Fn = system.file("extdata", package = "BSgenome.Drerio.UCSC.danRer10"),
        assembly2Fn = system.file("extdata", package = "BSgenome.Hsapiens.UCSC.hg38"),
        axt12Fn = axt_danRer, 
        axt21Fn = axt_hg38,
        cutoffs1 = 8L, 
        cutoffs2 = 4L
    )
    cneList <- ceScan(
        x = cneDanRer10Hg38, 
        tFilter = danRer10Filter,
        qFilter = hg38Filter,
        window = c(50L, 50L, 50L), 
        identity = c(45L, 48L, 49L)
    )
    cne_12_res <- CNE12(cneList[["45_50"]])


    # --- CNE Merging and Database Storage [] ---
    # Key functions: cneMerge, saveCNEToSQLite
    cneMergedList <- lapply(cneList, cneMerge)
    db_path <- tempfile()
    saveCNEToSQLite(
        cneMergedList[[1]], 
        dbName = db_path, 
        tableName = "danRer10_hg38_45_50",
        overwrite = TRUE
    )


    # --- Query and Density Visualization [] ---
    # Key functions: readCNERangesFromSQLite, plotCNEWidth, CNEDensity
    fetchedRanges <- readCNERangesFromSQLite(
        dbName = db_path, 
        tableName = "danRer10_hg38_45_50", 
        chr = "chr6", 
        start = 24000000L, 
        end = 27000000L, 
        whichAssembly = "first",
        minLength = 50L
    )
    cne_density <- CNEDensity(
        dbName = db_path, 
        tableName = "danRer10_hg38_45_50",
        whichAssembly = "first", 
        chr = "chr6", 
        start = 24000000L,
        end = 27000000L, 
        windowSize = 200L, 
        minLength = 50L
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_cner_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_cner_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_cner_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CNER:", paste0("    cner: ", packageVersion("CNEr"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cner_results.csv
    touch ${prefix}_cner_output.rds
    echo "BIOC_CNER:" > versions.yml
    echo "    cner: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CNER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CNER(ch_input)

    emit:
    results  = BIOC_CNER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CNER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CNER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CNER.out.versions  // channel: path(versions.yml)
}
