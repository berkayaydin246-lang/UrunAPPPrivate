import 'dart:io';

import 'support/score_v2_calibration_support.dart';

void main() {
  final results = scoreV2CalibrationFixtures.map(evaluateScoreV2Calibration);
  stdout.writeln(formatScoreV2CalibrationReport(results));
}
