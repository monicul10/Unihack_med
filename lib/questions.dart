/// The 7-question triage questionnaire (spec Section 1).
///
/// [Question.ro] and [Option.ro] are the exact Romanian strings sent to Jev as
/// keys and values, even when the app is shown in English. The rules in
/// triage.dart find each question by keywords in its key, not by its position.
class Option {
  final String ro, en;
  const Option(this.ro, this.en);
  String l(String lang) => lang == 'ro' ? ro : en;
}

class Question {
  final String ro, en;
  final String? hintRo, hintEn;
  final List<Option> options;
  final int defaultIndex;
  const Question(this.ro, this.en, this.options,
      {this.defaultIndex = 0, this.hintRo, this.hintEn});
  String q(String lang) => lang == 'ro' ? ro : en;
  String? hint(String lang) => lang == 'ro' ? hintRo : hintEn;
}

const questions = <Question>[
  Question(
    '1. Care este cauza arsurii?',
    '1. What is the cause of the burn?',
    [
      Option('Termică (opărire, flacără, atingere suprafață fierbinte)',
          'Thermal (scald, flame, contact with a hot surface)'),
      Option('Chimică (acizi, sodă caustică, înălbitori concentrați / detergenți industriali)',
          'Chemical (acids, caustic soda, concentrated bleach / industrial detergents)'),
      Option('Electrică (electrocutare)', 'Electrical (electric shock)'),
      Option('Radiații (expunere raze UV/X)', 'Radiation (UV/X-ray exposure)'),
      Option('Altele (frecare, la căzături)', 'Other (friction, falls)'),
      Option('Expunere la soare', 'Sun exposure'),
      Option('Nu știu ce a cauzat arsura', "I don't know what caused the burn"),
    ],
    defaultIndex: 0,
  ),
  Question(
    '2. Cât timp a durat expunerea la cauza arsurii?',
    '2. How long was the exposure to the cause of the burn?',
    [
      Option('< 1 secundă', '< 1 second'),
      Option('< 10 secunde', '< 10 seconds'),
      Option('> 1 minut', '> 1 minute'),
      Option('Expunere repetată', 'Repeated exposure'),
    ],
    defaultIndex: 1,
  ),
  Question(
    '3. Selectați gradul de durere resimțit la nivelul arsurii?',
    '3. Select the level of pain felt at the burn site:',
    [
      Option('0–2 (fără durere / disconfort)', '0–2 (no pain / discomfort)'),
      Option('3–4 (durere ușoară)', '3–4 (mild pain)'),
      Option('5–6 (durere moderată)', '5–6 (moderate pain)'),
      Option('7–8 (durere puternică)', '7–8 (severe pain)'),
      // The spec uses a hyphen here, unlike the en dash above.
      Option('9-10 (durere insuportabilă)', '9-10 (unbearable pain)'),
    ],
    defaultIndex: 2,
    hintRo: 'Amorțeala sau lipsa durerii poate indica o arsură profundă (nervi afectați).',
    hintEn: 'Numbness or lack of pain may indicate a deep burn (damaged nerves).',
  ),
  Question(
    '4. Ce vârstă are persoana afectată?',
    '4. How old is the affected person?',
    [
      Option('< 2 ani', '< 2 years'),
      Option('2–5 ani', '2–5 years'),
      Option('5–59 ani', '5–59 years'),
      Option('> 60 ani', '> 60 years'),
    ],
    defaultIndex: 2,
  ),
  Question(
    '5. Este arsura într-o zonă periculoasă/sensibilă (palme, tălpi, față, gât, zona genitală)?',
    '5. Is the burn in a dangerous/sensitive area (palms, soles, face, neck, genital area)?',
    [Option('Da', 'Yes'), Option('Nu', 'No')],
    defaultIndex: 1,
    hintRo: 'Arsurile pe zone critice necesită consult medical urgent indiferent de grad.',
    hintEn: 'Burns in critical areas require urgent medical attention regardless of grade.',
  ),
  Question(
    '6. Suprafața arsurii este mai mare de o palmă?',
    '6. Is the burn surface larger than one palm?',
    [Option('Da', 'Yes'), Option('Nu', 'No')],
    defaultIndex: 1,
    hintRo: 'Palma persoanei (fără degete) reprezintă aproximativ 1% din suprafața corpului.',
    hintEn: "The person's palm represents roughly 1% of total body surface area.",
  ),
  Question(
    '7. Există vezicule (bășici) mari?',
    '7. Are there large blisters (vesicles)?',
    [Option('Da', 'Yes'), Option('Nu', 'No')],
    defaultIndex: 1,
    hintRo: 'Veziculele indică de regulă o arsură de gradul 2 (grosime parțială).',
    hintEn: 'Blisters usually indicate a second-degree burn (partial thickness).',
  ),
];

/// The questionnaire as sent to Jev: exact Romanian question -> exact Romanian answer.
Map<String, String> chestionarFromAnswers(List<int> answers) => {
      for (var i = 0; i < questions.length; i++)
        questions[i].ro: questions[i].options[answers[i]].ro,
    };
