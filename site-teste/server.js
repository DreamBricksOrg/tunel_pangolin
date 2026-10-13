// Site de teste para o túnel Pangolin. Sem dependências: node server.js
const http = require("http");

const PORT = process.env.PORT || 3000;

const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]);

const server = http.createServer((req, res) => {
  if (req.url === "/api/ping") {
    res.writeHead(200, { "Content-Type": "application/json" });
    return res.end(JSON.stringify({ ok: true, time: new Date().toISOString() }));
  }

  const rows = Object.entries(req.headers)
    .map(([k, v]) => `<tr><td>${esc(k)}</td><td>${esc(v)}</td></tr>`)
    .join("");
  const viaTunnel = Boolean(req.headers["x-forwarded-for"]);

  res.writeHead(200, { "Content-Type": "text/html; charset=utf-8" });
  res.end(`<!doctype html>
<html lang="pt-BR">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Site de teste</title>
<style>
  body { font-family: system-ui, sans-serif; max-width: 760px; margin: 40px auto; padding: 0 16px; background: #f6f7f9; color: #1d2330; }
  .badge { display: inline-block; padding: 6px 12px; border-radius: 999px; font-weight: 600; color: #fff; background: ${viaTunnel ? "#1f9d55" : "#6b7280"}; }
  table { width: 100%; border-collapse: collapse; background: #fff; font-size: 14px; }
  td { border-bottom: 1px solid #e5e7eb; padding: 6px 8px; vertical-align: top; word-break: break-all; }
  td:first-child { font-weight: 600; width: 35%; }
  button { padding: 8px 14px; border: 0; border-radius: 6px; background: #2563eb; color: #fff; cursor: pointer; }
  code { background: #e5e7eb; padding: 2px 6px; border-radius: 4px; }
</style>
</head>
<body>
  <h1>Funcionou! 🎉</h1>
  <p><span class="badge">${viaTunnel ? "Acessado pelo túnel" : "Acesso local"}</span></p>
  <p>Host: <code>${esc(req.headers.host)}</code> · Servido pelo seu PC às ${new Date().toLocaleTimeString("pt-BR")}</p>
  <p><button onclick="ping()">Testar /api/ping</button> <span id="out"></span></p>
  <h2>Headers recebidos</h2>
  <table>${rows}</table>
<script>
  async function ping() {
    const t = performance.now();
    const r = await fetch("/api/ping").then((r) => r.json());
    document.getElementById("out").textContent = (r.ok ? "ok" : "erro") + " em " + Math.round(performance.now() - t) + " ms";
  }
</script>
</body>
</html>`);
});

server.listen(PORT, () => console.log(`Site de teste em http://localhost:${PORT}`));
