/// Burn triage rules: questionnaire keywords and weights, image-model mapping,
/// post-processing of Jev's answers, and the fallback when Jev is unavailable.
/// Follows the shared CromerCare specification (Sections 1, 2 and 5–8), so the
/// app and the website give the same result for the same input.
///
/// One local addition: for a "no burn" result, a radiation cause also requires
/// urgent transfer (the spec lists only chemical and electrical).
library;

// --- Section 1: weights ------------------------------------------------------
const questionWeightPriority = 1.2;
const questionWeightDefault = 1.0;

// --- Section 5: post-processing constants -------------------------------------
const noBurnMinSupport = 3.0;
const noBurnBurnIndicatorPenalty = 1.5;
const noBurnSensitiveAreaPenalty = 0.5;
const noBurnInconsistencySupportThreshold = 0.7;
const noBurnInconsistencySupport = 1.2;
const noBurnLowCertaintyThreshold = 0.5;
const noBurnLowCertaintySupport = 1.0;
const noBurnJevProbabilityThreshold = 0.5;
const noBurnJevProbabilitySupport = 1.0;
const fallbackNoBurnMinAnswers = 3;
const jevInconsistencyThreshold = 0.7;
const transferProbabilityThreshold = 0.5;
const lowBrightnessThreshold = 55.0;

// --- Class keys ----------------------------------------------------------------
const noBurn = 'no_burn';
const firstDegree = 'first_degree';
const secondDegree = 'second_degree';
const thirdDegree = 'third_degree';
const burnClasses = [firstDegree, secondDegree, thirdDegree];

/// 0 = no burn, 1–3 = burn grade.
int degreeOf(String classKey) => switch (classKey) {
      firstDegree => 1,
      secondDegree => 2,
      thirdDegree => 3,
      _ => 0,
    };

// --- Section 1: keyword matching on question keys ---------------------------------
bool _has(String text, List<String> words) {
  final t = text.toLowerCase();
  return words.any(t.contains);
}

bool isExposureKey(String k) => _has(k, ['expunere', 'exposure']);
bool isCauseKey(String k) => _has(k, ['cauza', 'cause']) && !isExposureKey(k);
bool isPainKey(String k) => _has(k, ['durere', 'pain']);
bool isSensitiveAreaKey(String k) => _has(k, ['zonă', 'zona', 'sensitive', 'area']);
bool isSizeKey(String k) => _has(k, ['suprafa', 'surface']);
bool isBlistersKey(String k) => _has(k, ['vezicule', 'blister']);

double questionWeight(String key) =>
    isCauseKey(key) || isExposureKey(key) ? questionWeightPriority : questionWeightDefault;

Map<String, double> questionWeights(Map<String, String> chestionar) =>
    {for (final k in chestionar.keys) k: questionWeight(k)};

String _norm(String? v) => (v ?? '').trim().toLowerCase();
bool isYes(String? v) => const ['da', 'yes'].contains(_norm(v));
bool isNo(String? v) => const ['nu', 'no'].contains(_norm(v));

// Cause categories (substring match on the lower-cased cause answer).
bool isHighRiskCause(String c) => _has(c, ['chimic', 'electric', 'chemical', 'electrical']);
bool isSunCause(String c) => _has(c, ['soare', 'sun exposure']);
bool isUnknownCause(String c) => _has(c, ['nu știu', 'nu stiu', "don't know", 'don’t know']);
bool isRadiationCause(String c) => _has(c, ['radia']); // "Radiații" / "Radiation"
bool isThermalOtherSunOrUnknown(String c) =>
    _has(c, ['termic', 'thermal', 'altele', 'other']) || isSunCause(c) || isUnknownCause(c);

// Exposure categories.
bool isBriefExposure(String e) => const ['< 1 secundă', '< 1 second'].contains(_norm(e));
bool isShortExposure(String e) =>
    isBriefExposure(e) || const ['< 10 secunde', '< 10 seconds'].contains(_norm(e));

const _noPainValues = [
  '0–2 (fără durere / disconfort)',
  '0-2 (fără durere / disconfort)',
  '0–2 (no pain / discomfort)',
  '0-2 (no pain / discomfort)',
];
bool isNoPain(String p) => _noPainValues.contains(_norm(p));

/// The answers the rules need, found by keyword in the question keys.
class Answers {
  final Map<String, String> chestionar;
  const Answers(this.chestionar);

  String _find(bool Function(String) isKey) {
    for (final e in chestionar.entries) {
      if (isKey(e.key)) return e.value;
    }
    return '';
  }

  String get cause => _find(isCauseKey);
  String get exposure => _find(isExposureKey);
  String get pain => _find(isPainKey);
  String get sensitiveArea => _find(isSensitiveAreaKey);
  String get size => _find(isSizeKey);
  String get blisters => _find(isBlistersKey);
}

// --- Section 2: image model output ------------------------------------------------
const imageLabels = ['Grad I (1st Degree)', 'Grad II (2nd Degree)', 'Grad III (3rd Degree)'];

class ImageModelOutput {
  final List<double> probabilities; // [grade 1, grade 2, grade 3], softmax
  final double brightness; // mean grayscale 0–255

  const ImageModelOutput(this.probabilities, this.brightness);

  int get _top {
    var best = 0;
    for (var i = 1; i < probabilities.length; i++) {
      if (probabilities[i] > probabilities[best]) best = i;
    }
    return best;
  }

  String get predictedClass => imageLabels[_top];
  double get confidence => probabilities[_top];
  bool get lowBrightnessWarning => brightness < lowBrightnessThreshold;
  String? get classKey => classKeyFromLabel(predictedClass);
}

/// Checked in this order: "iii"/"3rd", then "ii"/"2nd", then "i"/"1st".
String? classKeyFromLabel(String label) {
  final l = label.toLowerCase();
  if (l.contains('iii') || l.contains('3rd')) return thirdDegree;
  if (l.contains('ii') || l.contains('2nd')) return secondDegree;
  if (l.contains('i') || l.contains('1st')) return firstDegree;
  return null;
}

// --- Section 4: Jev response ----------------------------------------------------
class JevAnswers {
  final String choice;
  final Map<String, double> probabilities;
  final double? confidence;
  final double? severityScore;
  final double? transferProbability;
  final double? inconsistency;
  final String? model;
  final Map<String, dynamic> raw;

  const JevAnswers({
    required this.choice,
    required this.probabilities,
    this.confidence,
    this.severityScore,
    this.transferProbability,
    this.inconsistency,
    this.model,
    this.raw = const {},
  });

  /// Throws [FormatException] if the response has no usable classification.
  factory JevAnswers.fromJson(Map<String, dynamic> json) {
    double? num_(Object? v) => v is num ? v.toDouble() : null;
    Map<String, dynamic> obj(Object? v) => v is Map ? Map<String, dynamic>.from(v) : {};

    final answers = obj(json['answers']);
    final cls = obj(answers['final_burn_classification']);
    final choice = cls['choice'];
    if (choice is! String || !([noBurn, ...burnClasses].contains(choice))) {
      throw FormatException('Jev returned no valid final_burn_classification.choice: $choice');
    }
    return JevAnswers(
      choice: choice,
      probabilities: {
        for (final e in obj(cls['probabilities']).entries)
          if (e.value is num) e.key: (e.value as num).toDouble(),
      },
      confidence: num_(cls['confidence']),
      severityScore: num_(obj(answers['severity_score'])['score']),
      transferProbability: num_(obj(answers['requires_immediate_transfer'])['noul']),
      inconsistency: num_(obj(answers['answers_inconsistent_with_image'])['noul']),
      model: json['model'] as String?,
      raw: json,
    );
  }
}

// --- Section 6, steps 2–3: no-burn support score --------------------------------------
class NoBurnSupport {
  final double score;
  final double threshold;
  final List<String> reasons;
  final int answerSupportCount;
  final List<String> burnIndicators;

  const NoBurnSupport(
      this.score, this.threshold, this.reasons, this.answerSupportCount, this.burnIndicators);

  bool get reached => score >= threshold;
}

double _round2(double v) => (v * 100).round() / 100;

NoBurnSupport noBurnSupport(Answers a, ImageModelOutput image,
    {double? inconsistency, double? jevNoBurnProb}) {
  var score = 0.0;
  final reasons = <String>[];
  void add(bool cond, double points, String reason) {
    if (cond) {
      score += points;
      reasons.add(reason);
    }
  }

  // Answer-based items (counted in answerSupportCount).
  add(isNoPain(a.pain), 1.0, 'pain_none');
  add(isNo(a.blisters), 1.0, 'no_blisters');
  add(isNo(a.sensitiveArea), 1.0, 'no_sensitive_area');
  add(isNo(a.size), 1.0, 'small_surface');
  add(isBriefExposure(a.exposure), 1.2, 'exposure_brief');
  add(a.cause.trim().isNotEmpty && !isHighRiskCause(a.cause), 1.2, 'cause_not_high_risk');
  final answerSupportCount = reasons.length;

  // Model-based items.
  add(inconsistency != null && inconsistency >= noBurnInconsistencySupportThreshold,
      noBurnInconsistencySupport, 'answers_inconsistent_with_image');
  final topProb = image.probabilities.isEmpty
      ? image.confidence
      : image.probabilities.reduce((x, y) => x > y ? x : y);
  add(topProb < noBurnLowCertaintyThreshold, noBurnLowCertaintySupport, 'low_image_certainty');
  add(jevNoBurnProb != null && jevNoBurnProb >= noBurnJevProbabilityThreshold,
      noBurnJevProbabilitySupport, 'jev_no_burn_probable');

  var threshold = noBurnMinSupport;
  final indicators = <String>[];
  if (isYes(a.blisters)) {
    threshold += noBurnBurnIndicatorPenalty;
    indicators.add('blisters');
  }
  if (isYes(a.size)) {
    threshold += noBurnBurnIndicatorPenalty;
    indicators.add('large_surface');
  }
  if (isYes(a.sensitiveArea)) {
    threshold += noBurnSensitiveAreaPenalty;
    indicators.add('sensitive_area');
  }
  if (isHighRiskCause(a.cause)) {
    threshold += noBurnBurnIndicatorPenalty;
    indicators.add('high_risk_cause');
  }

  return NoBurnSupport(_round2(score), _round2(threshold), reasons, answerSupportCount, indicators);
}

// --- Section 5, step 5: red flags ------------------------------------------------------
bool hasRedFlags(Map<String, String> chestionar, ImageModelOutput image) {
  if (_has(image.predictedClass, ['3rd', 'third', 'iii'])) return true;
  if (_has(chestionar.values.join(' '), ['chimică', 'electrică', 'chemical', 'electrical'])) {
    return true;
  }
  return chestionar.entries
      .any((e) => _has(e.key, ['zonă', 'zona', 'suprafa', 'vezicule']) && isYes(e.value));
}

/// For "no burn": transfer only for chemical, electrical or (local rule) radiation.
bool _noBurnTransfer(Answers a) => isHighRiskCause(a.cause) || isRadiationCause(a.cause);

// --- Section 6, step 6 and Section 8: recommendation ------------------------------------
const goToHospital = 'go_to_hospital';
const treatAtHome = 'treat_at_home';
const nothingToDo = 'nothing_to_do';

String recommendationFor(bool requiresTransfer, String classKey) => requiresTransfer
    ? goToHospital
    : classKey == noBurn
        ? nothingToDo
        : treatAtHome;

/// Exact Romanian texts (INDICATII).
const indicatiiRo = {
  goToHospital: 'RECOMANDARE: Prezintă-te de urgență la spital / medic.\n\n'
      'Acoperă zona cu un pansament steril, curat, fără a aplica unguente sau gheață.\n'
      'Solicită evaluare medicală imediată.',
  treatAtHome: 'RECOMANDARE: Îngrijire și monitorizare la domiciliu.\n\n'
      'Răcește zona cu apă călduță/rece (nu gheață) timp de 10-15 minute.\n'
      'Aplică o cremă hidratantă/calmanta potrivită și monitorizează evoluția.',
  nothingToDo: 'RECOMANDARE: Nu este necesară nicio intervenție.\n\n'
      'Pielea nu prezintă semne care să necesite tratament; menține zona curată.',
};

/// English display versions of the same texts.
const indicatiiEn = {
  goToHospital: 'RECOMMENDATION: Go to a hospital / doctor urgently.\n\n'
      'Cover the area with a clean, sterile dressing, without ointments or ice.\n'
      'Seek immediate medical assessment.',
  treatAtHome: 'RECOMMENDATION: Care and monitoring at home.\n\n'
      'Cool the area with lukewarm/cool water (not ice) for 10-15 minutes.\n'
      'Apply a suitable moisturising/soothing cream and watch how it evolves.',
  nothingToDo: 'RECOMMENDATION: No intervention is needed.\n\n'
      'The skin shows no signs that need treatment; keep the area clean.',
};

// --- Section 6, step 7: false-positive warnings ---------------------------------------------
List<String> falsePositiveReasons(String choice, Answers a, {double? inconsistency}) {
  final reasons = <String>[];
  if (isHighRiskCause(a.cause)) return reasons;
  if (burnClasses.contains(choice)) {
    if (choice == thirdDegree &&
        isShortExposure(a.exposure) &&
        isThermalOtherSunOrUnknown(a.cause)) {
      reasons.add('third_degree_short_exposure');
    }
    if (choice == secondDegree && isBriefExposure(a.exposure)) {
      reasons.add('second_degree_short_exposure');
    }
    if (isSunCause(a.cause) && isShortExposure(a.exposure)) {
      reasons.add('sun_exposure_too_short');
    }
  }
  if (inconsistency != null && inconsistency >= jevInconsistencyThreshold && choice != noBurn) {
    reasons.add('answers_inconsistent_with_image');
  }
  return reasons;
}

// --- Section 9: decision ------------------------------------------------------------------
class TriageDecision {
  final String status; // 'success' or 'fallback'
  final String burnDegreeClassification;
  final String? jevOriginalClassification;
  final bool noBurnOverridden;
  final String? noBurnOverrideReason;
  final bool fallbackNoBurn;
  final NoBurnSupport noBurnSupport;
  final Map<String, double> classificationProbabilities;
  final double? classificationConfidence;
  final double? severityProbabilityScore;
  final bool requiresImmediateTransfer;
  final double? transferProbability;
  final String recommendation;
  final List<String> falsePositiveReasons;
  final double? jevInconsistencyProbability;
  final String? jevModel;
  final String? fallbackReason;
  final ImageModelOutput image;

  const TriageDecision({
    required this.status,
    required this.burnDegreeClassification,
    this.jevOriginalClassification,
    required this.noBurnOverridden,
    this.noBurnOverrideReason,
    this.fallbackNoBurn = false,
    required this.noBurnSupport,
    required this.classificationProbabilities,
    this.classificationConfidence,
    this.severityProbabilityScore,
    required this.requiresImmediateTransfer,
    this.transferProbability,
    required this.recommendation,
    required this.falsePositiveReasons,
    this.jevInconsistencyProbability,
    this.jevModel,
    this.fallbackReason,
    required this.image,
  });

  bool get isFallback => status == 'fallback';
  bool get possibleFalsePositive => falsePositiveReasons.isNotEmpty;
  int get degree => degreeOf(burnDegreeClassification);
  String get indicatii => indicatiiRo[recommendation]!;

  /// Shown as "Încredere" / "Confidence". With Jev: Jev's confidence; in the
  /// fallback: the image model's confidence.
  double get confidence => classificationConfidence ?? image.confidence;
}

/// Section 6: Jev answered successfully.
TriageDecision decideWithJev(
    JevAnswers jev, Map<String, String> chestionar, ImageModelOutput image) {
  final a = Answers(chestionar);
  var choice = jev.choice;
  final originalChoice = choice;

  final support = noBurnSupport(a, image,
      inconsistency: jev.inconsistency, jevNoBurnProb: jev.probabilities[noBurn]);

  // Step 4: only Jev can choose no_burn; the code only validates it.
  var overridden = false;
  String? overrideReason;
  if (choice == noBurn && !support.reached) {
    String? alternative;
    var best = -1.0;
    for (final k in burnClasses) {
      final p = jev.probabilities[k];
      if (p != null && p > best) {
        best = p;
        alternative = k;
      }
    }
    alternative ??= image.classKey;
    if (alternative != null) {
      choice = alternative;
      overridden = true;
      overrideReason = support.burnIndicators.isNotEmpty
          ? 'no_burn_contradicted_by_answers'
          : 'no_burn_insufficient_evidence';
    }
  }

  // Step 5: transfer.
  final transferProb = jev.transferProbability ?? 0.0;
  final requiresTransfer = choice == noBurn
      ? _noBurnTransfer(a)
      : transferProb >= transferProbabilityThreshold ||
          choice == thirdDegree ||
          hasRedFlags(chestionar, image);

  return TriageDecision(
    status: 'success',
    burnDegreeClassification: choice,
    jevOriginalClassification: originalChoice,
    noBurnOverridden: overridden,
    noBurnOverrideReason: overrideReason,
    noBurnSupport: support,
    classificationProbabilities: jev.probabilities,
    classificationConfidence: jev.confidence,
    severityProbabilityScore: jev.severityScore == null ? null : _round2(jev.severityScore!),
    requiresImmediateTransfer: requiresTransfer,
    transferProbability: transferProb,
    recommendation: recommendationFor(requiresTransfer, choice),
    falsePositiveReasons: falsePositiveReasons(choice, a, inconsistency: jev.inconsistency),
    jevInconsistencyProbability: jev.inconsistency,
    jevModel: jev.model,
    image: image,
  );
}

/// Section 7: Jev unavailable, error, timeout or malformed response.
TriageDecision decideFallback(
    Map<String, String> chestionar, ImageModelOutput image, String fallbackReason) {
  final a = Answers(chestionar);
  final support = noBurnSupport(a, image);
  final topProb = image.probabilities.reduce((x, y) => x > y ? x : y);

  final fallbackNoBurn = support.reached &&
      support.answerSupportCount >= fallbackNoBurnMinAnswers &&
      topProb < noBurnLowCertaintyThreshold;

  final classKey = fallbackNoBurn ? noBurn : (image.classKey ?? firstDegree);
  final requiresTransfer =
      fallbackNoBurn ? _noBurnTransfer(a) : hasRedFlags(chestionar, image);

  return TriageDecision(
    status: 'fallback',
    burnDegreeClassification: classKey,
    noBurnOverridden: false,
    fallbackNoBurn: fallbackNoBurn,
    noBurnSupport: support,
    classificationProbabilities: {
      for (var i = 0; i < burnClasses.length; i++) burnClasses[i]: image.probabilities[i],
    },
    severityProbabilityScore: image.confidence,
    requiresImmediateTransfer: requiresTransfer,
    recommendation: recommendationFor(requiresTransfer, classKey),
    falsePositiveReasons: falsePositiveReasons(classKey, a),
    fallbackReason: fallbackReason,
    image: image,
  );
}
