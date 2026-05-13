#!/usr/bin/env bun
//
// Dev-server shim: использует общий код из @lumen/cli.
// Запускается напрямую без CLI:
//   bun tools/dev-server.ts [path] [port]

import { startDevServer } from "../packages/lumen-cli/src/dev-server.ts"
import { resolve } from "path"

const root = resolve(Bun.argv[2] ?? "Examples/HelloApp")
const port = Number(Bun.argv[3] ?? 8080)

startDevServer({ root, port })
