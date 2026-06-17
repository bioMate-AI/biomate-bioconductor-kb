#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: MesKit — data_import_and_profiling
// Import somatic mutation, clinical, CCF, and copy number segmentation data to classify mutations and visualize mutational and CNA landscapes.
// Input: CRC_HZ.maf, CRC_HZ.clin.txt, CRC_HZ.ccf.tsv, CRC_HZ.seg.txt, COREAD_all_lesions.conf_99.txt, COREAD_amp_genes.conf_99.txt, COREAD_del_genes.conf_99.txt, IntOGen-DriverGenes_COREAD.tsv
// Container: quay.io/biocontainers/bioconductor-meskit:1.20.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: MesKit
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Load somatic mutations, clinical data, and CCF data using
//  * 2. [Visualization & Output] Classify mutations based on shared patterns using
//  * 3. [Visualization & Output] Visualize the mutational landscape of driver genes across
//  * 4. [Visualization & Output] Read copy number segmentation and GISTIC2 files using
//  * 5. [Visualization & Output] Visualize the CNA landscape across samples using plotCNA

nextflow.enable.dsl = 2

process BIOC_MESKIT_DATA_IMPORT_AND_PROFILING {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20-slim"

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
    .bm_deps <- c("MesKit")
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
        
        # Load required library
        library(MesKit)
        
        # Define input file paths (exactly as specified by user)
        maf.File <- "CRC_HZ.maf"
        ccf.File <- "CRC_HZ.ccf.tsv"
        clin.File <- "CRC_HZ.clin.txt"
        driverGene.file <- "IntOGen-DriverGenes_COREAD.tsv"
        segCN <- "CRC_HZ.seg.txt"
        all.lesions <- "COREAD_all_lesions.conf_99.txt"
        amp.genes <- "COREAD_amp_genes.conf_99.txt"
        del.genes <- "COREAD_del_genes.conf_99.txt"
        
        # --- Load somatic mutations, clinical data, and CCF data using ---
        maf <- readMaf(mafFile = maf.File,
                       ccfFile = ccf.File,
                       clinicalFile  = clin.File,
                       refBuild = "hg19")  
        
        # Save Maf object as RDS
        saveRDS(maf, file = "maf_object.rds")
        
        # --- Classify mutations based on shared patterns using ---
        driverGene <- as.character(read.table(driverGene.file)\$V1)
        mut.class <- classifyMut(maf, class =  "SP", patient.id = 'V402')
        
        # Save classified mutations to CSV
        write.csv(mut.class, file = "mut_class_V402.csv", row.names = FALSE)
        
        # --- Visualize the mutational landscape of driver genes across ---
        pdf("mut_profile_landscape.pdf", width = 11, height = 6.5)
        print(plotMutProfile(maf, class =  "SP", geneList = driverGene, use.tumorSampleLabel = TRUE))
        dev.off()
        
        # --- Read copy number segmentation and GISTIC2 files using ---
        seg <- readSegment(segFile = segCN, gisticAllLesionsFile = all.lesions,
                           gisticAmpGenesFile = amp.genes, gisticDelGenesFile = del.genes)
        
        # Save segment data for V402 to CSV and save full segment object
        write.csv(seg\$V402, file = "seg_V402.csv", row.names = FALSE)
        saveRDS(seg, file = "segment_object.rds")
        
        # --- Visualize the CNA landscape across samples using plotCNA ---
        pdf("cna_landscape.pdf", width = 10, height = 5)
        print(plotCNA(seg, patient.id = c("V402", "V750", "V824"), use.tumorSampleLabel = TRUE))
        dev.off()

    writeLines(c(
        '"BIOC_MESKIT_DATA_IMPORT_AND_PROFILING":',
        paste0('    MesKit: ', as.character(packageVersion('MesKit')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_data_import_and_profiling.csv versions.yml
    """
}

workflow BIOC_MESKIT_DATA_IMPORT_AND_PROFILING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ CRC_HZ.maf, CRC_HZ.clin.txt, CRC_HZ.ccf.tsv, CRC_HZ.seg.txt, COREAD_all_lesions.conf_99.txt, COREAD_amp_genes.conf_99.txt, COREAD_del_genes.conf_99.txt, IntOGen-DriverGenes_COREAD.tsv ] ]

    main:
    BIOC_MESKIT_DATA_IMPORT_AND_PROFILING(ch_input)

    emit:
    tables   = BIOC_MESKIT_DATA_IMPORT_AND_PROFILING.out.tables
    plots    = BIOC_MESKIT_DATA_IMPORT_AND_PROFILING.out.plots
    objects  = BIOC_MESKIT_DATA_IMPORT_AND_PROFILING.out.objects
    versions = BIOC_MESKIT_DATA_IMPORT_AND_PROFILING.out.versions
}
