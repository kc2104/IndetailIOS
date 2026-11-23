import { CANVASKIT_MODULES } from "lib/canvaskit-modules.js";

export const access = "public";

const ALLOWED_MODULES = new Set([
  "canvaskit.js",
  "skwasm.js",
  "skwasm_heavy.js",
  "chromium/canvaskit.js",
  "webparagraph/canvaskit.js",
]);

export default async function (req, res) {
  const segments = Array.isArray(req.params.path) ? req.params.path : [];
  const moduleName = segments.join("/");
  const source = CANVASKIT_MODULES[moduleName];
  if (!ALLOWED_MODULES.has(moduleName) || typeof source !== "string") {
    return res.status(404).send("Not found");
  }

  res.setHeader("Content-Type", "text/javascript; charset=utf-8");
  res.setHeader("Cache-Control", "public, max-age=31536000, immutable");
  res.setHeader("X-Content-Type-Options", "nosniff");
  return res.send(source);
}
