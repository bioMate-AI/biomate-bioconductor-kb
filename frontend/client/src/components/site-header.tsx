import { useState } from "react"
import { useLocation } from "wouter"
import { useAuth } from "@/contexts/auth-context"
import { Button } from "@/components/ui/button"
import {
  NavigationMenu,
  NavigationMenuContent,
  NavigationMenuItem,
  NavigationMenuLink,
  NavigationMenuList,
  NavigationMenuTrigger,
} from "@/components/ui/navigation-menu"
import { Sheet, SheetContent, SheetTrigger } from "@/components/ui/sheet"
import { Menu, X, User } from "lucide-react"
import { ThemeToggle } from "./theme-toggle"
import { UX_FEEDBACK_ADMIN_ENABLED } from "@/lib/feature-flags"
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu"

interface SiteHeaderProps {
  isAuthenticated?: boolean
}

export function SiteHeader({ isAuthenticated: isAuthenticatedProp }: SiteHeaderProps) {
  const [, setLocation] = useLocation()
  const { user, isAuthenticated: authState, logout } = useAuth()
  const isAdmin = (user?.role as string | undefined) === 'admin'
  const [mobileMenuOpen, setMobileMenuOpen] = useState(false)

  // Use prop if provided, otherwise use auth state
  const isAuthenticated = isAuthenticatedProp !== undefined ? isAuthenticatedProp : authState

  const handleLogout = async () => {
    await logout()
    setMobileMenuOpen(false)
  }

  const navigation = {
    main: [
      { name: "About", href: "/about" },
      // { name: "Pricing", href: "/pricing" }, // disabled until payment flow is fully tested
      { name: "Blog", href: "/blog" },
    ],
    authenticated: [
      // { name: "Dashboard", href: "/dashboard" }, // not ready
      { name: "Platform", href: "/" }
    ]
  }

  const handleNavigation = (href: string) => {
    setLocation(href)
    setMobileMenuOpen(false)
  }

  return (
    <header className="sticky top-0 z-50 w-full border-b bg-background/95 backdrop-blur supports-[backdrop-filter]:bg-background/60">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <div className="flex h-16 items-center justify-between">
          {/* Logo */}
          <div className="flex items-center">
            <button
              onClick={() => handleNavigation(isAuthenticated ? '/' : '/register')}
              className="flex items-center space-x-2"
            >
              <img src="/logo.png" alt="BioMate AI" className="h-12 w-auto" />
            </button>
          </div>

          {/* Desktop Navigation */}
          <nav className="hidden md:flex items-center space-x-6">
            {isAuthenticated ? (
              <>
                {navigation.authenticated.map((item) => (
                  <Button
                    key={item.name}
                    variant="ghost"
                    onClick={() => handleNavigation(item.href)}
                  >
                    {item.name}
                  </Button>
                ))}
              </>
            ) : (
              <>
                {navigation.main.map((item) => (
                  <Button
                    key={item.name}
                    variant="ghost"
                    onClick={() => handleNavigation(item.href)}
                  >
                    {item.name}
                  </Button>
                ))}
              </>
            )}
          </nav>

          {/* Right Side Actions */}
          <div className="flex items-center space-x-4">
            <ThemeToggle />

            {isAuthenticated ? (
              <DropdownMenu>
                <DropdownMenuTrigger asChild>
                  <Button variant="ghost" size="icon" className="hidden md:flex">
                    <User className="h-5 w-5" />
                  </Button>
                </DropdownMenuTrigger>
                <DropdownMenuContent align="end">
                  <DropdownMenuLabel>
                    {user?.name || 'My Account'}
                  </DropdownMenuLabel>
                  <DropdownMenuSeparator />
                  {/* <DropdownMenuItem onClick={() => handleNavigation('/dashboard')}>
                    Dashboard
                  </DropdownMenuItem> */}
                  <DropdownMenuItem onClick={() => handleNavigation('/')}>
                    Platform
                  </DropdownMenuItem>
                  <DropdownMenuItem onClick={() => handleNavigation('/projects')}>
                    Projects
                  </DropdownMenuItem>
                  {isAdmin && UX_FEEDBACK_ADMIN_ENABLED && (
                    <DropdownMenuItem onClick={() => handleNavigation('/admin/feedback-dashboard')}>
                      UX Feedback
                    </DropdownMenuItem>
                  )}
                  <DropdownMenuSeparator />
                  <DropdownMenuItem onClick={handleLogout}>
                    Logout
                  </DropdownMenuItem>
                </DropdownMenuContent>
              </DropdownMenu>
            ) : (
              <>
                <Button
                  variant="ghost"
                  onClick={() => handleNavigation('/login')}
                  className="hidden md:flex"
                >
                  Login
                </Button>
                <Button
                  onClick={() => handleNavigation('/register')}
                  className="hidden md:flex"
                >
                  Start Free Trial
                </Button>
              </>
            )}

            {/* Mobile Menu */}
            <Sheet open={mobileMenuOpen} onOpenChange={setMobileMenuOpen}>
              <SheetTrigger asChild className="md:hidden">
                <Button variant="ghost" size="icon">
                  {mobileMenuOpen ? (
                    <X className="h-5 w-5" />
                  ) : (
                    <Menu className="h-5 w-5" />
                  )}
                </Button>
              </SheetTrigger>
              <SheetContent side="right" className="w-64">
                <div className="flex flex-col space-y-4 mt-8">
                  {isAuthenticated ? (
                    <>
                      {navigation.authenticated.map((item) => (
                        <Button
                          key={item.name}
                          variant="ghost"
                          className="justify-start"
                          onClick={() => handleNavigation(item.href)}
                        >
                          {item.name}
                        </Button>
                      ))}
                      {isAdmin && UX_FEEDBACK_ADMIN_ENABLED && (
                        <Button
                          variant="ghost"
                          className="justify-start"
                          onClick={() => handleNavigation('/admin/feedback-dashboard')}
                        >
                          UX Feedback
                        </Button>
                      )}
                      <Button
                        variant="outline"
                        onClick={handleLogout}
                      >
                        Logout
                      </Button>
                    </>
                  ) : (
                    <>
                      {navigation.main.map((item) => (
                        <Button
                          key={item.name}
                          variant="ghost"
                          className="justify-start"
                          onClick={() => handleNavigation(item.href)}
                        >
                          {item.name}
                        </Button>
                      ))}
                      <Button
                        variant="ghost"
                        className="justify-start"
                        onClick={() => handleNavigation('/login')}
                      >
                        Login
                      </Button>
                      <Button onClick={() => handleNavigation('/register')}>
                        Start Free Trial
                      </Button>
                    </>
                  )}
                </div>
              </SheetContent>
            </Sheet>
          </div>
        </div>
      </div>
    </header>
  )
}
