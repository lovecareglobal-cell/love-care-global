// lib/models/id_catalog.dart - FIXED: RegExp cannot be const
// Pattern is stored as a String, converted to RegExp only when needed.

class IdTypeOption {
  final String id;
  final String label;
  final String example;
  final String hint;
  final String? patternSource;
  final String? patternError;

  const IdTypeOption({
    required this.id,
    required this.label,
    required this.example,
    required this.hint,
    String? pattern,
    this.patternError,
  }) : patternSource = pattern;

  // Use this everywhere: idType.pattern?.hasMatch(value)
  RegExp? get pattern =>
      patternSource == null ? null : RegExp(patternSource!);
}

class IdCatalog {
  static const Map<String, List<IdTypeOption>> byCountry = {
    'Ghana': [
      IdTypeOption(
        id: 'ghana_card',
        label: 'Ghana Card',
        example: 'GHA-123456789-0',
        hint: 'e.g. GHA-123456789-0',
        pattern: r'^GHA-\d{9}-\d$',
        patternError: 'Ghana Card must look like GHA-123456789-0',
      ),
      IdTypeOption(
        id: 'passport_gh',
        label: 'Passport',
        example: 'G1234567',
        hint: 'e.g. G1234567',
        pattern: r'^[A-Z]\d{7}$',
      ),
      IdTypeOption(
        id: 'voter_id_gh',
        label: 'Voter ID Card',
        example: '1234567890',
        hint: 'e.g. 1234567890',
        pattern: r'^\d{10}$',
      ),
      IdTypeOption(
        id: 'driving_licence_gh',
        label: 'Driving Licence',
        example: 'DL123456789',
        hint: 'e.g. DL123456789',
      ),
      IdTypeOption(
        id: 'nhis_gh',
        label: 'Health Insurance Card (NHIS)',
        example: '12345678',
        hint: 'e.g. 12345678',
      ),
    ],
    'Australia': [
      IdTypeOption(
        id: 'passport_au',
        label: 'Passport',
        example: 'P1234567',
        hint: 'e.g. P1234567',
        pattern: r'^[A-Z]\d{7}$',
        patternError: 'Australian passport must look like P1234567',
      ),
      IdTypeOption(
        id: 'drivers_licence_au',
        label: 'Driver Licence',
        example: '123456789',
        hint: 'e.g. 123456789 (varies by state)',
      ),
      IdTypeOption(
        id: 'medicare_au',
        label: 'Medicare Card',
        example: '1234 56789 1',
        hint: 'e.g. 1234 56789 1',
      ),
      IdTypeOption(
        id: 'proof_of_age_au',
        label: 'Proof of Age Card',
        example: '123456789',
        hint: 'e.g. 123456789',
      ),
    ],
    'India': [
      IdTypeOption(
        id: 'aadhaar',
        label: 'Aadhaar Card',
        example: '1234 5678 9012',
        hint: 'e.g. 1234 5678 9012',
        pattern: r'^\d{4}\s?\d{4}\s?\d{4}$',
      ),
      IdTypeOption(
        id: 'pan',
        label: 'PAN Card',
        example: 'ABCDE1234F',
        hint: 'e.g. ABCDE1234F',
        pattern: r'^[A-Z]{5}\d{4}[A-Z]$',
      ),
      IdTypeOption(
        id: 'passport_in',
        label: 'Passport',
        example: 'A1234567',
        hint: 'e.g. A1234567',
        pattern: r'^[A-Z]\d{7}$',
      ),
      IdTypeOption(
        id: 'voter_id_in',
        label: 'Voter ID Card',
        example: 'ABC1234567',
        hint: 'e.g. ABC1234567',
      ),
      IdTypeOption(
        id: 'driving_licence_in',
        label: 'Driving Licence',
        example: 'DL1234567890123',
        hint: 'e.g. DL1234567890123',
      ),
    ],
    'USA': [
      IdTypeOption(
        id: 'passport_us',
        label: 'Passport',
        example: 'C79403752',
        hint: 'e.g. C79403752',
        pattern: r'^[A-Z]\d{8}$',
      ),
      IdTypeOption(
        id: 'state_id_us',
        label: 'State ID Card',
        example: 'D1234567',
        hint: 'e.g. D1234567 (varies by state)',
      ),
      IdTypeOption(
        id: 'drivers_licence_us',
        label: 'Driver License',
        example: 'D1234567',
        hint: 'e.g. D1234567 (varies by state)',
      ),
    ],
    'United Kingdom': [
      IdTypeOption(
        id: 'passport_uk',
        label: 'Passport',
        example: '123456789',
        hint: 'e.g. 123456789',
        pattern: r'^\d{9}$',
      ),
      IdTypeOption(
        id: 'driving_licence_uk',
        label: 'Driving Licence',
        example: 'MORGA753116SM9IJ',
        hint: 'e.g. MORGA753116SM9IJ',
      ),
      IdTypeOption(
        id: 'brp_uk',
        label: 'Biometric Residence Permit',
        example: 'AB1234567',
        hint: 'e.g. AB1234567',
      ),
    ],
    'Nigeria': [
      IdTypeOption(
        id: 'nin_ng',
        label: 'National ID (NIN)',
        example: '12345678901',
        hint: 'e.g. 12345678901 (11 digits)',
        pattern: r'^\d{11}$',
      ),
      IdTypeOption(
        id: 'passport_ng',
        label: 'Passport',
        example: 'A12345678',
        hint: 'e.g. A12345678',
      ),
      IdTypeOption(
        id: 'voters_card_ng',
        label: "Voter's Card",
        example: '1234567890123456789',
        hint: 'e.g. 19 digits on card',
      ),
      IdTypeOption(
        id: 'drivers_licence_ng',
        label: 'Driver Licence',
        example: 'ABC12345AA12',
        hint: 'e.g. ABC12345AA12',
      ),
    ],
    'Kenya': [
      IdTypeOption(
        id: 'national_id_ke',
        label: 'National ID',
        example: '12345678',
        hint: 'e.g. 12345678 (8 digits)',
        pattern: r'^\d{8}$',
      ),
      IdTypeOption(
        id: 'passport_ke',
        label: 'Passport',
        example: 'A1234567',
        hint: 'e.g. A1234567',
      ),
    ],
    'South Africa': [
      IdTypeOption(
        id: 'id_number_za',
        label: 'South African ID Number',
        example: '8001015009087',
        hint: 'e.g. 8001015009087 (13 digits)',
        pattern: r'^\d{13}$',
      ),
      IdTypeOption(
        id: 'passport_za',
        label: 'Passport',
        example: 'A12345678',
        hint: 'e.g. A12345678',
      ),
    ],
    'Canada': [
      IdTypeOption(
        id: 'passport_ca',
        label: 'Passport',
        example: 'AB1234567',
        hint: 'e.g. AB1234567',
      ),
      IdTypeOption(
        id: 'drivers_licence_ca',
        label: 'Driver Licence',
        example: 'A1234-56789-12345',
        hint: 'e.g. varies by province',
      ),
      IdTypeOption(
        id: 'pr_card_ca',
        label: 'Permanent Resident Card',
        example: 'ABC123456789',
        hint: 'e.g. ABC123456789',
      ),
    ],
    'Philippines': [
      IdTypeOption(
        id: 'philsys_ph',
        label: 'PhilSys / National ID',
        example: '1234-5678-9012-3456',
        hint: 'e.g. 1234-5678-9012-3456',
      ),
      IdTypeOption(
        id: 'passport_ph',
        label: 'Passport',
        example: 'P1234567A',
        hint: 'e.g. P1234567A',
      ),
      IdTypeOption(
        id: 'drivers_licence_ph',
        label: 'Driver Licence',
        example: 'A01-12-345678',
        hint: 'e.g. A01-12-345678',
      ),
    ],
  };

  static const List<IdTypeOption> generic = [
    IdTypeOption(
      id: 'passport_generic',
      label: 'Passport',
      example: 'A1234567',
      hint: 'e.g. A1234567 - as printed on passport',
    ),
    IdTypeOption(
      id: 'national_id_generic',
      label: 'National ID / National Identity Card',
      example: '123456789',
      hint: 'e.g. as printed on your National ID',
    ),
    IdTypeOption(
      id: 'driving_licence_generic',
      label: 'Driving Licence',
      example: '123456789',
      hint: 'e.g. as printed on your Driving Licence',
    ),
  ];

  static List<String> get countries => byCountry.keys.toList()..sort();

  static List<IdTypeOption> forCountry(String? country) {
    if (country == null || country.isEmpty) return [];
    return byCountry[country] ?? generic;
  }
}
