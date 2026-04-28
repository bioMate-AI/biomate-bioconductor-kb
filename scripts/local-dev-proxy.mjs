/**
 * local-dev-proxy.mjs
 * Single entry point for local BioMate development.
 *
 * Port 3000 (this proxy):
 *   /              → serves webpage_design/index.html  (marketing homepage)
 *   /*.html        → serves webpage_design/*.html      (other marketing pages)
 *   /images/*      → serves webpage_design/images/*    (marketing assets)
 *   everything else → proxied to React app at port 5000
 *
 * Usage:  node scripts/local-dev-proxy.mjs
 */

import http from 'http'
import fs   from 'fs'
import path from 'path'
import { fileURLToPath } from 'url'

const __dirname  = path.dirname(fileURLToPath(import.meta.url))
const REPO_ROOT  = path.resolve(__dirname, '..')
const MARKETING  = path.join(REPO_ROOT, 'webpage_design')
const APP_PORT   = 5000   // React/Express dev server
const PROXY_PORT = 4000   // This proxy — open http://localhost:3000 in browser

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.css':  'text/css',
  '.js':   'application/javascript',
  '.png':  'image/png',
  '.jpg':  'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.svg':  'image/svg+xml',
  '.ico':  'image/x-icon',
  '.woff2':'font/woff2',
  '.woff': 'font/woff',
}

function serveStatic(res, filePath) {
  const ext  = path.extname(filePath).toLowerCase()
  const mime = MIME[ext] || 'application/octet-stream'
  const data = fs.readFileSync(filePath)
  res.writeHead(200, { 'Content-Type': mime, 'Content-Length': data.length })
  res.end(data)
}

function proxyToApp(req, res) {
  const options = {
    hostname: '127.0.0.1',
    port:     APP_PORT,
    path:     req.url,
    method:   req.method,
    headers:  { ...req.headers, host: `localhost:${APP_PORT}` },
  }
  const proxy = http.request(options, (pr) => {
    res.writeHead(pr.statusCode, pr.headers)
    pr.pipe(res, { end: true })
  })
  proxy.on('error', (e) => {
    res.writeHead(502)
    res.end(`App server unavailable (port ${APP_PORT}): ${e.message}`)
  })
  req.pipe(proxy, { end: true })
}

const server = http.createServer((req, res) => {
  const urlPath = req.url.split('?')[0]

  // Root → marketing homepage
  if (urlPath === '/' || urlPath === '/index.html') {
    return serveStatic(res, path.join(MARKETING, 'index.html'))
  }

  // Other marketing HTML pages
  if (urlPath.endsWith('.html')) {
    const candidate = path.join(MARKETING, urlPath)
    if (fs.existsSync(candidate)) return serveStatic(res, candidate)
  }

  // Marketing static assets (images, etc.)
  if (urlPath.startsWith('/images/')) {
    const candidate = path.join(MARKETING, urlPath)
    if (fs.existsSync(candidate)) return serveStatic(res, candidate)
  }

  // Everything else → React app + API
  proxyToApp(req, res)
})

server.listen(PROXY_PORT, () => {
  console.log(`\n  BioMate local dev proxy running`)
  console.log(`  ────────────────────────────────`)
  console.log(`  Marketing site:  http://localhost:${PROXY_PORT}/`)
  console.log(`  Platform app:    http://localhost:${PROXY_PORT}/app`)
  console.log(`  (React app must be running on port ${APP_PORT})\n`)
})
