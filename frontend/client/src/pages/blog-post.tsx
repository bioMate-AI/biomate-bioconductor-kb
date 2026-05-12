import { useLocation, useRoute } from "wouter"
import ReactMarkdown from "react-markdown"
import remarkGfm from "remark-gfm"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { ArrowLeft } from "lucide-react"

// Embedded post content (Vite ?raw imports — no fetch, no Vite serving concerns)
import ivonescimabMd from "@/blog-content/ivonescimab-bispecific-format.md?raw"
import cartMd from "@/blog-content/in-vivo-cart-capstan.md?raw"
import verveMd from "@/blog-content/verve-102-base-edit.md?raw"
import glp1Md from "@/blog-content/glp1-modality-race.md?raw"
import q4Md from "@/blog-content/q4-2024-fda-validation.md?raw"

const POST_CONTENT: Record<string, string> = {
  "ivonescimab-bispecific-format": ivonescimabMd,
  "in-vivo-cart-capstan": cartMd,
  "verve-102-base-edit": verveMd,
  "glp1-modality-race": glp1Md,
  "q4-2024-fda-validation": q4Md,
}

const POST_META: Record<string, { title: string; date: string; tag: string }> = {
  "ivonescimab-bispecific-format": {
    title: "What atlas data would have told Akeso about Ivonescimab — before HARMONi-2",
    date: "May 12, 2026",
    tag: "Bispecifics",
  },
  "in-vivo-cart-capstan": {
    title: "In vivo CAR-T's hardest problem isn't biology — it's multi-modality co-design",
    date: "May 12, 2026",
    tag: "Cell therapy",
  },
  "verve-102-base-edit": {
    title: "VERVE-102 is the gene editing trial everyone's watching — here's what BioMate would have designed",
    date: "May 12, 2026",
    tag: "Gene editing",
  },
  "glp1-modality-race": {
    title: "Tirzepatide for obesity, retatrutide for MASH: BioMate's GLP-1 bake-off",
    date: "May 12, 2026",
    tag: "Metabolic",
  },
  "q4-2024-fda-validation": {
    title: "BioMate would have predicted every Q4 2024 FDA approval — here's the panel",
    date: "May 12, 2026",
    tag: "Validation",
  },
}

function stripHeaderLines(md: string): string {
  // Drop the top H1 + the italic author/date line so the page header isn't duplicated
  const lines = md.split("\n")
  let i = 0
  while (i < lines.length && (lines[i].startsWith("# ") || lines[i].startsWith("*") || lines[i].trim() === "")) {
    i++
  }
  return lines.slice(i).join("\n")
}

export default function BlogPostPage() {
  const [, params] = useRoute<{ slug: string }>("/blog/:slug")
  const [, setLocation] = useLocation()
  const slug = params?.slug ?? ""
  const meta = POST_META[slug]
  const rawContent = POST_CONTENT[slug]

  if (!meta || !rawContent) {
    return (
      <div className="max-w-3xl mx-auto px-6 py-20">
        <p className="text-muted-foreground mb-4">Post not found.</p>
        <Button variant="link" onClick={() => setLocation("/blog")}>
          <ArrowLeft className="mr-2 h-4 w-4" /> Back to blog
        </Button>
      </div>
    )
  }

  const content = stripHeaderLines(rawContent)

  return (
    <div className="min-h-screen bg-background">
      <article className="max-w-3xl mx-auto px-6 py-16">
        <Button
          variant="link"
          className="px-0 mb-6"
          onClick={() => setLocation("/blog")}
        >
          <ArrowLeft className="mr-2 h-4 w-4" /> Back to all posts
        </Button>

        <header className="mb-10 space-y-3">
          <div className="flex items-center gap-3">
            <Badge variant="outline" className="text-xs font-normal">
              {meta.tag}
            </Badge>
            <span className="text-xs text-muted-foreground">{meta.date}</span>
          </div>
          <h1 className="text-3xl md:text-4xl font-bold tracking-tight leading-tight">
            {meta.title}
          </h1>
          <p className="text-sm text-muted-foreground">BioMate Research Team</p>
        </header>

        <div className="prose prose-neutral dark:prose-invert max-w-none prose-headings:tracking-tight prose-pre:bg-muted prose-pre:text-foreground">
          <ReactMarkdown remarkPlugins={[remarkGfm]}>{content}</ReactMarkdown>
        </div>
      </article>
    </div>
  )
}
