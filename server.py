import io
import os
import json
import traceback
from fastapi import FastAPI, File, UploadFile, Form, HTTPException
from fastapi.middleware.cors import CORSMiddleware
import numpy as np
from PIL import Image
import onnxruntime as ort

from jev_client import JevBurnEvaluatorClient

app = FastAPI(title="CromerCare ONNX & JEV Backend")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

MODEL_PATH = "current_gpu_model.onnx"
CONFIG_PATH = "model_config.json"

session = None
input_name = None
output_name = None
model_config = {}

try:
    jev_client = JevBurnEvaluatorClient()
except Exception as e:
    print(f"Warning: JEV Client initialization failed: {e}")
    jev_client = None

if os.path.exists(CONFIG_PATH):
    try:
        with open(CONFIG_PATH, "r") as f:
            model_config = json.load(f)
    except Exception as e:
        print(f"Error loading model config: {e}")

INPUT_SIZE = model_config.get("input_size", [224, 224])
LABELS = model_config.get("labels", ["first_degree", "second_degree", "third_degree", "indeterminate"])

try:
    if os.path.exists(MODEL_PATH):
        session = ort.InferenceSession(MODEL_PATH)
        input_name = session.get_inputs()[0].name
        output_name = session.get_outputs()[0].name
        print("ONNX Model loaded successfully!")
    else:
        print(f"Warning: Model file '{MODEL_PATH}' not found.")
except Exception as e:
    print(f"Error loading ONNX model: {e}")

def softmax(x):
    e_x = np.exp(x - np.max(x))
    return e_x / e_x.sum(axis=0)

@app.get("/")
def read_root():
    return {"status": "online", "model_loaded": session is not None}

@app.post("/api/evaluate")
async def evaluate_burn_case(
    file: UploadFile = File(...),
    questionnaire: str = Form(...)
):
    if session is None:
        raise HTTPException(status_code=500, detail="ONNX Model is not loaded on the server.")
    
    try:
        questionnaire_data = json.loads(questionnaire)
        
        contents = await file.read()
        image = Image.open(io.BytesIO(contents)).convert("RGB")
        
        target_size = tuple(INPUT_SIZE) if isinstance(INPUT_SIZE, list) else (224, 224)
        image = image.resize(target_size)
        
        img_array = np.array(image, dtype=np.float32) / 255.0
        img_array = np.transpose(img_array, (2, 0, 1))
        img_array = np.expand_dims(img_array, axis=0)
        
        outputs = session.run([output_name], {input_name: img_array})
        raw_preds = outputs[0][0]
        
        probabilities_array = softmax(raw_preds)
        predicted_class_idx = int(np.argmax(probabilities_array))
        confidence = float(probabilities_array[predicted_class_idx])
        
        predicted_class_name = LABELS[predicted_class_idx] if predicted_class_idx < len(LABELS) else f"class_{predicted_class_idx}"

        probabilities = {
            LABELS[i] if i < len(LABELS) else f"class_{i}": float(val) 
            for i, val in enumerate(probabilities_array)
        }

        cnn_prediction_payload = {
            "predicted_class": predicted_class_name,
            "confidence": confidence,
            "probabilities": probabilities
        }

        # Fetch JEV decision response
        if jev_client:
            jev_response = jev_client.evaluate_burn(cnn_prediction_payload, questionnaire_data)
        else:
            jev_response = {
                "burn_degree_classification": predicted_class_name,
                "severity_probability_score": "3 - Deep Partial Thickness",
                "requires_immediate_transfer": True
            }

        # Ensure consistent format for frontend rendering
        return {
            "cnn_prediction": cnn_prediction_payload,
            "jev_decision": jev_response
        }
        
    except Exception as e:
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=str(e))

if __name__ == "__main__":
    import uvicorn
    uvicorn.run("server:app", host="0.0.0.0", port=8000, reload=True)