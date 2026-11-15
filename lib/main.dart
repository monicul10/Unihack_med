import 'dart:async';
import 'dart:io';
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'assessment.dart';
import 'classifier.dart';
import 'jev_service.dart';
import 'questions.dart';
import 'scan_history.dart';

// ÎNLOCUIEȘTE CU DATELE DIN PROIECTUL TĂU NOU SUPABASE (Project Settings > API):
const String supabaseUrl = 'https://fzwiaeaspyvepblicmnd.supabase.co';
const String supabaseAnonKey = 'sb_publishable_1Synb5RPGhlTipS1oYDqlA_BJ07hFm9';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: supabaseUrl,
    publishableKey: supabaseAnonKey,
  );

  runApp(const DaVinciMedApp());
}

final supabase = Supabase.instance.client;

class DaVinciMedApp extends StatefulWidget {
  const DaVinciMedApp({super.key});

  @override
  State<DaVinciMedApp> createState() => _DaVinciMedAppState();
}

class _DaVinciMedAppState extends State<DaVinciMedApp> {
  bool isDarkMode = true;
  String currentLang = 'ro';

  void toggleTheme() => setState(() => isDarkMode = !isDarkMode);
  void toggleLang() =>
      setState(() => currentLang = currentLang == 'ro' ? 'en' : 'ro');

  @override
  Widget build(BuildContext context) {
    final bgColor = isDarkMode ? const Color(0xFF0E1C14) : const Color(0xFFEAEFE9);
    final accentColor = isDarkMode ? const Color(0xFFD8D7D3) : const Color(0xFF1C3826);

    return MaterialApp(
      title: 'DaVinciMed',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: isDarkMode ? Brightness.dark : Brightness.light,
        scaffoldBackgroundColor: bgColor,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF3F895A),
          brightness: isDarkMode ? Brightness.dark : Brightness.light,
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: bgColor,
          foregroundColor: accentColor,
          elevation: 0,
        ),
      ),
      home: StreamBuilder<AuthState>(
        stream: supabase.auth.onAuthStateChange,
        builder: (context, snapshot) {
          final session =
              snapshot.data?.session ?? supabase.auth.currentSession;
          if (session != null) {
            return CaptureScreen(
              isDarkMode: isDarkMode,
              currentLang: currentLang,
              onToggleTheme: toggleTheme,
              onToggleLang: toggleLang,
            );
          }
          return AuthScreen(
            isDarkMode: isDarkMode,
            currentLang: currentLang,
            onToggleTheme: toggleTheme,
            onToggleLang: toggleLang,
          );
        },
      ),
    );
  }
}

// ============================================================================
// SCREEN 1: AUTHENTICATION (LOGIN / REGISTER)
// ============================================================================
class AuthScreen extends StatefulWidget {
  final bool isDarkMode;
  final String currentLang;
  final VoidCallback onToggleTheme;
  final VoidCallback onToggleLang;

  const AuthScreen({
    super.key,
    required this.isDarkMode,
    required this.currentLang,
    required this.onToggleTheme,
    required this.onToggleLang,
  });

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isRegisterMode = false;
  bool _isLoading = false;

  bool get isRo => widget.currentLang == 'ro';

  Future<void> _submitAuth() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      _showSnack(isRo
          ? 'Te rugăm să introduci email-ul și parola.'
          : 'Please enter email and password.');
      return;
    }

    setState(() => _isLoading = true);

    try {
      if (_isRegisterMode) {
        final res = await supabase.auth.signUp(
          email: email,
          password: password,
        );
        if (res.session == null) {
          // Auto-login fallback matching sitev1.html
          await supabase.auth.signInWithPassword(
            email: email,
            password: password,
          );
        }
      } else {
        await supabase.auth.signInWithPassword(
          email: email,
          password: password,
        );
      }
    } on AuthException catch (e) {
      _showSnack(isRo
          ? 'Eroare autentificare: ${e.message}'
          : 'Auth error: ${e.message}');
    } catch (e) {
      _showSnack('Error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cardBg = widget.isDarkMode ? const Color(0xFF15261C) : const Color(0xFFD4E2D7);
    final accent = widget.isDarkMode ? const Color(0xFFD8D7D3) : const Color(0xFF1C3826);
    const medicalGreen = Color(0xFF3F895A);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.local_hospital, color: accent, size: 22),
                const SizedBox(width: 8),
                Text(
                  'DaVinciMed',
                  style: TextStyle(fontWeight: FontWeight.bold, color: accent),
                ),
              ],
            ),
            Text(
              isRo ? 'Analiză de prim ajutor' : 'First Aid Analysis',
              style: TextStyle(fontSize: 12, color: accent.withValues(alpha: 0.8)),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(widget.isDarkMode ? Icons.light_mode : Icons.dark_mode),
            onPressed: widget.onToggleTheme,
          ),
          TextButton(
            onPressed: widget.onToggleLang,
            child: Text(isRo ? 'EN' : 'RO', style: TextStyle(color: accent)),
          ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 400),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: medicalGreen, width: 1.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _isRegisterMode
                      ? (isRo ? 'Creare Cont Nou' : 'Create New Account')
                      : (isRo ? 'Autentificare Pacient' : 'Patient Login'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: accent,
                  ),
                ),
                const SizedBox(height: 20),
                Text(isRo ? 'Email' : 'Email', style: TextStyle(color: accent)),
                const SizedBox(height: 6),
                TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    hintText: 'nume@exemplu.ro',
                    filled: true,
                    fillColor: Colors.black.withValues(alpha: 0.15),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(isRo ? 'Parolă' : 'Password', style: TextStyle(color: accent)),
                const SizedBox(height: 6),
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: InputDecoration(
                    hintText: '••••••••',
                    filled: true,
                    fillColor: Colors.black.withValues(alpha: 0.15),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: medicalGreen,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: _isLoading ? null : _submitAuth,
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          _isRegisterMode
                              ? (isRo ? 'Înregistrare' : 'Register')
                              : (isRo ? 'Conectare' : 'Log In'),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
                const SizedBox(height: 14),
                GestureDetector(
                  onTap: () => setState(() => _isRegisterMode = !_isRegisterMode),
                  child: RichText(
                    textAlign: TextAlign.center,
                    text: TextSpan(
                      style: TextStyle(color: accent, fontSize: 13),
                      children: [
                        TextSpan(
                          text: _isRegisterMode
                              ? (isRo ? 'Ai deja un cont? ' : 'Already have an account? ')
                              : (isRo ? 'Nu ai un cont? ' : "Don't have an account? "),
                        ),
                        TextSpan(
                          text: _isRegisterMode
                              ? (isRo ? 'Conectează-te aici' : 'Log in here')
                              : (isRo ? 'Creează un cont nou' : 'Create a new account'),
                          style: const TextStyle(
                            color: Color(0xFF58B97D),
                            fontWeight: FontWeight.bold,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// ECRAN 2: CAPTURĂ POZĂ & UPLOAD ÎN BUCKET 'burn_photos' + TABEL 'scans'
// ============================================================================
class CaptureScreen extends StatefulWidget {
  final bool isDarkMode;
  final String currentLang;
  final VoidCallback onToggleTheme;
  final VoidCallback onToggleLang;

  const CaptureScreen({
    super.key,
    required this.isDarkMode,
    required this.currentLang,
    required this.onToggleTheme,
    required this.onToggleLang,
  });

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen> {
  final ImagePicker _picker = ImagePicker();
  bool _acceptedTerms = false;
  File? _selectedImage;

  bool get isRo => widget.currentLang == 'ro';

  Future<void> _pickImage(ImageSource source) async {
    if (!_acceptedTerms) {
      _showSnack(isRo
          ? 'Te rugăm să bifezi căsuța de acceptare a termenilor înainte de a face poza.'
          : 'Please check the disclaimer box before taking a photo.');
      return;
    }

    final XFile? picked = await _picker.pickImage(
      source: source,
      maxWidth: 800,
      maxHeight: 800,
      imageQuality: 85,
    );

    if (picked != null) {
      setState(() => _selectedImage = File(picked.path));
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.isDarkMode ? const Color(0xFFD8D7D3) : const Color(0xFF1C3826);
    const medicalGreen = Color(0xFF3F895A);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'DaVinciMed',
          style: TextStyle(fontWeight: FontWeight.bold, color: accent),
        ),
        actions: [
          IconButton(
            icon: Icon(widget.isDarkMode ? Icons.light_mode : Icons.dark_mode),
            onPressed: widget.onToggleTheme,
          ),
          TextButton(
            onPressed: widget.onToggleLang,
            child: Text(isRo ? 'EN' : 'RO', style: TextStyle(color: accent)),
          ),
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: isRo ? 'Istoric' : 'History',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => HistoryScreen(
                  isDarkMode: widget.isDarkMode,
                  currentLang: widget.currentLang,
                ),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Color(0xFFFF6B6B)),
            tooltip: isRo ? 'Deconectare' : 'Log Out',
            onPressed: () async => await supabase.auth.signOut(),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: widget.isDarkMode
                        ? const Color(0xBF4B2D0F)
                        : const Color(0xF2E6F0E9),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: widget.isDarkMode
                          ? const Color(0xFFD99B26)
                          : medicalGreen,
                      width: 1.5,
                    ),
                  ),
                  child: CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: _acceptedTerms,
                    activeColor: const Color(0xFFD99B26),
                    onChanged: (val) =>
                        setState(() => _acceptedTerms = val ?? false),
                    title: Text(
                      isRo
                          ? 'Înțeleg și accept în mod expres că această platformă NU oferă un diagnostic medical real și că rezultatele pot fi eronate.'
                          : 'I expressly understand and accept that this platform DOES NOT provide a real medical diagnosis and that results may be inaccurate.',
                      style: const TextStyle(fontSize: 12.5, height: 1.35),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                AspectRatio(
                  aspectRatio: 1,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: medicalGreen, width: 2.5),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: _selectedImage != null
                        ? Image.file(_selectedImage!, fit: BoxFit.cover)
                        : Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 160,
                                  height: 160,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.white70,
                                      width: 2,
                                    ),
                                  ),
                                  child: const Icon(
                                    Icons.camera_alt_outlined,
                                    color: Colors.white54,
                                    size: 48,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: accent,
                                    borderRadius: BorderRadius.circular(15),
                                  ),
                                  child: Text(
                                    isRo
                                        ? 'Poziționează leziunea aici'
                                        : 'Position injury here',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: widget.isDarkMode
                                          ? const Color(0xFF0E1C14)
                                          : Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 16),
                if (_selectedImage == null) ...[
                  ElevatedButton.icon(
                    icon: const Icon(Icons.camera_alt),
                    label: Text(
                        isRo ? 'Fă Poză Leziune' : 'Take Injury Photo'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accent,
                      foregroundColor: widget.isDarkMode
                          ? const Color(0xFF0E1C14)
                          : Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: _acceptedTerms
                        ? () => _pickImage(ImageSource.camera)
                        : null,
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.photo_library),
                    label: Text(isRo
                        ? 'Alege din Galerie'
                        : 'Choose from Gallery'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: accent,
                      side: const BorderSide(color: medicalGreen),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: _acceptedTerms
                        ? () => _pickImage(ImageSource.gallery)
                        : null,
                  ),
                ] else ...[
                  ElevatedButton.icon(
                    icon: const Icon(Icons.rotate_left),
                    label: Text(isRo ? 'Fă altă poză' : 'Take another photo'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: medicalGreen,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: () => setState(() => _selectedImage = null),
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.analytics_outlined),
                    label: Text(
                      isRo ? 'Continuă cu întrebările' : 'Continue to questions',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF3F895A),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => QuestionsScreen(
                            imageFile: _selectedImage!,
                            isDarkMode: widget.isDarkMode,
                            currentLang: widget.currentLang,
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// ECRAN 3: ÎNTREBĂRI (după poză)
// ============================================================================
class QuestionsScreen extends StatefulWidget {
  final File imageFile;
  final bool isDarkMode;
  final String currentLang;

  const QuestionsScreen({
    super.key,
    required this.imageFile,
    required this.isDarkMode,
    required this.currentLang,
  });

  @override
  State<QuestionsScreen> createState() => _QuestionsScreenState();
}

class _QuestionsScreenState extends State<QuestionsScreen> {
  late final List<int?> _answers = List.filled(questions.length, null);

  bool get isRo => widget.currentLang == 'ro';
  int get _answered => _answers.where((a) => a != null).length;

  @override
  Widget build(BuildContext context) {
    final bgColor =
        widget.isDarkMode ? const Color(0xFF0E1C14) : const Color(0xFFEAEFE9);
    final cardBg =
        widget.isDarkMode ? const Color(0xFF15261C) : const Color(0xFFD4E2D7);
    final accent =
        widget.isDarkMode ? const Color(0xFFD8D7D3) : const Color(0xFF1C3826);
    const medicalGreen = Color(0xFF3F895A);
    final lang = widget.currentLang;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Text(
          isRo ? 'Întrebări' : 'Questions',
          style: TextStyle(fontWeight: FontWeight.bold, color: accent),
        ),
        backgroundColor: bgColor,
        iconTheme: IconThemeData(color: accent),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.file(widget.imageFile,
                      height: 140, width: double.infinity, fit: BoxFit.cover),
                ),
                const SizedBox(height: 14),
                Text(
                  isRo
                      ? 'Răspunde la toate întrebările ($_answered/${questions.length})'
                      : 'Answer all questions ($_answered/${questions.length})',
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold, color: accent),
                ),
                const SizedBox(height: 12),
                for (var i = 0; i < questions.length; i++)
                  Container(
                    margin: const EdgeInsets.only(bottom: 14),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                          color: _answers[i] == null
                              ? medicalGreen.withValues(alpha: 0.4)
                              : medicalGreen,
                          width: 1.5),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${i + 1}. ${questions[i].q(lang)}',
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: accent)),
                        if (questions[i].hint(lang) != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(questions[i].hint(lang)!,
                                style: TextStyle(
                                    fontSize: 12,
                                    color: accent.withValues(alpha: 0.7))),
                          ),
                        const SizedBox(height: 8),
                        for (var j = 0; j < questions[i].options.length; j++)
                          InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: () => setState(() => _answers[i] = j),
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 6),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 10),
                              decoration: BoxDecoration(
                                color: _answers[i] == j
                                    ? medicalGreen.withValues(alpha: 0.3)
                                    : Colors.black.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                    color: _answers[i] == j
                                        ? medicalGreen
                                        : Colors.transparent),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    _answers[i] == j
                                        ? Icons.radio_button_checked
                                        : Icons.radio_button_off,
                                    size: 20,
                                    color: const Color(0xFF58B97D),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(questions[i].options[j].l(lang),
                                        style: TextStyle(
                                            fontSize: 13.5, color: accent)),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.analytics_outlined),
                  label: Text(
                    isRo ? 'Analizează' : 'Analyze',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: medicalGreen,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: _answered < questions.length
                      ? null
                      : () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => AnalysisScreen(
                                imageFile: widget.imageFile,
                                answers: _answers.cast<int>(),
                                isDarkMode: widget.isDarkMode,
                                currentLang: widget.currentLang,
                              ),
                            ),
                          ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// ECRAN 4: REZULTAT (model ONNX pe imagine + răspunsuri la întrebări)
// ============================================================================
class AnalysisScreen extends StatefulWidget {
  final File imageFile;
  final List<int> answers;
  final bool isDarkMode;
  final String currentLang;

  const AnalysisScreen({
    super.key,
    required this.imageFile,
    required this.answers,
    required this.isDarkMode,
    required this.currentLang,
  });

  @override
  State<AnalysisScreen> createState() => _AnalysisScreenState();
}

class _AnalysisScreenState extends State<AnalysisScreen> {
  late final Future<BurnAssessment> _future = _run();

  /// null = saving to history, true = saved, false = failed.
  bool? _saved;

  bool get isRo => widget.currentLang == 'ro';

  Future<BurnAssessment> _run() async {
    final r = await OnnxBurnClassifierService().classifyImageFile(widget.imageFile);
    debugPrint('MODEL PROBABILITIES (softmax): ${r.probabilities}');
    BurnAssessment result;
    String pct(List<double> p) =>
        p.map((v) => '${(v * 100).toStringAsFixed(1)}%').join(' / ');
    final watch = Stopwatch()..start();
    debugPrint('[JEV] Sending request to Edge Function "burn-decision"...');
    try {
      final decided = await JevService().decide(
        visionProbs: r.probabilities,
        brightness: r.brightness,
        answers: widget.answers,
      );
      debugPrint('[JEV] ✅ WORKS: answered in ${watch.elapsedMilliseconds} ms. '
          'Grad I / II / III = ${pct(decided)}');
      result = fromJev(r.probabilities, decided, widget.answers);
    } catch (e) {
      final reason = switch (e) {
        FunctionException(:final status, :final details) =>
          'Edge Function returned HTTP $status: $details',
        TimeoutException() => 'no answer within 25 s (timeout)',
        _ => '${e.runtimeType}: $e',
      };
      debugPrint('[JEV] ❌ FAILED after ${watch.elapsedMilliseconds} ms: $reason');
      debugPrint('[JEV] ⚠️ Using LOCAL FORMULA instead of Jev.');
      result = combine(r.probabilities, widget.answers);
    }
    _saveToHistory(result); // runs in the background; the result shows right away
    return result;
  }

  /// Saves the photo + result once per analysis. A failure doesn't hide the result.
  Future<void> _saveToHistory(BurnAssessment result) async {
    try {
      await ScanHistoryService().save(widget.imageFile, result);
      if (mounted) setState(() => _saved = true);
    } catch (e) {
      debugPrint('Saving to history failed: $e');
      if (mounted) setState(() => _saved = false);
    }
  }

  Widget _saveStatus(Color accent) {
    final (IconData icon, String text, Color color) = switch (_saved) {
      null => (
          Icons.cloud_upload_outlined,
          isRo ? 'Se salvează în istoric...' : 'Saving to history...',
          accent.withValues(alpha: 0.7),
        ),
      true => (
          Icons.cloud_done_outlined,
          isRo ? 'Salvat în istoric' : 'Saved to history',
          const Color(0xFF58B97D),
        ),
      false => (
          Icons.cloud_off_outlined,
          isRo ? 'Nu s-a putut salva în istoric' : 'Could not save to history',
          const Color(0xFFFF6B6B),
        ),
    };
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Text(text, style: TextStyle(fontSize: 12.5, color: color)),
      ],
    );
  }

  /// Opens Google Maps (app if installed, otherwise browser) with a search for
  /// hospitals. Google Maps uses the phone's location, so no permission is needed here.
  Future<void> _openNearestHospital() async {
    final url = Uri.parse('https://www.google.com/maps/search/?api=1&query=hospital');
    final opened = await launchUrl(url, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(isRo
            ? 'Nu s-a putut deschide Google Maps.'
            : 'Could not open Google Maps.'),
      ));
    }
  }

  Widget _hospitalMapCard(Color accent) {
    const red = Color(0xFFFF6B6B);
    return Material(
      color: red.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: _openNearestHospital,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: red, width: 1.5),
          ),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: red.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.map_outlined, size: 32, color: red),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isRo ? 'Găsește cel mai apropiat spital' : 'Find nearest hospital',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold, color: accent),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isRo ? 'Deschide în Google Maps' : 'Opens in Google Maps',
                      style: TextStyle(
                          fontSize: 12.5, color: accent.withValues(alpha: 0.75)),
                    ),
                  ],
                ),
              ),
              Icon(Icons.open_in_new, color: accent.withValues(alpha: 0.7)),
            ],
          ),
        ),
      ),
    );
  }

  Color _degreeColor(int degree) => switch (degree) {
        1 => Colors.green,
        2 => Colors.orange,
        _ => const Color(0xFFFF6B6B),
      };

  Widget _bar(String label, double prob, Color color, Color accent) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(label, style: TextStyle(fontSize: 13, color: accent)),
                Text('${(prob * 100).toStringAsFixed(1)}%',
                    style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.bold, color: color)),
              ],
            ),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: prob.clamp(0.0, 1.0),
                minHeight: 8,
                backgroundColor: Colors.black.withValues(alpha: 0.15),
                color: color,
              ),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final bgColor =
        widget.isDarkMode ? const Color(0xFF0E1C14) : const Color(0xFFEAEFE9);
    final cardBg =
        widget.isDarkMode ? const Color(0xFF15261C) : const Color(0xFFD4E2D7);
    final accent =
        widget.isDarkMode ? const Color(0xFFD8D7D3) : const Color(0xFF1C3826);
    const medicalGreen = Color(0xFF3F895A);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Text(isRo ? 'Rezultat' : 'Result',
            style: TextStyle(fontWeight: FontWeight.bold, color: accent)),
        backgroundColor: bgColor,
        iconTheme: IconThemeData(color: accent),
        elevation: 0,
      ),
      body: FutureBuilder<BurnAssessment>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(color: medicalGreen),
                  const SizedBox(height: 18),
                  Text(isRo ? 'Se analizează imaginea...' : 'Analyzing image...',
                      style: TextStyle(fontSize: 16, color: accent)),
                ],
              ),
            );
          }
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline,
                        size: 54, color: Color(0xFFFF6B6B)),
                    const SizedBox(height: 12),
                    Text(
                        snap.error is PhotoTooDarkException
                            ? (isRo ? 'Poza este prea întunecată' : 'Photo is too dark')
                            : (isRo ? 'Eroare la analiza modelului' : 'Model analysis error'),
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: accent)),
                    const SizedBox(height: 8),
                    Text(
                        snap.error is PhotoTooDarkException
                            ? (isRo
                                ? 'Fă poza din nou cu lumină mai bună sau cu bliț.'
                                : 'Retake the photo with better lighting or flash.')
                            : '${snap.error}',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 13, color: accent.withValues(alpha: 0.8))),
                  ],
                ),
              ),
            );
          }

          final a = snap.data!;
          final col = _degreeColor(a.predictedDegree);
          String g(int n) => isRo ? 'Arsură Grad $n' : 'Degree $n Burn';

          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Image.file(widget.imageFile,
                          height: 200, width: double.infinity, fit: BoxFit.cover),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: col.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: col, width: 2),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.check_circle_outline, size: 32, color: col),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  isRo
                                      ? 'Estimare: Arsură Gradul ${a.predictedDegree}'
                                      : 'Estimate: Degree ${a.predictedDegree} Burn',
                                  style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: accent),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${isRo ? 'Probabilitate' : 'Probability'}: ${(a.confidence * 100).toStringAsFixed(1)}%',
                                  style: TextStyle(
                                      fontSize: 13,
                                      color: accent.withValues(alpha: 0.8)),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (a.urgent) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF6B6B).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFFF6B6B)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.warning_amber_rounded,
                                color: Color(0xFFFF6B6B)),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                isRo
                                    ? 'Răspunsurile tale indică un risc ridicat (zonă sensibilă, arsură chimică/electrică sau probabilitate mare de grad 3). Mergi la urgență sau sună la 112.'
                                    : 'Your answers indicate a high-risk burn (sensitive area, chemical/electrical cause or high grade 3 probability). Go to emergency care or call your emergency number.',
                                style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: accent),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (a.predictedDegree >= 2) ...[
                      const SizedBox(height: 12),
                      _hospitalMapCard(accent),
                    ],
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: medicalGreen.withValues(alpha: 0.5), width: 1.5),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isRo
                                ? 'Probabilități finale (imagine + întrebări)'
                                : 'Final probabilities (image + questions)',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                                color: accent),
                          ),
                          const SizedBox(height: 14),
                          _bar(g(1), a.finalProbs[0], Colors.green, accent),
                          _bar(g(2), a.finalProbs[1], Colors.orange, accent),
                          _bar(g(3), a.finalProbs[2], const Color(0xFFFF6B6B), accent),
                          const Divider(height: 24),
                          Text(
                            a.source == 'jev'
                                ? (isRo
                                    ? 'Decizie: model Jev (imagine + întrebări)'
                                    : 'Decision: Jev model (image + questions)')
                                : (isRo
                                    ? 'Decizie: formulă locală (Jev indisponibil)'
                                    : 'Decision: local formula (Jev unavailable)'),
                            style: TextStyle(
                                fontSize: 12, color: accent.withValues(alpha: 0.7)),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '${isRo ? 'Doar model imagine' : 'Image model only'}: '
                            '${a.modelProbs.map((p) => '${(p * 100).toStringAsFixed(1)}%').join(' / ')}',
                            style: TextStyle(
                                fontSize: 12, color: accent.withValues(alpha: 0.7)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    _saveStatus(accent),
                    const SizedBox(height: 14),
                    Text(
                      isRo
                          ? 'Atenție: Această analiză are caracter informativ și nu înlocuiește un diagnostic medical profesionist.'
                          : 'Notice: This analysis is informational and does not replace professional medical diagnosis.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 12, color: accent.withValues(alpha: 0.65)),
                    ),
                    const SizedBox(height: 18),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.arrow_back),
                      label: Text(isRo ? 'Înapoi la captură' : 'Back to capture',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: medicalGreen,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () =>
                          Navigator.popUntil(context, (route) => route.isFirst),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
