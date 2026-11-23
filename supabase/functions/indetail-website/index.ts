const PROJECT_URL = "https://hulfgxqbdliaxulqjunj.supabase.co";
const BUCKET = "indetail-website";
const REVALIDATE = new Set([
  "index.html",
  "flutter_bootstrap.js",
  "flutter_service_worker.js",
  "main.dart.js",
  "version.json",
  "manifest.json",
]);

const MIME: Record<string, string> = {
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".json": "application/json; charset=utf-8",
  ".wasm": "application/wasm",
  ".png": "image/png",
  ".otf": "font/otf",
  ".frag": "text/plain; charset=utf-8",
  ".ico": "image/x-icon",
  ".css": "text/css",
  ".svg": "image/svg+xml",
  ".txt": "text/plain; charset=utf-8",
  ".bin": "application/octet-stream",
};

Deno.serve(async (req: Request) => {
  if (req.method !== "GET" && req.method !== "HEAD") {
    return new Response("Method not allowed", {
      status: 405,
      headers: { "Allow": "GET, HEAD", "X-Content-Type-Options": "nosniff" },
    });
  }

  const url = new URL(req.url);
  const segments = url.pathname.split("/").filter(Boolean);
  const slugIndex = segments.lastIndexOf("indetail-website");
  const assetSegments = slugIndex >= 0
    ? segments.slice(slugIndex + 1)
    : segments[0] === "functions" && segments[1] === "v1"
    ? segments.slice(3)
    : segments;

  let objectPath: string;
  try {
    objectPath = decodeURIComponent(assetSegments.join("/")) || "index.html";
  } catch {
    return new Response("Bad path", { status: 400 });
  }

  const parts = objectPath.split("/");
  if (
    objectPath.includes("\\") ||
    parts.some((part) => part === "." || part === ".." || part.length === 0) ||
    objectPath.includes("\0")
  ) {
    return new Response("Bad path", { status: 400 });
  }

  const encodedPath = parts.map((part) => encodeURIComponent(part)).join("/");
  const asset = await fetch(
    `${PROJECT_URL}/storage/v1/object/public/${BUCKET}/${encodedPath}`,
    { method: req.method },
  );
  const extension = objectPath.includes(".")
    ? objectPath.slice(objectPath.lastIndexOf(".")).toLowerCase()
    : "";
  const mimeType = MIME[extension] ?? "application/octet-stream";
  const headers = new Headers({
    "Content-Type": mimeType,
    "X-Content-Type-Options": "nosniff",
    "Cache-Control": REVALIDATE.has(objectPath)
      ? "no-cache, no-store, must-revalidate"
      : "public, max-age=31536000, immutable",
  });

  const body = req.method === "HEAD"
    ? null
    : extension === ".html"
    ? await asset.text()
    : asset.body;
  const response = new Response(body, {
    status: asset.status,
    headers,
  });
  response.headers.set("Content-Type", mimeType);
  return response;
});
