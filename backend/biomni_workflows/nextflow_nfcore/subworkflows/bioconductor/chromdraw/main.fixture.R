library(chromDraw)

input_file <- system.file('extdata', 'Ack_and_Stenopetalum_nutans.txt', package ='chromDraw')
color_file <- system.file('extdata', 'default_colors.txt', package ='chromDraw')

if (file.exists(input_file)) {
    file.copy(input_file, "karyotype_definition.txt", overwrite = TRUE)
} else {
    writeLines(c(
        "KARYOTYPE ACK ACK BEGIN",
        "CHR ACK1 al1 0 17000000",
        "BLOCK A A al1 0 6700000 yellow",
        "BLOCK B B al1 6700000 12400000 yellow",
        "CENTROMERE al1",
        "BLOCK C C al1 12400000 17000000 yellow",
        "MARK 35S_rDNA RECTANGLE 2 al1 11739990 white",
        "KARYOTYPE END"
    ), "karyotype_definition.txt")
}

if (file.exists(color_file)) {
    file.copy(color_file, "color_definitions.txt", overwrite = TRUE)
} else {
    writeLines(c(
        "COLOR yellow 255 255 0",
        "COLOR red 255 0 0",
        "COLOR white 255 255 255"
    ), "color_definitions.txt")
}