// ========================= lib/detection/live_tracker.dart =========================
import 'dart:math';

import 'inference_service.dart';

class _Track {
  double l, t, r, b;
  double conf;
  final List<double> classScore = List<double>.filled(4, 0.0);
  int hits = 1;
  int misses = 0;
  double boxAreaPx;

  _Track(this.l, this.t, this.r, this.b, this.conf, this.boxAreaPx);
}

/// Per-object temporal smoothing for the live overlay.
///
/// Raw per-frame detections flicker (a plant near the confidence gate appears
/// and disappears, two classes swap on the same plant). This keeps a small set
/// of tracks matched by box IoU between frames:
///  * a NEW object must score >= [enterConf] and be seen [confirmHits] frames
///    before it is shown (kills one-frame false positives);
///  * a SHOWN object survives [maxMisses] missed frames and keeps matching
///    at the lower per-frame gate (hysteresis, no flicker near the threshold);
///  * box position and class scores are smoothed with an EMA, and the shown
///    class is the highest smoothed score (no class flicker).
class LiveTracker {
  static const double matchIou     = 0.30;
  static const double enterConf    = 0.60;
  /// Frames needed before a new plant is shown / frames a shown plant may be
  /// missed. Adapted to device speed by [configureForLatency]: with ~3 results
  /// per second 2/2 is right, but at ~1 result per second it would take 2 s to
  /// show a plant and keep stale boxes for 2+ s.
  int confirmHits = 2;
  int maxMisses   = 2;

  void configureForLatency(double totalMs) {
    if (totalMs > 700) {
      confirmHits = 1;
      maxMisses   = 1;
    } else {
      confirmHits = 2;
      maxMisses   = 2;
    }
  }
  static const double boxAlpha     = 0.60; // weight of the newest box
  static const double scoreAlpha   = 0.50; // weight of the newest class score

  final List<_Track> _tracks = [];

  void reset() => _tracks.clear();

  static double _iou(_Track a, DetectionResult d) {
    final ix1 = max(a.l, d.bboxLeft!),  ix2 = min(a.r, d.bboxRight!);
    final iy1 = max(a.t, d.bboxTop!),   iy2 = min(a.b, d.bboxBottom!);
    if (ix2 <= ix1 || iy2 <= iy1) return 0;
    final inter = (ix2 - ix1) * (iy2 - iy1);
    final areaA = (a.r - a.l) * (a.b - a.t);
    final areaB = (d.bboxRight! - d.bboxLeft!) * (d.bboxBottom! - d.bboxTop!);
    final union = areaA + areaB - inter;
    return union <= 0 ? 0 : inter / union;
  }

  List<DetectionResult> update(List<DetectionResult> dets) {
    final valid = dets
        .where((d) =>
            d.bboxLeft != null &&
            d.bboxTop != null &&
            d.bboxRight != null &&
            d.bboxBottom != null &&
            d.saplingClass != null)
        .toList();

    // Greedy matching by descending IoU.
    final pairs = <List<double>>[]; // [trackIdx, detIdx, iou]
    for (var ti = 0; ti < _tracks.length; ti++) {
      for (var di = 0; di < valid.length; di++) {
        final iou = _iou(_tracks[ti], valid[di]);
        if (iou >= matchIou) pairs.add([ti.toDouble(), di.toDouble(), iou]);
      }
    }
    pairs.sort((a, b) => b[2].compareTo(a[2]));

    final usedTracks = <int>{};
    final usedDets = <int>{};
    for (final p in pairs) {
      final ti = p[0].toInt();
      final di = p[1].toInt();
      if (usedTracks.contains(ti) || usedDets.contains(di)) continue;
      usedTracks.add(ti);
      usedDets.add(di);

      final t = _tracks[ti];
      final d = valid[di];
      t.l = boxAlpha * d.bboxLeft!   + (1 - boxAlpha) * t.l;
      t.t = boxAlpha * d.bboxTop!    + (1 - boxAlpha) * t.t;
      t.r = boxAlpha * d.bboxRight!  + (1 - boxAlpha) * t.r;
      t.b = boxAlpha * d.bboxBottom! + (1 - boxAlpha) * t.b;
      t.conf = scoreAlpha * d.confidence + (1 - scoreAlpha) * t.conf;
      t.boxAreaPx = (t.r - t.l) * (t.b - t.t);
      final cls = d.saplingClass!.index;
      for (var c = 0; c < 4; c++) {
        t.classScore[c] = (1 - scoreAlpha) * t.classScore[c] +
            scoreAlpha * (c == cls ? d.confidence : 0.0);
      }
      t.hits++;
      t.misses = 0;
    }

    // Unmatched tracks age out.
    for (var ti = 0; ti < _tracks.length; ti++) {
      if (!usedTracks.contains(ti)) _tracks[ti].misses++;
    }
    _tracks.removeWhere((t) => t.misses > maxMisses);

    // Unmatched detections may start new tracks, but only if confident.
    for (var di = 0; di < valid.length; di++) {
      if (usedDets.contains(di)) continue;
      final d = valid[di];
      if (d.confidence < enterConf) continue;
      final t = _Track(d.bboxLeft!, d.bboxTop!, d.bboxRight!, d.bboxBottom!,
          d.confidence, d.boxAreaPx);
      t.classScore[d.saplingClass!.index] = d.confidence;
      _tracks.add(t);
    }

    // Output confirmed tracks.
    final out = <DetectionResult>[];
    for (final t in _tracks) {
      if (t.hits < confirmHits) continue;
      var best = 0;
      for (var c = 1; c < 4; c++) {
        if (t.classScore[c] > t.classScore[best]) best = c;
      }
      out.add(DetectionResult(
        saplingClass: SaplingClass.values[best],
        confidence:   t.conf,
        boxAreaPx:    t.boxAreaPx,
        isCalamansi:  true,
        bboxLeft:     t.l,
        bboxTop:      t.t,
        bboxRight:    t.r,
        bboxBottom:   t.b,
        maskPolygon:  null,
      ));
    }
    out.sort((a, b) => b.confidence.compareTo(a.confidence));
    return out;
  }
}