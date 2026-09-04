// THROWAWAY — this file exists only on m4/ci-bite-check, to prove CI goes red
// on a failing test (M4-T4.1 acceptance). Never merge this branch.
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('CI must go red on a failing test', () {
    expect(true, false);
  });
}
