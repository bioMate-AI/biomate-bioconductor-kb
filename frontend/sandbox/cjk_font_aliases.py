"""Make the Chinese/Japanese/Korean font names models habitually set resolve to Noto Sans CJK.

LLM-written plotting code nearly always sets e.g. plt.rcParams['font.sans-serif'] = ['SimHei'] for
Chinese labels. Those fonts are not installed, so matplotlib fell back to DejaVu Sans and drew tofu
boxes (live dev 2026-11-12: 0 missing-glyph warnings with the image defaults, 8 after setting SimHei).
Here every common CJK family name becomes an alias entry for the installed Noto Sans CJK face in the
prebuilt font cache — no font copies, and code that names any of them renders real glyphs.
Run once at image build (MPLCONFIGDIR=/opt/mplcache).
"""
import dataclasses
import os

import matplotlib
from matplotlib import font_manager as fm

ALIASES = [
    "SimHei", "Microsoft YaHei", "Microsoft JhengHei", "SimSun", "NSimSun", "KaiTi", "FangSong",
    "STHeiti", "STSong", "STKaiti", "Heiti SC", "Heiti TC", "PingFang SC", "PingFang TC",
    "Hiragino Sans GB", "Arial Unicode MS", "WenQuanYi Micro Hei", "WenQuanYi Zen Hei",
    "Noto Sans SC", "Noto Sans TC", "Noto Sans JP", "Noto Sans KR", "Source Han Sans SC",
    "Source Han Sans CN", "Droid Sans Fallback", "AR PL UMing CN", "Malgun Gothic", "MS Gothic",
]

mgr = fm._load_fontmanager(try_read_cache=False)
base = [e for e in mgr.ttflist if e.name.startswith("Noto Sans CJK")]
if not base:
    raise SystemExit("Noto Sans CJK is not installed — cannot alias CJK font names")
have = {e.name for e in mgr.ttflist}
added = 0
for alias in ALIASES:
    if alias in have:
        continue
    for e in base:  # every weight/style of the CJK family, renamed
        mgr.ttflist.append(dataclasses.replace(e, name=alias))  # FontEntry is a frozen dataclass
    added += 1
cache = os.path.join(matplotlib.get_cachedir(), f"fontlist-v{fm.FontManager.__version__}.json")
fm.json_dump(mgr, cache)
print(f"aliased {added} CJK family names to {sorted({e.name for e in base})} -> {cache}")
