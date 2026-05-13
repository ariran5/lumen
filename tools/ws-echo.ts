// Tiny WebSocket echo server for PlatformLab demo.
// Use: bun tools/ws-echo.ts [port?=9000]
//
// Echoes back any text message prefixed with "echo: ".
// На каждое подключение шлёт приветствие "hello from lumen ws-echo".
//
// Не зависит от внешних сервисов — раньше демо целился в
// wss://echo.websocket.events, который теперь retired (Heroku app снят).

const PORT = Number(Bun.argv[2] ?? 9000)

const server = Bun.serve({
  port: PORT,
  fetch(req, server) {
    if (server.upgrade(req)) return
    return new Response("ws echo — connect via WebSocket\n", { status: 200 })
  },
  websocket: {
    open(ws) {
      console.log("[ws] open", ws.remoteAddress)
      ws.send("hello from lumen ws-echo")
    },
    message(ws, message) {
      const text = typeof message === "string" ? message : new TextDecoder().decode(message)
      console.log("[ws] ←", text)
      ws.send(`echo: ${text}`)
    },
    close(ws, code, reason) {
      console.log("[ws] close", code, reason)
    },
  },
})

console.log(`ws-echo listening on ws://0.0.0.0:${server.port}`)
