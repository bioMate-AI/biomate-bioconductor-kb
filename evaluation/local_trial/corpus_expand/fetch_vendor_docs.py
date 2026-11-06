"""Instrument-vendor documentation (PDFs) -> (1) cleaned prose for mid-train AND (2) structured
error->fix rows that become GROUNDED diag_fix SFT. Highest-value source for the diagnosis task.

Input is a CURATED url list (respect each vendor's ToS -- only officially-public docs), TSV:
    <pdf_url>\t<vendor>\t<instrument>\t<license_or_tos_note>
Run:
  python fetch_vendor_docs.py --urls vendor_docs.tsv --out /opt/dlami/nvme/corpus/vendor.jsonl \
      --sft-out /opt/dlami/nvme/corpus/vendor_diagfix_sft.jsonl --decontam .../decontam.pkl
Needs: pip install pymupdf   (layout text). For scanned PDFs add OCR (not handled here).
Each vendor's error-table layout differs -> the parser is heuristic; tune per vendor and CHECK the
manifest's diagfix_rows before trusting. ToS status is recorded per doc in the manifest."""
import argparse, os, re, sys, json, urllib.request
sys.path.insert(0, os.path.dirname(__file__)); import common as C

ERR_HINT=re.compile(r"(?i)\b(error|fault|alarm|troubleshoot|failure|warning code|status code)\b")
# a row like:  E-1234   Laser temperature out of range   Restart the run / check chiller
ROW=re.compile(r"^\s*([A-Z]{0,4}[-_ ]?\d{2,5}[A-Za-z]?)\s{2,}(.{6,120}?)\s{2,}(.{6,200})$")

def pdf_text(blob):
    import fitz
    doc=fitz.open(stream=blob, filetype="pdf")
    return [p.get_text("text") for p in doc]

def parse_error_rows(pages, vendor, instrument):
    rows=[]
    for pg in pages:
        if not ERR_HINT.search(pg): continue
        for line in pg.split("\n"):
            m=ROW.match(line)
            if m:
                code,desc,fix=m.group(1).strip(),m.group(2).strip(),m.group(3).strip()
                rows.append({"instrument":instrument,"vendor":vendor,"error_code":code,
                             "description":desc,"fix":fix})
    return rows

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("--urls", required=True); ap.add_argument("--out", required=True)
    ap.add_argument("--sft-out", required=True); ap.add_argument("--decontam", default="")
    a=ap.parse_args()
    dec=None
    if a.decontam:
        import pickle; dec=pickle.load(open(a.decontam,"rb"))
    dd=C.Deduper(); man=C.Manifest("vendor"); f=C.open_out(a.out); sf=C.open_out(a.sft_out)
    kept=0; diagfix=0
    for ln in open(a.urls):
        ln=ln.strip()
        if not ln or ln.startswith("#"): continue
        parts=(ln.split("\t")+["","",""])[:4]; url,vendor,instrument,tos=parts
        try:
            blob=urllib.request.urlopen(urllib.request.Request(
                url, headers={"User-Agent":"biomate-corpus/1.0"}), timeout=180).read()
            pages=pdf_text(blob)
        except Exception: man.bump("fetch_or_parse_error"); continue
        man.bump("docs", tok=0)
        # (1) prose doc
        text=C.pii_redact(C.clean_prose("\n".join(pages)))
        ok,why=C.quality_ok(text,"prose",120)
        if ok and not (dec and dec.is_contaminated(text)) and dd.add(text):
            C.write_doc(f, text, "vendor_doc", url, tos, url, {"vendor":vendor,"instrument":instrument})
            kept+=1; man.bump("kept_prose", tok=C.tokens(text))
        # (2) error->fix rows -> grounded diag_fix SFT
        for row in parse_error_rows(pages, vendor, instrument):
            prompt=(f"You are BioMate. The {row['instrument'] or vendor} instrument reported: "
                    f"{row['error_code']} — {row['description']}. Diagnose and give the fix as JSON "
                    '{"root_cause": ..., "fix": ...}.')
            gold=json.dumps({"root_cause":row["description"],"fix":row["fix"]})
            sf.write(json.dumps({"messages":[{"role":"user","content":prompt},
                                             {"role":"assistant","content":gold}],
                                 "source":"vendor_errtable","vendor":vendor})+"\n")
            diagfix+=1
        man.bump("tos:"+(tos or "unspecified"))
    f.close(); sf.close(); man.c["diagfix_rows"]={"n":diagfix,"tok":0}
    man.dump(a.out.replace(".jsonl","_manifest.json"))
    print(f"Vendor done: {kept} prose docs, {diagfix} grounded diag_fix rows -> {a.out}, {a.sft_out}")
    print("REVIEW the manifest's diagfix_rows + a sample before training (error-table layouts vary per vendor).")

if __name__=="__main__": raise SystemExit(main())
