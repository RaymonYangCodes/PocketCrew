import { createClient } from "https://esm.sh/@supabase/supabase-js@2.57.4";

const jsonHeaders = { "Content-Type": "application/json" };

Deno.serve(async (request) => {
  if (request.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: jsonHeaders,
    });
  }

  try {
    const authHeader = request.headers.get("Authorization");
    if (!authHeader) throw new InviteError(401, "Authentication required");

    const supabaseURL = requiredEnv("SUPABASE_URL");
    const serviceKey = requiredEnv("SUPABASE_SERVICE_ROLE_KEY");
    const userClient = createClient(supabaseURL, requiredEnv("SUPABASE_ANON_KEY"), {
      global: { headers: { Authorization: authHeader } },
    });
    const admin = createClient(supabaseURL, serviceKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: authData, error: authError } = await userClient.auth.getUser();
    if (authError || !authData.user) throw new InviteError(401, "Authentication required");

    const payload = await request.json();
    const familyId = String(payload.familyId ?? "");
    const email = String(payload.email ?? "").trim().toLowerCase();
    if (!isUUID(familyId) || !isEmail(email)) {
      throw new InviteError(400, "A valid family and email are required");
    }

    const { data: membership } = await admin
      .from("family_guardians")
      .select("role")
      .eq("family_id", familyId)
      .eq("user_id", authData.user.id)
      .eq("status", "active")
      .maybeSingle();
    if (!membership) throw new InviteError(403, "Only a family guardian can invite someone");

    const oneHourAgo = new Date(Date.now() - 60 * 60 * 1000).toISOString();
    const { count } = await admin
      .from("family_invites")
      .select("id", { count: "exact", head: true })
      .eq("invited_by", authData.user.id)
      .gte("created_at", oneHourAgo);
    if ((count ?? 0) >= 5) {
      throw new InviteError(429, "Invite limit reached. Try again in an hour.");
    }

    const tokenBytes = crypto.getRandomValues(new Uint8Array(32));
    const token = Array.from(tokenBytes, (byte) => byte.toString(16).padStart(2, "0")).join("");
    const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(token));
    const tokenHash = Array.from(new Uint8Array(digest), (byte) =>
      byte.toString(16).padStart(2, "0")
    ).join("");
    const expiresAt = new Date(Date.now() + 72 * 60 * 60 * 1000).toISOString();

    const { data: family, error: familyError } = await admin
      .from("families")
      .select("name")
      .eq("id", familyId)
      .single();
    if (familyError) throw familyError;
    const { data: invite, error: inviteError } = await admin
      .from("family_invites")
      .insert({
        family_id: familyId,
        email,
        token_hash: tokenHash,
        invited_by: authData.user.id,
        expires_at: expiresAt,
      })
      .select("id")
      .single();
    if (inviteError) throw inviteError;

    const appURL = Deno.env.get("POCKETCREW_APP_URL") ?? "pocketcrew://invite";
    const separator = appURL.includes("?") ? "&" : "?";
    const inviteURL = `${appURL}${separator}token=${encodeURIComponent(token)}`;
    const emailResponse = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${requiredEnv("RESEND_API_KEY")}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        from: Deno.env.get("RESEND_FROM_EMAIL") ?? "PocketCrew <invites@example.com>",
        to: [email],
        subject: `Join ${family.name} on PocketCrew`,
        html: inviteHTML(family.name, inviteURL),
      }),
    });
    if (!emailResponse.ok) {
      await admin.from("family_invites").delete().eq("id", invite.id);
      throw new InviteError(502, "The invitation email provider rejected the message");
    }

    return new Response(JSON.stringify({ delivered: true }), { status: 200, headers: jsonHeaders });
  } catch (error) {
    const status = error instanceof InviteError ? error.status : 500;
    const message = error instanceof Error ? error.message : "Unable to send invitation";
    return new Response(JSON.stringify({ error: message }), { status, headers: jsonHeaders });
  }
});

class InviteError extends Error {
  constructor(public status: number, message: string) {
    super(message);
  }
}

function requiredEnv(name: string): string {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`Missing ${name}`);
  return value;
}

function isUUID(value: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
}

function isEmail(value: string): boolean {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value) && value.length <= 254;
}

function inviteHTML(familyName: string, inviteURL: string): string {
  const safeName = escapeHTML(familyName);
  const safeURL = escapeHTML(inviteURL);
  return `<!doctype html><html><body style="margin:0;background:#F7F3EA;font-family:Arial,sans-serif;color:#17251F"><div style="max-width:560px;margin:32px auto;background:white;border-radius:22px;padding:32px"><div style="font-size:24px;font-weight:800;color:#1F6A4A">PocketCrew</div><h1>Join ${safeName}</h1><p>A parent or guardian invited you to help manage their family’s PocketCrew. Sign in with this email address to accept.</p><p><a href="${safeURL}" style="display:inline-block;background:#1F6A4A;color:white;text-decoration:none;padding:14px 20px;border-radius:12px;font-weight:700">Accept family invitation</a></p><p style="color:#66736D;font-size:13px">This one-time link expires in 72 hours. PocketCrew is a learning ledger and does not hold or transfer money.</p></div></body></html>`;
}

function escapeHTML(value: string): string {
  return value.replace(/[&<>'"]/g, (character) => ({
    "&": "&amp;",
    "<": "&lt;",
    ">": "&gt;",
    "'": "&#39;",
    '"': "&quot;",
  })[character] ?? character);
}
