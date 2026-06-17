#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: StructuralVariantAnnotation — format_conversion_and_visualization
// Convert breakpoint GRanges to BEDPE format and visualize them using a circos plot.
// Input: gridss.vcf, COLO829T.purple.sv.ann.vcf.gz
// Container: quay.io/biocontainers/bioconductor-structuralvariantannotation:1.26.0--r45hdfd78af_0
// R packages: StructuralVariantAnnotation, VariantAnnotation, biovizBase, ggbio, rtracklayer
// Bioconductor: 3.20 | R: 4.4
// Requires: StructuralVariantAnnotation, VariantAnnotation, biovizBase, ggbio, rtracklayer
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load VCF and convert to GRanges using breakpointRanges
//  * 2. [Visualization & Output] Convert GRanges to Pairs and export to BEDPE using breakpointgr2pairs and rtracklayer::export
//  * 3. [Input & Preparation] Import BEDPE back to GRanges using pairs2breakpointgr and rtracklayer::import
//  * 4. [Visualization & Output] Prepare GRanges for circos plotting by adding a partner destination column
//  * 5. [Visualization & Output] Plot using ggbio and circle

nextflow.enable.dsl = 2

process BIOC_STRUCTURALVARIANTANNOTATION_FORMAT_CONVERSION_AND_VISUALIZATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-variant_calling:3.20-slim"

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
    .bm_deps <- c("StructuralVariantAnnotation", "VariantAnnotation", "biovizBase", "ggbio", "rtracklayer")
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
    library(StructuralVariantAnnotation)
    library(VariantAnnotation)
    library(rtracklayer)
    library(ggbio)
    library(biovizBase)
    
    # 1. Load VCF and convert to GRanges using breakpointRanges
    vcf_file <- "gridss.vcf"
    vcf <- VariantAnnotation::readVcf(vcf_file)
    gr <- breakpointRanges(vcf)
    
    # 2. Convert GRanges to Pairs and export to BEDPE using breakpointgr2pairs and rtracklayer::export
    rtracklayer::export(breakpointgr2pairs(gr), con="example.bedpe")
    
    # 3. Import BEDPE back to GRanges using pairs2breakpointgr and rtracklayer::import
    bedpe.gr <- pairs2breakpointgr(rtracklayer::import("example.bedpe"))
    
    # Save the imported GRanges object as an RDS file
    saveRDS(bedpe.gr, "imported_bedpe_gr.rds")
    
    # 4. Prepare GRanges for circos plotting by adding a partner destination column
    colo829_vcf_file <- "COLO829T.purple.sv.ann.vcf.gz"
    colo829_vcf <- VariantAnnotation::readVcf(colo829_vcf_file)
    colo829_bpgr <- breakpointRanges(colo829_vcf)
    
    gr.circos <- colo829_bpgr[seqnames(colo829_bpgr) %in% seqlevels(biovizBase::hg19sub)]
    seqlevels(gr.circos) <- seqlevels(biovizBase::hg19sub)
    mcols(gr.circos)\$to.gr <- granges(partner(gr.circos))
    
    # 5. Plot using ggbio and circle
    p <- ggbio() +
    	circle(gr.circos, geom="link", linked.to="to.gr") +
    	circle(biovizBase::hg19sub, geom='ideo', fill='gray70') +
    	circle(biovizBase::hg19sub, geom='scale', size=2) +
    	circle(biovizBase::hg19sub, geom='text', aes(label=seqnames), vjust=0, size=3)
    
    # Save the circos plot to a PDF file
    pdf("circos_plot.pdf", width = 10, height = 10)
    print(p)
    dev.off()

    writeLines(c(
        '"BIOC_STRUCTURALVARIANTANNOTATION_FORMAT_CONVERSION_AND_VISUALIZATION":',
        paste0('    StructuralVariantAnnotation: ', as.character(packageVersion('StructuralVariantAnnotation')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_format_conversion_and_visualization.csv versions.yml
    """
}

workflow BIOC_STRUCTURALVARIANTANNOTATION_FORMAT_CONVERSION_AND_VISUALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ gridss.vcf, COLO829T.purple.sv.ann.vcf.gz ] ]

    main:
    BIOC_STRUCTURALVARIANTANNOTATION_FORMAT_CONVERSION_AND_VISUALIZATION(ch_input)

    emit:
    tables   = BIOC_STRUCTURALVARIANTANNOTATION_FORMAT_CONVERSION_AND_VISUALIZATION.out.tables
    plots    = BIOC_STRUCTURALVARIANTANNOTATION_FORMAT_CONVERSION_AND_VISUALIZATION.out.plots
    objects  = BIOC_STRUCTURALVARIANTANNOTATION_FORMAT_CONVERSION_AND_VISUALIZATION.out.objects
    versions = BIOC_STRUCTURALVARIANTANNOTATION_FORMAT_CONVERSION_AND_VISUALIZATION.out.versions
}
