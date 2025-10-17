import { useState } from "react"
import { useLocation } from "wouter"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Card, CardContent, CardDescription, CardFooter, CardHeader, CardTitle } from "@/components/ui/card"
import { Badge } from "@/components/ui/badge"
import { Search, Calendar, Clock, ArrowRight } from "lucide-react"

export default function BlogPage() {
  const [, setLocation] = useLocation()
  const [searchQuery, setSearchQuery] = useState("")

  // Mock blog posts data
  const blogPosts = [
    {
      slug: "ai-proteomics-breakthrough",
      title: "How AI is Revolutionizing Proteomics Analysis",
      excerpt: "Discover how artificial intelligence and machine learning are transforming the way researchers analyze protein data and identify novel biomarkers.",
      author: "Dr. Sarah Chen",
      authorImage: "https://api.dicebear.com/7.x/avataaars/svg?seed=Sarah",
      date: "2025-10-15",
      readTime: "8 min read",
      category: "Research",
      image: "https://images.unsplash.com/photo-1532187863486-abf9dbad1b69?w=800&h=400&fit=crop"
    },
    {
      slug: "workflow-automation-guide",
      title: "A Complete Guide to Workflow Automation in Bioinformatics",
      excerpt: "Learn how to automate complex bioinformatics pipelines and save valuable research time with our comprehensive guide.",
      author: "Prof. Michael Rodriguez",
      authorImage: "https://api.dicebear.com/7.x/avataaars/svg?seed=Michael",
      date: "2025-10-12",
      readTime: "12 min read",
      category: "Tutorial",
      image: "https://images.unsplash.com/photo-1451187580459-43490279c0fa?w=800&h=400&fit=crop"
    },
    {
      slug: "genomics-best-practices",
      title: "Best Practices for Genomics Data Analysis",
      excerpt: "Essential guidelines and recommendations for conducting robust genomics research and ensuring reproducible results.",
      author: "Dr. Emily Watson",
      authorImage: "https://api.dicebear.com/7.x/avataaars/svg?seed=Emily",
      date: "2025-10-08",
      readTime: "10 min read",
      category: "Research",
      image: "https://images.unsplash.com/photo-1576086213369-97a306d36557?w=800&h=400&fit=crop"
    },
    {
      slug: "machine-learning-drug-discovery",
      title: "Machine Learning Applications in Drug Discovery",
      excerpt: "Explore how ML algorithms are accelerating drug discovery by predicting molecular interactions and identifying promising compounds.",
      author: "Dr. James Liu",
      authorImage: "https://api.dicebear.com/7.x/avataaars/svg?seed=James",
      date: "2025-10-05",
      readTime: "15 min read",
      category: "AI & ML",
      image: "https://images.unsplash.com/photo-1587825140708-dfaf72ae4b04?w=800&h=400&fit=crop"
    },
    {
      slug: "collaborative-research-tools",
      title: "The Future of Collaborative Research in Biomedicine",
      excerpt: "How modern cloud-based platforms are enabling seamless collaboration between research teams across the globe.",
      author: "Dr. Maria Garcia",
      authorImage: "https://api.dicebear.com/7.x/avataaars/svg?seed=Maria",
      date: "2025-10-01",
      readTime: "6 min read",
      category: "Collaboration",
      image: "https://images.unsplash.com/photo-1522071820081-009f0129c71c?w=800&h=400&fit=crop"
    },
    {
      slug: "data-security-biomedical-research",
      title: "Data Security and Privacy in Biomedical Research",
      excerpt: "Understanding HIPAA compliance, data encryption, and best practices for protecting sensitive research data.",
      author: "Dr. Robert Kim",
      authorImage: "https://api.dicebear.com/7.x/avataaars/svg?seed=Robert",
      date: "2025-09-28",
      readTime: "7 min read",
      category: "Security",
      image: "https://images.unsplash.com/photo-1563986768609-322da13575f3?w=800&h=400&fit=crop"
    }
  ]

  const categories = ["All", "Research", "Tutorial", "AI & ML", "Collaboration", "Security"]
  const [selectedCategory, setSelectedCategory] = useState("All")

  const filteredPosts = blogPosts.filter(post => {
    const matchesSearch = post.title.toLowerCase().includes(searchQuery.toLowerCase()) ||
                         post.excerpt.toLowerCase().includes(searchQuery.toLowerCase())
    const matchesCategory = selectedCategory === "All" || post.category === selectedCategory
    return matchesSearch && matchesCategory
  })

  return (
    <div className="min-h-screen bg-background py-12">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        {/* Header */}
        <div className="text-center mb-12">
          <h1 className="text-4xl font-bold mb-4">BioMate Blog</h1>
          <p className="text-xl text-muted-foreground max-w-2xl mx-auto">
            Insights, tutorials, and news from the world of biomedical research and AI
          </p>
        </div>

        {/* Search and Filters */}
        <div className="mb-8 space-y-4">
          <div className="relative max-w-xl mx-auto">
            <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 h-4 w-4 text-muted-foreground" />
            <Input
              placeholder="Search articles..."
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              className="pl-10"
            />
          </div>

          <div className="flex flex-wrap gap-2 justify-center">
            {categories.map((category) => (
              <Button
                key={category}
                variant={selectedCategory === category ? "default" : "outline"}
                size="sm"
                onClick={() => setSelectedCategory(category)}
              >
                {category}
              </Button>
            ))}
          </div>
        </div>

        {/* Featured Post */}
        {filteredPosts.length > 0 && (
          <Card className="mb-12 overflow-hidden hover:shadow-lg transition-shadow cursor-pointer"
                onClick={() => setLocation(`/blog/${filteredPosts[0].slug}`)}>
            <div className="md:flex">
              <div className="md:w-1/2">
                <img
                  src={filteredPosts[0].image}
                  alt={filteredPosts[0].title}
                  className="w-full h-64 md:h-full object-cover"
                />
              </div>
              <div className="md:w-1/2 p-8">
                <Badge className="mb-4">{filteredPosts[0].category}</Badge>
                <CardHeader className="p-0 mb-4">
                  <CardTitle className="text-3xl mb-2">{filteredPosts[0].title}</CardTitle>
                  <CardDescription className="text-base">{filteredPosts[0].excerpt}</CardDescription>
                </CardHeader>
                <div className="flex items-center gap-4 text-sm text-muted-foreground">
                  <div className="flex items-center gap-2">
                    <img
                      src={filteredPosts[0].authorImage}
                      alt={filteredPosts[0].author}
                      className="w-8 h-8 rounded-full"
                    />
                    <span>{filteredPosts[0].author}</span>
                  </div>
                  <div className="flex items-center gap-1">
                    <Calendar className="h-4 w-4" />
                    <span>{new Date(filteredPosts[0].date).toLocaleDateString()}</span>
                  </div>
                  <div className="flex items-center gap-1">
                    <Clock className="h-4 w-4" />
                    <span>{filteredPosts[0].readTime}</span>
                  </div>
                </div>
                <Button className="mt-6" onClick={() => setLocation(`/blog/${filteredPosts[0].slug}`)}>
                  Read Article
                  <ArrowRight className="ml-2 h-4 w-4" />
                </Button>
              </div>
            </div>
          </Card>
        )}

        {/* Blog Posts Grid */}
        <div className="grid md:grid-cols-2 lg:grid-cols-3 gap-8">
          {filteredPosts.slice(1).map((post) => (
            <Card
              key={post.slug}
              className="overflow-hidden hover:shadow-lg transition-shadow cursor-pointer flex flex-col"
              onClick={() => setLocation(`/blog/${post.slug}`)}
            >
              <img
                src={post.image}
                alt={post.title}
                className="w-full h-48 object-cover"
              />
              <CardHeader>
                <Badge className="w-fit mb-2">{post.category}</Badge>
                <CardTitle className="text-xl">{post.title}</CardTitle>
                <CardDescription>{post.excerpt}</CardDescription>
              </CardHeader>
              <CardFooter className="mt-auto flex-col items-start gap-4">
                <div className="flex items-center gap-2 text-sm text-muted-foreground w-full">
                  <img
                    src={post.authorImage}
                    alt={post.author}
                    className="w-6 h-6 rounded-full"
                  />
                  <span>{post.author}</span>
                </div>
                <div className="flex items-center gap-4 text-sm text-muted-foreground w-full">
                  <div className="flex items-center gap-1">
                    <Calendar className="h-3 w-3" />
                    <span>{new Date(post.date).toLocaleDateString()}</span>
                  </div>
                  <div className="flex items-center gap-1">
                    <Clock className="h-3 w-3" />
                    <span>{post.readTime}</span>
                  </div>
                </div>
              </CardFooter>
            </Card>
          ))}
        </div>

        {filteredPosts.length === 0 && (
          <div className="text-center py-12">
            <p className="text-muted-foreground">No articles found matching your search.</p>
          </div>
        )}
      </div>
    </div>
  )
}
