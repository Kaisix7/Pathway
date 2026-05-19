import 'package:flutter/material.dart';

class SettingsView extends StatefulWidget {
  const SettingsView({super.key});

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  String selectedLanguage = 'en';

  final languages = {
    'en': 'English',
    'ru': 'Russian',
    'kk': 'Kazakh',
    'tr': 'Turkish',
    'zh': 'Chinese',
    'ar': 'Arabic',
    'fr': 'French',
    'de': 'German',
    'es': 'Spanish',
    'it': 'Italian',
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Settings")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: DropdownButton<String>(
          value: selectedLanguage,
          isExpanded: true,
          items: languages.entries.map((entry) {
            return DropdownMenuItem(
              value: entry.key,
              child: Text(entry.value),
            );
          }).toList(),
          onChanged: (value) {
            setState(() {
              selectedLanguage = value!;
            });
          },
        ),
      ),
    );
  }
}