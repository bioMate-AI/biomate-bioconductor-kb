/**
 * API Client for BioMate
 *
 * This file contains all API calls to the backend.
 * TODO: Update BASE_URL when deploying to production
 */

const BASE_URL = import.meta.env.VITE_API_URL || '/api'

class ApiClient {
  private getHeaders(): HeadersInit {
    const token = localStorage.getItem('auth_token')
    return {
      'Content-Type': 'application/json',
      ...(token && { 'Authorization': `Bearer ${token}` })
    }
  }

  async request<T>(
    endpoint: string,
    options: RequestInit = {}
  ): Promise<T> {
    const url = `${BASE_URL}${endpoint}`

    const config: RequestInit = {
      ...options,
      headers: {
        ...this.getHeaders(),
        ...options.headers
      }
    }

    try {
      const response = await fetch(url, config)

      if (!response.ok) {
        const error = await response.json().catch(() => ({
          message: 'An error occurred'
        }))
        throw new Error(error.message || `HTTP ${response.status}`)
      }

      return await response.json()
    } catch (error) {
      console.error('API request failed:', error)
      throw error
    }
  }

  // Auth endpoints
  async login(email: string, password: string) {
    return this.request('/auth/login', {
      method: 'POST',
      body: JSON.stringify({ email, password })
    })
  }

  async register(name: string, email: string, password: string) {
    return this.request('/auth/register', {
      method: 'POST',
      body: JSON.stringify({ name, email, password })
    })
  }

  async logout() {
    return this.request('/auth/logout', {
      method: 'POST'
    })
  }

  async forgotPassword(email: string) {
    return this.request('/auth/forgot-password', {
      method: 'POST',
      body: JSON.stringify({ email })
    })
  }

  async resetPassword(token: string, password: string) {
    return this.request('/auth/reset-password', {
      method: 'POST',
      body: JSON.stringify({ token, password })
    })
  }

  async verifyEmail(token: string) {
    return this.request('/auth/verify-email', {
      method: 'POST',
      body: JSON.stringify({ token })
    })
  }

  // Contact form
  async submitContactForm(data: {
    name: string
    email: string
    company?: string
    subject: string
    message: string
  }) {
    return this.request('/contact', {
      method: 'POST',
      body: JSON.stringify(data)
    })
  }

  // Subscription endpoints
  async createCheckoutSession(plan: string) {
    return this.request<{ sessionId: string }>('/subscriptions/checkout', {
      method: 'POST',
      body: JSON.stringify({ plan })
    })
  }

  async getSubscription() {
    return this.request('/subscriptions/current', {
      method: 'GET'
    })
  }

  async cancelSubscription() {
    return this.request('/subscriptions/cancel', {
      method: 'POST'
    })
  }

  // User endpoints
  async getCurrentUser() {
    return this.request('/users/me', {
      method: 'GET'
    })
  }

  async updateUser(data: Partial<{
    name: string
    email: string
  }>) {
    return this.request('/users/me', {
      method: 'PATCH',
      body: JSON.stringify(data)
    })
  }
}

export const api = new ApiClient()
