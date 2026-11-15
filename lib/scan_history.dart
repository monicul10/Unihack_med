import 'dart:io';

// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'triage.dart';

const _bucket = 'burn_photos';

/// One row of the user's history. [degree] is 0 for "no burn" and 1–3 for a
/// burn grade. [degree] and [probability] are null for scans saved before
/// results were stored ("Not analyzed").
class ScanRecord {
  final DateTime createdAt;
  final int? degree;
  final double? probability;
  final String? imageUrl; // short-lived signed URL, null if the photo is missing

  const ScanRecord(this.createdAt, this.degree, this.probability, this.imageUrl);
}

/// Saves analyzed scans and reads them back. Supabase RLS limits every query to
/// the logged-in user's own rows and photos (see supabase/migrations).
class ScanHistoryService {
  SupabaseClient get _db => Supabase.instance.client;

  /// Uploads the photo to `<user_id>/<timestamp>.<ext>` and stores the result.
  Future<void> save(File image, TriageDecision result) async {
    final user = _db.auth.currentUser;
    if (user == null) throw Exception('Not logged in');

    final ext = image.path.split('.').last.toLowerCase();
    final path = '${user.id}/${DateTime.now().millisecondsSinceEpoch}.$ext';

    await _db.storage.from(_bucket).upload(path, image);
    await _db.from('scans').insert({
      'user_id': user.id,
      'image_path': path,
      'degree': result.degree, // 0 = no burn
      'probability': result.confidence,
    });
  }

  /// The user's scans, newest first, with signed photo URLs valid for 1 hour.
  Future<List<ScanRecord>> fetch() async {
    final user = _db.auth.currentUser;
    if (user == null) throw Exception('Not logged in');

    final rows = await _db
        .from('scans')
        .select('created_at, degree, probability, image_path')
        .eq('user_id', user.id)
        .order('created_at', ascending: false);

    final paths = [
      for (final r in rows)
        if (r['image_path'] != null) r['image_path'] as String
    ];
    final urls = <String, String>{};
    if (paths.isNotEmpty) {
      final signed = await _db.storage.from(_bucket).createSignedUrlsResult(paths, 3600);
      for (final s in signed) {
        if (s is SignedUrlSuccess) urls[s.path] = s.signedUrl;
      }
    }

    return [
      for (final r in rows)
        ScanRecord(
          DateTime.parse(r['created_at'] as String).toLocal(),
          r['degree'] as int?,
          (r['probability'] as num?)?.toDouble(),
          urls[r['image_path']],
        )
    ];
  }
}

// ============================================================================
// ECRAN: ISTORIC SCANĂRI
// ============================================================================
class HistoryScreen extends StatefulWidget {
  final bool isDarkMode;
  final String currentLang;

  const HistoryScreen({super.key, required this.isDarkMode, required this.currentLang});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  late Future<List<ScanRecord>> _future = ScanHistoryService().fetch();

  bool get isRo => widget.currentLang == 'ro';

  Future<void> _reload() async {
    final f = ScanHistoryService().fetch();
    setState(() => _future = f);
    await f.catchError((_) => <ScanRecord>[]);
  }

  String _date(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}.${two(d.month)}.${d.year}  ${two(d.hour)}:${two(d.minute)}';
  }

  Color _degreeColor(int? degree) => switch (degree) {
        0 => const Color(0xFF58B97D),
        1 => Colors.green,
        2 => Colors.orange,
        3 => const Color(0xFFFF6B6B),
        _ => Colors.grey,
      };

  @override
  Widget build(BuildContext context) {
    final bgColor = widget.isDarkMode ? const Color(0xFF0E1C14) : const Color(0xFFEAEFE9);
    final cardBg = widget.isDarkMode ? const Color(0xFF15261C) : const Color(0xFFD4E2D7);
    final accent = widget.isDarkMode ? const Color(0xFFD8D7D3) : const Color(0xFF1C3826);
    const medicalGreen = Color(0xFF3F895A);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Text(isRo ? 'Istoric' : 'History',
            style: TextStyle(fontWeight: FontWeight.bold, color: accent)),
        backgroundColor: bgColor,
        iconTheme: IconThemeData(color: accent),
        elevation: 0,
      ),
      body: FutureBuilder<List<ScanRecord>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: medicalGreen));
          }

          final Widget message;
          if (snap.hasError) {
            message = _Message(
              icon: Icons.error_outline,
              title: isRo ? 'Istoricul nu a putut fi încărcat' : 'Could not load history',
              detail: '${snap.error}',
              accent: accent,
            );
          } else if (snap.data!.isEmpty) {
            message = _Message(
              icon: Icons.history,
              title: isRo ? 'Nicio scanare încă' : 'No scans yet',
              detail: isRo
                  ? 'Rezultatele analizelor tale vor apărea aici.'
                  : 'Your analysis results will appear here.',
              accent: accent,
            );
          } else {
            message = const SizedBox.shrink();
          }

          final scans = snap.data ?? const <ScanRecord>[];
          return RefreshIndicator(
            color: medicalGreen,
            onRefresh: _reload,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                if (scans.isEmpty) message,
                for (final s in scans)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: _degreeColor(s.degree), width: 1.5),
                    ),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: SizedBox(
                            width: 76,
                            height: 76,
                            child: s.imageUrl == null
                                ? _photoPlaceholder()
                                : Image.network(
                                    s.imageUrl!,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, _, _) => _photoPlaceholder(),
                                  ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                switch (s.degree) {
                                  null => isRo ? 'Neanalizată' : 'Not analyzed',
                                  0 => isRo ? 'Fără arsură' : 'No burn',
                                  _ => isRo
                                      ? 'Arsură Gradul ${s.degree}'
                                      : 'Degree ${s.degree} Burn',
                                },
                                style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: s.degree == null ? accent : _degreeColor(s.degree)),
                              ),
                              if (s.probability != null) ...[
                                const SizedBox(height: 3),
                                Text(
                                  '${isRo ? 'Încredere' : 'Confidence'}: '
                                  '${(s.probability! * 100).toStringAsFixed(1)}%',
                                  style: TextStyle(fontSize: 13, color: accent),
                                ),
                              ],
                              const SizedBox(height: 3),
                              Text(
                                _date(s.createdAt),
                                style: TextStyle(
                                    fontSize: 12, color: accent.withValues(alpha: 0.7)),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _photoPlaceholder() => Container(
        color: Colors.black26,
        child: const Icon(Icons.image_not_supported_outlined, color: Colors.white54),
      );
}

class _Message extends StatelessWidget {
  final IconData icon;
  final String title, detail;
  final Color accent;

  const _Message(
      {required this.icon, required this.title, required this.detail, required this.accent});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 80),
        child: Column(
          children: [
            Icon(icon, size: 54, color: accent.withValues(alpha: 0.6)),
            const SizedBox(height: 12),
            Text(title,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: accent)),
            const SizedBox(height: 6),
            Text(detail,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: accent.withValues(alpha: 0.75))),
          ],
        ),
      );
}
