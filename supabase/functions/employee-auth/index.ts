const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json; charset=utf-8",
  "Cache-Control": "no-store",
};

const response = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: corsHeaders });

const sha256 = async (value: string): Promise<string> => {
  const bytes = new TextEncoder().encode(value);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest), (part) => part.toString(16).padStart(2, "0")).join("");
};

const requestIp = (request: Request): string => {
  const cloudflare = request.headers.get("cf-connecting-ip")?.trim();
  if (cloudflare) return cloudflare;
  const forwarded = request.headers.get("x-forwarded-for")?.split(",")[0]?.trim();
  return forwarded || "edge-ip-unavailable";
};

const rateLimit = async (
  supabaseUrl: string,
  serviceKey: string,
  bucketKeys: string[],
  limit: number,
  windowSeconds: number,
): Promise<boolean> => {
  const result = await fetch(`${supabaseUrl}/rest/v1/rpc/consume_employee_auth_attempts`, {
    method: "POST",
    headers: {
      apikey: serviceKey,
      Authorization: `Bearer ${serviceKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      p_bucket_keys: bucketKeys,
      p_limit: limit,
      p_window_seconds: windowSeconds,
    }),
  });
  if (!result.ok) return false;
  return (await result.json()) === true;
};

const genericLoginError = () => response({ error: "Employee ID or password is incorrect." }, 401);

Deno.serve(async (request: Request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (request.method !== "POST") return response({ error: "Use POST for this endpoint." }, 405);

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !anonKey || !serviceKey) {
    return response({ error: "Authentication service is not configured." }, 503);
  }

  const declaredLength = Number(request.headers.get("content-length") || 0);
  if (declaredLength > 8192) return response({ error: "Request is too large." }, 413);

  let input: Record<string, unknown>;
  try {
    const raw = await request.text();
    if (raw.length > 8192) return response({ error: "Request is too large." }, 413);
    const parsed = JSON.parse(raw);
    if (parsed === null || Array.isArray(parsed) || typeof parsed !== "object") throw new Error("invalid body");
    input = parsed as Record<string, unknown>;
  } catch {
    return response({ error: "Request body must be valid JSON." }, 400);
  }

  const action = input.action;
  const ipHash = await sha256(requestIp(request));

  if (action === "signup") {
    const displayName = typeof input.displayName === "string" ? input.displayName.trim() : "";
    const email = typeof input.email === "string" ? input.email.trim().toLowerCase() : "";
    const password = typeof input.password === "string" ? input.password : "";
    if (displayName.length < 1 || displayName.length > 80) {
      return response({ error: "Enter a name between 1 and 80 characters." }, 400);
    }
    if (email.length > 254 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
      return response({ error: "Enter a valid email address." }, 400);
    }
    if (password.length < 10 || password.length > 128) {
      return response({ error: "Use a password with at least 10 characters." }, 400);
    }

    const emailHash = await sha256(email);
    const allowed = await rateLimit(
      supabaseUrl,
      serviceKey,
      [`signup:ip:${ipHash}`, `signup:email:${emailHash}`],
      5,
      3600,
    );
    if (!allowed) return response({ error: "Too many signup attempts. Try again later." }, 429);

    const signup = await fetch(`${supabaseUrl}/auth/v1/signup`, {
      method: "POST",
      headers: { apikey: anonKey, Authorization: `Bearer ${anonKey}`, "Content-Type": "application/json" },
      body: JSON.stringify({ email, password, data: { display_name: displayName } }),
    });
    const auth = await signup.json().catch(() => ({}));
    if (!signup.ok || !auth.user?.id || (Array.isArray(auth.user.identities) && auth.user.identities.length === 0)) {
      if (signup.status === 429) return response({ error: "Signup is temporarily limited. Try again later." }, 429);
      return response({ error: "We could not create this account. Check the details or try signing in." }, 400);
    }

    const profile = await fetch(
      `${supabaseUrl}/rest/v1/profiles?select=employee_id&id=eq.${encodeURIComponent(auth.user.id)}&limit=1`,
      { headers: { apikey: serviceKey, Authorization: `Bearer ${serviceKey}` } },
    );
    const profiles = await profile.json().catch(() => []);
    const employeeId = Array.isArray(profiles) ? profiles[0]?.employee_id : null;
    if (!profile.ok || typeof employeeId !== "string" || !/^ids\d{4}$/.test(employeeId)) {
      return response({ error: "Your account was created, but its Employee ID could not be loaded. Contact the INDETAIL Admin." }, 503);
    }

    return response({
      ok: true,
      employee_id: employeeId,
      confirmation_required: !auth.session,
      auth: auth.session ? { ...auth.session, user: auth.user } : null,
    });
  }

  if (action === "login") {
    const employeeId = typeof input.employeeId === "string" ? input.employeeId.trim().toLowerCase() : "";
    const password = typeof input.password === "string" ? input.password : "";
    if (!/^ids\d{4}$/.test(employeeId) || password.length < 1 || password.length > 128) return genericLoginError();

    const idHash = await sha256(employeeId);
    const allowed = await rateLimit(
      supabaseUrl,
      serviceKey,
      [`login:ip:${ipHash}`, `login:id:${idHash}`],
      5,
      900,
    );
    if (!allowed) return response({ error: "Too many sign-in attempts. Try again in 15 minutes." }, 429);

    const profileResult = await fetch(
      `${supabaseUrl}/rest/v1/profiles?select=id,email,is_active&employee_id=eq.${encodeURIComponent(employeeId)}&limit=1`,
      { headers: { apikey: serviceKey, Authorization: `Bearer ${serviceKey}` } },
    );
    if (!profileResult.ok) return response({ error: "Authentication service is temporarily unavailable." }, 503);
    const profiles = await profileResult.json().catch(() => []);
    const profile = Array.isArray(profiles) ? profiles[0] : null;
    if (!profile?.id || !profile?.email || profile.is_active !== true) return genericLoginError();

    const login = await fetch(`${supabaseUrl}/auth/v1/token?grant_type=password`, {
      method: "POST",
      headers: { apikey: anonKey, Authorization: `Bearer ${anonKey}`, "Content-Type": "application/json" },
      body: JSON.stringify({ email: profile.email, password }),
    });
    const auth = await login.json().catch(() => ({}));
    if (!login.ok || !auth.access_token || !auth.user?.id) {
      if (login.status === 429) return response({ error: "Too many sign-in attempts. Try again later." }, 429);
      return genericLoginError();
    }
    return response({ ...auth, employee_id: employeeId });
  }

  return response({ error: "Unknown authentication action." }, 400);
});
