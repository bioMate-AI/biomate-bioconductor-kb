#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: iBBiG — binary_biclustering
// Perform iterative binary bi-clustering on a binary matrix, visualize the resulting modules, extract sub-matrices, and save the results.
// Input: binMat@Seeddata
// Container: quay.io/biocontainers/bioconductor-ibbig:1.54.0--r45h01b2380_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: iBBiG
// Visualizations: cluster plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the package and prepare the binary matrix
//  * 2. [Core Analysis] Run the iBBiG algorithm to extract a specified number of modules
//  * 3. [Visualization & Output] Plot the biclustering results and generate diagnostic plots
//  * 4. [Core Analysis] Extract the sub-matrices of the clusters
//  * 5. [Visualization & Output] Write the bicluster results to a text file

nextflow.enable.dsl = 2

process BIOC_IBBIG_BINARY_BICLUSTERING {
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
        library(iBBiG)
        
        # 1. Load the package and prepare the binary matrix
        input_file <- "binMat@Seeddata"
        if (!file.exists(input_file)) {
          stop(paste("Required input file", input_file, "does not exist in the working directory."))
        }
        
        # Read the binary matrix robustly (supporting RDS, TSV, or CSV formats)
        binMat_data <- tryCatch({
          readRDS(input_file)
        }, error = function(e) {
          tryCatch({
            as.matrix(read.table(input_file, header=TRUE, row.names=1, check.names=FALSE))
          }, error = function(e2) {
            as.matrix(read.csv(input_file, header=TRUE, row.names=1, check.names=FALSE))
          })
        })
        
        if (!is.matrix(binMat_data)) {
          binMat_data <- as.matrix(binMat_data)
        }
        
        # 2. Run the iBBiG algorithm to extract a specified number of modules
        res <- iBBiG(binMat_data, nModules=10)
        
        # Save the main result object
        saveRDS(res, "iBBiG_results.rds")
        
        # 3. Plot the biclustering results and generate diagnostic plots
        pdf("biclustering_plots.pdf", width=10, height=8)
        plot(res)
        drawHeatmap2(res@Seeddata, res, number=4)
        biclustmember(res,res@Seeddata)
        biclustbarchart(res@Seeddata, Bicres=res)
        plotclust(res, res@Seeddata)
        dev.off()
        
        # 4. Extract the sub-matrices of the clusters
        Modules <- bicluster(res@Seeddata, res, 1:3)
        
        # Save extracted modules
        saveRDS(Modules, "extracted_modules.rds")
        for (i in seq_along(Modules)) {
          write.csv(Modules[[i]], file=paste0("Bicluster_", i, ".csv"), row.names=TRUE)
        }
        
        # 5. Write the bicluster results to a text file
        writeBiclusterResults("Modules.txt", res, bicName="Output from iBBiG with default parameters", geneNames=rownames(res@Seeddata), arrayNames=colnames(res@Seeddata))

    writeLines(c(
        '"BIOC_IBBIG_BINARY_BICLUSTERING":',
        paste0('    iBBiG: ', as.character(packageVersion('iBBiG')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_binary_biclustering.csv versions.yml
    """
}

workflow BIOC_IBBIG_BINARY_BICLUSTERING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ binMat@Seeddata ] ]

    main:
    BIOC_IBBIG_BINARY_BICLUSTERING(ch_input)

    emit:
    tables   = BIOC_IBBIG_BINARY_BICLUSTERING.out.tables
    plots    = BIOC_IBBIG_BINARY_BICLUSTERING.out.plots
    objects  = BIOC_IBBIG_BINARY_BICLUSTERING.out.objects
    versions = BIOC_IBBIG_BINARY_BICLUSTERING.out.versions
}
