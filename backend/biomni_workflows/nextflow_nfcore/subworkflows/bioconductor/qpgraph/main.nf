#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: qpgraph — eqtl_network_estimation
// Estimate an eQTL network from genotyping cross data, physical maps, and gene annotations.
// Input: cross.RData, physical_map.RData, gene_annotation.csv, genome_info.RData
// Container: quay.io/biocontainers/bioconductor-qpgraph:2.44.0--r45h01b2380_0
// R packages: GenomeInfoDb, graph, qpgraph, qtl
// Bioconductor: 3.20 | R: 4.4
// Requires: GenomeInfoDb, graph, qpgraph, qtl
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Define estimation parameters using eQTLnetworkEstimationParam
//  * 2. [Core Analysis] Estimate the initial network using eQTLnetworkEstimate with a formula
//  * 3. [Core Analysis] Apply FDR correction to filter the network
//  * 4. [Core Analysis] Refine the network using non-rejection rates conditioning on genes
//  * 5. [Core Analysis] Filter by effect size (epsilon) and select significant associations (alpha)
//  * 6. [Core Analysis] Extract eQTL associations using alleQTL
//  * 7. [Visualization & Output] Plot the network using hive plots or standard graphs

nextflow.enable.dsl = 2

process BIOC_QPGRAPH_EQTL_NETWORK_ESTIMATION {
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
    .bm_deps <- c("GenomeInfoDb", "graph", "qpgraph", "qtl")
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
        library(qpgraph)
        library(qtl)
        library(GenomeInfoDb)
        library(grid)
        library(graph)
        
        # ==========================================
        # 1. Load User Input Files
        # ==========================================
        
        # Load cross object
        env_cross <- new.env()
        load("cross.RData", envir = env_cross)
        if ("cross" %in% ls(env_cross)) {
          cross <- env_cross\$cross
        } else {
          cross <- env_cross[[ls(env_cross)[1]]]
        }
        
        # Load physical map
        env_pmap <- new.env()
        load("physical_map.RData", envir = env_pmap)
        if ("pMap" %in% ls(env_pmap)) {
          pMap <- env_pmap\$pMap
        } else {
          pMap <- env_pmap[[ls(env_pmap)[1]]]
        }
        
        # Load gene annotation
        annot <- read.csv("gene_annotation.csv", row.names=1, stringsAsFactors=FALSE)
        
        # Load genome info (Seqinfo object)
        env_genome <- new.env()
        load("genome_info.RData", envir = env_genome)
        if ("genome" %in% ls(env_genome)) {
          genome <- env_genome\$genome
        } else {
          genome <- env_genome[[ls(env_genome)[1]]]
        }
        
        # ==========================================
        # 2. eQTL Network Estimation Workflow
        # ==========================================
        
        # Stage 1: Define estimation parameters
        param <- eQTLnetworkEstimationParam(cross, physicalMap=pMap,
                                            geneAnnotation=annot, genome=genome)
        
        # Stage 2: Estimate the initial network using a formula
        eqtlnet.q0 <- eQTLnetworkEstimate(param, ~ marker + gene, verbose=FALSE)
        
        # Stage 3: Apply FDR correction to filter the network
        eqtlnet.q0.fdr <- eQTLnetworkEstimate(param, estimate=eqtlnet.q0,
                                              p.value=0.05, method="fdr")
        
        # Stage 4: Refine the network using non-rejection rates conditioning on genes
        eqtlnet.q0.fdr.nrr <- eQTLnetworkEstimate(param, ~ marker + gene | gene(q=3),
                                                  estimate=eqtlnet.q0.fdr, verbose=FALSE)
        
        # Stage 5: Filter by effect size (epsilon)
        eqtlnet.q0.fdr.nrr <- eQTLnetworkEstimate(param, estimate=eqtlnet.q0.fdr.nrr,
                                                  epsilon=0.1)
        
        # Stage 6: Extract eQTL associations
        eqtls <- alleQTL(eqtlnet.q0.fdr.nrr)
        
        # Stage 7: Select significant associations (alpha)
        eqtlnet.q0.fdr.nrr.sel <- eQTLnetworkEstimate(param, estimate=eqtlnet.q0.fdr.nrr,
                                                      alpha=0.05)
        
        # ==========================================
        # 3. Save Outputs and Plotting
        # ==========================================
        
        # Save tabular results
        write.csv(eqtls, "all_eQTL_associations.csv", row.names=FALSE)
        
        # Save network objects
        saveRDS(eqtlnet.q0.fdr.nrr, "eqtl_network_refined.rds")
        saveRDS(eqtlnet.q0.fdr.nrr.sel, "eqtl_network_selected.rds")
        
        # Plot the network using hive plots for each chromosome
        pdf("eQTL_hive_plots.pdf", width=8, height=8)
        chrs <- seqnames(genome)
        for (chr in chrs) {
          tryCatch({
            plot(eqtlnet.q0.fdr.nrr.sel, type="hive", chr=chr)
            grid.text(paste0("Chromosome: ", chr), x=unit(0.5, "npc"), y=unit(0.95, "npc"), just="centre")
          }, error = function(e) {
            warning("Could not plot hive plot for chromosome ", chr, ": ", e\$message)
          })
        }
        dev.off()

    writeLines(c(
        '"BIOC_QPGRAPH_EQTL_NETWORK_ESTIMATION":',
        paste0('    qpgraph: ', as.character(packageVersion('qpgraph')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_eqtl_network_estimation.csv versions.yml
    """
}

workflow BIOC_QPGRAPH_EQTL_NETWORK_ESTIMATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ cross.RData, physical_map.RData, gene_annotation.csv, genome_info.RData ] ]

    main:
    BIOC_QPGRAPH_EQTL_NETWORK_ESTIMATION(ch_input)

    emit:
    tables   = BIOC_QPGRAPH_EQTL_NETWORK_ESTIMATION.out.tables
    plots    = BIOC_QPGRAPH_EQTL_NETWORK_ESTIMATION.out.plots
    objects  = BIOC_QPGRAPH_EQTL_NETWORK_ESTIMATION.out.objects
    versions = BIOC_QPGRAPH_EQTL_NETWORK_ESTIMATION.out.versions
}
