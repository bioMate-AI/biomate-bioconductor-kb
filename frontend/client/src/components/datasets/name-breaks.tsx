/**
 * File names in a narrow box: a long name like `brunello_library_screen_day14.count.txt` may only
 * break AFTER a name separator (_ . - /), never inside a word. Pair with `[overflow-wrap:break-word]`
 * (not `anywhere`: that lets the box shrink to one character and wrap every letter) so a single
 * separator-free run longer than the box is the only thing ever split.
 */
import { Fragment, type ReactNode } from "react"

/** The name with a `<wbr>` after each separator — the only places it may wrap. */
export function breakAtSeparators(name: string): ReactNode {
  const parts = name.split(/(?<=[_.\-/])/)
  if (parts.length <= 1) return name
  return parts.map((p, i) => (
    <Fragment key={i}>{p}{i < parts.length - 1 ? <wbr /> : null}</Fragment>
  ))
}

/** "pairs/S1_R1.fastq.gz" → { folders: ["pairs"], base: "S1_R1.fastq.gz" }. */
export function splitPath(name: string): { folders: string[]; base: string } {
  const parts = name.split("/").filter(Boolean)
  const base = parts.pop() ?? name
  return { folders: parts, base }
}
