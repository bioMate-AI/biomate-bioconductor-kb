import { Button } from "@/components/ui/button"
import { Card, CardContent, CardHeader } from "@/components/ui/card"
import { useLocation } from "wouter"
import { Target, Users, Lightbulb, Award } from "lucide-react"

export default function AboutPage() {
  const [, setLocation] = useLocation()

  const team = [
    {
      name: "Dr. Sarah Chen",
      role: "Co-Founder & CEO",
      image: "https://api.dicebear.com/7.x/avataaars/svg?seed=Sarah",
      bio: "Former Principal Investigator at Stanford, PhD in Computational Biology"
    },
    {
      name: "Dr. Michael Rodriguez",
      role: "Co-Founder & CTO",
      image: "https://api.dicebear.com/7.x/avataaars/svg?seed=Michael",
      bio: "Ex-Google AI researcher, PhD in Computer Science from MIT"
    },
    {
      name: "Dr. Emily Watson",
      role: "Head of Research",
      image: "https://api.dicebear.com/7.x/avataaars/svg?seed=Emily",
      bio: "Proteomics expert from Johns Hopkins, 15+ years in drug discovery"
    },
    {
      name: "Dr. James Liu",
      role: "Head of AI",
      image: "https://api.dicebear.com/7.x/avataaars/svg?seed=James",
      bio: "Former DeepMind researcher, PhD in Machine Learning"
    },
    {
      name: "Dr. Maria Garcia",
      role: "Head of Product",
      image: "https://api.dicebear.com/7.x/avataaars/svg?seed=Maria",
      bio: "Product leader with 10+ years in biotech, MBA from Harvard"
    },
    {
      name: "Dr. Robert Kim",
      role: "Head of Security",
      image: "https://api.dicebear.com/7.x/avataaars/svg?seed=Robert",
      bio: "Cybersecurity expert, former CISO at biotech companies"
    }
  ]

  const values = [
    {
      icon: Target,
      title: "Scientific Excellence",
      description: "We maintain the highest standards of scientific rigor in everything we build"
    },
    {
      icon: Users,
      title: "Researcher-First",
      description: "Every feature is designed with researchers' needs and workflows in mind"
    },
    {
      icon: Lightbulb,
      title: "Innovation",
      description: "We push the boundaries of what's possible with AI and biomedicine"
    },
    {
      icon: Award,
      title: "Trust & Security",
      description: "Your data security and privacy are our top priorities"
    }
  ]

  return (
    <div className="min-h-screen bg-background">
      {/* Hero Section */}
      <section className="relative overflow-hidden border-b">
        <div className="absolute inset-0 bg-gradient-to-br from-blue-500/10 via-purple-500/10 to-pink-500/10" />
        <div className="relative max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-24">
          <div className="text-center space-y-6">
            <h1 className="text-5xl font-bold">
              Accelerating biomedical research
              <br />
              <span className="text-transparent bg-clip-text bg-gradient-to-r from-blue-500 via-purple-500 to-pink-500">
                with artificial intelligence
              </span>
            </h1>
            <p className="text-xl text-muted-foreground max-w-3xl mx-auto">
              BioMate was founded by researchers who experienced firsthand the challenges of modern biomedical research.
              We're building the tools we wish we had.
            </p>
          </div>
        </div>
      </section>

      {/* Mission Section */}
      <section className="py-24 border-b">
        <div className="max-w-4xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="text-center mb-12">
            <h2 className="text-4xl font-bold mb-4">Our Mission</h2>
            <p className="text-xl text-muted-foreground">
              To empower researchers with AI-powered tools that accelerate discovery and improve human health
            </p>
          </div>

          <div className="prose prose-lg dark:prose-invert max-w-none">
            <p>
              The complexity of biomedical research has grown exponentially. Researchers today must navigate massive datasets,
              complex workflows, and rapidly evolving methodologies. Traditional tools haven't kept pace.
            </p>
            <p>
              BioMate was born from a simple observation: artificial intelligence could transform how researchers work,
              but existing solutions were either too generic, too expensive, or too complex.
            </p>
            <p>
              We built BioMate to be different. A platform that combines cutting-edge AI with deep domain expertise in biomedicine.
              Tools that are powerful yet intuitive. Technology that augments human intelligence rather than replacing it.
            </p>
            <p>
              Today, we're proud to serve thousands of researchers across hundreds of institutions worldwide.
              But we're just getting started.
            </p>
          </div>
        </div>
      </section>

      {/* Values Section */}
      <section className="py-24 border-b">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="text-center mb-16">
            <h2 className="text-4xl font-bold mb-4">Our Values</h2>
            <p className="text-xl text-muted-foreground">
              The principles that guide everything we do
            </p>
          </div>

          <div className="grid md:grid-cols-2 lg:grid-cols-4 gap-8">
            {values.map((value, index) => (
              <Card key={index}>
                <CardHeader>
                  <div className="w-12 h-12 rounded-lg bg-primary/10 flex items-center justify-center mb-4">
                    <value.icon className="h-6 w-6 text-primary" />
                  </div>
                  <h3 className="text-xl font-semibold mb-2">{value.title}</h3>
                  <p className="text-muted-foreground">{value.description}</p>
                </CardHeader>
              </Card>
            ))}
          </div>
        </div>
      </section>

      {/* Team Section */}
      <section className="py-24 border-b">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="text-center mb-16">
            <h2 className="text-4xl font-bold mb-4">Meet Our Team</h2>
            <p className="text-xl text-muted-foreground">
              World-class researchers and engineers building the future of biomedicine
            </p>
          </div>

          <div className="grid md:grid-cols-2 lg:grid-cols-3 gap-8">
            {team.map((member, index) => (
              <Card key={index}>
                <CardContent className="p-6">
                  <div className="text-center">
                    <img
                      src={member.image}
                      alt={member.name}
                      className="w-24 h-24 rounded-full mx-auto mb-4"
                    />
                    <h3 className="text-xl font-semibold mb-1">{member.name}</h3>
                    <p className="text-primary font-medium mb-3">{member.role}</p>
                    <p className="text-sm text-muted-foreground">{member.bio}</p>
                  </div>
                </CardContent>
              </Card>
            ))}
          </div>
        </div>
      </section>

      {/* Stats Section */}
      <section className="py-24 border-b">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="grid grid-cols-2 md:grid-cols-4 gap-8 text-center">
            <div>
              <div className="text-4xl font-bold text-primary mb-2">2021</div>
              <div className="text-muted-foreground">Founded</div>
            </div>
            <div>
              <div className="text-4xl font-bold text-primary mb-2">10,000+</div>
              <div className="text-muted-foreground">Researchers</div>
            </div>
            <div>
              <div className="text-4xl font-bold text-primary mb-2">500+</div>
              <div className="text-muted-foreground">Institutions</div>
            </div>
            <div>
              <div className="text-4xl font-bold text-primary mb-2">50+</div>
              <div className="text-muted-foreground">Countries</div>
            </div>
          </div>
        </div>
      </section>

      {/* CTA Section */}
      <section className="py-24">
        <div className="max-w-4xl mx-auto px-4 sm:px-6 lg:px-8 text-center">
          <h2 className="text-4xl font-bold mb-4">Join us in transforming research</h2>
          <p className="text-xl text-muted-foreground mb-8">
            Whether you're a researcher, institution, or partner, we'd love to hear from you
          </p>
          <div className="flex flex-col sm:flex-row gap-4 justify-center">
            <Button size="lg" onClick={() => setLocation('/register')}>
              Start Free Trial
            </Button>
            <Button size="lg" variant="outline" onClick={() => setLocation('/contact')}>
              Contact Us
            </Button>
          </div>
        </div>
      </section>
    </div>
  )
}
