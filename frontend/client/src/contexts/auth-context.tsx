import React, { createContext, useContext, useState, useEffect } from 'react'
import { useLocation } from 'wouter'

interface User {
  id: string
  email: string
  name: string
  role: 'free' | 'pro' | 'team' | 'enterprise'
  subscription?: {
    plan: string
    status: 'active' | 'trialing' | 'canceled' | 'past_due'
    currentPeriodEnd: string
  }
}

interface AuthContextType {
  user: User | null
  isAuthenticated: boolean
  isLoading: boolean
  login: (email: string, password: string) => Promise<void>
  register: (name: string, email: string, password: string) => Promise<void>
  logout: () => Promise<void>
  loginWithGoogle: () => Promise<void>
  loginWithGithub: () => Promise<void>
}

const AuthContext = createContext<AuthContextType | undefined>(undefined)

export function AuthProvider({ children }: { children: React.ReactNode }) {
  const [user, setUser] = useState<User | null>(null)
  const [isLoading, setIsLoading] = useState(true)
  const [, setLocation] = useLocation()

  // Check if user is already logged in on mount
  useEffect(() => {
    const checkAuth = async () => {
      try {
        const token = localStorage.getItem('auth_token')
        if (token) {
          // Validate token with backend
          const response = await fetch('/api/auth/me', {
            headers: {
              'Authorization': `Bearer ${token}`
            },
            credentials: 'include'
          })

          if (response.ok) {
            const data = await response.json()
            if (data.success && data.user) {
              // Map backend user to frontend User type
              const user: User = {
                id: data.user.id,
                email: data.user.email,
                name: data.user.fullName,
                role: data.subscription?.subscriptionTier === 'enterprise' ? 'enterprise' :
                      data.subscription?.subscriptionTier === 'professional' ? 'pro' :
                      data.subscription?.subscriptionTier === 'team' ? 'team' : 'free',
                subscription: data.subscription ? {
                  plan: data.subscription.subscriptionTier || 'Free',
                  status: data.subscription.trialing ? 'trialing' : data.subscription.subscriptionStatus,
                  currentPeriodEnd: data.user.currentPeriodEnd ||
                                   (data.subscription.trialing ? data.user.trialEndsAt : new Date().toISOString())
                } : undefined
              }
              setUser(user)
            }
          } else {
            // Token invalid or expired, clear storage
            localStorage.removeItem('auth_token')
            localStorage.removeItem('user')
          }
        }
      } catch (error) {
        console.error('Auth check failed:', error)
        // Clear storage on error
        localStorage.removeItem('auth_token')
        localStorage.removeItem('user')
      } finally {
        setIsLoading(false)
      }
    }

    checkAuth()
  }, [])

  const login = async (email: string, password: string) => {
    try {
      const response = await fetch('/api/auth/login', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        credentials: 'include', // Include cookies
        body: JSON.stringify({ email, password })
      })

      const data = await response.json()

      if (!response.ok) {
        // Handle trial expired error
        if (data.error === 'TRIAL_EXPIRED') {
          throw new Error('Your trial has expired. Please subscribe to continue.')
        }
        throw new Error(data.error || 'Login failed')
      }

      if (!data.success) {
        throw new Error(data.error || 'Login failed')
      }

      // Store token and user data
      localStorage.setItem('auth_token', data.token)
      localStorage.setItem('user', JSON.stringify(data.user))

      // Map backend user to frontend User type
      const user: User = {
        id: data.user.id,
        email: data.user.email,
        name: data.user.fullName,
        role: data.subscription?.subscriptionTier === 'enterprise' ? 'enterprise' :
              data.subscription?.subscriptionTier === 'professional' ? 'pro' :
              data.subscription?.subscriptionTier === 'team' ? 'team' : 'free',
        subscription: data.subscription ? {
          plan: data.subscription.subscriptionTier || 'Free',
          status: data.subscription.trialing ? 'trialing' : data.subscription.subscriptionStatus,
          currentPeriodEnd: data.user.currentPeriodEnd ||
                           (data.subscription.trialing ? data.user.trialEndsAt : new Date().toISOString())
        } : undefined
      }

      setUser(user)

      // Redirect to dashboard
      setLocation('/dashboard')
    } catch (error) {
      console.error('Login error:', error)
      throw error
    }
  }

  const register = async (name: string, email: string, password: string) => {
    try {
      const response = await fetch('/api/auth/register', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        credentials: 'include', // Include cookies
        body: JSON.stringify({
          fullName: name,
          email,
          password,
          termsAccepted: true // Assume terms accepted if registering
        })
      })

      const data = await response.json()

      if (!response.ok) {
        throw new Error(data.error || 'Registration failed')
      }

      if (!data.success) {
        throw new Error(data.error || 'Registration failed')
      }

      // Store token and user data
      localStorage.setItem('auth_token', data.token)
      localStorage.setItem('user', JSON.stringify(data.user))

      // Map backend user to frontend User type
      const user: User = {
        id: data.user.id,
        email: data.user.email,
        name: data.user.fullName,
        role: 'free', // New registrations start on free trial
        subscription: {
          plan: 'Trial',
          status: 'trialing',
          currentPeriodEnd: data.user.trialEndsAt
        }
      }

      setUser(user)

      // Redirect to dashboard (skip pricing for now)
      setLocation('/dashboard')
    } catch (error) {
      console.error('Registration error:', error)
      throw error
    }
  }

  const logout = async () => {
    try {
      await fetch('/api/auth/logout', {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${localStorage.getItem('auth_token')}`
        },
        credentials: 'include'
      })
    } catch (error) {
      console.error('Logout error:', error)
    } finally {
      // Clear local storage
      localStorage.removeItem('auth_token')
      localStorage.removeItem('user')
      setUser(null)
      setLocation('/home')
    }
  }

  const loginWithGoogle = async () => {
    try {
      // TODO: Implement Google OAuth
      window.location.href = '/api/auth/google'
    } catch (error) {
      console.error('Google login failed:', error)
      throw error
    }
  }

  const loginWithGithub = async () => {
    try {
      // TODO: Implement GitHub OAuth
      window.location.href = '/api/auth/github'
    } catch (error) {
      console.error('GitHub login failed:', error)
      throw error
    }
  }

  return (
    <AuthContext.Provider
      value={{
        user,
        isAuthenticated: !!user,
        isLoading,
        login,
        register,
        logout,
        loginWithGoogle,
        loginWithGithub
      }}
    >
      {children}
    </AuthContext.Provider>
  )
}

export function useAuth() {
  const context = useContext(AuthContext)
  if (context === undefined) {
    throw new Error('useAuth must be used within an AuthProvider')
  }
  return context
}
