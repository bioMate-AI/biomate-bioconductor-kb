#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: RedeR — nested_subgraphs
// Extract differentially expressed genes from multiple time points, map expression values to node colors, nest them into hierarchical containers, and visualize ov
// Input: ER.limma, hs.inter
// Container: quay.io/biocontainers/bioconductor-reder:3.6.0--r45hdfd78af_0
// R packages: igraph, RedeR, TreeAndLeaf
// Bioconductor: 3.20 | R: 4.4
// Requires: RedeR, igraph
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Initialize the RedeR application and reset the port
//  * 2. [Core Analysis] Extract subgraphs for each time-point contrast using subg
//  * 3. [Core Analysis] Map gene symbols to node labels and logFC values to node colors using att.setv
//  * 4. [Core Analysis] Set container labels on the subgraphs
//  * 5. [Core Analysis] Send the subgraphs to RedeR as nested containers using addGraphToRedeR
//  * 6. [Core Analysis] Nest overlapping nodes into sub-containers using nestNodes
//  * 7. [Core Analysis] Assign edges to containers using mergeOutEdges
//  * 8. [Core Analysis] Run the interactive layout using relaxRedeR
//  * 9. [Core Analysis] Add a color legend using addLegendToRedeR
//  * 10. [Core Analysis] Select and highlight specific nodes using selectNodes

nextflow.enable.dsl = 2

process BIOC_REDER_NESTED_SUBGRAPHS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20-slim"

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
    .bm_deps <- c("igraph", "RedeR", "TreeAndLeaf")
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
        
        # Load required packages
        library("RedeR")
        library("igraph")
        
        # Helper function to load input files robustly from the working directory
        load_input <- function(filename) {
          if (file.exists(filename)) {
            # Try reading as RDS
            obj <- tryCatch(readRDS(filename), error = function(e) NULL)
            if (!is.null(obj)) return(obj)
            
            # Try loading as RData
            env <- new.env()
            tryCatch(load(filename, envir = env), error = function(e) NULL)
            if (length(env) > 0) return(env[[names(env)[1]]])
            
            # Try reading as CSV
            tryCatch({
              return(read.csv(filename, stringsAsFactors = FALSE))
            }, error = function(e) NULL)
          }
          
          # Try with common extensions
          for (ext in c(".rds", ".RData", ".rda", ".csv", ".tsv")) {
            fn <- paste0(filename, ext)
            if (file.exists(fn)) {
              if (ext == ".rds") {
                return(readRDS(fn))
              } else if (ext %in% c(".RData", ".rda")) {
                env <- new.env()
                load(fn, envir = env)
                return(env[[names(env)[1]]])
              } else if (ext %in% c(".csv", ".tsv")) {
                return(read.csv(fn, stringsAsFactors = FALSE))
              }
            }
          }
          stop(paste("Required input file", filename, "not found in the working directory."))
        }
        
        # Read user input files
        ER.limma <- load_input("ER.limma")
        hs.inter <- load_input("hs.inter")
        
        # Extract subgraphs and set attributes for 3h time point
        deg.t3 <- ER.limma[ER.limma\$degenes.t3!=0,]
        gt3 <- subg(g=hs.inter, dat=deg.t3, refcol=1)
        gt3 <- att.setv(g=gt3, from="Symbol", to="nodeLabel")
        gt3 <- att.setv(g=gt3, from="logFC.t3", to="nodeColor", 
          breaks=seq(-2,2,0.4), pal=2)
        
        # Extract subgraphs and set attributes for 6h time point
        deg.t6 <- ER.limma[ER.limma\$degenes.t6!=0,]
        gt6 <- subg(g=hs.inter, dat=deg.t6, refcol=1)
        gt6 <- att.setv(g=gt6, from="Symbol", to="nodeLabel")
        gt6 <- att.setv(g=gt6, from="logFC.t6", to="nodeColor",
          breaks=seq(-2,2,0.4), pal=2)
        
        # Extract subgraphs and set attributes for 12h time point
        deg.t12 <- ER.limma[ER.limma\$degenes.t12!=0,]
        gt12 <- subg(g=hs.inter, dat=deg.t12, refcol=1)
        gt12 <- att.setv(g=gt12, from="Symbol", to="nodeLabel")
        gt12 <- att.setv(g=gt12, from="logFC.t12", to="nodeColor", 
          breaks=seq(-2,2,0.4), pal=2)
        
        # Customize subgraph names
        gt3\$nestLabel <- "3h"
        gt6\$nestLabel <- "6h"
        gt12\$nestLabel <- "12h"
        
        # Write processed subgraphs and extracted DE genes to output files
        write.csv(deg.t3, "deg_t3.csv", row.names = FALSE)
        write.csv(deg.t6, "deg_t6.csv", row.names = FALSE)
        write.csv(deg.t12, "deg_t12.csv", row.names = FALSE)
        
        saveRDS(gt3, "gt3_processed.rds")
        saveRDS(gt6, "gt6_processed.rds")
        saveRDS(gt12, "gt12_processed.rds")
        
        # Run interactive RedeR visualization steps inside a try-catch block
        # to ensure robustness in headless or non-interactive environments.
        tryCatch({
          # Initialize the RedeR application
          startRedeR()
          
          # Reset the RedeR application
          resetRedeR()
        
          # Send nested subgraphs to the RedeR application
          N1 <- addGraphToRedeR(gt3, gcoord=c(10,25), gscale=20, 
            isNested=TRUE, theme='th1', zoom=30)
          N2 <- addGraphToRedeR(gt6, gcoord=c(20,70), gscale=50, 
            isNested=TRUE, theme='th1', zoom=30)
          N3 <- addGraphToRedeR(gt12, gcoord=c(70,55), gscale=80, 
            isNested=TRUE, theme='th1', zoom=30)
        
          # Nest overlapping nodes into sub-containers
          N4 <- nestNodes(nodes=V(gt3)\$name, parent=N2, theme='th2')
          N5 <- nestNodes(nodes=V(gt3)\$name, parent=N3, theme='th2')
          nestNodes(nodes=V(gt3)\$name, parent=N5, theme='th2')
        
          # Assign edges to containers
          mergeOutEdges(nlevels=2)
        
          # Run the interactive layout
          relaxRedeR(p1=100, p2=100, p3=5, p4=150, 
            p5=5, p8=10, p9=20)
        
          # Add a color legend
          scl <- gt3\$legNodeColor\$scale
          names(scl) <- gt3\$legNodeColor\$legend 
          addLegendToRedeR(scl, type="nodecolor",
            title="Node color (logFC)", stretch = 0.1)
        
          # Select and highlight specific nodes
          selectNodes("RET")
          
        }, error = function(e) {
          message("RedeR interactive visualization skipped or failed (expected in headless environments): ", e\$message)
        })

    writeLines(c(
        '"BIOC_REDER_NESTED_SUBGRAPHS":',
        paste0('    RedeR: ', as.character(packageVersion('RedeR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_nested_subgraphs.csv versions.yml
    """
}

workflow BIOC_REDER_NESTED_SUBGRAPHS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ ER.limma, hs.inter ] ]

    main:
    BIOC_REDER_NESTED_SUBGRAPHS(ch_input)

    emit:
    tables   = BIOC_REDER_NESTED_SUBGRAPHS.out.tables
    plots    = BIOC_REDER_NESTED_SUBGRAPHS.out.plots
    objects  = BIOC_REDER_NESTED_SUBGRAPHS.out.objects
    versions = BIOC_REDER_NESTED_SUBGRAPHS.out.versions
}
