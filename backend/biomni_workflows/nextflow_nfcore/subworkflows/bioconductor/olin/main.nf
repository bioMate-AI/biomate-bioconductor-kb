#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: OLIN — within_array_normalization
// Perform optimized local intensity- and location-dependent normalization (OLIN/OSLIN) on a two-color microarray slide and visually inspect the results.
// Input: raw_microarray_data.RData, spot_coordinates.RData
// Container: quay.io/biocontainers/bioconductor-olin:1.88.0--r45hdfd78af_0
// R packages: marray, OLIN
// Bioconductor: 3.20 | R: 4.4
// Requires: OLIN, marray
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load raw microarray data and spot coordinates
//  * 2. [Core Analysis] Visually inspect raw foreground/background intensities and spatial/intensity-dependent dye biases
//  * 3. [Core Analysis] Perform optimized local regression normalization (OLIN or OSLIN)
//  * 4. [Visualization & Output] Plot normalized data to verify the removal of systematic biases

nextflow.enable.dsl = 2

process BIOC_OLIN_WITHIN_ARRAY_NORMALIZATION {
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
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("marray", "OLIN")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
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
            library(OLIN)
            library(marray)
            
            # Verify input files exist
            if (!file.exists("raw_microarray_data.RData") || !file.exists("spot_coordinates.RData")) {
              stop("Required input files 'raw_microarray_data.RData' and/or 'spot_coordinates.RData' are missing from the working directory.")
            }
            
            # Load user input data
            load("raw_microarray_data.RData")
            load("spot_coordinates.RData")
            
            # Ensure the expected objects 'sw' and 'sw.xy' are available in the environment
            if (!exists("sw")) {
              # Fallback: find any marrayRaw object
              objs <- ls()
              for (o in objs) {
                if (inherits(get(o), "marrayRaw")) {
                  sw <- get(o)
                  break
                }
              }
            }
            
            if (!exists("sw.xy")) {
              # Fallback: find any list containing X and Y matrices
              objs <- ls()
              for (o in objs) {
                val <- get(o)
                if (is.list(val) && "X" %in% names(val) && "Y" %in% names(val)) {
                  sw.xy <- val
                  break
                }
              }
            }
            
            if (!exists("sw") || !exists("sw.xy")) {
              stop("Could not locate appropriate 'sw' (marrayRaw) or 'sw.xy' (coordinates list) objects in the loaded files.")
            }
            
            # Open PDF device to capture all visual inspection and normalization plots
            pdf("olin_normalization_plots.pdf", width = 10, height = 8)
            
            # --- STAGE 2: Visual inspection of raw data ---
            fgbg.visu(sw[,1])
            
            plot(maA(sw[,1]),maM(sw[,1]),xlab="A",ylab="M",pch='.')
            
            mxy.plot(maM(sw)[,1],Ngc=maNgc(sw),Ngr=maNgr(sw),
                             Nsc=maNsc(sw),Nsr=maNsr(sw))
            
            mxy.abs.plot(maM(sw)[,1],Ngc=maNgc(sw),Ngr=maNgr(sw),Nsc=maNsc(sw),Nsr=maNsr(sw))
            
            mxy2.plot(maM(sw)[,1],X=as.matrix(sw.xy\$X)[,1],Y=as.matrix(sw.xy\$Y)[,1],
                      Ngc=maNgc(sw),Ngr=maNgr(sw),Nsc=maNsc(sw),Nsr=maNsr(sw))
            
            # --- STAGE 3: Perform optimized local regression normalization (OLIN) ---
            norm.olin <- olin(sw[,1],X=as.matrix(sw.xy\$X)[,1],Y=as.matrix(sw.xy\$Y)[,1])
            
            # --- STAGE 4: Plot OLIN normalized data to verify removal of systematic biases ---
            plot(maA(norm.olin),maM(norm.olin),main="OLIN",pch=".")
            
            mxy.plot(norm.olin,Ngc=maNgc(norm.olin),Ngr=maNgr(norm.olin),
                            Nsc=maNsc(norm.olin),Nsr=maNsr(norm.olin),main="OLIN")
            
            # --- STAGE 3 (Alternative): Perform optimized scaling local regression normalization (OSLIN) ---
            norm.oslin <- olin(sw[,1],X=as.matrix(sw.xy\$X)[,1],Y=as.matrix(sw.xy\$Y)[,1],alpha=c(0.1,1,0.1),OSLIN=TRUE)
            
            # --- STAGE 4 (Alternative): Plot OSLIN normalized data to verify removal of systematic biases ---
            plot(maA(norm.oslin),maM(norm.oslin),main="OSLIN",pch=".")
            
            mxy.plot(norm.oslin,Ngc=maNgc(norm.oslin),Ngr=maNgr(norm.oslin),
                            Nsc=maNsc(norm.oslin),Nsr=maNsr(norm.oslin),main="OSLIN")
            
            # Close the plotting device
            dev.off()
            
            # Save normalized objects to disk
            saveRDS(norm.olin, file = "norm_olin.rds")
            saveRDS(norm.oslin, file = "norm_oslin.rds")

    writeLines(c(
        '"BIOC_OLIN_WITHIN_ARRAY_NORMALIZATION":',
        paste0('    OLIN: ', as.character(packageVersion('OLIN')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_within_array_normalization.csv versions.yml
    """
}

workflow BIOC_OLIN_WITHIN_ARRAY_NORMALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ raw_microarray_data.RData, spot_coordinates.RData ] ]

    main:
    BIOC_OLIN_WITHIN_ARRAY_NORMALIZATION(ch_input)

    emit:
    tables   = BIOC_OLIN_WITHIN_ARRAY_NORMALIZATION.out.tables
    plots    = BIOC_OLIN_WITHIN_ARRAY_NORMALIZATION.out.plots
    objects  = BIOC_OLIN_WITHIN_ARRAY_NORMALIZATION.out.objects
    versions = BIOC_OLIN_WITHIN_ARRAY_NORMALIZATION.out.versions
}
