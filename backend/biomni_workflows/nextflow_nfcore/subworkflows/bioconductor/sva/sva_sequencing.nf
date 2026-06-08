#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: sva — sva_sequencing
// Estimate latent variables in count-based sequencing data using svaseq, optionally incorporating negative control probes (supervised SVA).
// Input: raw_counts.csv, sample_metadata.csv
// Container: quay.io/biocontainers/bioconductor-sva:3.58.0--r45h01b2380_0
// Requires: sva
// Visualizations: plot (ggplot/base)
// QC: low-count filtering, batch-effect correction
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Filter low-count genes
//  * 2. [Input & Preparation] Define null and alternative model matrices
//  * 3. [Core Analysis] Run svaseq to estimate surrogate variables
//  * 4. [Core Analysis] Optionally run supervised svaseq by providing control probes

nextflow.enable.dsl = 2

process BIOC_SVA_SVA_SEQUENCING {
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
        for (.bm_f in list.files(".", recursive = TRUE, full.names = TRUE)) {
          .bm_bn <- basename(.bm_f)
          if (!file.exists(.bm_bn)) try(file.copy(.bm_f, .bm_bn), silent = TRUE)
        }
        
        library(sva)
        
        # Read user input files
        zfGenes <- read.csv("raw_counts.csv", row.names = 1, check.names = FALSE)
        metadata <- read.csv("sample_metadata.csv", row.names = 1, check.names = FALSE)
        
        # Extract group variable from metadata
        if ("group" %in% colnames(metadata)) {
          group = as.factor(metadata\$group)
        } else {
          group = as.factor(metadata[, 1])
        }
        
        # 1. Filter low-count genes
        filter = apply(zfGenes, 1, function(x) length(x[x>5])>=2)
        filtered = zfGenes[filter,]
        dat0 = as.matrix(filtered)
        
        # 2. Define null and alternative model matrices
        mod1 = model.matrix(~group)
        mod0 = cbind(mod1[,1])
        
        # Estimate the number of surrogate variables dynamically
        n.sv = num.sv(dat0, mod1, method="leek")
        
        # 3. Run svaseq to estimate surrogate variables (unsupervised)
        svseq_obj = svaseq(dat0, mod1, mod0, n.sv=n.sv)
        svseq = svseq_obj\$sv
        
        # 4. Run supervised svaseq by providing empirical control probes
        # Using the posterior probability that a gene is NOT affected by the group variable
        controls = 1 - svseq_obj\$pprob.b
        sup_svseq = svaseq(dat0, mod1, mod0, controls=controls, n.sv=n.sv)\$sv
        
        # Write outputs
        write.csv(svseq, "unsupervised_svaseq.csv", row.names = FALSE)
        write.csv(sup_svseq, "supervised_svaseq.csv", row.names = FALSE)
        
        saveRDS(list(
          unsupervised_sv = svseq,
          supervised_sv = sup_svseq,
          filtered_data = dat0,
          controls = controls
        ), "svaseq_output.rds")
        
        pdf("svaseq_plots.pdf", width = 10, height = 5)
        par(mfrow = c(1, 2))
        plot(svseq, pch=19, col="blue", main="Unsupervised svaseq")
        plot(sup_svseq, svseq, pch=19, col="blue", main="Supervised vs Unsupervised")
        dev.off()

    writeLines(c(
        '"BIOC_SVA_SVA_SEQUENCING":',
        paste0('    sva: ', as.character(packageVersion('sva')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_sva_sequencing.csv versions.yml
    """
}

workflow BIOC_SVA_SVA_SEQUENCING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ raw_counts.csv, sample_metadata.csv ] ]

    main:
    BIOC_SVA_SVA_SEQUENCING(ch_input)

    emit:
    tables   = BIOC_SVA_SVA_SEQUENCING.out.tables
    plots    = BIOC_SVA_SVA_SEQUENCING.out.plots
    objects  = BIOC_SVA_SVA_SEQUENCING.out.objects
    versions = BIOC_SVA_SVA_SEQUENCING.out.versions
}
