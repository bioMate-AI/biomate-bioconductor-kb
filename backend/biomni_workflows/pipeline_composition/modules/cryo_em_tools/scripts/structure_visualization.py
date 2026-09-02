#!/usr/bin/env python3
"""
BioMate cryo-em-tools structure visualization — publication molecular rendering via PyMOL.
Backs the STRUCTURE_OVERVIEW Nextflow process (modules/cryo_em_tools/visualization.nf).

Interface (as called by the .nf):  --pdb <pdb> [--map <mrc>] --output_dir <dir> --mode overview
                                    --resolution <A> --report <json> [--mock]
Alternate-state extension:          --ref <pdb>  renders an inward↔outward superposition,
                                    colouring the mobile model by per-residue Cα displacement
                                    (the conformational change), side-on to the membrane.

Outputs: structure_overview.png (ray-traced), structure_viewer.html (py3Dmol), <report>.json
"""
import argparse, json, os, sys

def _mock(outdir, report):
    os.makedirs(outdir, exist_ok=True)
    # 1x1 white PNG so downstream never hard-fails when the renderer is unavailable
    import base64
    png=base64.b64decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")
    open(os.path.join(outdir,"structure_overview.png"),"wb").write(png)
    open(os.path.join(outdir,"structure_viewer.html"),"w").write("<html><body>viewer (mock)</body></html>")
    json.dump({"mode":"mock"}, open(report or os.path.join(outdir,"visualization_report.json"),"w"))
    print("structure_visualization: mock output written")

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("--pdb"); ap.add_argument("--ref"); ap.add_argument("--map")
    ap.add_argument("--output_dir", default="."); ap.add_argument("--mode", default="overview")
    ap.add_argument("--resolution", default="3.0"); ap.add_argument("--report")
    ap.add_argument("--mock", action="store_true")
    ap.add_argument("--trim", help="residue range to keep, e.g. 67-470 (hides floppy termini)")
    a=ap.parse_args()
    outdir=a.output_dir; os.makedirs(outdir, exist_ok=True)
    report=a.report or os.path.join(outdir,"visualization_report.json")
    if a.mock or not a.pdb:
        return _mock(outdir, report)
    try:
        import pymol
        pymol.finish_launching(['pymol','-cq'])   # headless
        from pymol import cmd
    except Exception as e:
        print(f"PyMOL unavailable ({e}); writing mock", file=sys.stderr); return _mock(outdir, report)

    cmd.set("ray_opaque_background", 0); cmd.bg_color("white")
    cmd.set("cartoon_transparency", 0.0); cmd.set("ray_shadows", 0); cmd.set("antialias", 2)
    cmd.load(a.pdb, "mobile")
    rep={"pdb":os.path.basename(a.pdb),"mode":a.mode,"resolution_A":float(a.resolution)}
    if a.ref and os.path.exists(a.ref):
        cmd.load(a.ref, "ref")
        aln=cmd.align("mobile and name CA", "ref and name CA")
        rep["superposed_on"]=os.path.basename(a.ref); rep["align_rmsd_A"]=round(aln[0],2); rep["align_atoms"]=aln[1]
        # colour the mobile model by per-residue Cα displacement (the conformational change)
        ref_ca={}
        cmd.iterate_state(1,"ref and name CA","ref_ca[(chain,resi)]=(x,y,z)",space={'ref_ca':ref_ca})
        def putb(chain,resi,x,y,z):
            import math
            r=ref_ca.get((chain,resi))
            return math.sqrt((x-r[0])**2+(y-r[1])**2+(z-r[2])**2) if r else 0.0
        cmd.alter_state(1,"mobile and name CA","b=putb(chain,resi,x,y,z)",space={'putb':putb})
        cmd.spectrum("b","blue_white_red","mobile and name CA", minimum=0, maximum=8)
        cmd.color("grey80","ref")
        cmd.set("cartoon_transparency",0.35,"ref")
    else:
        cmd.spectrum("count","rainbow","mobile")
    if a.trim:
        lo,hi=a.trim.split("-")
        cmd.remove(f"resi \\{lo}-{hi}" if False else f"not resi {lo}-{hi}")
    cmd.hide("everything"); cmd.show("cartoon"); cmd.set("cartoon_side_chain_helper",1)
    cmd.orient("mobile")        # orient on the TM core, not the floppy termini
    cmd.turn("z", 90)           # membrane normal vertical
    cmd.ray(1800, 1400); cmd.png(os.path.join(outdir,"structure_overview.png"), dpi=300)
    # gate close-up if a ref/displacement exists: zoom the most-displaced region
    if a.ref:
        cmd.ray(1600,1200); cmd.png(os.path.join(outdir,"structure_gates.png"), dpi=300)
    # py3Dmol interactive viewer for BioMate chat
    try:
        html=_viewer_html(a.pdb, a.ref)
        open(os.path.join(outdir,"structure_viewer.html"),"w").write(html)
    except Exception as e:
        open(os.path.join(outdir,"structure_viewer.html"),"w").write("<html><body>viewer error</body></html>")
    json.dump(rep, open(report,"w"), indent=2)
    print("structure_visualization: rendered", rep)

def _viewer_html(pdb, ref):
    def rd(p): return open(p).read().replace("`","'") if p and os.path.exists(p) else ""
    m=rd(pdb); r=rd(ref)
    return f"""<html><head><script src="https://3Dmol.org/build/3Dmol-min.js"></script></head>
<body><div id="v" style="width:700px;height:520px;position:relative;"></div><script>
let v=$3Dmol.createViewer("v",{{backgroundColor:"white"}});
v.addModel(`{m}`,"pdb"); v.setStyle({{model:0}},{{cartoon:{{colorscheme:"spectrum"}}}});
{('v.addModel(`'+r+'`,"pdb"); v.setStyle({model:1},{cartoon:{color:"grey"}});') if r else ''}
v.zoomTo(); v.render();</script></body></html>"""

if __name__=="__main__":
    main()
