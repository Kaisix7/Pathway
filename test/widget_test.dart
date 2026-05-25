import 'package:flutter_test/flutter_test.dart';

void main() {

  
  test('Smoke test: basic math works', () {
    expect(1 + 1, 2);
  });

  
  test('Sanity test: progress calculation is logical', () {
    int done = 2;
    int total = 4;

    double progress = done / total;
    int percent = (progress * 100).round();

    expect(percent, 50);
  });

  
    test('Regression test: progress should not exceed 100%', () {
    int done = 10;
    int total = 4;

    double progress = total == 0 ? 0 : (done / total).clamp(0.0, 1.0);
    int percent = (progress * 100).round();

    expect(percent, 100);
  });

  test('Re-test: fixing previous bug with zero tasks', () {
    int done = 0;
    int total = 0;

    double progress = total == 0 ? 0 : (done / total);
    int percent = (progress * 100).round();

    expect(percent, 0);
  });

}