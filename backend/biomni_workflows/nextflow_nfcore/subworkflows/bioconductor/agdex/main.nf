#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: AGDEX — cross_species_differential_expression_agreement
// Evaluate the agreement of differential expression profiles across two experiments (e.g., human and mouse) at both the genome-wide and gene-set levels.
// Input: human.data, mouse.data, gset.data, map.data
// Container: quay.io/biocontainers/bioconductor-agdex:1.58.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: AGDEX, Biobase, GSEABase
// Visualizations: scatter plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Create dex.set objects for each experiment using make.dex.set.object
//  * 2. [Core Analysis] Run the AGDEX analysis using agdex
//  * 3. [Visualization & Output] Visualize results using agdex.scatterplot
//  * 4. [Core Analysis] Extract gene-set details using get.gset.result.details

nextflow.enable.dsl = 2

process BIOC_AGDEX_CROSS_SPECIES_DIFFERENTIAL_EXPRESSION_AGREEMENT {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim"

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
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("AGDEX", "Biobase", "GSEABase")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))  # CRAN binaries (Posit PPM)
      .bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressWarnings(suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=.bin), error=function(e) try(install.packages(.bm_miss), silent=TRUE))))
    }
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
        
    # Load required libraries
    library(AGDEX)
    library(Biobase)
    library(GSEABase)
    
    # Robust helper function to read input files (handles RDS or RData/rda formats)
    read_input <- function(file_path) {
      if (!file.exists(file_path)) {
        stop(paste("Required input file does not exist in the working directory:", file_path))
      }
      
      # Try reading as RDS first
      obj <- tryCatch(readRDS(file_path), error = function(e) NULL)
      if (!is.null(obj)) return(obj)
      
      # If not RDS, try loading as RData
      env <- new.env()
      tryCatch({
        load(file_path, envir = env)
        vars <- names(env)
        if (length(vars) == 1) {
          return(env[[vars]])
        } else if (length(vars) > 1) {
          return(as.list(env))
        }
      }, error = function(e) {
        stop(paste("Failed to read file:", file_path, "as RDS or RData."))
      })
    }
    
    # 1. Read User Inputs
    human.data <- read_input("human.data")
    mouse.data <- read_input("mouse.data")
    gset.data  <- read_input("gset.data")
    map.data   <- read_input("map.data")
    
    # Dynamically determine contrast definitions from the second column of phenotype data
    human.groups <- unique(as.character(pData(human.data)[, 2]))
    human.comp.def <- paste(human.groups[1], human.groups[2], sep="-")
    
    mouse.groups <- unique(as.character(pData(mouse.data)[, 2]))
    mouse.comp.def <- paste(mouse.groups[1], mouse.groups[2], sep="-")
    
    # 2. Create dex.set objects for each experiment
    dex.set.human <- make.dex.set.object(Eset.data= human.data,                            
                                         comp.var=2,                                       
                                         comp.def=human.comp.def,  
                                         gset.collection=gset.data)                        
    dex.set.mouse <- make.dex.set.object(mouse.data,
                                         comp.var=2,
                                         comp.def=mouse.comp.def,
                                         gset.collection=NULL)                                      
    
    # 3. Run the AGDEX analysis
    agdex.res<-agdex(dex.setA=dex.set.human,
                     dex.setB=dex.set.mouse,
                     map.data=map.data,
                     min.nperms=5,
                     max.nperms=10)
    
    # 4. Visualize results and save to PDF
    pdf("agdex_scatterplot.pdf", width=7, height=7)
    agdex.scatterplot(agdex.res, gset.id=NULL)
    dev.off()
    
    # 5. Extract gene-set details
    gset.res.stats<-get.gset.result.details(agdex.res, gset.ids = NULL, alpha=0.01)
    
    # Dynamically select the first gene set ID from the provided GeneSetCollection
    target_gset_id <- names(gset.data)[1]
    target.gset.res<-get.gset.result.details(agdex.res, gset.ids=target_gset_id)
    
    # 6. Save meaningful results to output files
    saveRDS(agdex.res, "agdex_results.rds")
    saveRDS(gset.res.stats, "gset_res_stats.rds")
    saveRDS(target.gset.res, "target_gset_res.rds")
    
    # Export key result tables to CSV
    if (!is.null(agdex.res\$gwide.agdex.result)) {
      write.csv(agdex.res\$gwide.agdex.result, "gwide_agdex_result.csv", row.names=TRUE)
    } else if (!is.null(agdex.res\$gwide.agdex.res)) {
      write.csv(agdex.res\$gwide.agdex.res, "gwide_agdex_result.csv", row.names=TRUE)
    }
    
    if (!is.null(agdex.res\$gset.res)) {
      write.csv(agdex.res\$gset.res, "gset_result.csv", row.names=FALSE)
    } else if (!is.null(agdex.res\$gset.result)) {
      write.csv(agdex.res\$gset.result, "gset_result.csv", row.names=FALSE)
    }
    
    if (!is.null(agdex.res\$meta.dex.res)) {
      write.csv(agdex.res\$meta.dex.res, "meta_dex_res.csv", row.names=FALSE)
    }
    
    # Export detailed gene-set statistics to CSV
    if (!is.null(gset.res.stats\$enrichA.details)) {
      write.csv(gset.res.stats\$enrichA.details, "gset_res_stats_enrichA_details.csv", row.names=FALSE)
    }
    if (!is.null(gset.res.stats\$enrichB.details)) {
      write.csv(gset.res.stats\$enrichB.details, "gset_res_stats_enrichB_details.csv", row.names=FALSE)
    }
    if (!is.null(gset.res.stats\$agdex.details)) {
      write.csv(gset.res.stats\$agdex.details, "gset_res_stats_agdex_details.csv", row.names=FALSE)
    }
    
    if (!is.null(target.gset.res\$agdex.details)) {
      write.csv(target.gset.res\$agdex.details, "target_gset_agdex_details.csv", row.names=FALSE)
    }
    
    cat("AGDEX pipeline completed successfully. Outputs saved to working directory.\n")

    writeLines(c(
        '"BIOC_AGDEX_CROSS_SPECIES_DIFFERENTIAL_EXPRESSION_AGREEMENT":',
        paste0('    AGDEX: ', as.character(packageVersion('AGDEX')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cross_species_differential_expression_agreement.csv versions.yml
    """
}

workflow BIOC_AGDEX_CROSS_SPECIES_DIFFERENTIAL_EXPRESSION_AGREEMENT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ human.data, mouse.data, gset.data, map.data ] ]

    main:
    BIOC_AGDEX_CROSS_SPECIES_DIFFERENTIAL_EXPRESSION_AGREEMENT(ch_input)

    emit:
    tables   = BIOC_AGDEX_CROSS_SPECIES_DIFFERENTIAL_EXPRESSION_AGREEMENT.out.tables
    plots    = BIOC_AGDEX_CROSS_SPECIES_DIFFERENTIAL_EXPRESSION_AGREEMENT.out.plots
    objects  = BIOC_AGDEX_CROSS_SPECIES_DIFFERENTIAL_EXPRESSION_AGREEMENT.out.objects
    versions = BIOC_AGDEX_CROSS_SPECIES_DIFFERENTIAL_EXPRESSION_AGREEMENT.out.versions
}
