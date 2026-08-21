import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

type RequestBody = {
  action?: "create" | "update" | "delete";
  user_id?: string;
  email?: string;
  password?: string;
  full_name?: string;
  username?: string;
  role?: string;
};

const allowedRoles = new Set(["admin", "ketua"]);
const validUserRoles = new Set([
  "admin",
  "ketua",
  "bendahara",
  "sekretaris",
  "viewer",
]);

function jsonResponse(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

  if (!supabaseUrl || !serviceRoleKey) {
    return jsonResponse(
      { success: false, error: "Supabase admin environment is not configured" },
      500,
    );
  }

  const authHeader = req.headers.get("Authorization") ?? "";
  const token = authHeader.replace("Bearer ", "").trim();
  if (!token) {
    return jsonResponse({ success: false, error: "Missing bearer token" }, 401);
  }

  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data: authData, error: authError } = await admin.auth.getUser(token);
  if (authError || !authData.user) {
    return jsonResponse({ success: false, error: "Invalid bearer token" }, 401);
  }

  const { data: callerProfile, error: profileError } = await admin
    .from("profiles")
    .select("role")
    .eq("id", authData.user.id)
    .maybeSingle();

  if (profileError) {
    return jsonResponse({ success: false, error: profileError.message }, 500);
  }

  if (!allowedRoles.has(callerProfile?.role ?? "")) {
    return jsonResponse({ success: false, error: "Access denied" }, 403);
  }
  const callerRole = callerProfile?.role ?? "";

  let body: RequestBody;
  try {
    body = await req.json();
  } catch {
    return jsonResponse({ success: false, error: "Invalid JSON body" }, 400);
  }

  const role = body.role ?? "viewer";
  if (body.role && !validUserRoles.has(role)) {
    return jsonResponse({ success: false, error: "Invalid role" }, 400);
  }

  try {
    if (body.action === "create") {
      if (!body.email || !body.password || !body.full_name) {
        return jsonResponse(
          { success: false, error: "email, password, and full_name are required" },
          400,
        );
      }

      // Only an admin may create an admin account (ketua is blocked to keep
      // the single-bootstrap-admin model intact).
      if (role === "admin" && callerRole !== "admin") {
        return jsonResponse(
          { success: false, error: "Only an admin can create an admin account" },
          403,
        );
      }

      const { data, error } = await admin.auth.admin.createUser({
        email: body.email,
        password: body.password,
        email_confirm: true,
        user_metadata: {
          full_name: body.full_name,
          username: body.username,
          role,
        },
      });
      if (error) throw error;

      const userId = data.user?.id;
      if (!userId) {
        return jsonResponse({ success: false, error: "User was not created" }, 500);
      }

      const { error: upsertError } = await admin.from("profiles").upsert({
        id: userId,
        email: body.email,
        full_name: body.full_name,
        username: body.username,
        role,
      });
      if (upsertError) throw upsertError;

      return jsonResponse({ success: true, user_id: userId });
    }

    if (body.action === "update") {
      if (!body.user_id) {
        return jsonResponse({ success: false, error: "user_id is required" }, 400);
      }

      // A ketua may not grant admin, nor modify/demote an existing admin.
      if (callerRole !== "admin") {
        const { data: targetProfile } = await admin
          .from("profiles")
          .select("role")
          .eq("id", body.user_id)
          .maybeSingle();
        const targetRole = targetProfile?.role ?? "";
        if (role === "admin" || targetRole === "admin") {
          return jsonResponse(
            {
              success: false,
              error: "Only an admin can grant or modify an admin account",
            },
            403,
          );
        }
      }

      const attributes: Record<string, unknown> = {
        user_metadata: {
          full_name: body.full_name,
          username: body.username,
          role,
        },
      };
      if (body.email) attributes.email = body.email;
      if (body.password) attributes.password = body.password;

      const { error } = await admin.auth.admin.updateUserById(
        body.user_id,
        attributes,
      );
      if (error) throw error;

      const { data, error: profileUpdateError } = await admin
        .from("profiles")
        .update({
          email: body.email,
          full_name: body.full_name,
          username: body.username,
          role,
        })
        .eq("id", body.user_id)
        .select("updated_at")
        .single();
      if (profileUpdateError) throw profileUpdateError;

      return jsonResponse({
        success: true,
        user_id: body.user_id,
        updated_at: data?.updated_at,
      });
    }

    if (body.action === "delete") {
      if (!body.user_id) {
        return jsonResponse({ success: false, error: "user_id is required" }, 400);
      }

      // A ketua may not delete an admin account.
      if (callerRole !== "admin") {
        const { data: targetProfile } = await admin
          .from("profiles")
          .select("role")
          .eq("id", body.user_id)
          .maybeSingle();
        if ((targetProfile?.role ?? "") === "admin") {
          return jsonResponse(
            { success: false, error: "Only an admin can delete an admin account" },
            403,
          );
        }
      }

      await admin.from("profiles").delete().eq("id", body.user_id);
      const { error } = await admin.auth.admin.deleteUser(body.user_id);
      if (error && !error.message.toLowerCase().includes("not found")) {
        throw error;
      }

      return jsonResponse({ success: true, user_id: body.user_id });
    }

    return jsonResponse({ success: false, error: "Unknown action" }, 400);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    return jsonResponse({ success: false, error: message }, 500);
  }
});
