// supabase/functions/tts-generate/index.ts
import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const supabase = createClient(supabaseUrl, serviceKey);

// TODO: replace with your actual TTS provider
async function synthesizeToMp3(text: string, voice?: string, speed?: number): Promise<Uint8Array> {
  // Example pseudo-code:
  // const resp = await fetch("https://your-tts-provider.com/api", {...});
  // const buf = await resp.arrayBuffer();
  // return new Uint8Array(buf);
  throw new Error("synthesizeToMp3 not implemented yet");
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", {
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Methods": "POST, OPTIONS",
        "Access-Control-Allow-Headers": "content-type",
      },
    });
  }

  try {
    const { cardId, side, text, voice, speed } = await req.json();

    // 1. Check existing cache
    const { data: existing } = await supabase
      .from("card_audio")
      .select("*")
      .eq("card_id", cardId)
      .eq("side", side)
      .eq("voice", voice)
      .eq("speed", speed)
      .maybeSingle();

    if (existing) {
      return new Response(JSON.stringify(existing), {
        headers: {
          "Content-Type": "application/json",
          "Access-Control-Allow-Origin": "*",
        },
      });
    }

    // 2. Generate MP3 bytes
    const mp3Bytes = await synthesizeToMp3(text, voice, speed);

    // 3. Upload to Storage
    const filePath = `${cardId}/${side}-${Date.now()}.mp3`;

    const { error: uploadError } = await supabase.storage
      .from("card-audio")
      .upload(filePath, mp3Bytes, {
        contentType: "audio/mpeg",
        upsert: true,
      });

    if (uploadError) throw uploadError;

    const {
      data: { publicUrl },
    } = supabase.storage.from("card-audio").getPublicUrl(filePath);

    // 4. Save row in DB
    const { data: inserted, error: insertError } = await supabase
      .from("card_audio")
      .insert({
        card_id: cardId,
        side,
        audio_url: publicUrl,
        voice,
        speed,
      })
      .select()
      .single();

    if (insertError) throw insertError;

    return new Response(JSON.stringify(inserted), {
      headers: {
        "Content-Type": "application/json",
        "Access-Control-Allow-Origin": "*",
      },
    });
  } catch (e) {
    console.error(e);
    return new Response(JSON.stringify({ error: String(e) }), {
      status: 500,
      headers: {
        "Content-Type": "application/json",
        "Access-Control-Allow-Origin": "*",
      },
    });
  }
});
