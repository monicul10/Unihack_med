import io
import json
import time
import traceback
from fastapi import FastAPI, File, UploadFile, Form, HTTPException, Request
from starlette.concurrency import run_in_threadpool
from fastapi.middleware.cors import CORSMiddleware
from PIL import Image, UnidentifiedImageError
from fastapi.responses import HTMLResponse, RedirectResponse, Response
from cnn_inference import BurnCNNInference
from jev_client import JevBurnEvaluatorClient
from pathlib import Path
from dotenv import load_dotenv

APP_VERSION = "2026-11-15.2"
CLIENT_LOG_MAX_BYTES = 32 * 1024
CLIENT_LOG_MAX_MSG = 500
CLIENT_LOG_MAX_EVENTS = 200

BASE_DIR = Path(__file__).resolve().parent

load_dotenv(BASE_DIR / ".env")

app = FastAPI(title="CromerCare ONNX & JEV Backend")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)



@app.middleware("http")
async def log_api_requests(request: Request, call_next):
    if not request.url.path.startswith("/api/"):
        return await call_next(request)
    started = time.perf_counter()
    client = request.client.host if request.client else "?"
    print(
        f"[http] -> {request.method} {request.url.path} "
        f"content-length={request.headers.get('content-length', '-')} client={client}",
        flush=True,
    )
    try:
        response = await call_next(request)
    except Exception:
        print(
            f"[http] !! {request.method} {request.url.path} raised after "
            f"{(time.perf_counter() - started) * 1000:.0f} ms",
            flush=True,
        )
        raise
    print(
        f"[http] <- {request.method} {request.url.path} {response.status_code} "
        f"in {(time.perf_counter() - started) * 1000:.0f} ms",
        flush=True,
    )
    return response


cnn_engine = None
jev_client = None

try:
    cnn_engine = BurnCNNInference()
    print("CNN Inference Engine initialized successfully!")
except Exception as e:
    print(f"Error initializing CNN Inference Engine: {e}")

try:
    jev_client = JevBurnEvaluatorClient()
    print("JEV Client initialized successfully!")
except Exception as e:
    print(f"Warning: JEV Client initialization failed: {e}")


@app.get("/", include_in_schema=False)
def root():
    return RedirectResponse(url="/app", status_code=307)


@app.get("/favicon.ico", include_in_schema=False)
def favicon():
    return RedirectResponse(url="/logo.png", status_code=307)


@app.get("/favicon.svg", include_in_schema=False)
def favicon_svg():
    return Response(
        (BASE_DIR / "static" / "logo.svg").read_bytes(),
        media_type="image/svg+xml",
        headers={"Cache-Control": "public, max-age=86400"},
    )


@app.get("/logo.png", include_in_schema=False)
def logo_png():
    path = BASE_DIR / "static" / "logo.png"
    if not path.is_file():
        raise HTTPException(status_code=404, detail="logo.png not found")
    return Response(
        path.read_bytes(),
        media_type="image/png",
        headers={"Cache-Control": "public, max-age=86400"},
    )


@app.get("/app", response_class=HTMLResponse)
def serve_ui():
    with open(BASE_DIR / "demo.html", "r", encoding="utf-8") as f:
        return HTMLResponse(
            f.read(),
            headers={"Cache-Control": "no-store, max-age=0", "Pragma": "no-cache"},
        )


@app.get("/api/ping")
def ping():
    return {"ok": True, "version": APP_VERSION}


def _clean_log_text(value, limit):
    text = str(value) if value is not None else ""
    return text.replace("\r", " ").replace("\n", " ")[:limit]


@app.post("/api/client-log", include_in_schema=False)
async def client_log(request: Request):
    """Receive small diagnostic batches from the browser. Never raises."""
    try:
        declared = request.headers.get("content-length")
        if declared and declared.isdigit() and int(declared) > CLIENT_LOG_MAX_BYTES:
            return Response(status_code=204)
        raw = await request.body()
        if len(raw) > CLIENT_LOG_MAX_BYTES:
            return Response(status_code=204)
        data = json.loads(raw)
        if not isinstance(data, dict):
            return Response(status_code=204)
        session = _clean_log_text(data.get("session"), 8) or "?"
        header = (
            f"[client {session}] page v{_clean_log_text(data.get('version'), 40)} "
            f"ua={_clean_log_text(data.get('ua'), 200)}"
        )
        events = data.get("events")
        if not isinstance(events, list):
            return Response(status_code=204)
        lines = []
        for ev in events[:CLIENT_LOG_MAX_EVENTS]:
            if not isinstance(ev, dict):
                continue
            t = ev.get("t")
            t = int(t) if isinstance(t, (int, float)) and not isinstance(t, bool) else 0
            level = _clean_log_text(ev.get("level"), 10) or "info"
            msg = _clean_log_text(ev.get("msg"), CLIENT_LOG_MAX_MSG)
            lines.append(f"[client {session}] +{t}ms {level}: {msg}")
        if lines:
            print(header, flush=True)
            print("\n".join(lines), flush=True)
    except Exception:
        pass
    return Response(status_code=204)


@app.post("/api/evaluate")
async def evaluate_burn_case(
    file: UploadFile = File(...),
    questionnaire: str = Form(...)
):
    if cnn_engine is None:
        raise HTTPException(status_code=500, detail="ONNX Model is not loaded on the server.")

    try:
        questionnaire_data = json.loads(questionnaire)
    except json.JSONDecodeError:
        raise HTTPException(status_code=400, detail="Invalid JSON format in 'questionnaire' field.")

    t_start = time.perf_counter()
    try:
        contents = await file.read()
        print(f"[evaluate] request received, image {len(contents)} bytes")
        image = Image.open(io.BytesIO(contents))
    except UnidentifiedImageError:
        print("[evaluate] ERROR: uploaded file is not a valid image")
        raise HTTPException(status_code=400, detail="Uploaded file is not a valid image.")

    try:
        # 1. Run normalized CNN inference (worker thread keeps the event loop free)
        t_cnn = time.perf_counter()
        cnn_prediction_payload = await run_in_threadpool(cnn_engine.predict, image)
        print(
            f"[evaluate] CNN done in {(time.perf_counter() - t_cnn) * 1000:.0f} ms, "
            f"class={cnn_prediction_payload.get('predicted_class')}"
        )

        # Quality gate: reject images that are too dark
        if cnn_prediction_payload.get("low_brightness_warning"):
            print("[evaluate] rejected: low brightness")
            raise HTTPException(
                status_code=422,
                detail={
                    "code": "low_brightness",
                    "message": "Image is too dark. Please retake the photo with the flash on or in better light.",
                    "image_brightness": cnn_prediction_payload.get("image_brightness"),
                },
            )

        # 2. Run JEV evaluation (blocking HTTP call, so also off the event loop)
        if jev_client is not None:
            t_jev = time.perf_counter()
            jev_response = await run_in_threadpool(
                jev_client.evaluate_burn, cnn_prediction_payload, questionnaire_data
            )
            jev_status = jev_response.get("status") if isinstance(jev_response, dict) else None
            reason = ""
            if isinstance(jev_response, dict) and jev_response.get("fallback_reason"):
                reason = f", fallback_reason={str(jev_response['fallback_reason'])[:150]}"
            print(f"[evaluate] Jev done in {(time.perf_counter() - t_jev) * 1000:.0f} ms, status={jev_status}{reason}")
        else:
            raise HTTPException(status_code=503, detail="JEV Evaluator service is unavailable.")

        print(f"[evaluate] total {(time.perf_counter() - t_start) * 1000:.0f} ms")
        return {
            "cnn_prediction": cnn_prediction_payload,
            "jev_decision": jev_response
        }

    except HTTPException:
        raise
    except Exception as e:
        traceback.print_exc()
        print(f"[evaluate] ERROR after {(time.perf_counter() - t_start) * 1000:.0f} ms: {type(e).__name__}")
        raise HTTPException(status_code=500, detail=str(e))


if __name__ == "__main__":
    import uvicorn
    uvicorn.run("server:app", host="0.0.0.0", port=8000, reload=True)