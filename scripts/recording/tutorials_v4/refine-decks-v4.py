#!/usr/bin/env python3
"""Apply the drug-dev refinement catalog (A-K) to a tutorial deck HTML.
Contract-preserving: never adds/removes a <section class="scene">, never touches
data-seconds / window.__timeline. Idempotent. Prints a per-rule change count.

Usage: refine_decks.py <file.html> [--write]
"""
import re, sys

def refine(html):
    counts = {}
    def sub(name, pat, repl, s, flags=0):
        new, n = re.subn(pat, repl, s, flags=flags)
        if n: counts[name] = counts.get(name, 0) + n
        return new

    # C / hero-band: remove the whole <div class="hero-band"> ... </div> block.
    # It is a direct child of .s-text.hero and self-contained; match balanced by
    # consuming up to the matching close before the hero section's </div></section>.
    # The band always ends right before the scene's closing. Use a non-greedy block
    # that stops at the first "</div>\n  </section>" style boundary is unsafe; instead
    # match the known structure: <div class="hero-band"> ... </div> where the content
    # has no nested hero-band. We remove from <div class="hero-band"> to the </div>
    # that precedes the </div></section> of scene 01. Practically: the band is the
    # LAST child of .s-text, so it ends at "</div></div></section>" (band, s-text,
    # section). Capture lazily up to that triple-close and drop the band only.
    def drop_hero_band(s):
        out = []
        i = 0
        openre = re.compile(r'<div class="hero-band"[^>]*>')
        while True:
            mo = openre.search(s, i)
            if not mo:
                out.append(s[i:]); break
            j = mo.start()
            out.append(s[i:j])
            # walk forward counting <div> depth from the band open
            k = j
            depth = 0
            tagre = re.compile(r'<(/?)div\b[^>]*>')
            while k < len(s):
                m = tagre.search(s, k)
                if not m: k = len(s); break
                if m.group(1) == '':  # <div...>
                    depth += 1
                else:                 # </div>
                    depth -= 1
                k = m.end()
                if depth == 0:
                    break
            counts['C hero-band'] = counts.get('C hero-band', 0) + 1
            i = k  # skip the whole band
        return ''.join(out)
    html = drop_hero_band(html)

    # A / hero centering: top:60px -> top:46%;transform:translateY(-50%) on .s-text.hero
    html = sub('A hero-center',
               r'(class="s-text hero"[^>]*?style="[^"]*?)top:60px',
               r'\1top:46%;transform:translateY(-50%)', html)

    # K / ends recap: remove <div class="ends"> ... </div> (one level, no nested div)
    html = sub('K ends',
               r'<div class="ends">(?:(?!</div>).)*?(?:<span\b[^>]*>(?:(?!</span>).)*?</span>\s*)+</div>',
               '', html, flags=re.S)

    # D,F / confirm beat: remove <li ...>...你确认之前，什么都不会运行...</li>
    html = sub('DF confirm-beat',
               r'<li\b[^>]*>(?:(?!</li>).)*?什么都不会运行(?:(?!</li>).)*?</li>\s*',
               '', html, flags=re.S)

    # G / data-cursor confirm
    html = sub('G cursor', r'\s*data-cursor="\d+:confirm"', '', html)
    # E,G / strip |NN-NN:confirm from data-rings
    html = sub('EG ring-confirm', r'\|\d+-\d+:confirm', '', html)
    # E,G / strip |NN:foot@.. from data-focus (the confirm-beat's focus)
    html = sub('EG foot-focus', r'\|\d+:foot@[0-9.]+L?', '', html)

    # I / 简短而具体： prefix
    html = sub('I jianduan', r'简短而具体[：:，、]\s*', '', html)

    return html, counts

def main():
    if len(sys.argv) < 2:
        print("usage: refine_decks.py <file> [--write]"); sys.exit(1)
    path = sys.argv[1]; write = '--write' in sys.argv[2:]
    with open(path, encoding='utf-8') as f: src = f.read()
    # contract guard: scene count + data-seconds must be unchanged
    scenes_before = src.count('class="scene')
    ds_before = re.findall(r'data-seconds="[^"]*"', src)
    out, counts = refine(src)
    scenes_after = out.count('class="scene')
    ds_after = re.findall(r'data-seconds="[^"]*"', out)
    ok = (scenes_before == scenes_after and ds_before == ds_after)
    tag = 'OK' if ok else 'CONTRACT-VIOLATION'
    print(f"[{tag}] {path}  scenes {scenes_before}->{scenes_after}  "
          f"data-seconds {'same' if ds_before==ds_after else 'CHANGED'}  "
          f"rules={counts}")
    if not ok:
        sys.exit(2)
    if write and counts:
        with open(path, 'w', encoding='utf-8') as f: f.write(out)
        print("   written.")

if __name__ == '__main__':
    main()
