library(HMMcopy)

copy_or_create_wig <- function(filename, default_vals) {
    src <- system.file("extdata", filename, package = "HMMcopy")
    if (src != "" && file.exists(src)) {
        file.copy(src, filename, overwrite = TRUE)
    } else {
        lines <- c("fixedStep chrom=6 start=9990001 step=10000 span=10000", default_vals)
        writeLines(lines, filename)
    }
}

copy_or_create_wig("normal.wig", c("7351", "11080", "9369", "9505", "10392", "10785", "11084", "9712", "5320", "11014", "10318"))
copy_or_create_wig("gc.wig", c("0.3932", "0.3925", "0.3689", "0.3634", "0.3903", "0.3854", "0.4264", "0.3826", "0.4011", "0.3944", "0.3667"))
copy_or_create_wig("map.wig", c("0.558421", "0.929000", "0.975162", "0.963870", "0.889620", "0.952784", "0.916659", "0.940946", "0.422648", "0.974912", "0.971846"))
copy_or_create_wig("tumour.wig", c("7000", "11500", "9000", "9200", "10000", "10500", "11000", "9500", "5000", "10800", "10000"))