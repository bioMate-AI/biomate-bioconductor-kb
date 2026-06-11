library(ape)
library(lattice)
library(clst)
library(clstutils)

archive <- system.file('extdata', 'vaginal_16s.refpkg.tar.gz', package='clstutils')
untar(archive)
file.copy("vaginal_16s.refpkg", "refpkg", recursive = TRUE)

placefile_src <- system.file('extdata', 'merged.json', package='clstutils')
file.copy(placefile_src, "merged.json")
file.copy(placefile_src, "placefile")

distfile_src <- system.file('extdata', 'merged.distmat.bz2', package='clstutils')
file.copy(distfile_src, "merged.distmat.bz2")
file.copy(distfile_src, "distfile")