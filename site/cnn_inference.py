import json
from pathlib import Path
import numpy as np
import onnxruntime as ort
from PIL import Image

BASE_DIR = Path(__file__).resolve().parent


class BurnCNNInference:
    def __init__(
        self,
        config_path: str | Path = BASE_DIR / "model_config.json",
        onnx_path: str | Path | None = None,
    ):
        self.config_path = Path(config_path)

        with open(self.config_path, "r", encoding="utf-8") as f:
            self.config = json.load(f)

        model_filename = self.config.get("model_file", "burn_classifier_v2_probs.onnx")
        self.onnx_path = Path(onnx_path) if onnx_path else (BASE_DIR / model_filename)

        self.idx_to_class = self.config.get("class_labels") or self.config["idx_to_class"]
        self.resize_shorter_side = int(self.config.get("resize_shorter_side", 256))
        self.crop_size = int(self.config.get("crop_size", 224))
        self.min_brightness = float(self.config.get("min_brightness", 55.0))
        self.mean = np.array(self.config["normalize_mean"], dtype=np.float32)
        self.std = np.array(self.config["normalize_std"], dtype=np.float32)

        available_providers = ort.get_available_providers()
        preferred = ["CUDAExecutionProvider", "CPUExecutionProvider"]
        providers = [p for p in preferred if p in available_providers] or available_providers

        self.session = ort.InferenceSession(str(self.onnx_path), providers=providers)
        self.input_name = self.config.get("input_name") or self.session.get_inputs()[0].name
        self.output_name = self.config.get("output_name") or self.session.get_outputs()[0].name

    def preprocess(self, image: Image.Image) -> tuple[np.ndarray, float]:
        rgb_image = image.convert("RGB")

        # Measure average brightness before normalization
        brightness = float(np.mean(np.array(rgb_image.convert("L"), dtype=np.float32)))

        # Resize shorter side preserving aspect ratio, then center-crop to crop_size
        w, h = rgb_image.size
        if w < h:
            new_w = self.resize_shorter_side
            new_h = int(round(h * (self.resize_shorter_side / w)))
        else:
            new_h = self.resize_shorter_side
            new_w = int(round(w * (self.resize_shorter_side / h)))

        resized = rgb_image.resize((new_w, new_h), Image.Resampling.BILINEAR)

        left = (new_w - self.crop_size) // 2
        top = (new_h - self.crop_size) // 2
        cropped = resized.crop((left, top, left + self.crop_size, top + self.crop_size))

        arr = np.array(cropped, dtype=np.float32) / 255.0
        arr = ((arr - self.mean) / self.std).astype(np.float32)
        arr = np.transpose(arr, (2, 0, 1))  # HWC -> CHW
        arr = np.expand_dims(arr, axis=0)   # Add batch dimension
        return arr, brightness

    def predict(self, image: Image.Image) -> dict:
        input_tensor, brightness = self.preprocess(image)
        outputs = self.session.run([self.output_name], {self.input_name: input_tensor})
        raw_scores = np.asarray(outputs[0][0], dtype=np.float32)

        # Avoid double-softmax if the ONNX model already outputs probabilities
        if np.all((raw_scores >= 0.0) & (raw_scores <= 1.0)) and np.isclose(np.sum(raw_scores), 1.0, atol=1e-3):
            probabilities = raw_scores
        else:
            exp_logits = np.exp(raw_scores - np.max(raw_scores))
            probabilities = exp_logits / np.sum(exp_logits)

        predicted_idx = int(np.argmax(probabilities))

        return {
            "predicted_class": self.idx_to_class[str(predicted_idx)],
            "confidence": float(probabilities[predicted_idx]),
            "probabilities": {
                self.idx_to_class[str(i)]: float(p)
                for i, p in enumerate(probabilities)
            },
            "image_brightness": round(brightness, 2),
            "low_brightness_warning": brightness < self.min_brightness,
        }