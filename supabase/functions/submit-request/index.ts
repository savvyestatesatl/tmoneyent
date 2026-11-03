import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

Deno.serve(async (req) => {
  if (req.method !== "POST") return new Response("Method not allowed", { status: 405 });
  const auth = req.headers.get("Authorization") || "";
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") || "";
  if (auth !== "Bearer " + anonKey) return Response.json({ error: "Unauthorized" }, { status: 401 });

  const url = Deno.env.get("SUPABASE_URL")!;
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const db = createClient(url, serviceKey);
  const input = await req.json();
  const singer = String(input.singer_name || "").trim();
  const title = String(input.song_title || "").trim();
  const artist = String(input.artist || "").trim();
  const submissionKey = String(input.submission_key || "");
  if (!singer || singer.length > 60 || !title || title.length > 120 || artist.length > 120 || !/^[0-9a-f-]{36}$/i.test(submissionKey)) {
    return Response.json({ error: "Please check the singer name and song details." }, { status: 400 });
  }

  const { data: event, error: eventError } = await db.from("karaoke_events")
    .select("id").eq("is_active", true).single();
  if (eventError || !event) return Response.json({ error: "No active karaoke session." }, { status: 503 });

  let { data: request, error } = await db.from("karaoke_requests").insert({
    event_id: event.id, singer_name: singer, song_title: title,
    artist: artist || null, submission_key: submissionKey, status: "pending"
  }).select("id,sms_notified_at").single();

  if (error?.code === "23505") {
    const existing = await db.from("karaoke_requests").select("id,sms_notified_at")
      .eq("submission_key", submissionKey).maybeSingle();
    request = existing.data;
    error = existing.error;
  }
  if (error || !request) return Response.json({ error: "Your request could not be saved. Please try again." }, { status: 500 });

  const sid = Deno.env.get("TWILIO_ACCOUNT_SID");
  const twilioToken = Deno.env.get("TWILIO_AUTH_TOKEN");
  const from = Deno.env.get("TWILIO_FROM_NUMBER");
  const to = Deno.env.get("TMONEY_DJ_PHONE");
  if (!sid || !twilioToken || !from || !to) {
    return Response.json({ ok: true, sms_sent: false, request_id: request.id });
  }
  if (request.sms_notified_at) return Response.json({ ok: true, sms_sent: true, duplicate: true, request_id: request.id });

  const form = new URLSearchParams({
    To: to, From: from,
    Body: ["T-MONEY KARAOKE REQUEST", "Singer: " + singer, "Song: " + title, artist ? "Artist: " + artist : ""].filter(Boolean).join("\n")
  });
  const response = await fetch("https://api.twilio.com/2010-04-01/Accounts/" + sid + "/Messages.json", {
    method: "POST",
    headers: { Authorization: "Basic " + btoa(sid + ":" + twilioToken), "Content-Type": "application/x-www-form-urlencoded" },
    body: form
  });
  if (!response.ok) return Response.json({ ok: true, sms_sent: false, request_id: request.id });
  await db.from("karaoke_requests").update({ sms_notified_at: new Date().toISOString() }).eq("id", request.id);
  return Response.json({ ok: true, sms_sent: true, request_id: request.id });
});