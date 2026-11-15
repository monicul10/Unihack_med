// Burn triage via Jev System One (shared CromerCare spec, Sections 2–4).
// Deploy:  supabase functions deploy burn-triage
// Secrets: supabase secrets set JEV_AI_API_KEY=...   (optional: JEV_AI_API_URL, JEV_AI_MODEL)
//
// The app sends { vision_output, chestionar }. This function adds the question
// weights and the four Jev questions (kept server-side so the app can't change
// them), calls Jev, and returns Jev's JSON unchanged. Post-processing and the
// fallback run in the app (lib/triage.dart).

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const DEFAULT_ENDPOINT = "https://jev-ai.pro/api/v1/systemone";
const DEFAULT_MODEL = "jev-latest";
const LOW_BRIGHTNESS = 55.0;
const TIMEOUT_MS = 20_000; // spec: 5 s connect + 15 s read

const QUESTION_WEIGHT_PRIORITY = 1.2;
const QUESTION_WEIGHT_DEFAULT = 1.0;

const WEIGHT_INSTRUCTION =
  "Answers to the cause and exposure duration questions are 20% more important " +
  "(weight 1.2) than the other answers (weight 1.0); see question_weights in the " +
  "state, and weight the answers accordingly.";

const QUESTIONS = {
  final_burn_classification: {
    type: "choice",
    instructions:
      "Using the burn-grade probabilities in vision_output and the patient answers in chestionar, " +
      "classify the injury. Never conclude 'no_burn' from a single answer; several answers must agree. " +
      "Causes are thermal, chemical, electrical, radiation (UV/X), other (friction, falls), sun exposure " +
      "('Expunere la soare'; typically 1st degree, sometimes 2nd degree with blisters) and unknown " +
      "('Nu știu ce a cauzat arsura'; the grade is then less certain, so do not be overconfident). " +
      "The exposure duration and the age of the patient are also in chestionar; weigh them (very short " +
      "exposure makes deep burns unlikely unless the cause is chemical or electrical; children under 5 " +
      "and adults over 60 have thinner skin and burn more deeply). Low probabilities combined with no " +
      "pain, no blisters, a small surface, no sensitive area and a very brief exposure indicate healthy " +
      "skin. When the image is uncertain and several answers are implausible for a burn or inconsistent " +
      "with each other (for example an unknown cause with a very short exposure, no pain and no blisters, " +
      "or a severe-looking grade with trivial answers), choose 'no_burn', whatever the cause, including " +
      "unknown; never because of one answer alone. " + WEIGHT_INSTRUCTION,
    criteria: {
      no_burn:
        "No burn / normal / healthy skin, or not a burn at all. Choose it when the image is uncertain " +
        "(low probabilities across all burn grades) and several answers are implausible for a burn or " +
        "inconsistent with each other, for example an unknown cause with a very short exposure, no pain " +
        "(0-2) and no blisters, or a severe-looking grade with trivial answers. This applies to any cause, " +
        "including 'Nu știu ce a cauzat arsura'. Never choose this class because of a single answer: " +
        "several answers must agree.",
      first_degree:
        "Grad I (1st degree / superficial): epidermis only. Red, dry, painful skin, no blisters, blanches " +
        "on pressure. Typical of mild sunburn (cause 'Expunere la soare' / 'Sun exposure') or brief scald.",
      second_degree:
        "Grad II (2nd degree / partial thickness): epidermis and part of the dermis. Blisters, moist or " +
        "weeping surface, marked pain. A sunburn is sometimes 2nd degree when blisters are present.",
      third_degree:
        "Grad III (3rd degree / full thickness): all skin layers destroyed. White, brown, black or leathery " +
        "skin, may be painless due to nerve damage. Often chemical, electrical or prolonged flame exposure.",
    },
  },
  severity_score: {
    type: "score",
    instructions:
      "Rate the overall clinical severity of this case from vision_output and chestionar. " +
      WEIGHT_INSTRUCTION,
    criteria: [
      "0 - No injury, healthy skin",
      "1 - Minimal: small superficial redness, home care",
      "2 - Mild: superficial burn, small area, manageable pain",
      "3 - Moderate: blisters or partial thickness, needs medical review",
      "4 - Severe: large area, sensitive zone or deep burn, urgent care",
      "5 - Critical: full thickness, chemical or electrical injury, emergency",
    ],
  },
  requires_immediate_transfer: {
    type: "noul",
    instructions:
      "The patient needs immediate transfer to an emergency or burn unit based on vision_output and " +
      "chestionar. Sensitive areas are palms, soles, face, neck and the genital area. " +
      WEIGHT_INSTRUCTION,
    criteria: {
      true:
        "Deep or large burn, sensitive area (palms, soles, face, neck, genital area), " +
        "chemical/electrical cause, or severe pain",
      false: "Superficial or no burn that can be managed with first aid",
    },
  },
  answers_inconsistent_with_image: {
    type: "noul",
    instructions:
      "The chestionar answers (exposure duration, age, pain, blisters, cause) are inconsistent with the " +
      "visual burn grade in vision_output, for example a deep burn grade with a very short exposure (the " +
      "exposure duration is the main signal), or a sunburn with only seconds of sun. Low pain and no " +
      "blisters also weigh against deep burns. " + WEIGHT_INSTRUCTION,
    criteria: {
      true: "The questionnaire answers contradict the visual burn grade",
      false: "The questionnaire answers are consistent with the visual burn grade",
    },
  },
};

const json = (body: unknown, status = 200): Response =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });

interface VisionOutput {
  status: string;
  probabilities: { degree_1: number; degree_2: number; degree_3: number };
  image_brightness: number;
}

const isExposureKey = (k: string) => /expunere|exposure/.test(k.toLowerCase());
const isCauseKey = (k: string) => /cauza|cause/.test(k.toLowerCase()) && !isExposureKey(k);

const questionWeights = (chestionar: Record<string, string>) =>
  Object.fromEntries(
    Object.keys(chestionar).map((k) => [
      k,
      isCauseKey(k) || isExposureKey(k) ? QUESTION_WEIGHT_PRIORITY : QUESTION_WEIGHT_DEFAULT,
    ]),
  );

const isValidVision = (v: unknown): v is VisionOutput => {
  const o = v as VisionOutput | undefined;
  const p = o?.probabilities;
  return typeof o?.status === "string" &&
    typeof o.image_brightness === "number" &&
    typeof p?.degree_1 === "number" &&
    typeof p.degree_2 === "number" &&
    typeof p.degree_3 === "number";
};

const isValidChestionar = (c: unknown): c is Record<string, string> =>
  typeof c === "object" && c !== null && !Array.isArray(c) &&
  Object.keys(c).length > 0 && Object.keys(c).length <= 20 &&
  Object.values(c).every((v) => typeof v === "string" && v.length <= 300);

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "method not allowed" }, 405);

  try {
    const { vision_output, chestionar } = await req.json();

    if (!isValidVision(vision_output) || !isValidChestionar(chestionar)) {
      return json({ error: "bad request: missing or invalid vision_output / chestionar" }, 400);
    }

    // Brightness gate: Jev is not called for photos that are too dark.
    if (vision_output.status === "low_brightness" || vision_output.image_brightness < LOW_BRIGHTNESS) {
      return json({
        detail: {
          code: "low_brightness",
          message: `Image too dark (brightness ${vision_output.image_brightness} < ${LOW_BRIGHTNESS}).`,
          image_brightness: vision_output.image_brightness,
        },
      }, 422);
    }

    const apiKey = Deno.env.get("JEV_AI_API_KEY");
    if (!apiKey) return json({ error: "server misconfiguration: missing JEV_AI_API_KEY" }, 500);
    const apiUrl = Deno.env.get("JEV_AI_API_URL") || DEFAULT_ENDPOINT;
    const model = Deno.env.get("JEV_AI_MODEL") || DEFAULT_MODEL;

    const upstream = await fetch(apiUrl, {
      method: "POST",
      headers: { Authorization: `Bearer ${apiKey}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        model,
        state: { vision_output, chestionar, question_weights: questionWeights(chestionar) },
        questions: QUESTIONS,
      }),
      signal: AbortSignal.timeout(TIMEOUT_MS),
    });

    const text = await upstream.text();
    if (!upstream.ok) {
      console.error(`Jev error ${upstream.status}: ${text}`);
      // 401 invalid key, 402 no credits, 422 invalid request, 429 rate limited.
      return json({ error: `jev returned ${upstream.status}`, upstream_status: upstream.status, detail: text }, 502);
    }

    return new Response(text, { headers: { ...cors, "Content-Type": "application/json" } });
  } catch (e) {
    const message = e instanceof Error ? `${e.name}: ${e.message}` : String(e);
    console.error("burn-triage error:", message);
    return json({ error: "upstream error", detail: message }, 502);
  }
});
