import io
import os
from fastapi import FastAPI, File, HTTPException, UploadFile
from fastapi.responses import HTMLResponse
from fastapi.staticfiles import StaticFiles
from PIL import Image

from cnn_inference import BurnCNNInference
from jev_client import JevAPIClient

app = FastAPI(title="Burn CNN + Jev Pipeline Backend")

# Mount directories for static UI assets and test images
app.mount("/static", StaticFiles(directory="static"), name="static")

cnn_engine = BurnCNNInference()
jev_client = JevAPIClient()

@app.get("/", response_class=HTMLResponse)
async def serve_frontend():
    with open("demo.html", "r") as f:
        return f.read()

@app.post("/api/analyze/upload")
async def analyze_uploaded_image(file: UploadFile = File(...)):
    try:
        image_bytes = await file.read()
        image = Image.open(io.BytesIO(image_bytes))
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid image file format.")
    
    # Step 1: Run CNN Inference to extract probabilities
    cnn_results = cnn_engine.predict(image)
    
    # Step 2: Feed CNN probabilities into Jev API
    jev_decision = jev_client.evaluate_probabilities(cnn_results)
    
    return {
        "source": "uploaded_picture",
        "cnn_probabilities": cnn_results,
        "jev_output": jev_decision
    }