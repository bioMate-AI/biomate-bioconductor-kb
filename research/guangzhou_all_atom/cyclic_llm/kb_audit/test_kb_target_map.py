import kb_target_map as K
def test_alpha_v_beta_3_is_not_avb6(): assert "avb6" not in K.map_kb("ITGAV,ITGB3")
def test_alpha_v_beta_6_maps(): assert K.map_kb("ITGAV,ITGB6") == ["avb6"] and K.map_kb("ITGB6") == ["avb6"]
def test_single_beta1_is_ambiguous_not_mapped(): assert K.map_kb("ITGB1") == [] and K.map_kb("ITGA4") == []
def test_a4b7_requires_both_chains(): assert K.map_kb("ITGA4,ITGB7") == ["a4b7"] and "a4b1" not in K.map_kb("ITGA4,ITGB7")
def test_pdl1_single_gene(): assert K.map_kb("CD274") == ["pdl1"] and K.map_kb("CD274,PDCD1") == ["pdl1"]
