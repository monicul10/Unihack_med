# CromerCare – burn triage

CromerCare is a web & mobile app for first-aid burn triage. The user logs in, fills in a 7-question questionnaire and takes a photo of the injury. The app returns:

- the burn grade (no burn / 1st / 2nd / 3rd degree), with a confidence value
- a severity score (0–5)
- whether urgent transfer to a hospital is needed
- a recommendation text (go to hospital / treat at home / nothing to do)
- a warning when the answers don't fit the photo (possible false positive)
- for urgent cases, a map with the nearest hospital and a link to Google Maps directions

Each analysis is saved to the user's history in Supabase.

> CromerCare does not provide a medical diagnosis. Results can be wrong.

## How it works

```
Phone / browser (demo.html)
   │  photo + questionnaire (POST /api/evaluate)
   ▼
FastAPI server (server.py)
   ├─ cnn_inference.py   → ONNX image model (current_gpu_model.onnx): 1st/2nd/3rd degree probabilities
   ├─ brightness check   → rejects photos darker than 55/255 (HTTP 422)
   └─ jev_client.py      → Jev System One API: final class, severity, transfer, consistency check
                            + code rules (weights, no-burn validation, red flags, warnings)
   ▼
Result shown in the page, saved to Supabase (table "Incidente")
```

If the Jev API is unavailable (no credits, network error, timeout), the server uses a **fallback**: the image model's grade plus the same code rules. The analysis still completes, with `status: "fallback"`.

## Files

| File | Purpose |
|---|---|
| `server.py` | FastAPI server: serves the page, runs the analysis, logs requests |
| `jev_client.py` | Jev request, questionnaire weights, post-processing rules, fallback, recommendation texts |
| `cnn_inference.py` | Loads and runs the ONNX image model, measures brightness |
| `model_config.json` | Image model settings: file name, input/output names, preprocessing, class labels, brightness limit |
| `current_gpu_model.onnx` | The trained image model (about 14 MB) |
| `demo.html` | The whole web app: login, questionnaire, camera, results, history, hospital map, ro/en, dark/light mode |
| `static/logo.svg` | Fallback logo only (SVG recreation), used if `logo.png` fails to load in the header |
| `static/logo.png` | The site logo (required): header, browser tab icon, apple-touch-icon and `/favicon.ico`, served at `/logo.png` with a 1 day cache |
| `supabase/incidente_policies.sql` | Row-level security so each user sees only their own history |
| `requirements.txt` | Python packages |
| `.env.example` | Template for the secret settings (copy it to `.env`) |
| `.gitignore` | Keeps `.env` and Python caches out of Git |

**Never commit `.env`.** It holds your Jev API key.

## Requirements

- Python 3.10 or newer (3.11–3.14 tested). Very new versions may not have an `onnxruntime` build yet.
- A Jev API key with credits ([jev-ai.pro](https://jev-ai.pro))
- A Supabase project (already configured in `demo.html`, see below)
- For phone testing: `cloudflared` (free, no account needed)

## Setup (Linux / WSL)

```bash
git clone --branch site git@github.com:monicul10/Unihack_med.git
cd Unihack_med/site

# Use the system Python, not an alias to another version
/usr/bin/python3 -m venv .venv
source .venv/bin/activate
python -m pip install --upgrade pip
python -m pip install -r requirements.txt

# Secret settings
cp .env.example .env
nano .env        # set JEV_AI_API_KEY=your_real_key, then Ctrl+O, Enter, Ctrl+X
```

Check that the packages are installed:

```bash
python -c "import fastapi, uvicorn, onnxruntime, PIL, numpy, requests, dotenv; print('ok')"
```

### `.env` settings

| Variable | Required | Default |
|---|---|---|
| `JEV_AI_API_KEY` | yes | – |
| `JEV_AI_ENDPOINT` | no | `https://jev-ai.pro/api/v1/systemone` |
| `JEV_AI_MODEL` | no | `jev-latest` |

The server reads `.env` only at startup. **Restart the server after changing it.**

## Run

```bash
cd Unihack_med/site
source .venv/bin/activate
python server.py
```

You should see:

```
CNN Inference Engine initialized successfully!
JEV Client initialized successfully!
Uvicorn running on http://0.0.0.0:8000
```

Open `http://localhost:8000` on the same computer. It redirects to `/app`.

Every new terminal needs `source .venv/bin/activate` first. Stop the server with `Ctrl+C` before running `git pull`, because the auto-reload restarts it mid-update.

## Test from a phone

Phones only allow the camera and location on HTTPS. A Cloudflare quick tunnel gives your local server a temporary HTTPS address.

Install it once (Linux / WSL, x86-64):

```bash
curl -L -o cloudflared.deb https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
sudo dpkg -i cloudflared.deb
```

With the server running, in a **second** terminal:

```bash
cloudflared tunnel --protocol http2 --url http://localhost:8000
```

1. Wait for the box with `https://<random-words>.trycloudflare.com` and the line `Registered tunnel connection`.
2. Wait another 30–60 seconds, then check: `curl -s https://<your-address>.trycloudflare.com/api/ping` should print `{"ok":true,"version":"..."}`.
3. Open the address in Chrome or Samsung Internet on the phone, directly rather than from a link inside another app.
4. Check that the version label under the buttons matches the one `/api/ping` returned.

Notes:
- Every restart of `cloudflared` gives a **new** address.
- Anyone with the link can use the site and your Jev credits. Stop the tunnel (`Ctrl+C`) when you're done.
- Restarting only the server keeps the same tunnel address.

## Supabase

The Supabase URL and the public (publishable) key are in `demo.html` (`SUPABASE_URL`, `SUPABASE_ANON_KEY`). Results go to the table set by `SUPABASE_RESULTS_TABLE` (`Incidente`).

Expected table (create it only for a new project):

```sql
create table if not exists public."Incidente" (
  id bigint generated by default as identity primary key,
  image_base64 text,
  data_crearii timestamptz default now(),
  user_id uuid references auth.users (id),
  grad_arsura text,
  incredere double precision
);
```

Then run `supabase/incidente_policies.sql` in the Supabase SQL Editor, so each user can only read and insert their own rows. Make sure no other policy on the table uses `true` (everyone sees everything):

```sql
select policyname, cmd, qual, with_check from pg_policies where tablename = 'Incidente';
```

## Quick checks

Run these with the server running, in a second terminal from the project folder.

Jev key works (expects `HTTP 200`; `402` means no credits, `401` a wrong key):

```bash
set -a; source .env; set +a
curl -s -m 20 -o /dev/null -w "HTTP %{http_code}\n" https://jev-ai.pro/api/v1/systemone \
  -H "Authorization: Bearer $JEV_AI_API_KEY" -H "Content-Type: application/json" \
  -d '{"model":"jev-latest","state":"ping","questions":{"ok":{"type":"noul","instructions":"Is this text non-empty?"}}}'
```

Full analysis with a test image (expects `"status":"success"`):

```bash
source .venv/bin/activate
python -c "from PIL import Image; Image.new('RGB',(400,400),(200,120,100)).save('/tmp/test.jpg')"
curl -s -F "file=@/tmp/test.jpg" -F 'questionnaire={}' http://localhost:8000/api/evaluate \
  | grep -oE '"status":"[a-z_]+"|"jev_model":"[^"]+"|"recommendation":"[a-z_]+"|"fallback_reason":"[^"]{0,120}'
```

## API

| Method | Path | Purpose |
|---|---|---|
| GET | `/` | Redirects to `/app` |
| GET | `/app` | The web app (served with `Cache-Control: no-store`) |
| GET | `/api/ping` | `{"ok": true, "version": "..."}` |
| POST | `/api/evaluate` | Multipart: `file` (image) and `questionnaire` (JSON string). Returns `{cnn_prediction, jev_decision}` |
| POST | `/api/client-log` | Browser diagnostics, printed in the server terminal as `[client ...]` lines |
| GET | `/favicon.ico` | Redirects to `/logo.png` |
| GET | `/favicon.svg` | Fallback SVG logo |
| GET | `/logo.png` | PNG logo, query string ignored (404 if `static/logo.png` is missing) |

`APP_VERSION` is defined in both `server.py` and `demo.html`. Keep them equal and bump both on every change.

## Questionnaire and Jev logic (summary)

The full specification is in `jev_client.py`.

- Questions, in order:
  1. Cause (weight **1.2**)
  2. Exposure duration (weight **1.2**)
  3. Pain
  4. Age
  5. Sensitive area (palms, soles, face, neck, genital area)
  6. Surface larger than a palm
  7. Large blisters

  Questions 3–7 have weight 1.0. Answers are sent as Romanian strings keyed by the Romanian question text.
- Jev receives the image model's probabilities, the answers and the weights. It answers 4 questions:
  - `final_burn_classification` (choice)
  - `severity_score` (0–5)
  - `requires_immediate_transfer` (probability)
  - `answers_inconsistent_with_image` (probability)
- **No burn** is never decided from one answer.
  - Only Jev can choose it, and the code checks it with a weighted support score.
  - The score must reach at least 3.0. The bar rises by 1.5 for blisters, a large surface or a chemical/electrical cause, and by 0.5 for a sensitive area.
  - If it isn't reached, the most likely burn grade is shown instead.
- **Urgent transfer**:
  - For a burn: Jev's transfer probability ≥ 0.5, 3rd degree, chemical/electrical cause, or "Da" for sensitive area, surface or blisters.
  - For "no burn": only a chemical/electrical cause and radiation burns ("Radiații (expunere raze UV/X)").
- **False-positive warnings** (warning only, never changes the result):
  - 3rd degree with exposure under 10 s
  - 2nd degree with exposure under 1 s
  - sun exposure under 10 s
  - Jev's inconsistency ≥ 0.7

  These are never raised for chemical/electrical causes.

## Nearest hospital map (OpenStreetMap)

When the result says urgent transfer, the app asks for the user's location and shows the nearest hospital on a map. The map uses OpenStreetMap tiles (Leaflet), and the hospital search uses the Overpass API. Tapping the map or the hospital marker opens Google Maps directions. No API key, account or billing is needed.

Coordinates stay in the browser. They are not logged, stored or sent to our server. Only the Overpass API receives them, to run the hospital query.

Fair use: the public OpenStreetMap tile server ([tile usage policy](https://operations.osmfoundation.org/policies/tiles/)) and the public Overpass instances ([Overpass usage policy](https://wiki.openstreetmap.org/wiki/Overpass_API#Public_Overpass_API_instances)) are free shared services meant for light use. For heavy traffic, use a commercial tile provider or self-host. Map data is © OpenStreetMap contributors.

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `ModuleNotFoundError: No module named 'fastapi'` | The virtual environment isn't active: run `source .venv/bin/activate`. If it persists, check `type -a python` for an alias to another Python version. |
| `JEV Client initialization failed` | `.env` is missing or `JEV_AI_API_KEY` is misspelled. |
| Server log shows `status=fallback, fallback_reason=HTTP 402` | Jev credits are exhausted. Top up or use another key, then restart the server. |
| "Imaginea este prea întunecată" | The photo is below brightness 55/255. Retake it with more light or the flash. |
| Camera doesn't start on the phone | The page must be on HTTPS. Tap "Activează camera", or allow the camera in the browser's site settings. Every new tunnel address asks for permission again. |
| Phone shows old behaviour | Close the tab and reopen it. Compare the version label with `/api/ping`. |
| Analysis spinner never stops | Check the server terminal. With no `[http] -> POST /api/evaluate` line, the request never arrived: restart the tunnel and use the new address. The `[client ...]` lines show what the phone did and any JavaScript error. |
| Map says "service unavailable" | The free OpenStreetMap/Overpass servers are busy. Try again later. |

A healthy analysis prints, in order:

```
[http] -> POST /api/evaluate ...
[evaluate] request received, image N bytes
[evaluate] CNN done in X ms, class=...
[evaluate] Jev done in X ms, status=success
[evaluate] total X ms
[http] <- POST /api/evaluate 200 in X ms
```

- **Stops after "request received":** the image model failed. Look for a traceback.
- **Stops after "CNN done":** Jev is slow or unreachable. It times out after 20 s and falls back.
- **On the phone:** the page gives up after 45 s with a connection message and re-enables the button.
