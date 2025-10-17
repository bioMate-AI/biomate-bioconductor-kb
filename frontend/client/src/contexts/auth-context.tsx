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
          // TODO: Validate token with backend
          const storedUser = localStorage.getItem('user')
          if (storedUser) {
            setUser(JSON.parse(storedUser))
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
    try {
      // TODO: Replace with actual API call
      const response = await fetch('/api/auth/login', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ email, password })
      })

      if (!response.ok) {
        throw new Error('Login failed')
      }

      const data = await response.json()

      // Store token and user data
      localStorage.setItem('auth_token', data.token)
      localStorage.setItem('user', JSON.stringify(data.user))
      setUser(data.user)

      // Redirect to dashboard
      setLocation('/dashboard')
    } catch (error) {
      // For demo purposes, create a mock user
      console.log('Using mock login')
      const mockUser: User = {
        id: '1',
        email,
        name: 'Dr. Jane Smith',
        role: 'pro',
        subscription: {
          plan: 'Pro',
          status: 'active',
          currentPeriodEnd: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000).toISOString()
        }
      }

      localStorage.setItem('auth_token', 'mock_token_' + Date.now())
      localStorage.setItem('user', JSON.stringify(mockUser))
      setUser(mockUser)
      setLocation('/dashboard')
    }
  }

  const register = async (name: string, email: string, password: string) => {
    try {
      // TODO: Replace with actual API call
      const response = await fetch('/api/auth/register', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ name, email, password })
      })

      if (!response.ok) {
        throw new Error('Registration failed')
      }

      const data = await response.json()

      // Store token and user data
      localStorage.setItem('auth_token', data.token)
      localStorage.setItem('user', JSON.stringify(data.user))
      setUser(data.user)

      // Redirect to pricing to select plan
      setLocation('/pricing')
    } catch (error) {
      // For demo purposes, create a mock user
      console.log('Using mock registration')
      const mockUser: User = {
        id: Date.now().toString(),
        email,
        name,
        role: 'free'
      }

      localStorage.setItem('auth_token', 'mock_token_' + Date.now())
      localStorage.setItem('user', JSON.stringify(mockUser))
      setUser(mockUser)
      setLocation('/pricing')
    }
  }

  const logout = async () => {
    try {
      // TODO: Call backend logout endpoint
      await fetch('/api/auth/logout', {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${localStorage.getItem('auth_token')}`
        }
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
