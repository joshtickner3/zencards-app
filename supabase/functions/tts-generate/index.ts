// supabase/functions/tts-generate/index.ts
import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// ─────────────────────────────
// Supabase client (service role)
// ─────────────────────────────
const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const supabase = createClient(supabaseUrl, serviceKey);

// ─────────────────────────────
// CORS
// ─────────────────────────────
const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "https://zencardstudy.com",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers":
    "authorization, apikey, content-type, x-client-info",
};

// ─────────────────────────────
// OpenAI TTS → MP3
// ─────────────────────────────
async function synthesizeToMp3(
  text: string,
  voice?: string,
  speed?: number,
): Promise<Uint8Array> {
  const apiKey = Deno.env.get("OPENAI_API_KEY");
  if (!apiKey) {
    throw new Error("OPENAI_API_KEY is not set in environment");
  }

  const model = "gpt-4o-mini-tts";

  const allowedVoices = [
    "alloy", "echo", "fable", "onyx", "nova", "shimmer",
    "coral", "verse", "ballad", "ash", "sage", "marni", "cedar",
  ];

  const chosenVoice =
    voice && allowedVoices.includes(voice) ? voice : "alloy";

  const payload: Record<string, unknown> = {
    model,
    voice: chosenVoice,
    input: text,
    format: "mp3",
  };

  if (typeof speed === "number") payload.speed = speed;

  const resp = await fetch("https://api.openai.com/v1/audio/speech", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(payload),
  });

  if (!resp.ok) {
    const errText = await resp.text().catch(() => "");
    throw new Error(`OpenAI TTS failed: ${resp.status} ${errText}`);
  }

  const arrayBuf = await resp.arrayBuffer();
  return new Uint8Array(arrayBuf);
}

// ─────────────────────────────
// HTTP handler
// ─────────────────────────────
serve(async (req) => {
  // CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Only POST allowed" }), {
      status: 405,
      headers: { "Content-Type": "application/json", ...corsHeaders },
    });
  }

  try {
    const body = await req.json().catch(() => null);

    if (!body) {
      return new Response(JSON.stringify({ error: "Invalid JSON body" }), {
        status: 400,
        headers: { "Content-Type": "application/json", ...corsHeaders },
      });
    }

    const { cardId, side, text, voice, speed } = body;

    if (!cardId || !side || !text) {
      return new Response(
        JSON.stringify({ error: "cardId, side, and text are required" }),
        {
          status: 400,
          headers: { "Content-Type": "application/json", ...corsHeaders },
        },
      );
    }

    // 1) Check cache
    const { data: existing, error: existingError } = await supabase
      .from("card_audio")
      .select("audio_url, voice, speed")
      .eq("card_id", cardId)
      .eq("side", side)
      .eq("voice", voice)
      .eq("speed", speed)
      .maybeSingle();

    if (existingError) {
      console.error("[tts-generate] query error:", existingError);
    }

    if (existing && existing.audio_url) {
      console.log("[tts-generate] cache hit", { cardId, side, voice, speed });
      return new Response(
        JSON.stringify({ audio_url: existing.audio_url }),
        { headers: { "Content-Type": "application/json", ...corsHeaders } },
      );
    }

    console.log("[tts-generate] cache miss – generating", {
      cardId,
      side,
      voice,
      speed,
    });

    // 2) Generate MP3 via OpenAI
    const mp3Bytes = await synthesizeToMp3(text, voice, speed);

    // 3) Upload to Storage
    const filePath = `${cardId}/${side}-${Date.now()}.mp3`;

    const { error: uploadError } = await supabase.storage
      .from("card-audio")
      .upload(filePath, mp3Bytes, {
        contentType: "audio/mpeg",
        upsert: true,
      });

    if (uploadError) {
      console.error("[tts-generate] upload error:", uploadError);
      throw uploadError;
    }

    // 4) Public URL
    const { data: publicUrlData } = supabase
      .storage
      .from("card-audio")
      .getPublicUrl(filePath);

    const publicUrl = publicUrlData.publicUrl;
    if (!publicUrl) {
      throw new Error("Could not get public URL for uploaded audio");
    }

    // 5) Insert DB row
    const { data: inserted, error: insertError } = await supabase
      .from("card_audio")
      .insert({
        card_id: cardId,
        side,
        audio_url: publicUrl,
        voice,
        speed,
      })
      .select("audio_url")
      .single();

    if (insertError) {
      console.error("[tts-generate] insert error:", insertError);
      throw insertError;
    }

    console.log("[tts-generate] success", { cardId, side });

    return new Response(
      JSON.stringify({ audio_url: inserted.audio_url }),
      { headers: { "Content-Type": "application/json", ...corsHeaders } },
    );
  } catch (e) {
    console.error("[tts-generate] error:", e);
    const message = e instanceof Error ? e.message : String(e);
    return new Response(JSON.stringify({ error: message }), {
      status: 500,
      headers: { "Content-Type": "application/json", ...corsHeaders },
    });
  }
});
