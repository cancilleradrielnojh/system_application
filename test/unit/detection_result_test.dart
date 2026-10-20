// White-box unit tests: DetectionResult + InferenceService constants
// Source: lib/detection/inference_service.dart
//
// Technique: statement + branch coverage. Every `case` of the three switch
// getters (className, recommendation, healthScore) is executed, including the
// `null` branch, and the clamp() boundaries (below 0, 0, 1, above 1) of each
// score formula are exercised.
//
//   UT-DR-01..06  DetectionResult
//   UT-IC-01..03  InferenceService constants / class contract
import 'package:flutter_test/flutter_test.dart';
import 'package:system_application/detection/inference_service.dart';

DetectionResult _d(SaplingClass? c, {double conf = 0.5}) => DetectionResult(
      saplingClass: c,
      confidence: conf,
      boxAreaPx: 1000,
      isCalamansi: true,
    );

void main() {
  group('DetectionResult.className', () {
    test('UT-DR-01 every enum branch maps to the exact class label', () {
      expect(_d(SaplingClass.healthy).className, 'Healthy');
      expect(_d(SaplingClass.pestDamaged).className, 'Pest-Damaged');
      expect(_d(SaplingClass.wilting).className, 'Wilting');
      expect(_d(SaplingClass.yellowing).className, 'Yellowing');
    });

    test('UT-DR-02 null class (no decision) maps to Unknown', () {
      expect(_d(null).className, 'Unknown');
    });
  });

  group('DetectionResult.healthScore', () {
    // class -> [base, multiplier]  (from the formulas in the source)
    final formulas = <SaplingClass, List<double>>{
      SaplingClass.healthy: [90, 10],
      SaplingClass.yellowing: [60, 15],
      SaplingClass.wilting: [40, 20],
      SaplingClass.pestDamaged: [20, 20],
    };

    test('UT-DR-03 score = base + confidence * multiplier for conf 0..1', () {
      formulas.forEach((cls, f) {
        for (final conf in [0.0, 0.25, 0.5, 0.9, 1.0]) {
          expect(_d(cls, conf: conf).healthScore,
              closeTo(f[0] + conf * f[1], 1e-9),
              reason: '$cls @ $conf');
        }
      });
    });

    test('UT-DR-04 clamp boundaries: conf below 0 and above 1 are capped', () {
      formulas.forEach((cls, f) {
        // conf < 0  -> added part clamps to 0 -> exactly the base
        expect(_d(cls, conf: -0.5).healthScore, closeTo(f[0], 1e-9),
            reason: '$cls conf=-0.5');
        // conf > 1  -> added part clamps to the multiplier -> base + mult
        expect(_d(cls, conf: 1.7).healthScore, closeTo(f[0] + f[1], 1e-9),
            reason: '$cls conf=1.7');
      });
    });

    test('UT-DR-05 null class scores 0, and class bands never overlap', () {
      expect(_d(null, conf: 0.99).healthScore, 0);
      // Highest score of a worse class stays below the lowest score of the
      // next better class, so Statistics never ranks them out of order.
      final pestMax = _d(SaplingClass.pestDamaged, conf: 1).healthScore;
      final wiltMin = _d(SaplingClass.wilting, conf: 0).healthScore;
      final wiltMax = _d(SaplingClass.wilting, conf: 1).healthScore;
      final yellowMin = _d(SaplingClass.yellowing, conf: 0).healthScore;
      final yellowMax = _d(SaplingClass.yellowing, conf: 1).healthScore;
      final healthyMin = _d(SaplingClass.healthy, conf: 0).healthScore;
      expect(pestMax, lessThanOrEqualTo(wiltMin));
      expect(wiltMax, lessThanOrEqualTo(yellowMin));
      expect(yellowMax, lessThanOrEqualTo(healthyMin));
    });
  });

  group('DetectionResult.recommendation + constructor', () {
    test('UT-DR-06 each class has its own text; null has the fallback', () {
      final texts = <String>{};
      for (final cls in SaplingClass.values) {
        final t = _d(cls).recommendation;
        expect(t.trim(), isNotEmpty, reason: '$cls');
        expect(t, isNot('No recommendation available.'), reason: '$cls');
        texts.add(t);
      }
      expect(texts.length, SaplingClass.values.length,
          reason: 'recommendations must differ per class');
      expect(_d(null).recommendation, 'No recommendation available.');
    });

    test('UT-DR-07 optional fields default to null', () {
      final d = _d(SaplingClass.healthy);
      expect(d.secondaryClass, isNull);
      expect(d.secondaryConfidence, isNull);
      expect(d.bboxLeft, isNull);
      expect(d.bboxTop, isNull);
      expect(d.bboxRight, isNull);
      expect(d.bboxBottom, isNull);
      expect(d.maskPolygon, isNull);
    });
  });

  group('InferenceService contract', () {
    test('UT-IC-01 enum order is the model class-index contract', () {
      // _toEnum maps 0..3 to these values in this order. Reordering the enum
      // would silently change what the app reports.
      expect(SaplingClass.values, [
        SaplingClass.healthy,
        SaplingClass.pestDamaged,
        SaplingClass.wilting,
        SaplingClass.yellowing,
      ]);
      expect(SaplingClass.values.length, 4);
    });

    test('UT-IC-02 pinned thresholds match the documented values', () {
      expect(InferenceService.inputSize, 640);
      expect(InferenceService.confThreshold, 0.70);
      expect(InferenceService.calamansiPresenceThreshold, 0.80);
      expect(InferenceService.secondaryClassThreshold, 0.60);
      expect(InferenceService.iouThreshold, 0.15);
      expect(InferenceService.crossClassIouThreshold, 0.40);
      expect(InferenceService.minBoxAreaPx, 300);
      expect(InferenceService.maxBoxAreaPx, 55000);
      expect(InferenceService.maxAspectRatio, 3.0);
      expect(InferenceService.maskBinaryThreshold, 0.5);
      expect(InferenceService.blurThreshold, 80.0);
    });

    test('UT-IC-03 thresholds are consistent with each other', () {
      expect(InferenceService.confThreshold,
          lessThanOrEqualTo(InferenceService.calamansiPresenceThreshold));
      expect(InferenceService.secondaryClassThreshold,
          lessThanOrEqualTo(InferenceService.confThreshold));
      expect(InferenceService.minBoxAreaPx,
          lessThan(InferenceService.maxBoxAreaPx));
      expect(InferenceService.minSidePx,
          lessThan(InferenceService.maxSidePx));
      expect(InferenceService.maskOutlineThreshold,
          lessThan(InferenceService.maskBinaryThreshold));
      for (final t in [
        InferenceService.confThreshold,
        InferenceService.calamansiPresenceThreshold,
        InferenceService.secondaryClassThreshold,
        InferenceService.iouThreshold,
        InferenceService.crossClassIouThreshold,
      ]) {
        expect(t, inInclusiveRange(0.0, 1.0));
      }
    });
  });
}