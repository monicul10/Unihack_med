import json
import numpy as np
import onnxruntime as ort
from PIL import Image

class BurnCNNInference:
    def __init__(self):
        self.config_path = f"model_config.json"
        self.onnx_path = f"current_gpu_model.onnx"
        
        with open(self.config_path, "r") as f:
            self.config = json.load(f)
            
        self.idx_to_class = self.config["idx_to_class"]
        self.mean = np.array(self.config["normalize_mean"], dtype=np.float32)
        self.std = np.array(self.config["normalize_std"], dtype=np.float32)
        
        # Initialize ONNX Runtime session
        self.session = ort.InferenceSession(self.onnx_path)
        self.input_name = self.session.get_inputs()[0].name

    def preprocess(self, image: Image.Image):
        # Resize to 224x224 as required by MobileNetV3-Large
        image = image.convert("RGB").resize((224, 224), Image.Resampling.BILINEAR)
        arr = np.array(image, dtype=np.float32) / 255.0
        
        # Apply ImageNet normalization
        arr = (arr - self.mean) / self.std
        arr = np.transpose(arr, (2, 0, 1))  # HWC -> CHW format
        arr = np.expand_dims(arr, axis=0)   # Add batch dimension
        return arr

    def predict(self, image: Image.Image):
        input_tensor = self.preprocess(image)
        outputs = self.session.run(None, {self.input_name: input_tensor})
        logits = outputs[0][0]
        
        # Compute Softmax probabilities
        exp_logits = np.exp(logits - np.max(logits))
        probabilities = exp_logits / np.sum(exp_logits)
        
        predicted_idx = int(np.argmax(probabilities))
        
        return {
            "predicted_class": self.idx_to_class[str(predicted_idx)],
            "confidence": float(probabilities[predicted_idx]),
            "probabilities": {
                self.idx_to_class[str(i)]: float(p) 
                for i, p in enumerate(probabilities)
            }
        }