import React, { createContext, useContext, useState, useEffect } from 'react'
import { useLocation } from 'wouter'
import { analytics } from '@/lib/analytics'

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

function mapResponseToUser(data: any): User {
  return {
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
}

export function AuthProvider({ children }: { children: React.ReactNode }) {
  const [user, setUser] = useState<User | null>(null)
  const [isLoading, setIsLoading] = useState(true)
  const [, setLocation] = useLocation()

  // Check if user is already logged in on mount.
  // The httpOnly cookie (biomate_token) is sent automatically with credentials: 'include'.
  // Also clear any stale localStorage entries left over from the old token-in-storage approach.
  useEffect(() => {
    const checkAuth = async () => {
      // Clean up legacy localStorage keys
      localStorage.removeItem('auth_token')
      localStorage.removeItem('user')

      try {
        const response = await fetch('/api/auth/me', {
          credentials: 'include'
        })

        if (response.ok) {
          const data = await response.json()
          if (data.success && data.user) {
            setUser(mapResponseToUser(data))
          }
        }
      } catch (error) {
        console.error('Auth check failed:', error)
      } finally {
        setIsLoading(false)
      }
    }

    checkAuth()
  }, [])

  const login = async (email: string, password: string) => {
    const response = await fetch('/api/auth/login', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      credentials: 'include', // server sets httpOnly biomate_token cookie
      body: JSON.stringify({ email, password })
    })

    const data = await response.json()

    if (!response.ok) {
      if (data.error === 'TRIAL_EXPIRED') {
        throw new Error('Your trial has expired. Please subscribe to continue.')
      }
      if (data.error === 'TOO_MANY_ATTEMPTS') {
        throw new Error('Too many login attempts. Please try again in 15 minutes.')
      }
      throw new Error(data.message || data.error || 'Login failed')
    }

    if (!data.success) {
      throw new Error(data.error || 'Login failed')
    }

    const mappedUser = mapResponseToUser(data)
    setUser(mappedUser)
    analytics.identify(mappedUser.id, { plan: mappedUser.role, email: mappedUser.email, name: mappedUser.name })
    analytics.track('user_logged_in', { plan: mappedUser.role })
    setLocation('/dashboard')
  }

  const register = async (name: string, email: string, password: string) => {
    const response = await fetch('/api/auth/register', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      credentials: 'include', // server sets httpOnly biomate_token cookie
      body: JSON.stringify({
        fullName: name,
        email,
        password,
        termsAccepted: true
      })
    })

    const data = await response.json()

    if (!response.ok) {
      throw new Error(data.error || 'Registration failed')
    }

    if (!data.success) {
      throw new Error(data.error || 'Registration failed')
    }

    const newUser = {
      id: data.user.id,
      email: data.user.email,
      name: data.user.fullName,
      role: 'free' as const,
      subscription: {
        plan: 'Trial',
        status: 'trialing' as const,
        currentPeriodEnd: data.user.trialEndsAt
      }
    }
    setUser(newUser)
    analytics.identify(newUser.id, { plan: newUser.role, email: newUser.email, name: newUser.name })
    analytics.track('user_registered', { plan: newUser.role })

    setLocation('/dashboard')
  }

  const logout = async () => {
    analytics.track('user_logged_out')
    analytics.reset()
    try {
      await fetch('/api/auth/logout', {
        method: 'POST',
        credentials: 'include' // server clears the httpOnly cookie
      })
    } catch (error) {
      console.error('Logout error:', error)
    } finally {
      setUser(null)
      setLocation('/login')
    }
  }

  const loginWithGoogle = async () => {
    window.location.href = '/api/auth/google'
  }

  const loginWithGithub = async () => {
    window.location.href = '/api/auth/github'
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
