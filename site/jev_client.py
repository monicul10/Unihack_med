import os
import requests

DEFAULT_ENDPOINT = "https://jev-ai.pro/api/v1/systemone"

# Option keys match the class keys the frontend (demo.html) translates.
BURN_CLASS_CRITERIA = {
    "no_burn": (
        "No burn / normal / healthy skin, or not a burn at all. Choose it when the image is "
        "uncertain (low probabilities across all burn grades) and several answers are implausible "
        "for a burn or inconsistent with each other, for example an unknown cause with a very "
        "short exposure, no pain (0-2) and no blisters, or a severe-looking grade with trivial "
        "answers. This applies to any cause, including 'Nu știu ce a cauzat arsura'. "
        "Never choose this class because of a single answer: several answers must agree."
    ),
    "first_degree": (
        "Grad I (1st degree / superficial): epidermis only. Red, dry, painful skin, "
        "no blisters, blanches on pressure. Typical of mild sunburn (cause 'Expunere la soare' / "
        "'Sun exposure') or brief scald."
    ),
    "second_degree": (
        "Grad II (2nd degree / partial thickness): epidermis and part of the dermis. "
        "Blisters, moist or weeping surface, marked pain. A sunburn is sometimes 2nd degree "
        "when blisters are present."
    ),
    "third_degree": (
        "Grad III (3rd degree / full thickness): all skin layers destroyed. White, brown, "
        "black or leathery skin, may be painless due to nerve damage. Often chemical, "
        "electrical or prolonged flame exposure."
    ),
}

SEVERITY_LEVELS = [
    "0 - No injury, healthy skin",
    "1 - Minimal: small superficial redness, home care",
    "2 - Mild: superficial burn, small area, manageable pain",
    "3 - Moderate: blisters or partial thickness, needs medical review",
    "4 - Severe: large area, sensitive zone or deep burn, urgent care",
    "5 - Critical: full thickness, chemical or electrical injury, emergency",
]


INDICATII = {
    "go_to_hospital": (
        "RECOMANDARE: Prezintă-te de urgență la spital / medic.\n"
        "- Acoperă zona cu un pansament steril, curat, fără a aplica unguente sau gheață.\n"
        "- Solicită evaluare medicală imediată."
    ),
    "treat_at_home": (
        "RECOMANDARE: Îngrijire și monitorizare la domiciliu.\n"
        "- Răcește zona cu apă călduță/rece (nu gheață) timp de 10-15 minute.\n"
        "- Aplică o cremă hidratantă/calmanta potrivită și monitorizează evoluția."
    ),
    "nothing_to_do": (
        "RECOMANDARE: Nu este necesară nicio intervenție.\n"
        "- Pielea nu prezintă semne care să necesite tratament; menține zona curată."
    ),
}


# Questions 1 (cause) and 2 (exposure) are 20% more important than the others.
QUESTION_WEIGHT_PRIORITY = 1.2
QUESTION_WEIGHT_DEFAULT = 1.0
WEIGHT_INSTRUCTION = (
    "Answers to the cause and exposure duration questions are 20% more important "
    "(weight 1.2) than the other answers (weight 1.0); see `question_weights` in the "
    "state, and weight the answers accordingly."
)
# Weighted support needed before a "no_burn" answer is accepted. Each burn-indicating
# answer raises the required support; a "Da" for the sensitive area only describes
# location, so it raises it less.
NO_BURN_MIN_SUPPORT = 3.0
NO_BURN_BURN_INDICATOR_PENALTY = 1.5
NO_BURN_SENSITIVE_AREA_PENALTY = 0.5
# Suspicion signals that also count as support for "no_burn".
NO_BURN_INCONSISTENCY_SUPPORT_THRESHOLD = 0.7
NO_BURN_INCONSISTENCY_SUPPORT = 1.2
NO_BURN_LOW_CERTAINTY_THRESHOLD = 0.5
NO_BURN_LOW_CERTAINTY_SUPPORT = 1.0
NO_BURN_JEV_PROBABILITY_THRESHOLD = 0.5
NO_BURN_JEV_PROBABILITY_SUPPORT = 1.0
# The fallback (no Jev) needs at least this many distinct supporting answers.
FALLBACK_NO_BURN_MIN_ANSWERS = 3
NO_BURN_REASON = "no_burn_insufficient_evidence"
NO_BURN_CONTRADICTED_REASON = "no_burn_contradicted_by_answers"
PAIN_NONE_VALUES = ("0–2 (fără durere / disconfort)", "0-2 (fără durere / disconfort)", "0–2 (no pain / discomfort)", "0-2 (no pain / discomfort)")
NO_VALUES = ("nu", "no")


SUN_CAUSE_KEYS = ("soare", "sun exposure")
UNKNOWN_CAUSE_KEYS = ("nu știu", "nu stiu", "don't know", "don’t know")
HIGH_RISK_CAUSE_KEYS = ("chimic", "electric", "chemical", "electrical")
RADIATION_CAUSE_KEYS = ("radia", "radiation")
EXPOSURE_BRIEF_VALUES = ("< 1 secundă", "< 1 second")
EXPOSURE_SHORT_VALUES = EXPOSURE_BRIEF_VALUES + ("< 10 secunde", "< 10 seconds")
JEV_INCONSISTENCY_THRESHOLD = 0.7


def _is_exposure_key(key) -> bool:
    k = str(key).lower()
    return "expunere" in k or "exposure" in k


def _is_cause_key(key) -> bool:
    k = str(key).lower()
    return ("cauza" in k or "cause" in k) and not _is_exposure_key(key)


def _answer(questionnaire: dict, matcher) -> str:
    """Lower-cased answer of the first questionnaire entry whose key satisfies matcher."""
    for key, value in (questionnaire or {}).items():
        if matcher(key):
            return str(value).strip().lower()
    return ""


def _is_pain_key(key) -> bool:
    k = str(key).lower()
    return "durere" in k or "pain" in k


def _is_sensitive_key(key) -> bool:
    k = str(key).lower()
    return "zonă" in k or "zona" in k or "sensitive" in k or "area" in k


def _is_size_key(key) -> bool:
    k = str(key).lower()
    return "suprafa" in k or "surface" in k


def _is_blisters_key(key) -> bool:
    k = str(key).lower()
    return "vezicule" in k or "blister" in k


def _question_weight(key) -> float:
    if _is_cause_key(key) or _is_exposure_key(key):
        return QUESTION_WEIGHT_PRIORITY
    return QUESTION_WEIGHT_DEFAULT


def _question_weights(questionnaire: dict) -> dict:
    return {str(key): _question_weight(key) for key in (questionnaire or {})}


def _is_high_risk_cause(questionnaire: dict) -> bool:
    cause = _answer(questionnaire, _is_cause_key)
    return any(k in cause for k in HIGH_RISK_CAUSE_KEYS)


def _requires_transfer_without_burn(questionnaire: dict) -> bool:
    """Urgent transfer for a final "no_burn": high-risk cause or radiation exposure."""
    if _is_high_risk_cause(questionnaire):
        return True
    cause = _answer(questionnaire, _is_cause_key)
    return any(k in cause for k in RADIATION_CAUSE_KEYS)


# Support codes that come from questionnaire answers (the rest are suspicion signals).
ANSWER_SUPPORT_CODES = (
    "pain_none", "no_blisters", "no_sensitive_area", "small_surface", "exposure_brief", "cause_not_high_risk",
)


def _cnn_top_probability(cnn_prediction: dict) -> float | None:
    """Highest CNN class probability (image certainty), or None if unavailable."""
    cnn_prediction = cnn_prediction or {}
    values = []
    for v in (cnn_prediction.get("probabilities") or {}).values():
        try:
            values.append(float(v))
        except (TypeError, ValueError):
            continue
    if values:
        return max(values)
    try:
        return float(cnn_prediction["confidence"])
    except (KeyError, TypeError, ValueError):
        return None


def _no_burn_support(
    questionnaire: dict,
    cnn_prediction: dict | None = None,
    jev_inconsistency: float | None = None,
    jev_no_burn_probability: float | None = None,
) -> dict:
    """Weighted evidence for "not a burn" versus the evidence required to accept it.

    Burn-indicating answers (blisters, size, sensitive area, chemical/electrical cause)
    raise the threshold instead of vetoing; suspicion signals add support.
    """
    q = questionnaire or {}
    score = 0.0
    reasons = []

    def add(code, weight):
        nonlocal score
        score += weight
        reasons.append(code)

    if _answer(q, _is_pain_key) in tuple(v.lower() for v in PAIN_NONE_VALUES):
        add("pain_none", QUESTION_WEIGHT_DEFAULT)
    if _answer(q, _is_blisters_key) in NO_VALUES:
        add("no_blisters", QUESTION_WEIGHT_DEFAULT)
    if _answer(q, _is_sensitive_key) in NO_VALUES:
        add("no_sensitive_area", QUESTION_WEIGHT_DEFAULT)
    if _answer(q, _is_size_key) in NO_VALUES:
        add("small_surface", QUESTION_WEIGHT_DEFAULT)
    if _answer(q, _is_exposure_key) in EXPOSURE_BRIEF_VALUES:
        add("exposure_brief", QUESTION_WEIGHT_PRIORITY)
    # Unknown cause counts as support like any other non-chemical/electrical cause.
    if _answer(q, _is_cause_key) and not _is_high_risk_cause(q):
        add("cause_not_high_risk", QUESTION_WEIGHT_PRIORITY)

    if jev_inconsistency is not None and jev_inconsistency >= NO_BURN_INCONSISTENCY_SUPPORT_THRESHOLD:
        add("answers_inconsistent_with_image", NO_BURN_INCONSISTENCY_SUPPORT)
    top = _cnn_top_probability(cnn_prediction)
    if top is not None and top < NO_BURN_LOW_CERTAINTY_THRESHOLD:
        add("low_image_certainty", NO_BURN_LOW_CERTAINTY_SUPPORT)
    if jev_no_burn_probability is not None and jev_no_burn_probability >= NO_BURN_JEV_PROBABILITY_THRESHOLD:
        add("jev_no_burn_probable", NO_BURN_JEV_PROBABILITY_SUPPORT)

    burn_indicators = []
    threshold = NO_BURN_MIN_SUPPORT
    for key, value in q.items():
        if _is_yes(value):
            if _is_blisters_key(key):
                burn_indicators.append("blisters")
                threshold += NO_BURN_BURN_INDICATOR_PENALTY
            elif _is_size_key(key):
                burn_indicators.append("large_surface")
                threshold += NO_BURN_BURN_INDICATOR_PENALTY
            elif _is_sensitive_key(key):
                burn_indicators.append("sensitive_area")
                threshold += NO_BURN_SENSITIVE_AREA_PENALTY
    if _is_high_risk_cause(q):
        burn_indicators.append("high_risk_cause")
        threshold += NO_BURN_BURN_INDICATOR_PENALTY

    return {
        "score": round(score, 2),
        "threshold": round(threshold, 2),
        "reasons": reasons,
        "answer_support_count": sum(1 for r in reasons if r in ANSWER_SUPPORT_CODES),
        "burn_indicators": burn_indicators,
    }


def _best_burn_class(probabilities, cnn_prediction: dict) -> str | None:
    """Most probable burn class from Jev (excluding no_burn), else the CNN class."""
    if isinstance(probabilities, dict):
        candidates = {}
        for k, v in probabilities.items():
            if k == "no_burn" or k not in BURN_CLASS_CRITERIA:
                continue
            try:
                candidates[k] = float(v)
            except (TypeError, ValueError):
                continue
        if candidates:
            return max(candidates, key=candidates.get)
    return _cnn_class_key((cnn_prediction or {}).get("predicted_class"))


def _recommendation_key(class_key, requires_transfer) -> str:
    if requires_transfer:
        return "go_to_hospital"
    if class_key == "no_burn":
        return "nothing_to_do"
    return "treat_at_home"


def _is_yes(value) -> bool:
    return str(value).strip().lower() in {"da", "yes"}


def _red_flags(cnn_prediction: dict, questionnaire: dict) -> bool:
    """Deterministic clinical red flags that always require transfer."""
    predicted_class = str(cnn_prediction.get("predicted_class", "")).lower()
    q_values = " ".join(str(v).lower() for v in questionnaire.values())

    is_third_degree = any(k in predicted_class for k in ["3rd", "third", "iii"])
    high_risk_cause = any(k in q_values for k in ["chimică", "electrică", "chemical", "electrical"])
    sensitive_or_large = any(
        _is_yes(v)
        for k, v in questionnaire.items()
        if any(term in str(k).lower() for term in ["zonă", "zona", "suprafa", "vezicule"])
    )
    return is_third_degree or high_risk_cause or sensitive_or_large


def _false_positive_check(cnn_prediction: dict, questionnaire: dict, class_key) -> dict:
    """Warn-only detection of burn grades that look overestimated versus the answers.

    Never alters the classification, transfer flag or recommendation.
    """
    questionnaire = questionnaire or {}
    cause = _answer(questionnaire, _is_cause_key)
    exposure = _answer(questionnaire, _is_exposure_key)

    reasons = []
    if _is_high_risk_cause(questionnaire):
        # Never flag chemical/electrical burns.
        pass
    elif class_key in ("first_degree", "second_degree", "third_degree"):
        brief = exposure in EXPOSURE_BRIEF_VALUES
        short = exposure in EXPOSURE_SHORT_VALUES
        thermal_other_sun_unknown = any(
            k in cause for k in ("termic", "thermal", "altele", "other") + SUN_CAUSE_KEYS + UNKNOWN_CAUSE_KEYS
        )
        sun = any(k in cause for k in SUN_CAUSE_KEYS)

        if class_key == "third_degree" and short and thermal_other_sun_unknown:
            reasons.append("third_degree_short_exposure")
        if class_key == "second_degree" and brief:
            reasons.append("second_degree_short_exposure")
        if sun and short:
            reasons.append("sun_exposure_too_short")

    return {"possible_false_positive": bool(reasons), "false_positive_reasons": reasons}


def _cnn_class_key(predicted_class) -> str | None:
    label = str(predicted_class or "").lower()
    if "iii" in label or "3rd" in label:
        return "third_degree"
    if "ii" in label or "2nd" in label:
        return "second_degree"
    if "i" in label or "1st" in label:
        return "first_degree"
    return None


class JevBurnEvaluatorClient:
    def __init__(self, api_key: str | None = None, endpoint: str | None = None):
        self.api_key = api_key or os.getenv("JEV_AI_API_KEY") or os.getenv("TYPESAFE_API_KEY")
        if not self.api_key:
            raise ValueError("JEV_AI_API_KEY environment variable is not set.")

        self.endpoint = endpoint or os.getenv("JEV_AI_ENDPOINT", DEFAULT_ENDPOINT)
        self.model = os.getenv("JEV_AI_MODEL", "jev-latest")
        self.session = requests.Session()
        self.session.headers.update({
            "Authorization": f"Bearer {self.api_key}",
            "Content-Type": "application/json",
        })

    def _fallback_triage(self, cnn_prediction: dict, questionnaire: dict, error_reason: str) -> dict:
        """Deterministic clinical red-flag fallback if the JEV API is unreachable or rejects the call."""
        class_key = _cnn_class_key(cnn_prediction.get("predicted_class"))
        support = _no_burn_support(questionnaire, cnn_prediction)
        top = _cnn_top_probability(cnn_prediction)
        fallback_no_burn = (
            support["score"] >= support["threshold"]
            and support["answer_support_count"] >= FALLBACK_NO_BURN_MIN_ANSWERS
            and top is not None
            and top < NO_BURN_LOW_CERTAINTY_THRESHOLD
        )
        if fallback_no_burn:
            class_key = "no_burn"
            requires_transfer = _requires_transfer_without_burn(questionnaire)
        else:
            requires_transfer = _red_flags(cnn_prediction, questionnaire)
        recommendation = _recommendation_key(class_key, requires_transfer)
        fp = _false_positive_check(cnn_prediction, questionnaire, class_key)
        return {
            "status": "fallback",
            "burn_degree_classification": class_key or cnn_prediction.get("predicted_class"),
            "severity_probability_score": cnn_prediction.get("confidence"),
            "requires_immediate_transfer": requires_transfer,
            "recommendation": recommendation,
            "indicatii": INDICATII[recommendation],
            "fallback_reason": error_reason,
            **fp,
            "no_burn_overridden": False,
            "fallback_no_burn": fallback_no_burn,
            "no_burn_support": support,
            "jev_inconsistency_probability": None,
        }

    def build_payload(self, cnn_prediction: dict, questionnaire: dict) -> dict:
        # The CNN returns probabilities keyed by label, in class-index order (Grad I, II, III).
        probs = list((cnn_prediction.get("probabilities") or {}).values())
        degree_probs = {f"degree_{i + 1}": round(float(p), 4) for i, p in enumerate(probs)}

        vision_output = {
            "status": "low_brightness" if cnn_prediction.get("low_brightness_warning") else "ok",
            "probabilities": degree_probs,
            "image_brightness": cnn_prediction.get("image_brightness"),
        }

        return {
            "model": self.model,
            "state": {
                "vision_output": vision_output,
                "chestionar": questionnaire,
                "question_weights": _question_weights(questionnaire),
            },
            "questions": {
                "final_burn_classification": {
                    "type": "choice",
                    "instructions": (
                        "Using the burn-grade probabilities in `vision_output` and the patient "
                        "answers in `chestionar`, classify the injury. Never conclude 'no_burn' from "
                        "a single answer; several answers must agree. Causes are thermal, chemical, electrical, radiation (UV/X), "
                        "other (friction, falls), sun exposure ('Expunere la soare'; typically 1st "
                        "degree, sometimes 2nd degree with blisters) and unknown ('Nu știu ce a "
                        "cauzat arsura'; the grade is then less certain, so do not be overconfident). "
                        "The exposure duration and the age of the patient are also in `chestionar`; "
                        "weigh them (very short exposure makes deep burns unlikely unless the cause "
                        "is chemical or electrical; children under 5 and adults over 60 have thinner "
                        "skin and burn more deeply). Low probabilities combined with no pain, no "
                        "blisters, a small surface, no sensitive area and a very brief exposure "
                        "indicate healthy skin. When the image is uncertain and several answers are "
                        "implausible for a burn or inconsistent with each other (for example an unknown "
                        "cause with a very short exposure, no pain and no blisters, or a severe-looking "
                        "grade with trivial answers), choose 'no_burn', whatever the cause, including "
                        "unknown; never because of one answer alone. " + WEIGHT_INSTRUCTION
                    ),
                    "criteria": BURN_CLASS_CRITERIA,
                },
                "severity_score": {
                    "type": "score",
                    "instructions": (
                        "Rate the overall clinical severity of this case from `vision_output` "
                        "and `chestionar`. " + WEIGHT_INSTRUCTION
                    ),
                    "criteria": SEVERITY_LEVELS,
                },
                "requires_immediate_transfer": {
                    "type": "noul",
                    "instructions": (
                        "The patient needs immediate transfer to an emergency or burn unit "
                        "based on `vision_output` and `chestionar`. Sensitive areas are palms, "
                        "soles, face, neck and the genital area. " + WEIGHT_INSTRUCTION
                    ),
                    "criteria": {
                        "true": "Deep or large burn, sensitive area (palms, soles, face, neck, genital area), chemical/electrical cause, or severe pain",
                        "false": "Superficial or no burn that can be managed with first aid",
                    },
                },
                "answers_inconsistent_with_image": {
                    "type": "noul",
                    "instructions": (
                        "The `chestionar` answers (exposure duration, age, pain, blisters, cause) "
                        "are inconsistent with the visual burn grade in `vision_output`, for "
                        "example a deep burn grade with a very short exposure (the exposure "
                        "duration is the main signal), or a sunburn with only seconds of sun. "
                        "Low pain and no blisters also weigh against deep burns. " + WEIGHT_INSTRUCTION
                    ),
                    "criteria": {
                        "true": "The questionnaire answers contradict the visual burn grade",
                        "false": "The questionnaire answers are consistent with the visual burn grade",
                    },
                },
            },
        }

    def evaluate_burn(self, cnn_prediction: dict, questionnaire: dict) -> dict:
        """Sends CNN probabilities + questionnaire to Jev System One, with a clinical fallback."""
        payload = self.build_payload(cnn_prediction, questionnaire)

        try:
            response = self.session.post(self.endpoint, json=payload, timeout=(5, 15))
            if not response.ok:
                # 422 bodies name the offending field; keep them for debugging.
                return self._fallback_triage(
                    cnn_prediction, questionnaire,
                    f"HTTP {response.status_code}: {response.text[:500]}",
                )

            api_data = response.json()
            answers = api_data["answers"]
            classification = answers["final_burn_classification"]
            severity = answers.get("severity_score", {})
            transfer = answers.get("requires_immediate_transfer", {})

            choice = classification.get("choice")
            original_choice = choice

            inconsistency = answers.get("answers_inconsistent_with_image", {}).get("noul")
            inconsistency = float(inconsistency) if inconsistency is not None else None
            jev_probs = classification.get("probabilities")
            jev_no_burn_prob = None
            if isinstance(jev_probs, dict) and jev_probs.get("no_burn") is not None:
                try:
                    jev_no_burn_prob = float(jev_probs["no_burn"])
                except (TypeError, ValueError):
                    jev_no_burn_prob = None
            support = _no_burn_support(questionnaire, cnn_prediction, inconsistency, jev_no_burn_prob)

            no_burn_overridden = False
            override_reason = None
            if choice == "no_burn" and support["score"] < support["threshold"]:
                override_reason = NO_BURN_CONTRADICTED_REASON if support["burn_indicators"] else NO_BURN_REASON
                alternative = _best_burn_class(jev_probs, cnn_prediction)
                if alternative:
                    choice = alternative
                    no_burn_overridden = True
                else:
                    override_reason = None

            transfer_probability = float(transfer.get("noul", 0.0))
            if choice == "no_burn":
                # Only chemical/electrical causes and radiation can injure without visible burns.
                requires_transfer = _requires_transfer_without_burn(questionnaire)
            else:
                # Red flags computed in code always force transfer, regardless of the model answer.
                requires_transfer = (
                    transfer_probability >= 0.5
                    or choice == "third_degree"
                    or _red_flags(cnn_prediction, questionnaire)
                )

            severity_value = severity.get("score")
            recommendation = _recommendation_key(choice, requires_transfer)

            fp = _false_positive_check(cnn_prediction, questionnaire, choice)
            if (
                inconsistency is not None
                and inconsistency >= JEV_INCONSISTENCY_THRESHOLD
                and not _is_high_risk_cause(questionnaire)
                and choice != "no_burn"
            ):
                fp["possible_false_positive"] = True
                fp["false_positive_reasons"].append("answers_inconsistent_with_image")
            return {
                "status": "success",
                "burn_degree_classification": choice,
                "jev_original_classification": original_choice,
                "no_burn_overridden": no_burn_overridden,
                "no_burn_override_reason": override_reason if no_burn_overridden else None,
                "no_burn_support": support,
                "classification_probabilities": classification.get("probabilities"),
                "classification_confidence": classification.get("confidence"),
                "severity_probability_score": round(float(severity_value), 2) if severity_value is not None else None,
                "requires_immediate_transfer": requires_transfer,
                "transfer_probability": transfer_probability,
                "recommendation": recommendation,
                "indicatii": INDICATII[recommendation],
                **fp,
                "jev_inconsistency_probability": inconsistency,
                "jev_model": api_data.get("model"),
                "raw_jev_response": api_data,
            }
        except (requests.RequestException, ValueError, KeyError, TypeError) as exc:
            return self._fallback_triage(cnn_prediction, questionnaire, f"{type(exc).__name__}: {exc}")
