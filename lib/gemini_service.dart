import 'package:google_generative_ai/google_generative_ai.dart';

class GeminiService {

  final model = GenerativeModel(
    model: 'gemini-3-flash-preview',
    apiKey: 'AIzaSyDTCwMwaN6pyluopFZFHfXWqMcVwAYtLcM',
  );

  Future<String> ask(String text) async {
    try {

      final response = await model.generateContent([
        Content.text(text)
      ]);

      return response.text ?? "No response";

    } catch (e) {
      return "Gemini error: $e";
    }
  }
}