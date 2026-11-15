import 'package:supabase_flutter/supabase_flutter.dart';

import 'classifier.dart';
import 'triage.dart';

/// Thrown when Jev can't be used. [message] becomes the fallback_reason,
/// for example "HTTP 402: insufficient_balance".
class JevUnavailable implements Exception {
  final String message;
  const JevUnavailable(this.message);
  @override
  String toString() => message;
}

/// Sends the image-model output and the questionnaire to Jev through the
/// "burn-triage" Supabase Edge Function (spec Section 3). The function adds the
/// question weights and the four Jev questions, and keeps the API key on the server.
class JevService {
  static const functionName = 'burn-triage';

  double _r4(double v) => (v * 10000).round() / 10000;

  Future<JevAnswers> ask(ImageModelOutput image, Map<String, String> chestionar) async {
    final payload = {
      'vision_output': {
        'status': image.lowBrightnessWarning ? 'low_brightness' : 'ok',
        'probabilities': {
          'degree_1': _r4(image.probabilities[0]),
          'degree_2': _r4(image.probabilities[1]),
          'degree_3': _r4(image.probabilities[2]),
        },
        'image_brightness': (image.brightness * 10).round() / 10,
      },
      'chestionar': chestionar,
    };

    final FunctionResponse res;
    try {
      res = await Supabase.instance.client.functions
          .invoke(functionName, body: payload)
          .timeout(const Duration(seconds: 25));
    } on FunctionException catch (e) {
      final d = e.details;
      if (e.status == 422 && d is Map && d['detail'] is Map && d['detail']['code'] == 'low_brightness') {
        throw PhotoTooDarkException(image.brightness);
      }
      // The function wraps Jev errors (401 key, 402 credits, 429 rate limit) in a 502.
      if (d is Map && d['upstream_status'] is int) {
        throw JevUnavailable('HTTP ${d['upstream_status']}: ${d['detail']}');
      }
      throw JevUnavailable('HTTP ${e.status}: $d');
    }

    final data = res.data;
    if (data is! Map) throw JevUnavailable('Malformed Jev response: $data');
    try {
      return JevAnswers.fromJson(Map<String, dynamic>.from(data));
    } on FormatException catch (e) {
      throw JevUnavailable(e.message);
    }
  }
}
