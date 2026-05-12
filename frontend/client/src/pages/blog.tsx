import { useLocation } from "wouter"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { Calendar, ArrowRight } from "lucide-react"

const POSTS = [
  {
    slug: "ivonescimab-bispecific-format",
    title: "What atlas data would have told Akeso about Ivonescimab — before HARMONi-2",
    date: "May 12, 2026",
    excerpt:
      "PD-1×VEGF bispecific beat Keytruda head-to-head in HARMONi-2. The CrossMab format choice was correct — and recoverable from atlas data alone.",
    tag: "Bispecifics",
  },
  {
    slug: "in-vivo-cart-capstan",
    title: "In vivo CAR-T's hardest problem isn't biology — it's multi-modality co-design",
    date: "May 12, 2026",
    excerpt:
      "Capstan, Kelonia, Umoja are racing to skip ex vivo manufacturing ($400K-500K/patient → $5-50K). The design problem is LNP × CAR target × architecture, and only multi-modality platforms solve it.",
    tag: "Cell therapy",
  },
  {
    slug: "verve-102-base-edit",
    title: "VERVE-102 is the gene editing trial everyone's watching — here's what BioMate would have designed",
    date: "May 12, 2026",
    excerpt:
      "Verve's in vivo PCSK9 base editing program is the most-watched gene therapy trial in the world. Atlas + editor selection recovers their design exactly.",
    tag: "Gene editing",
  },
  {
    slug: "glp1-modality-race",
    title: "Tirzepatide for obesity, retatrutide for MASH: BioMate's GLP-1 bake-off",
    date: "May 12, 2026",
    excerpt:
      "Every pharma asks 'what's the next GLP-1?' The race is now modality — receptor combination, delivery, indication tradeoffs. We give you the bake-off in 30 seconds.",
    tag: "Metabolic",
  },
  {
    slug: "q4-2024-fda-validation",
    title: "BioMate would have predicted every Q4 2024 FDA approval — here's the panel",
    date: "May 12, 2026",
    excerpt:
      "We ran our atlas-driven modality triage on every Q4 2024 FDA approval. 7/7 verdicts match the documented label safety profile.",
    tag: "Validation",
  },
]

export default function BlogPage() {
  const [, setLocation] = useLocation()

  return (
    <div className="min-h-screen bg-background">
      {/* Hero */}
      <section className="border-b bg-gradient-to-br from-blue-500/5 via-purple-500/5 to-pink-500/5">
        <div className="max-w-5xl mx-auto px-6 py-20 text-center space-y-4">
          <Badge variant="secondary" className="mb-2">Research notes</Badge>
          <h1 className="text-4xl font-bold tracking-tight">BioMate Research Notes</h1>
          <p className="text-lg text-muted-foreground max-w-3xl mx-auto">
            Engineering and scientific deep-dives from the team building
            multi-modality drug development AI. We write up the methods,
            the validation, and the honest limitations.
          </p>
        </div>
      </section>

      {/* Post grid */}
      <section className="max-w-5xl mx-auto px-6 py-16">
        <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
          {POSTS.map((post) => (
            <Card
              key={post.slug}
              className="flex flex-col cursor-pointer hover:shadow-md transition-shadow"
              data-testid={`blog-card-${post.slug}`}
              onClick={() => setLocation(`/blog/${post.slug}`)}
            >
              <CardHeader>
                <div className="flex items-center gap-3 mb-2">
                  <Badge variant="outline" className="text-xs font-normal">
                    {post.tag}
                  </Badge>
                  <span className="text-xs text-muted-foreground inline-flex items-center gap-1">
                    <Calendar className="h-3 w-3" />
                    {post.date}
                  </span>
                </div>
                <CardTitle className="text-lg leading-snug">{post.title}</CardTitle>
              </CardHeader>
              <CardContent className="flex-1 flex flex-col">
                <p className="text-sm text-muted-foreground leading-relaxed flex-1">
                  {post.excerpt}
                </p>
                <Button
                  variant="link"
                  className="px-0 mt-4 self-start"
                  onClick={(e) => {
                    e.stopPropagation()
                    setLocation(`/blog/${post.slug}`)
                  }}
                >
                  Read post <ArrowRight className="ml-1 h-4 w-4" />
                </Button>
              </CardContent>
            </Card>
          ))}
        </div>
      </section>

      {/* CTA */}
      <section className="border-t bg-muted/30">
        <div className="max-w-5xl mx-auto px-6 py-16 text-center space-y-4">
          <h2 className="text-2xl font-semibold">
            Want to see these workflows on your target?
          </h2>
          <p className="text-muted-foreground">
            Open the assistant and try them yourself. The capabilities page lists every workflow.
          </p>
          <Button size="lg" onClick={() => setLocation("/capabilities")}>
            See capabilities <ArrowRight className="ml-2 h-4 w-4" />
          </Button>
        </div>
      </section>
    </div>
  )
}
