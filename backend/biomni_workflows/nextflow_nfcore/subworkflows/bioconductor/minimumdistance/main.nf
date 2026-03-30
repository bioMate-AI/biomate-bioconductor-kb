#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: MinimumDistance
// Analysis of de novo copy number variants in trios from high-dimensional genotyping platforms.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/MinimumDistance/inst/doc/MinimumDistance.R
// Upstream  : SummarizedExperiment, VanillaICE, grid, oligoClasses
// Downstream: none
//
// Install: BiocManager::install("MinimumDistance")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MINIMUMDISTANCE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-minimumdistance"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-minimumdistance:1.50.0--r44_0' :
        'quay.io/biocontainers/bioconductor-minimumdistance:1.50.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_minimumdistance_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_minimumdistance_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_minimumdistance_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ArrayViews)
    library(CopyNumScanParams)
    library(DNAcopyParam)
    library(FilterParamMD)
    library(GRanges)
    library(HmmTrellisParam)
    library(IRanges)
    library(MAP2)
    library(MinDistExperiment)
    library(MinDistParam)
    library(jsonlite)

    # --- Registerbackend [] ---
    # Key functions: registerDoSEQ
    library(oligoClasses)
    library(VanillaICE)
    library(SummarizedExperiment)
    library(MinimumDistance)
    foreach::registerDoSEQ()
    # --- Featureannotation [] ---
    # Key functions: fread, path, GRanges, IRanges
    library(data.table)
    extdir <- system.file("extdata", package="VanillaICE")
    features <- suppressWarnings(fread(file.path(extdir, "SNP_info.csv")))
    fgr <- GRanges(paste0("chr", features$Chr), IRanges(features$Position, width=1),
                   isSnp=features[["Intensity Only"]]==0)
    # --- Seqinfo [] ---
    # Key functions: seqlevels, seqinfo
    library(BSgenome.Hsapiens.UCSC.hg18)
    sl <- seqlevels(BSgenome.Hsapiens.UCSC.hg18)
    seqlevels(fgr) <- sl[sl %in% seqlevels(fgr)]
    seqinfo(fgr) <- seqinfo(BSgenome.Hsapiens.UCSC.hg18)[seqlevels(fgr),]
    fgr <- sort(fgr)
    # --- Sourcefiles [] ---
    # Key functions: files
    files <- list.files(extdir, full.names=TRUE, recursive=TRUE, pattern="FinalReport")
    # --- Arrayviews [] ---
    # Key functions: create, ArrayViews, show
    ##
    ## Where to keep parsed files
    ##
    parsedDir <- "ParsedFiles"
    if(!file.exists(parsedDir)) dir.create(parsedDir)
    # --- Fread [] ---
    # Key functions: fread
    ## read the first file
    dat <- fread(files[1], skip="[Data]")
    head(dat,n=3)
    # --- Scan Params [] ---
    # Key functions: CopyNumScanParams
    scan_params <- CopyNumScanParams(index_genome=index_genome,
                                     select=select_columns,
                                     cnvar="Log R Ratio",
                                     bafvar="B Allele Freq",
                                     gtvar=c("Allele1 - AB", "Allele2 - AB"))
    # --- Parsesourcefile [] ---
    # Key functions: parsedPath, parseSourceFile
    parsedPath(views)
    parseSourceFile(views[, 1], scan_params)
    # --- List Parsed Files [] ---
    # Key functions: files, parsedPath
    head(list.files(parsedPath(views)), n=3)
    # --- Views [] ---
    # Key functions: lrr, baf, genotypes
    lrr(views)[1:2, 2:4]
    ## or
    lrr(views[1:2, 2:4])
    ## B allele frequencies
    baf(views[1:2, 2:4])
    # --- Pedigree Hapmap [] ---
    # Key functions: ParentOffspring, parsedPath
    ped_hapmap <- ParentOffspring(id = "hapmap", father="12287_03",
                                  mother="12287_02",
                                  offspring="12287_01",
                                  parsedPath=parsedPath(views))
    # --- Pedigree List [] ---
    # Key functions: ParentOffspringList, ParentOffspring, parsedPath, pedigreeName
    ped_list <- ParentOffspringList(pedigrees=list(
                                      ParentOffspring(id = "hapmap", father="12287_03",
                                                      mother="12287_02",
                                                      offspring="12287_01",
                                                      parsedPath=parsedPath(views)),
    # --- Sample Data [] ---
    # Key functions: csv, path, setNames
    sample_info <- read.csv(file.path(extdir, "sample_data.csv"), stringsAsFactors=FALSE)
    ind_id <- setNames(gsub(" ", "", sample_info$IndividualID), sample_info$File)
    colnames(views) <- ind_id[gsub(".txt", "", colnames(views))]
    # --- Mindistexperiment [] ---
    # Key functions: MinDistExperiment
    me <- MinDistExperiment(views, pedigree=ped_list[[2]])
    colnames(me)
    me
    # --- Param Class [] ---
    # Key functions: MinDistParam, show
    params <- MinDistParam()
    show(params)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_minimumdistance_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_minimumdistance_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_minimumdistance_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MINIMUMDISTANCE:", paste0("    minimumdistance: ", packageVersion("MinimumDistance"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_minimumdistance_results.csv
    touch ${prefix}_minimumdistance_output.rds
    echo "BIOC_MINIMUMDISTANCE:" > versions.yml
    echo "    minimumdistance: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MINIMUMDISTANCE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MINIMUMDISTANCE(ch_input)

    emit:
    results  = BIOC_MINIMUMDISTANCE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MINIMUMDISTANCE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MINIMUMDISTANCE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MINIMUMDISTANCE.out.versions  // channel: path(versions.yml)
}
