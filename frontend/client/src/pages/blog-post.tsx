import { useRoute, useLocation } from "wouter"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { Separator } from "@/components/ui/separator"
import { Calendar, Clock, ArrowLeft, Share2, Bookmark } from "lucide-react"
import { Card, CardContent } from "@/components/ui/card"

export default function BlogPostPage() {
  const [, params] = useRoute('/blog/:slug')
  const [, setLocation] = useLocation()

  // Mock blog post data - in real app, fetch based on slug
  const post = {
    slug: params?.slug || "",
    title: "How AI is Revolutionizing Proteomics Analysis",
    excerpt: "Discover how artificial intelligence and machine learning are transforming the way researchers analyze protein data and identify novel biomarkers.",
    content: `
# Introduction

Artificial intelligence and machine learning are fundamentally changing how we approach proteomics analysis. Recent advances in deep learning have enabled researchers to process and analyze protein data at unprecedented scales and speeds.

## The Challenge

Traditional proteomics analysis methods face several key challenges:

- **Data Volume**: Modern mass spectrometry generates terabytes of data
- **Complexity**: Protein interactions and modifications create intricate patterns
- **Time**: Manual analysis can take weeks or months
- **Accuracy**: Human analysis is prone to bias and error

## AI Solutions

Machine learning models can now:

1. **Identify Proteins**: Deep learning algorithms achieve >95% accuracy in protein identification
2. **Predict Structures**: AlphaFold and similar models predict 3D protein structures with atomic accuracy
3. **Discover Biomarkers**: AI can identify novel disease biomarkers from complex datasets
4. **Accelerate Workflows**: Automated pipelines reduce analysis time from weeks to hours

## Real-World Applications

### Cancer Research

AI-powered proteomics has led to the discovery of new cancer biomarkers, enabling earlier detection and personalized treatment strategies.

### Drug Development

Machine learning models predict protein-drug interactions, accelerating the drug discovery process and reducing costs.

### Precision Medicine

Personalized protein profiles help clinicians tailor treatments to individual patients based on their unique molecular signatures.

## Getting Started with BioMate

Our platform makes it easy to leverage AI for your proteomics research:

- Upload your mass spectrometry data
- Choose from pre-configured AI models or train custom ones
- Visualize results in interactive dashboards
- Collaborate with your team in real-time

## Conclusion

The integration of AI into proteomics analysis represents a paradigm shift in biomedical research. As these technologies continue to evolve, we can expect even more breakthroughs in our understanding of protein function and disease mechanisms.

Ready to accelerate your proteomics research? [Start your free trial](/register) today.
    `,
    author: "Dr. Sarah Chen",
    authorBio: "Principal Investigator at Stanford University, specializing in computational proteomics and AI applications in biomedicine.",
    authorImage: "https://api.dicebear.com/7.x/avataaars/svg?seed=Sarah",
    date: "2025-10-15",
    readTime: "8 min read",
    category: "Research",
    image: "https://images.unsplash.com/photo-1532187863486-abf9dbad1b69?w=1200&h=600&fit=crop"
  }

  const relatedPosts = [
    {
      slug: "workflow-automation-guide",
      title: "A Complete Guide to Workflow Automation",
      image: "https://images.unsplash.com/photo-1451187580459-43490279c0fa?w=400&h=200&fit=crop"
    },
    {
      slug: "machine-learning-drug-discovery",
      title: "Machine Learning in Drug Discovery",
      image: "https://images.unsplash.com/photo-1587825140708-dfaf72ae4b04?w=400&h=200&fit=crop"
    }
  ]

  return (
    <div className="min-h-screen bg-background">
      {/* Header Image */}
      <div className="w-full h-96 overflow-hidden">
        <img
          src={post.image}
          alt={post.title}
          className="w-full h-full object-cover"
        />
      </div>

      {/* Content */}
      <div className="max-w-4xl mx-auto px-4 sm:px-6 lg:px-8 py-12">
        <Button
          variant="ghost"
          onClick={() => setLocation('/blog')}
          className="mb-8"
        >
          <ArrowLeft className="mr-2 h-4 w-4" />
          Back to Blog
        </Button>

        <article>
          {/* Header */}
          <header className="mb-8">
            <Badge className="mb-4">{post.category}</Badge>
            <h1 className="text-4xl md:text-5xl font-bold mb-4">{post.title}</h1>
            <p className="text-xl text-muted-foreground mb-6">{post.excerpt}</p>

            <div className="flex items-center justify-between flex-wrap gap-4">
              <div className="flex items-center gap-4">
                <img
                  src={post.authorImage}
                  alt={post.author}
                  className="w-12 h-12 rounded-full"
                />
                <div>
                  <div className="font-semibold">{post.author}</div>
                  <div className="flex items-center gap-4 text-sm text-muted-foreground">
                    <div className="flex items-center gap-1">
                      <Calendar className="h-4 w-4" />
                      <span>{new Date(post.date).toLocaleDateString()}</span>
                    </div>
                    <div className="flex items-center gap-1">
                      <Clock className="h-4 w-4" />
                      <span>{post.readTime}</span>
                    </div>
                  </div>
                </div>
              </div>

              <div className="flex gap-2">
                <Button variant="outline" size="sm">
                  <Bookmark className="h-4 w-4 mr-2" />
                  Save
                </Button>
                <Button variant="outline" size="sm">
                  <Share2 className="h-4 w-4 mr-2" />
                  Share
                </Button>
              </div>
            </div>
          </header>

          <Separator className="my-8" />

          {/* Article Content */}
          <div className="prose prose-lg dark:prose-invert max-w-none">
            {post.content.split('\n').map((paragraph, index) => {
              if (paragraph.startsWith('# ')) {
                return <h1 key={index} className="text-3xl font-bold mt-8 mb-4">{paragraph.slice(2)}</h1>
              } else if (paragraph.startsWith('## ')) {
                return <h2 key={index} className="text-2xl font-bold mt-6 mb-3">{paragraph.slice(3)}</h2>
              } else if (paragraph.startsWith('### ')) {
                return <h3 key={index} className="text-xl font-bold mt-4 mb-2">{paragraph.slice(4)}</h3>
              } else if (paragraph.startsWith('- ')) {
                return <li key={index} className="ml-6 my-2">{paragraph.slice(2)}</li>
              } else if (paragraph.match(/^\d+\. /)) {
                return <li key={index} className="ml-6 my-2">{paragraph.replace(/^\d+\. /, '')}</li>
              } else if (paragraph.trim() !== '') {
                // Handle inline links
                const linkRegex = /\[([^\]]+)\]\(([^)]+)\)/g
                const parts = []
                let lastIndex = 0
                let match

                while ((match = linkRegex.exec(paragraph)) !== null) {
                  if (match.index > lastIndex) {
                    parts.push(paragraph.slice(lastIndex, match.index))
                  }
                  parts.push(
                    <a
                      key={match.index}
                      href={match[2]}
                      className="text-primary hover:underline"
                    >
                      {match[1]}
                    </a>
                  )
                  lastIndex = match.index + match[0].length
                }

                if (lastIndex < paragraph.length) {
                  parts.push(paragraph.slice(lastIndex))
                }

                return <p key={index} className="my-4 text-lg leading-relaxed">{parts.length > 0 ? parts : paragraph}</p>
              }
              return null
            })}
          </div>

          <Separator className="my-8" />

          {/* Author Bio */}
          <Card>
            <CardContent className="p-6">
              <div className="flex gap-4">
                <img
                  src={post.authorImage}
                  alt={post.author}
                  className="w-20 h-20 rounded-full"
                />
                <div>
                  <h3 className="font-semibold text-lg mb-2">About {post.author}</h3>
                  <p className="text-muted-foreground">{post.authorBio}</p>
                </div>
              </div>
            </CardContent>
          </Card>
        </article>

        {/* Related Posts */}
        <div className="mt-16">
          <h2 className="text-2xl font-bold mb-6">Related Articles</h2>
          <div className="grid md:grid-cols-2 gap-6">
            {relatedPosts.map((relatedPost) => (
              <Card
                key={relatedPost.slug}
                className="overflow-hidden hover:shadow-lg transition-shadow cursor-pointer"
                onClick={() => setLocation(`/blog/${relatedPost.slug}`)}
              >
                <img
                  src={relatedPost.image}
                  alt={relatedPost.title}
                  className="w-full h-48 object-cover"
                />
                <CardContent className="p-4">
                  <h3 className="font-semibold">{relatedPost.title}</h3>
                </CardContent>
              </Card>
            ))}
          </div>
        </div>
      </div>
    </div>
  )
}
