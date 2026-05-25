Map<String, dynamic> buildVisaInfo({
  required String countryName,
  required Map<String, dynamic> raw,
}) {
  final stayDays = (raw['days'] ?? 'Unknown').toString();
  final visaType = (raw['type'] ?? 'Contact embassy').toString();

  final bool visaRequired = visaType.toLowerCase().contains('required') &&
      !visaType.toLowerCase().contains('visa-free');

  return {
    'name': raw['name'] ?? countryName,
    'days': stayDays,
    'type': visaType,
    'entry': raw['entry'] ?? (visaRequired ? 'Apply before arrival' : 'Entry usually allowed with passport'),
    'passport_validity': raw['passport_validity'] ?? 'Passport should usually be valid for at least 6 months',
    'registration': raw['registration'] ?? 'Check local migration registration rules after arrival',
    'documents': raw['documents'] ??
        (visaRequired
            ? 'Passport, visa application, accommodation info, return ticket'
            : 'Passport, accommodation address, return/onward ticket'),
    'processing': raw['processing'] ?? (visaRequired ? 'Processing time depends on embassy or eVisa portal' : 'No visa processing needed before travel'),
    'extension': raw['extension'] ?? 'Extension rules depend on visa category and migration service decision',
    'notes': raw['notes'] ?? 'Rules may change. Recheck before travel and before visa expiry.',
  };
}
