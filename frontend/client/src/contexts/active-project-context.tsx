/**
 * Active-project context.
 *
 * Holds the user's currently-selected project (or null). Persisted to
 * localStorage so a page refresh preserves the selection. Consumers
 * (chat-interface, etc.) read activeProjectId from here and thread it
 * into the chat-stream context — that's what activates the project
 * framework.
 *
 * See docs/20260612_DATASET_STORAGE_AND_SESSION_BOUNDARIES.md: a chat
 * is project-scoped only when this id is non-null. Null is the default
 * and explicitly valid — standalone chats stay project-less.
 */
import React, { createContext, useCallback, useContext, useEffect, useMemo, useState } from 'react'
import { api } from '@/lib/api'
import { useAuth } from './auth-context'

interface Project {
  id: string
  name: string
  description?: string | null
  status: 'active' | 'archived' | 'completed'
  primaryDomain?: string | null
  createdAt?: string
}

interface ActiveProjectContextValue {
  activeProjectId: string | null
  activeProject: Project | null
  projects: Project[]
  loading: boolean
  setActiveProjectId: (id: string | null) => void
  refresh: () => Promise<void>
  createProject: (name: string, opts?: { description?: string; primaryDomain?: string }) => Promise<Project>
  archiveProject: (id: string) => Promise<void>
  deleteProject: (id: string) => Promise<void>
  renameProject: (id: string, name: string) => Promise<void>
}

const STORAGE_KEY = 'biomate-active-project-id'

const ActiveProjectContext = createContext<ActiveProjectContextValue | null>(null)

export function ActiveProjectProvider({ children }: { children: React.ReactNode }) {
  const { user } = useAuth()
  const [projects, setProjects] = useState<Project[]>([])
  const [loading, setLoading] = useState(false)
  const [activeProjectId, setActiveProjectIdState] = useState<string | null>(() => {
    try {
      return typeof window !== 'undefined' ? localStorage.getItem(STORAGE_KEY) : null
    } catch {
      return null
    }
  })

  const setActiveProjectId = useCallback((id: string | null) => {
    setActiveProjectIdState(id)
    try {
      if (id) localStorage.setItem(STORAGE_KEY, id)
      else localStorage.removeItem(STORAGE_KEY)
    } catch {
      // ignore localStorage failures (private mode, etc.)
    }
  }, [])

  const refresh = useCallback(async () => {
    if (!user) {
      setProjects([])
      return
    }
    setLoading(true)
    try {
      const res = await api.listProjects('active')
      setProjects(res.projects ?? [])
      // If the persisted active project is no longer in the active list,
      // clear it — the user may have archived/deleted it elsewhere.
      if (activeProjectId && !(res.projects ?? []).some((p) => p.id === activeProjectId)) {
        setActiveProjectId(null)
      }
    } catch (e) {
      console.warn('[active-project] refresh failed:', e)
      setProjects([])
    } finally {
      setLoading(false)
    }
  }, [user, activeProjectId, setActiveProjectId])

  useEffect(() => {
    void refresh()
  }, [user]) // intentional: refresh on user identity change

  const createProject = useCallback(
    async (name: string, opts?: { description?: string; primaryDomain?: string }) => {
      const res = await api.createProject({ name, ...(opts ?? {}) })
      const created = res.project as Project
      setProjects((prev) => [created, ...prev])
      return created
    },
    []
  )

  const archiveProject = useCallback(
    async (id: string) => {
      await api.archiveProject(id)
      setProjects((prev) => prev.filter((p) => p.id !== id))
      if (activeProjectId === id) setActiveProjectId(null)
    },
    [activeProjectId, setActiveProjectId]
  )

  const deleteProject = useCallback(
    async (id: string) => {
      await api.deleteProject(id)
      setProjects((prev) => prev.filter((p) => p.id !== id))
      if (activeProjectId === id) setActiveProjectId(null)
    },
    [activeProjectId, setActiveProjectId]
  )

  const renameProject = useCallback(async (id: string, name: string) => {
    const res = await api.updateProject(id, { name })
    setProjects((prev) => prev.map((p) => (p.id === id ? (res.project as Project) : p)))
  }, [])

  const activeProject = useMemo(
    () => (activeProjectId ? projects.find((p) => p.id === activeProjectId) ?? null : null),
    [activeProjectId, projects]
  )

  const value: ActiveProjectContextValue = {
    activeProjectId,
    activeProject,
    projects,
    loading,
    setActiveProjectId,
    refresh,
    createProject,
    archiveProject,
    deleteProject,
    renameProject,
  }

  return <ActiveProjectContext.Provider value={value}>{children}</ActiveProjectContext.Provider>
}

export function useActiveProject() {
  const ctx = useContext(ActiveProjectContext)
  if (!ctx) {
    throw new Error('useActiveProject must be used inside ActiveProjectProvider')
  }
  return ctx
}
