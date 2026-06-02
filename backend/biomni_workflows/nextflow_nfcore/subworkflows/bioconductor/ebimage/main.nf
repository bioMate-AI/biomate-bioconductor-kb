#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: EBImage
// EBImage provides general purpose functionality for image processing and analysis. In the context of 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/EBImage/inst/doc/EBImage-introduction.R
// Upstream  : none
// Downstream: CRImage, cytomapper, flowcatchR, DonaPLLP2013, furrowSeg
//
// Install: BiocManager::install("EBImage")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_EBIMAGE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-ebimage"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-ebimage:4.48.0--r44_0' :
        'quay.io/biocontainers/bioconductor-ebimage:4.48.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_ebimage_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_ebimage_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_ebimage_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(EBImage)
    library(jsonlite)


    # --- Read Image [] ---
    # Key functions: readImage, images, sample.png, display, text, dev.print, browser, raster
    f = system.file("images", "sample.png", package="EBImage")
    img = readImage(f)
    display(img, method="browser")

    ## ----display-raster, fig.width=dim(img)[1L]/.dpi, fig.height=dim(img)[2L]/.dpi, dpi=.dpi/2----
    display(img, method="raster")
    text(x = 20, y = 20, label = "Parrots", adj = c(0,1), col = "orange", cex = 2)

    ## ----dev-print, eval=FALSE----------------------------------------------------
    #  filename = "parrots.jpg"
    #  dev.print(jpeg, filename = filename , width = dim(img)[1], height = dim(img)[2])

    file.info(filename)$size

    ## ----dev-print3, echo=FALSE, sfig.width=dim(img)[1L]/.dpi, fig.height=dim(img)[2L]/.dpi, dpi=.dpi/2----
    invisible(file.remove(filename))

    ## ----readImageColor-pre, echo=FALSE-------------------------------------------
    imgcol = readImage(system.file("images", "sample-color.png", package="EBImage"))
    #  imgcol = readImage(system.file("images", "sample-color.png", package="EBImage"))

    # --- Image Data [] ---
    # Key functions: imageData, is.Image, as.array, numberOfFrames, render, total
    imageData(img)[1:3, 1:6]
    is.Image( as.array(img) )
    hist(img)
    range(img)
    img
    print(img, short=TRUE)
    print(imgcol, short=TRUE)
    numberOfFrames(imgcol, type = "render")
    numberOfFrames(imgcol, type = "total")
    nuc

    # --- Color Mode [] ---
    # Key functions: colorMode, display, rep, red, green, combine, transpose, translate
    colorMode(imgcol) = Grayscale
    display(imgcol, all=TRUE)

    ## ----Image-character, fig.width=7/.dpi, fig.height=7/.dpi, dpi=10*.dpi--------
    colorMat = matrix(rep(c("red","green", "#0000ff"), 25), 5, 5)
    colorImg = Image(colorMat)
    colorImg
    display(colorImg, interpolate=FALSE)
    img_neg = max(img) - img
    display( img_neg )
    img_comb = combine(
      img,
      img + 0.3,
      img * 2,
      img ^ 0.5
    )

    display(img_comb, all=TRUE)

    ## ----cropthreshold-pre, echo=FALSE--------------------------------------------

    # --- Resize [] ---
    # Key functions: resize, display, flip, flop, combine, affine, makeBrush, filter2
    #  img_resize = resize(img, w=256, h=256)
    #  display(img_resize )

    ## ----resize-post, echo=FALSE, fig.width=dim(img_resize)[1L]/.dpi, fig.height=dim(img_resize)[2L]/.dpi, dpi=.dpi/2----
    display(img_resize)
    img_flip = flip(img)
    img_flop = flop(img)

    display(combine(img_flip, img_flop), all=TRUE)
    m =  matrix(c(1, -.5, 128, 0, 1, 0), nrow=3, ncol=2)
    img_affine = affine(img, m)
    display( img_affine )
    w = makeBrush(size = 31, shape = 'gaussian', sigma = 5)
    plot(w[(nrow(w)+1)/2, ], ylab = "w", xlab = "", cex = 0.7)
    img_flo = filter2(img, w)
    display(img_flo)
    nuc_gblur = gblur(nuc, sigma = 5)
    display(nuc_gblur, all=TRUE )
    fhi = matrix(1, nrow = 3, ncol = 3)
    fhi[2, 2] = -8

    # --- Logo [] ---
    # Key functions: readImage, display, makeBrush, erode, dilate, combine, otsu, function
    #  shapes = readImage(system.file('images', 'shapes.png', package='EBImage'))
    #  logo = shapes[110:512,1:130]
    #  display(logo)

    ## ----logo-post, echo=FALSE, fig.width=dim(logo)[1L]/.dpi, fig.height=dim(logo)[2L]/.dpi, dpi=.dpi----
    display(logo)
    kern = makeBrush(5, shape='diamond')
    display(kern, interpolate=FALSE)
    logo_erode= erode(logo, kern)
    logo_dilate = dilate(logo, kern)

    display(combine(logo_erode, logo_dilate), all=TRUE)
    threshold = otsu(nuc)
    threshold
    nuc_th = combine( mapply(function(frame, th) frame > th, getFrames(nuc), threshold, SIMPLIFY=FALSE) )
    display(nuc_th, all=TRUE)
    disc = makeBrush(31, "disc")
    disc = disc / sum(disc)
    offset = 0.05
    nuc_bg = filter2( nuc, disc )

    # --- Displaybw [] ---
    # Key functions: display, normalize, colorLabels, watershed, distmap, propagate, seq.int, combine
    display( normalize(logo_label) )
    display( colorLabels(logo_label) )
    nmask = watershed( distmap(nuc_th), 2 )
    display(colorLabels(nmask), all=TRUE)
    voronoiExamp = propagate(seeds = nmask, x = nmask, lambda = 100)
    voronoiPaint = colorLabels (voronoiExamp)
    display(voronoiPaint)
    objects = list(
        seq.int(from = 2, to = max(logo_label), by = 2),
        seq.int(from = 1, to = max(logo_label), by = 2)
        )
    logos = combine(logo_label, logo_label)
    z = rmObjects(logos, objects, reenumerate=FALSE)
    display(z, all=TRUE)
    showIds = function(image) lapply(getFrames(image), function(frame) unique(as.vector(frame)))

    showIds(z)
    showIds( reenumerate(z) )
    filled_logo = fillHull(logo)
    display(filled_logo)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_ebimage_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_ebimage_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_ebimage_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_EBIMAGE:", paste0("    ebimage: ", packageVersion("EBImage"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ebimage_results.csv
    touch ${prefix}_ebimage_output.rds
    echo "BIOC_EBIMAGE:" > versions.yml
    echo "    ebimage: 0.0.0" >> versions.yml
    """
}


workflow BIOC_EBIMAGE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_EBIMAGE(ch_input)

    emit:
    results  = BIOC_EBIMAGE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_EBIMAGE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_EBIMAGE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_EBIMAGE.out.versions  // channel: path(versions.yml)
}
