// Tiny JSON HTTP router with per-IP token-bucket rate limiting and CORS (spec §14.3:
// rate-limit all endpoints). No framework: keeps the server image small and the surface obvious.
import { createServer, type IncomingMessage, type Server, type ServerResponse } from "node:http";

export interface Req {
  method: string;
  path: string;
  params: Record<string, string>;
  body: Record<string, unknown>;
  headers: IncomingMessage["headers"];
  ip: string;
}

export type Handler = (req: Req) => Promise<{ status?: number; body: unknown }>;

export class HttpError extends Error {
  constructor(
    readonly status: number,
    readonly code: string,
  ) {
    super(code);
  }
}

interface Route {
  method: string;
  parts: string[];
  handler: Handler;
}

export class Router {
  private readonly routes: Route[] = [];
  private readonly buckets = new Map<string, { tokens: number; at: number }>();

  constructor(
    private readonly ratePerSec = 10,
    private readonly burst = 30,
    private readonly allowOrigin = "*",
  ) {}

  on(method: string, path: string, handler: Handler): this {
    this.routes.push({ method, parts: path.split("/").filter(Boolean), handler });
    return this;
  }

  listen(port: number, host = "0.0.0.0"): Promise<Server> {
    const server = createServer((req, res) => void this.handle(req, res));
    return new Promise((resolve) => server.listen(port, host, () => resolve(server)));
  }

  private allow(ip: string): boolean {
    const now = Date.now() / 1000;
    const b = this.buckets.get(ip) ?? { tokens: this.burst, at: now };
    b.tokens = Math.min(this.burst, b.tokens + (now - b.at) * this.ratePerSec);
    b.at = now;
    if (b.tokens < 1) {
      this.buckets.set(ip, b);
      return false;
    }
    b.tokens -= 1;
    this.buckets.set(ip, b);
    if (this.buckets.size > 10000) this.buckets.clear();
    return true;
  }

  private async handle(req: IncomingMessage, res: ServerResponse): Promise<void> {
    res.setHeader("Access-Control-Allow-Origin", this.allowOrigin);
    res.setHeader("Access-Control-Allow-Headers", "authorization, content-type");
    res.setHeader("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS");
    if (req.method === "OPTIONS") {
      res.writeHead(204).end();
      return;
    }
    const ip = req.socket.remoteAddress ?? "?";
    const send = (status: number, body: unknown): void => {
      res.writeHead(status, { "content-type": "application/json" }).end(JSON.stringify(body));
    };
    if (!this.allow(ip)) return send(429, { error: "rate_limited" });
    const url = new URL(req.url ?? "/", "http://x");
    const parts = url.pathname.split("/").filter(Boolean);
    const route = this.routes.find(
      (r) =>
        r.method === req.method &&
        r.parts.length === parts.length &&
        r.parts.every((p, i) => p.startsWith(":") || p === parts[i]),
    );
    if (!route) return send(404, { error: "not_found" });
    const params: Record<string, string> = {};
    route.parts.forEach((p, i) => {
      if (p.startsWith(":")) params[p.slice(1)] = decodeURIComponent(parts[i]!);
    });
    let body: Record<string, unknown> = {};
    if (req.method === "POST" || req.method === "PUT") {
      const chunks: Buffer[] = [];
      let size = 0;
      for await (const c of req) {
        size += (c as Buffer).length;
        if (size > 32768) return send(413, { error: "too_large" });
        chunks.push(c as Buffer);
      }
      if (size > 0) {
        try {
          body = JSON.parse(Buffer.concat(chunks).toString("utf8")) as Record<string, unknown>;
        } catch {
          return send(400, { error: "bad_json" });
        }
      }
    }
    try {
      const out = await route.handler({
        method: req.method ?? "GET",
        path: url.pathname,
        params,
        body,
        headers: req.headers,
        ip,
      });
      send(out.status ?? 200, out.body);
    } catch (e) {
      const status = (e as { status?: number }).status ?? 500;
      const code = (e as { code?: string }).code ?? "internal";
      if (status >= 500)
        console.error(
          JSON.stringify({
            level: "error",
            msg: "api error",
            path: url.pathname,
            error: String(e),
          }),
        );
      send(status, { error: status >= 500 ? "internal" : code });
    }
  }
}
