import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'visa_info_helper.dart';

class VisaView extends StatefulWidget {
  const VisaView({super.key});

  @override
  State<VisaView> createState() => _VisaViewState();
}

class _VisaViewState extends State<VisaView> {
  String selectedCountry = 'US';
  Map<String, dynamic> visaData = {};

  List<DropdownMenuItem<String>> _countryItems() {
    final entries = visaData.entries.toList()
      ..sort((a, b) => (a.value['name'] ?? '').toString().compareTo((b.value['name'] ?? '').toString()));

    return entries
        .map(
          (entry) => DropdownMenuItem<String>(
            value: entry.key,
            child: Text((entry.value['name'] ?? entry.key).toString()),
          ),
        )
        .toList();
  }

  @override
  void initState() {
    super.initState();
    loadData();
  }

  Future<void> loadData() async {
    final data = await rootBundle.loadString('assets/visa_data.json');
    setState(() {
      visaData = json.decode(data);
    });
  }

  @override
  Widget build(BuildContext context) {
    final info = buildVisaInfo(
      countryName: selectedCountry,
      raw: visaData[selectedCountry] ?? {
        "name": selectedCountry,
        "days": "Unknown",
        "type": "Contact embassy"
      },
    );

    return Scaffold(
      appBar: AppBar(title: const Text("Visa Info")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [

            /// ВЫБОР СТРАНЫ
            DropdownButtonFormField<String>(
              value: selectedCountry,
              decoration: const InputDecoration(
                labelText: 'Select country',
                border: OutlineInputBorder(),
              ),
              items: _countryItems(),
              onChanged: (value) {
                setState(() {
                  selectedCountry = value ?? 'US';
                });
              },
            ),

            const SizedBox(height: 30),

          
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    blurRadius: 10,
                    color: Colors.black.withOpacity(0.1),
                  )
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Country: ${info['name']}",
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  Text("Stay: ${info['days']}"),
                  Text("Type: ${info['type']}"),
                  Text("Entry: ${info['entry']}"),
                  Text("Passport: ${info['passport_validity']}"),
                  Text("Registration: ${info['registration']}"),
                  Text("Documents: ${info['documents']}"),
                  Text("Processing: ${info['processing']}"),
                  Text("Extension: ${info['extension']}"),
                  Text("Notes: ${info['notes']}"),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
