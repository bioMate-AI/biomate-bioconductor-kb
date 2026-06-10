library(PhyloProfile)

# Construct a synthetic domain architecture file matching PhyloProfile's expected format
domain_lines <- c(
    "seedID\torthoID\tlength\tfeature\tstart\tend\tweight",
    "100136at6656\t100136at6656|PLAF7@36329@1|Q8ILT8|1\t200\tPF00001\t10\t50\t1.0",
    "100136at6656\t100136at6656|PLAF7@36329@1|Q8ILT8|1\t200\tPF00002\t60\t100\t1.0",
    "100136at6656\t100136at6656|POLVAN@319348@0|319348_0:004132|1\t250\tPF00001\t15\t55\t1.0"
)

writeLines(domain_lines, "gene.domains")