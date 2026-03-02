import { useLocation } from "wouter"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Progress } from "@/components/ui/progress"
import { StatusBadge } from "@/components/ui/status-badge"
import {
  ArrowRight,
  Workflow,
  FileText,
  TrendingUp,
  Clock,
  Star,
  CreditCard
} from "lucide-react"

export default function DashboardPage() {
  const [, setLocation] = useLocation()

  const recentWorkflows = [
    {
      id: "1",
      name: "DIA-LCMS Proteomics Analysis",
      status: "completed",
      date: "2 hours ago",
      results: "4,521 proteins identified"
    },
    {
      id: "2",
      name: "RNA-Seq Differential Expression",
      status: "running",
      date: "30 minutes ago",
      progress: 65
    },
    {
      id: "3",
      name: "Genomic Variant Calling",
      status: "completed",
      date: "Yesterday",
      results: "1,234 variants detected"
    }
  ]

  const quickActions = [
    {
      icon: Workflow,
      title: "New Workflow",
      description: "Start a new analysis",
      action: () => setLocation('/')
    },
    {
      icon: FileText,
      title: "View Projects",
      description: "Manage your projects",
      action: () => setLocation('/projects')
    },
    {
      icon: Star,
      title: "Browse Tools",
      description: "Explore available tools",
      action: () => setLocation('/')
    }
  ]

  const stats = [
    { label: "Workflows Run", value: "127", trend: "+12%" },
    { label: "Storage Used", value: "24.3 GB", trend: "50 GB limit" },
    { label: "Team Members", value: "5", trend: "10 max" },
    { label: "API Calls", value: "8.2K", trend: "+23%" }
  ]

  return (
    <div className="min-h-screen bg-background">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-12">
        {/* Header */}
        <div className="mb-8">
          <h1 className="text-4xl font-bold mb-2">Welcome back, Dr. Smith</h1>
          <p className="text-muted-foreground">
            Here's what's happening with your research today.
          </p>
        </div>

        {/* Quick Stats */}
        <div className="grid md:grid-cols-2 lg:grid-cols-4 gap-6 mb-8">
          {stats.map((stat, index) => (
            <Card key={index}>
              <CardHeader className="pb-2">
                <CardDescription>{stat.label}</CardDescription>
              </CardHeader>
              <CardContent>
                <div className="flex items-baseline justify-between">
                  <div className="text-3xl font-bold">{stat.value}</div>
                  <Badge variant="secondary" className="text-xs">
                    {stat.trend}
                  </Badge>
                </div>
              </CardContent>
            </Card>
          ))}
        </div>

        <div className="grid lg:grid-cols-3 gap-8">
          {/* Main Content */}
          <div className="lg:col-span-2 space-y-8">
            {/* Recent Workflows */}
            <Card>
              <CardHeader>
                <div className="flex items-center justify-between">
                  <CardTitle>Recent Workflows</CardTitle>
                  <Button variant="ghost" size="sm" onClick={() => setLocation('/')}>
                    View All
                    <ArrowRight className="ml-2 h-4 w-4" />
                  </Button>
                </div>
              </CardHeader>
              <CardContent className="space-y-4">
                {recentWorkflows.map((workflow) => (
                  <div
                    key={workflow.id}
                    className="flex items-start justify-between p-4 border rounded-lg hover:bg-accent transition-colors cursor-pointer"
                    onClick={() => setLocation('/')}
                  >
                    <div className="flex-1">
                      <div className="flex items-center gap-2 mb-1">
                        <h4 className="font-semibold">{workflow.name}</h4>
                        <StatusBadge
                          status={workflow.status === "completed" ? "success" : "running"}
                        >
                          {workflow.status}
                        </StatusBadge>
                      </div>
                      <div className="flex items-center gap-2 text-sm text-muted-foreground">
                        <Clock className="h-3 w-3" />
                        <span>{workflow.date}</span>
                      </div>
                      {workflow.status === "running" && workflow.progress !== undefined && (
                        <div className="mt-2">
                          <Progress value={workflow.progress} className="h-2" />
                          <p className="text-xs text-muted-foreground mt-1">
                            {workflow.progress}% complete
                          </p>
                        </div>
                      )}
                      {workflow.status === "completed" && workflow.results && (
                        <p className="text-sm text-muted-foreground mt-1">
                          {workflow.results}
                        </p>
                      )}
                    </div>
                  </div>
                ))}
              </CardContent>
            </Card>

            {/* Usage & Limits */}
            <Card>
              <CardHeader>
                <CardTitle>Usage & Limits</CardTitle>
                <CardDescription>Your current plan: Pro</CardDescription>
              </CardHeader>
              <CardContent className="space-y-4">
                <div>
                  <div className="flex justify-between text-sm mb-2">
                    <span>Storage</span>
                    <span className="text-muted-foreground">24.3 GB / 50 GB</span>
                  </div>
                  <Progress value={48.6} />
                </div>
                <div>
                  <div className="flex justify-between text-sm mb-2">
                    <span>Team Members</span>
                    <span className="text-muted-foreground">5 / 10</span>
                  </div>
                  <Progress value={50} />
                </div>
                <div>
                  <div className="flex justify-between text-sm mb-2">
                    <span>API Calls (this month)</span>
                    <span className="text-muted-foreground">8,234 / Unlimited</span>
                  </div>
                  <Progress value={100} />
                </div>
                <Button
                  variant="outline"
                  className="w-full"
                  onClick={() => setLocation('/pricing')}
                >
                  <TrendingUp className="mr-2 h-4 w-4" />
                  Upgrade Plan
                </Button>
              </CardContent>
            </Card>
          </div>

          {/* Sidebar */}
          <div className="space-y-8">
            {/* Quick Actions */}
            <Card>
              <CardHeader>
                <CardTitle>Quick Actions</CardTitle>
              </CardHeader>
              <CardContent className="space-y-2">
                {quickActions.map((action, index) => (
                  <Button
                    key={index}
                    variant="outline"
                    className="w-full justify-start"
                    onClick={action.action}
                  >
                    <action.icon className="mr-3 h-4 w-4" />
                    <div className="text-left">
                      <div className="font-semibold">{action.title}</div>
                      <div className="text-xs text-muted-foreground">
                        {action.description}
                      </div>
                    </div>
                  </Button>
                ))}
              </CardContent>
            </Card>

            {/* Subscription Info */}
            <Card>
              <CardHeader>
                <CardTitle className="flex items-center gap-2">
                  <CreditCard className="h-5 w-5" />
                  Subscription
                </CardTitle>
              </CardHeader>
              <CardContent className="space-y-4">
                <div>
                  <div className="text-sm text-muted-foreground mb-1">Current Plan</div>
                  <div className="font-semibold">Pro Plan</div>
                </div>
                <div>
                  <div className="text-sm text-muted-foreground mb-1">Next Billing Date</div>
                  <div className="font-semibold">November 17, 2025</div>
                </div>
                <div>
                  <div className="text-sm text-muted-foreground mb-1">Amount</div>
                  <div className="font-semibold">$49.00/month</div>
                </div>
                <Button variant="outline" className="w-full" size="sm">
                  Manage Subscription
                </Button>
              </CardContent>
            </Card>

            {/* Help & Resources */}
            <Card>
              <CardHeader>
                <CardTitle>Help & Resources</CardTitle>
              </CardHeader>
              <CardContent className="space-y-3">
                <a
                  href="/blog"
                  className="block text-sm text-primary hover:underline"
                >
                  → Read our latest blog posts
                </a>
                <a
                  href="/contact"
                  className="block text-sm text-primary hover:underline"
                >
                  → Contact support
                </a>
              </CardContent>
            </Card>
          </div>
        </div>
      </div>
    </div>
  )
}
