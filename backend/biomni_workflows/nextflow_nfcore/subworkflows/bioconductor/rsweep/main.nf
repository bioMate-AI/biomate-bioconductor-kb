#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: rSWeeP — sequence_vectorization_and_phylogeny
// Vectorize biological sequences from FASTA files, construct a phylogenetic tree, and evaluate taxonomic consistency.
// Input: directory, metadata_mitochondrial.csv
// Container: quay.io/biocontainers/bioconductor-rsweep:1.22.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: ape, rSWeeP
// Visualizations: PCA plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Vectorize sequences using SWeePlite
//  * 2. [Core Analysis] Calculate distance matrix using dist
//  * 3. [Input & Preparation] Build phylogenetic tree using Neighbor-Joining (nj)
//  * 4. [Core Analysis] Evaluate tree consistency using PCCI and PMPG
//  * 5. [Core Analysis] Perform PCA on vectorized sequences using prcomp

nextflow.enable.dsl = 2

process BIOC_RSWEEP_SEQUENCE_VECTORIZATION_AND_PHYLOGENY {
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
    .bm_deps <- c("rSWeeP", "ape")
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
    library(rSWeeP)
    library(ape)
    
    # 1. Vectorize sequences using SWeePlite
    # User input: 'directory' containing FASTA files
    path = "directory/"
    sw = SWeePlite(path,seqtype='AA',mask=c(4),psz=1000)
    sw\$info
    
    # Save SWeeP projection object
    saveRDS(sw, "sweep_output.rds")
    
    # 2. Calculate distance matrix using dist
    mdist = dist(sw\$proj,method='euclidean')
    
    # 3. Build phylogenetic tree using Neighbor-Joining (nj)
    tr = nj(mdist)
    
    # Root the tree with the first tip
    if (length(tr\$tip.label) > 0) {
      tr = root(tr, outgroup = tr\$tip.label[1])
    }
    
    # Save phylogenetic tree
    write.tree(tr, "phylogenetic_tree.nwk")
    
    # Plot tree to PDF
    pdf("phylogenetic_tree.pdf", width = 10, height = 10)
    plot(tr)
    dev.off()
    
    # 4. Evaluate tree consistency using PCCI and PMPG
    # User input: 'metadata_mitochondrial.csv'
    pathmetadata <- "metadata_mitochondrial.csv"
    mt = read.csv(pathmetadata,header=TRUE)
    
    data = data.frame(sp=mt\$fileName,family=mt\$family) 
    
    pcci_res = PCCI(tr,data)
    pmpg_res = PMPG(tr,data)
    
    # Save consistency metrics
    write.csv(pcci_res\$tab, "pcci_results.csv", row.names = FALSE)
    write.csv(pmpg_res\$tab, "pmpg_results.csv", row.names = FALSE)
    
    # 5. Perform PCA on vectorized sequences using prcomp
    pca_output <- prcomp (sw\$proj , scale = FALSE)
    
    # Save PCA coordinates
    write.csv(pca_output\$x, "pca_coordinates.csv", row.names = TRUE)
    
    # Plot PCA to PDF
    pdf("pca_plots.pdf", width = 9, height = 7)
    par(mfrow=c(1,2))
    family_colors <- as.numeric(factor(mt\$family, levels = unique(mt\$family)))
    plot(pca_output\$x[,1],pca_output\$x[,2],xlab = 'PC-1' , ylab = 'PC-2' , pch =20 , col = family_colors)
    legend("bottomright",unique(mt\$family),col=as.character(c(1:length(unique(mt\$family)))),pch=20)
    plot(pca_output\$x[,3],pca_output\$x[,4],xlab = 'PC-3' , ylab = 'PC-4' , pch =20 , col = family_colors)
    dev.off()

    writeLines(c(
        '"BIOC_RSWEEP_SEQUENCE_VECTORIZATION_AND_PHYLOGENY":',
        paste0('    rSWeeP: ', as.character(packageVersion('rSWeeP')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_sequence_vectorization_and_phylogeny.csv versions.yml
    """
}

workflow BIOC_RSWEEP_SEQUENCE_VECTORIZATION_AND_PHYLOGENY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ directory, metadata_mitochondrial.csv ] ]

    main:
    BIOC_RSWEEP_SEQUENCE_VECTORIZATION_AND_PHYLOGENY(ch_input)

    emit:
    tables   = BIOC_RSWEEP_SEQUENCE_VECTORIZATION_AND_PHYLOGENY.out.tables
    plots    = BIOC_RSWEEP_SEQUENCE_VECTORIZATION_AND_PHYLOGENY.out.plots
    objects  = BIOC_RSWEEP_SEQUENCE_VECTORIZATION_AND_PHYLOGENY.out.objects
    versions = BIOC_RSWEEP_SEQUENCE_VECTORIZATION_AND_PHYLOGENY.out.versions
}
