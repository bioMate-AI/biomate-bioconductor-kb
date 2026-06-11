#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: CNORfeeder — static_boolean_integration
// Infer a data-driven network, integrate it with a compressed prior knowledge network, weight the integrated links (optionally using a PPI network), and train the
// Input: CNOlistDREAM, DreamModel, PPINigraph, UniprotIDdream
// Container: quay.io/biocontainers/bioconductor-cnorfeeder:1.50.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: CNORfeeder, CellNOptR
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Infer data-driven network (DDN) using makeBTables
//  * 2. [Core Analysis] Rank links using linksRanking
//  * 3. [Core Analysis] Preprocess and compress the PKN using preprocessing
//  * 4. [Core Analysis] Map and integrate the DDN to the compressed model using mapBTables2model
//  * 5. [Core Analysis] Weight the integrated links using weighting
//  * 6. [Core Analysis] Train the weighted model using gaBinaryT1W
//  * 7. [Visualization & Output] Plot the optimized model and fit using plotModel and cutAndPlotResultsT1

nextflow.enable.dsl = 2

process BIOC_CNORFEEDER_STATIC_BOOLEAN_INTEGRATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-proteomics:3.20"

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
        library(CellNOptR)
        library(CNORfeeder)
        
        # Helper function to read RDS files from the working directory
        read_input <- function(name, optional = FALSE) {
          if (file.exists(name)) {
            return(readRDS(name))
          } else if (file.exists(paste0(name, ".rds"))) {
            return(readRDS(paste0(name, ".rds")))
          } else {
            if (optional) {
              return(NULL)
            } else {
              stop(paste("Error: Required input file", name, "not found in the working directory."))
            }
          }
        }
        
        # 1. Load User Inputs
        CNOlistDREAM <- read_input("CNOlistDREAM")
        DreamModel <- read_input("DreamModel")
        PPINigraph <- read_input("PPINigraph", optional = TRUE)
        UniprotIDdream <- read_input("UniprotIDdream", optional = TRUE)
        
        # 2. Infer data-driven network (DDN) using makeBTables
        BTable <- makeBTables(CNOlist=CNOlistDREAM, k=2, measErr=c(0.1, 0))
        
        # 3. Rank links using linksRanking
        Lrank <- linksRanking(CNOlist=CNOlistDREAM, measErr=c(0.1, 0), savefile=FALSE)
        for (i in seq_along(Lrank)) {
          suffix <- if (!is.null(names(Lrank)) && names(Lrank)[i] != "") names(Lrank)[i] else i
          write.csv(as.data.frame(Lrank[[i]]), paste0("links_ranking_", suffix, ".csv"), row.names = FALSE)
        }
        
        # 4. Preprocess and compress the PKN using preprocessing
        model <- preprocessing(data=CNOlistDREAM, model=DreamModel)
        
        # 5. Map and integrate the DDN to the compressed model using mapBTables2model
        modelIntegr <- mapBTables2model(BTable=BTable, model=model, allInter=TRUE)
        
        # Output integrated links
        integrated_links <- modelIntegr\$reacID[modelIntegr\$indexIntegr]
        writeLines(as.character(integrated_links), "integrated_links.txt")
        
        # Plot integrated model
        pdf("model_integrated.pdf")
        plotModel(model=modelIntegr, CNOlist=CNOlistDREAM, indexIntegr=modelIntegr\$indexIntegr)
        dev.off()
        
        # 6. Weight the integrated links using weighting
        # First call (without PPI)
        modelIntegrWeight <- weighting(modelIntegr=modelIntegr, PKNmodel=DreamModel, CNOlist=CNOlistDREAM, integrFac=10)
        
        # Second call (with PPI, if optional files are provided)
        if (!is.null(PPINigraph) && !is.null(UniprotIDdream)) {
          modelIntegrWeight <- weighting(modelIntegr=modelIntegr, PKNmodel=DreamModel, CNOlist=CNOlistDREAM, integrFac=10, UniprotID=UniprotIDdream, PPI=PPINigraph)
        }
        
        saveRDS(modelIntegrWeight, "modelIntegrWeight.rds")
        
        # 7. Train the weighted model using gaBinaryT1W
        DreamT1opt <- gaBinaryT1W(CNOlist=CNOlistDREAM, model=modelIntegrWeight, maxGens=2, popSize=5, verbose=FALSE)
        saveRDS(DreamT1opt, "DreamT1opt.rds")
        
        # 8. Plot the optimized model and fit using plotModel and cutAndPlotResultsT1
        pdf("model_optimized.pdf")
        plotModel(model=modelIntegrWeight, CNOlist=CNOlistDREAM, bString=DreamT1opt\$bString)
        dev.off()
        
        pdf("results_fit.pdf")
        cutAndPlotResultsT1(model=modelIntegrWeight, CNOlist=CNOlistDREAM, bString=DreamT1opt\$bString)
        dev.off()
        
        message("Pipeline completed successfully. Outputs written to working directory.")

    writeLines(c(
        '"BIOC_CNORFEEDER_STATIC_BOOLEAN_INTEGRATION":',
        paste0('    CNORfeeder: ', as.character(packageVersion('CNORfeeder')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_static_boolean_integration.csv versions.yml
    """
}

workflow BIOC_CNORFEEDER_STATIC_BOOLEAN_INTEGRATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ CNOlistDREAM, DreamModel, PPINigraph, UniprotIDdream ] ]

    main:
    BIOC_CNORFEEDER_STATIC_BOOLEAN_INTEGRATION(ch_input)

    emit:
    tables   = BIOC_CNORFEEDER_STATIC_BOOLEAN_INTEGRATION.out.tables
    plots    = BIOC_CNORFEEDER_STATIC_BOOLEAN_INTEGRATION.out.plots
    objects  = BIOC_CNORFEEDER_STATIC_BOOLEAN_INTEGRATION.out.objects
    versions = BIOC_CNORFEEDER_STATIC_BOOLEAN_INTEGRATION.out.versions
}
