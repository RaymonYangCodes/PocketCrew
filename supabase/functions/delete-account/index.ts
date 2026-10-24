import { createClient } from "https://esm.sh/@supabase/supabase-js@2.57.4";

const jsonHeaders = { "Content-Type": "application/json" };

Deno.serve(async (request) => {
  if (request.method !== "POST") {
    return response(405, { error: "Method not allowed" });
  }

  try {
    const authorization = request.headers.get("Authorization");
    if (!authorization) throw new DeleteError(401, "Authentication required");

    const supabaseURL = requiredEnv("SUPABASE_URL");
    const userClient = createClient(supabaseURL, requiredEnv("SUPABASE_ANON_KEY"), {
      global: { headers: { Authorization: authorization } },
    });
    const admin = createClient(supabaseURL, requiredEnv("SUPABASE_SERVICE_ROLE_KEY"), {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: authData, error: authError } = await userClient.auth.getUser();
    if (authError || !authData.user) throw new DeleteError(401, "Authentication required");
    const userId = authData.user.id;

    const { data: membership, error: membershipError } = await admin
      .from("family_guardians")
      .select("family_id,role")
      .eq("user_id", userId)
      .eq("status", "active")
      .maybeSingle();
    if (membershipError) throw membershipError;

    if (membership) {
      const { data: others, error: othersError } = await admin
        .from("family_guardians")
        .select("user_id,role")
        .eq("family_id", membership.family_id)
        .eq("status", "active")
        .neq("user_id", userId)
        .order("joined_at", { ascending: true });
      if (othersError) throw othersError;

      if (membership.role === "owner" && (others?.length ?? 0) === 0) {
        await deleteFamilyProofs(admin, membership.family_id);
        const { error: familyError } = await admin
          .from("families")
          .delete()
          .eq("id", membership.family_id);
        if (familyError) throw familyError;
      } else {
        const successorId = others![0].user_id;
        if (membership.role === "owner") {
          const { error: transferError } = await admin
            .from("family_guardians")
            .update({ role: "owner" })
            .eq("family_id", membership.family_id)
            .eq("user_id", successorId);
          if (transferError) throw transferError;
        }
        const { error: familyCreatorError } = await admin
          .from("families")
          .update({ created_by: successorId })
          .eq("id", membership.family_id)
          .eq("created_by", userId);
        if (familyCreatorError) throw familyCreatorError;
        await removeGuardianFromSnapshot(admin, membership.family_id, userId, successorId);
        const { error: acceptedInviteError } = await admin
          .from("family_invites")
          .update({ accepted_by: null })
          .eq("accepted_by", userId);
        if (acceptedInviteError) throw acceptedInviteError;
        const { error: createdInviteError } = await admin
          .from("family_invites")
          .delete()
          .eq("invited_by", userId);
        if (createdInviteError) throw createdInviteError;
        const { error: membershipDeleteError } = await admin
          .from("family_guardians")
          .delete()
          .eq("family_id", membership.family_id)
          .eq("user_id", userId);
        if (membershipDeleteError) throw membershipDeleteError;
      }
    }

    const { error: deleteUserError } = await admin.auth.admin.deleteUser(userId, false);
    if (deleteUserError) throw deleteUserError;
    return response(200, { deleted: true });
  } catch (error) {
    const status = error instanceof DeleteError ? error.status : 500;
    const message = error instanceof Error ? error.message : "Unable to delete account";
    return response(status, { error: message });
  }
});

async function removeGuardianFromSnapshot(
  admin: any,
  familyId: string,
  userId: string,
  successorId: string,
) {
  const { data: snapshot, error } = await admin
    .from("family_snapshots")
    .select("state,revision")
    .eq("family_id", familyId)
    .single();
  if (error) throw error;
  const state = snapshot.state ?? {};
  state.users = Array.isArray(state.users)
    ? state.users.filter((user: any) => user.id !== userId)
    : [];
  state.members = Array.isArray(state.members)
    ? state.members.filter((member: any) => member.userId !== userId)
    : [];
  const { data: updated, error: updateError } = await admin
    .from("family_snapshots")
    .update({ state, revision: snapshot.revision + 1, updated_by: successorId })
    .eq("family_id", familyId)
    .eq("revision", snapshot.revision)
    .select("family_id")
    .maybeSingle();
  if (updateError) throw updateError;
  if (!updated) throw new DeleteError(409, "The family changed. Please try deletion again.");
}

async function deleteFamilyProofs(admin: any, familyId: string) {
  const bucket = admin.storage.from("proof-images");
  const folders: Array<{ name: string }> = [];
  for (let offset = 0;; offset += 100) {
    const { data: page, error } = await bucket.list(familyId, { limit: 100, offset });
    if (error) throw error;
    folders.push(...(page ?? []));
    if ((page?.length ?? 0) < 100) break;
  }
  const paths: string[] = [];
  for (const folder of folders) {
    const folderPath = `${familyId}/${folder.name}`;
    for (let offset = 0;; offset += 100) {
      const { data: files, error } = await bucket.list(folderPath, { limit: 100, offset });
      if (error) throw error;
      for (const file of files ?? []) paths.push(`${folderPath}/${file.name}`);
      if ((files?.length ?? 0) < 100) break;
    }
  }
  for (let index = 0; index < paths.length; index += 1000) {
    const { error: removalError } = await bucket.remove(paths.slice(index, index + 1000));
    if (removalError) throw removalError;
  }
}

function requiredEnv(name: string): string {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`Missing ${name}`);
  return value;
}

function response(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), { status, headers: jsonHeaders });
}

class DeleteError extends Error {
  constructor(public status: number, message: string) {
    super(message);
  }
}
