#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ChIPXpress — rank_targets_prebuilt_db
// Rank predicted TF bound genes using a pre-built gene expression database from the ChIPXpressData package.
// Input: Oct4ESC_ChIPgenes, DB_GPL1261.bigmemory.desc
// Container: quay.io/biocontainers/bioconductor-chipxpress:1.42.0--r42hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: ChIPXpress, ChIPXpressData, bigmemory
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the ChIPXpress and ChIPXpressData packages
//  * 2. [Core Analysis] Attach the pre-built big.matrix database using attach.big.matrix
//  * 3. [Core Analysis] Run ChIPXpress with the TF Entrez ID, the ranked ChIP target Entrez IDs, and the attached database
//  * 4. [Visualization & Output] Map the ranked output back to gene symbols using the original annotation data

nextflow.enable.dsl = 2

process BIOC_CHIPXPRESS_RANK_TARGETS_PREBUILT_DB {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

    input:
    tuple val(meta), path(input_files, stageAs: '?/*')

    output:
    tuple val(meta), path("*.csv"), emit: tables, optional: true
    tuple val(meta), path("*.pdf"), emit: plots,  optional: true
    tuple val(meta), path("*.rds"), emit: objects, optional: true
    path "versions.yml",            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
    
    # Load required libraries
    library(ChIPXpress)
    library(ChIPXpressData)
    library(bigmemory)
    
    # 1. Read the user input files from the working directory
    # Read Oct4ESC_ChIPgenes dataframe robustly (handling CSV, RDS, or extensionless files)
    if (file.exists("Oct4ESC_ChIPgenes.csv")) {
      Oct4ESC_ChIPgenes <- read.csv("Oct4ESC_ChIPgenes.csv", stringsAsFactors = FALSE)
    } else if (file.exists("Oct4ESC_ChIPgenes.rds")) {
      Oct4ESC_ChIPgenes <- readRDS("Oct4ESC_ChIPgenes.rds")
    } else if (file.exists("Oct4ESC_ChIPgenes")) {
      Oct4ESC_ChIPgenes <- tryCatch(
        readRDS("Oct4ESC_ChIPgenes"),
        error = function(e) read.csv("Oct4ESC_ChIPgenes", stringsAsFactors = FALSE)
      )
    } else {
      stop("Required input file 'Oct4ESC_ChIPgenes' (CSV or RDS) not found in the working directory.")
    }
    
    # Verify the descriptor file exists in the working directory
    if (!file.exists("DB_GPL1261.bigmemory.desc")) {
      stop("Required descriptor file 'DB_GPL1261.bigmemory.desc' not found in the working directory.")
    }
    
    # 2. Attach the pre-built big.matrix database
    path <- "."
    DB_GPL1261 <- attach.big.matrix("DB_GPL1261.bigmemory.desc", path=path)
    
    # 3. Run ChIPXpress with the TF Entrez ID, ranked ChIP target Entrez IDs, and the database
    Output <- ChIPXpress(TFID="18999",ChIP=Oct4ESC_ChIPgenes\$EntrezID,DB=DB_GPL1261)
    
    # 4. Map the ranked output back to gene symbols using the original annotation data
    GeneNames <- Oct4ESC_ChIPgenes\$Annotation[match(names(Output[[1]]),
                                              Oct4ESC_ChIPgenes\$EntrezID)]
    Result <- data.frame(1:length(Output[[1]]),GeneNames,names(Output[[1]]),Output[[1]])
    colnames(Result) <- c("Rank","GeneNames","EntrezID","ChIPXpressScore")
    
    # 5. Write output files
    # Save the final ranked target genes table
    write.csv(Result, "ChIPXpress_Ranked_Targets.csv", row.names = FALSE)
    
    # Save the raw Output list object
    saveRDS(Output, "ChIPXpress_Output.rds")
    
    # Generate a diagnostic plot of the ChIPXpress scores
    pdf("ChIPXpress_Scores_Distribution.pdf", width = 7, height = 5)
    hist(Result\$ChIPXpressScore, 
         main = "Distribution of ChIPXpress Scores", 
         xlab = "ChIPXpress Score", 
         col = "skyblue", 
         border = "white",
         breaks = 30)
    dev.off()

    writeLines(c(
        '"BIOC_CHIPXPRESS_RANK_TARGETS_PREBUILT_DB":',
        paste0('    ChIPXpress: ', as.character(packageVersion('ChIPXpress')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rank_targets_prebuilt_db.csv versions.yml
    """
}

workflow BIOC_CHIPXPRESS_RANK_TARGETS_PREBUILT_DB_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ Oct4ESC_ChIPgenes, DB_GPL1261.bigmemory.desc ] ]

    main:
    BIOC_CHIPXPRESS_RANK_TARGETS_PREBUILT_DB(ch_input)

    emit:
    tables   = BIOC_CHIPXPRESS_RANK_TARGETS_PREBUILT_DB.out.tables
    plots    = BIOC_CHIPXPRESS_RANK_TARGETS_PREBUILT_DB.out.plots
    objects  = BIOC_CHIPXPRESS_RANK_TARGETS_PREBUILT_DB.out.objects
    versions = BIOC_CHIPXPRESS_RANK_TARGETS_PREBUILT_DB.out.versions
}
