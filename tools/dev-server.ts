#!/usr/bin/env bun
//
// Lumen dev server — serves a fast-app folder over HTTP.
// Usage:
//   bun tools/dev-server.ts [path] [port]
//
//   bun tools/dev-server.ts Examples/HelloApp 8080
//
// Routes:
//   GET /.well-known/lumen.json  →  ./manifest.json
//   GET /<anything>              →  ./<anything>

import { join, resolve } from "path"
import { existsSync, statSync } from "fs"

const root = resolve(Bun.argv[2] ?? "Examples/HelloApp")
const port = Number(Bun.argv[3] ?? 8080)

if (!existsSync(root) || !statSync(root).isDirectory()) {
  console.error(`✗ not a directory: ${root}`)
  process.exit(1)
}

if (!existsSync(join(root, "manifest.json"))) {
  console.error(`✗ no manifest.json in ${root}`)
  process.exit(1)
}

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, OPTIONS",
  "Access-Control-Allow-Headers": "*",
  "Cache-Control": "no-store",
}

const server = Bun.serve({
  port,
  fetch(req) {
    const url = new URL(req.url)
    let pathname = url.pathname

    if (pathname === "/.well-known/lumen.json") {
      pathname = "/manifest.json"
    }
    if (pathname === "/") {
      pathname = "/manifest.json"
    }

    const filePath = join(root, pathname)

    // Light path traversal guard
    if (!filePath.startsWith(root)) {
      return new Response("forbidden", { status: 403, headers: cors })
    }

    const file = Bun.file(filePath)
    const stamp = new Date().toLocaleTimeString()
    console.log(`[${stamp}] GET ${pathname}`)

    return new Response(file, { headers: cors })
  },
  error() {
    return new Response("not found", { status: 404, headers: cors })
  },
})

console.log(`Lumen dev server`)
console.log(`  serving: ${root}`)
console.log(`  manifest: http://localhost:${port}/.well-known/lumen.json`)
console.log(`  entry:    http://localhost:${port}/index.js`)
console.log(`  open in Lumen:  http://localhost:${port}`)
console.log()
