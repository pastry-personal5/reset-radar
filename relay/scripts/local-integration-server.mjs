import { createServer } from "node:http";
import { unstable_dev } from "wrangler";

const port = Number.parseInt(process.argv[2] ?? "", 10);
const writeTokenDigest = process.env.WRITE_TOKEN_DIGEST;
const adminTokenDigest = process.env.ADMIN_TOKEN_DIGEST;

if (!Number.isInteger(port) || port < 1024 || port > 65534 ||
    !/^[0-9a-f]{64}$/.test(writeTokenDigest ?? "") ||
    !/^[0-9a-f]{64}$/.test(adminTokenDigest ?? "")) {
  process.exitCode = 2;
} else {
  const worker = await unstable_dev("src/index.ts", {
    config: "wrangler.jsonc",
    experimental: {
      disableExperimentalWarning: true,
      disableDevRegistry: true,
      showInteractiveDevSession: false,
      watch: false,
    },
    inspect: false,
    inspectorPort: port + 1,
    ip: "127.0.0.1",
    local: true,
    logLevel: "none",
    port: 0,
    vars: {
      ADMIN_TOKEN_DIGEST: adminTokenDigest,
      WRITE_TOKEN_DIGEST: writeTokenDigest,
    },
  });

  const server = createServer(async (request, response) => {
    try {
      const chunks = [];
      for await (const chunk of request) chunks.push(chunk);
      const body = chunks.length === 0 ? undefined : Buffer.concat(chunks);
      const forwarded = await worker.fetch(`http://reset-radar.local${request.url}`, {
        body,
        headers: request.headers,
        method: request.method,
      });
      const responseBody = Buffer.from(await forwarded.arrayBuffer());
      // Undici transparently decodes a compressed Miniflare response but retains its encoding
      // header. Do not send an already-decoded body with that stale header to URLSession.
      const headers = new Headers(forwarded.headers);
      headers.delete("content-encoding");
      headers.delete("content-length");
      headers.delete("transfer-encoding");
      response.writeHead(forwarded.status, Object.fromEntries(headers));
      response.end(responseBody);
    } catch {
      response.writeHead(502);
      response.end();
    }
  });
  await new Promise((resolve, reject) => {
    server.once("error", reject);
    server.listen(port, "127.0.0.1", resolve);
  });

  let stopping = false;
  const stop = async () => {
    if (stopping) return;
    stopping = true;
    await new Promise((resolve) => server.close(resolve));
    await worker.stop();
    process.exit(0);
  };
  process.once("SIGINT", () => void stop());
  process.once("SIGTERM", () => void stop());
  // `waitUntilExit()` is tied to Wrangler's interactive session and may resolve when a test
  // runner has no TTY. Keep the programmatic worker strongly owned until an explicit signal.
  await new Promise(() => {});
}
