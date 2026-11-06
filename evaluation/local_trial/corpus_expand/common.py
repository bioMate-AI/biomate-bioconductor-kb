"""Shared core for corpus expansion: cleaning, quality filtering, PII, MinHash near-dedup,
decontamination vs holdout/SFT, and manifest. The per-source fetchers (PMC, Bioconductor, forums,
workflows, vendor docs) all import from here so quality rules are applied consistently.

Runs on the GPU/disk box. Deps: datasketch (MinHash LSH), optionally trafilatura/pymupdf in fetchers.
Doc schema everywhere: {"text","source","id","license","url","meta"}."""
import re, json, html as _html, hashlib, os, unicodedata

# ---------- cleaning ----------
def strip_html(s):
    s=re.sub(r"(?is)<(script|style)[^>]*>.*?</\1>"," ", s or "")
    s=re.sub(r"(?s)<!--.*?-->"," ", s)
    s=re.sub(r"(?s)<[^>]+>"," ", s)
    return _html.unescape(s)

def norm_unicode(s): return unicodedata.normalize("NFC", s or "")

def norm_ws(s):
    s=norm_unicode(s)
    s="".join(ch for ch in s if ch=="\n" or ch=="\t" or ord(ch)>=32)  # strip control chars
    return re.sub(r"[ \t]+"," ", re.sub(r"\n{3,}","\n\n", s.strip()))

_BOILER=re.compile(r"(?i)^(references?|bibliography|acknowledge?ments?|conflict of interest|"
                   r"competing interests|author contributions|funding|copyright|license|"
                   r"table of contents|download|edit on github|\[!\[|supplementary)")
def clean_prose(s, drop_boiler=True):
    s=norm_ws(s)
    if not drop_boiler: return s
    out=[]; skipping=False
    for l in s.split("\n"):
        t=l.strip()
        if _BOILER.match(t):  # drop a boilerplate section header and (for refs) the tail after it
            if re.match(r"(?i)^(references?|bibliography)\b", t): skipping=True
            continue
        if skipping: continue
        out.append(l)
    return "\n".join(out).strip()

def tokens(s): return int(len(re.findall(r"\S+", s or ""))*1.33)

# ---------- quality (Gopher/FineWeb-style heuristics) ----------
_WORD=re.compile(r"[A-Za-z]+")
_STOP={"the","of","and","to","in","a","is","for","with","that","this","are","as","be","on","by"}
def quality_ok(text, kind="prose", min_tok=50):
    t=text or ""
    if tokens(t) < min_tok: return False, "too_short"
    words=re.findall(r"\S+", t)
    if not words: return False, "empty"
    if kind=="code":  # lighter rules for code/usage
        if len(t) > 200_000: return False, "too_long_code"
        alnum=sum(c.isalnum() for c in t)/max(len(t),1)
        return (alnum>0.25, "ok" if alnum>0.25 else "low_alnum")
    # prose rules
    alpha_frac=sum(c.isalpha() for c in t)/max(len(t),1)
    if alpha_frac < 0.60: return False, "low_alpha"          # tables/numbers dumps
    mean_wlen=sum(len(w) for w in words)/len(words)
    if not (2.5 <= mean_wlen <= 12): return False, "word_len"
    low=t.lower(); wl=re.findall(r"[a-z']+", low)
    stop_frac=sum(w in _STOP for w in wl)/max(len(wl),1)
    if stop_frac < 0.02: return False, "no_stopwords"        # not natural English
    lines=[l for l in t.split("\n") if l.strip()]
    if lines:
        dup=1-len(set(lines))/len(lines)
        if dup > 0.5: return False, "dup_lines"
    sym_frac=sum(c in "#*=-_|>" for c in t)/max(len(t),1)
    if sym_frac > 0.15: return False, "symbol_heavy"
    return True, "ok"

# ---------- PII ----------
_EMAIL=re.compile(r"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}")
_PHONE=re.compile(r"(?<!\d)(\+?\d[\d\-\s().]{7,}\d)(?!\d)")
def pii_redact(s):
    s=_EMAIL.sub("[EMAIL]", s or "")
    s=_PHONE.sub("[PHONE]", s)
    return s

# ---------- MinHash near-dedup ----------
class Deduper:
    """Exact + MinHash-LSH near-dup. add(text)->True if UNIQUE (kept), False if duplicate."""
    def __init__(self, threshold=0.8, num_perm=128, shingle=5):
        self.seen_exact=set(); self.i=0; self.num_perm=num_perm; self.shingle=shingle; self.lsh=None
        try:
            from datasketch import MinHash, MinHashLSH
            self._MinHash=MinHash; self.lsh=MinHashLSH(threshold=threshold, num_perm=num_perm)
        except ImportError:
            import sys; print("WARNING: datasketch not installed -> EXACT dedup only (near-dup NOT "
                              "removed). `pip install datasketch` for MinHash near-dedup.", file=sys.stderr)
    def _mh(self, text):
        w=re.sub(r"[^a-z0-9]+"," ", text.lower()).split()
        sh=set(" ".join(w[j:j+self.shingle]) for j in range(max(len(w)-self.shingle+1,1)))
        m=self._MinHash(num_perm=self.num_perm)
        for s in sh: m.update(s.encode())
        return m
    def add(self, text):
        h=hashlib.sha256(re.sub(r"\s+"," ",text.lower()).strip().encode()).hexdigest()
        if h in self.seen_exact: return False
        self.seen_exact.add(h)
        if self.lsh is None: return True          # exact-only fallback (datasketch absent)
        m=self._mh(text)
        if self.lsh.query(m): return False
        self.lsh.insert(f"d{self.i}", m); self.i+=1
        return True

# ---------- decontamination vs holdout / SFT ----------
class Decontaminator:
    """Flags corpus docs that overlap eval/holdout or SFT text (train/test leakage) via n-gram hashes."""
    def __init__(self, n=13, hit_thresh=1):
        self.n=n; self.hit_thresh=hit_thresh; self.grams=set()
    def _ngrams(self, text):
        w=re.sub(r"[^a-z0-9]+"," ", (text or "").lower()).split()
        return set(" ".join(w[i:i+self.n]) for i in range(len(w)-self.n+1))
    def add_reference_text(self, text):
        for g in self._ngrams(text): self.grams.add(hashlib.md5(g.encode()).hexdigest()[:16])
    def load_jsonl(self, path, fields=("text","query","prompt")):
        if not os.path.exists(path): return
        for l in open(path):
            try: r=json.loads(l)
            except: continue
            if "messages" in r:
                for m in r["messages"]: self.add_reference_text(str(m.get("content","")))
            for f in fields:
                if r.get(f): self.add_reference_text(str(r[f]))
    def is_contaminated(self, text):
        hits=0
        for g in self._ngrams(text):
            if hashlib.md5(g.encode()).hexdigest()[:16] in self.grams:
                hits+=1
                if hits>=self.hit_thresh: return True
        return False

# ---------- manifest / output ----------
class Manifest:
    def __init__(self, source): self.source=source; self.c={}
    def bump(self, key, n=1, tok=0): d=self.c.setdefault(key,{"n":0,"tok":0}); d["n"]+=n; d["tok"]+=tok
    def dump(self, path):
        json.dump({"source":self.source,"counts":self.c}, open(path,"w"), indent=2)
        return self.c

def open_out(path):
    os.makedirs(os.path.dirname(path), exist_ok=True); return open(path,"w")
def write_doc(f, text, source, id="", license="", url="", meta=None):
    f.write(json.dumps({"text":text,"source":source,"id":id,"license":license,"url":url,
                        "meta":meta or {}})+"\n")
