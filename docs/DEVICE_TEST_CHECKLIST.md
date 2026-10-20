# Physical-device test checklist (manual)

These cases need the real camera, the OS permission dialogs and the OS gallery
picker, which a Flutter integration test cannot operate. Run them by hand on
the phone, tick the result, and keep a screenshot or screen recording as
evidence. Record the device model, Android version and app build in the header.

Device: __________  OS: __________  Build: __________  Tester: __________  Date: __________

Status values: PASS / FAIL / BLOCKED / NOT RUN

| ID | Test objective | Procedure | Expected result | Status | Evidence / remarks |
|---|---|---|---|---|---|
| PD-01 | Camera permission, first use | Fresh install. Home > START SCAN. Tap Allow. | Preview appears; no crash. | | |
| PD-02 | Camera permission denied | Fresh install. START SCAN. Tap Deny. | Permission message is shown; app does not crash; Back returns to Home. | | |
| PD-03 | Permission granted later | After PD-02, enable camera in system settings, reopen the scanner. | Preview appears. | | |
| PD-04 | Live detection, healthy sapling | Point at a healthy calamansi sapling in daylight. | Box + class label + confidence overlay; label reads Healthy; overlay updates about once per second. | | |
| PD-05 | Live detection, each class | Repeat PD-04 with Yellowing, Pest-Damaged, Wilting samples. | Label matches the visible symptom for each; record any mismatch. | | |
| PD-06 | Live detection, no plant | Point at a wall, a desk, a hand. | No detection boxes (or note any false positives). | | |
| PD-07 | Live overlay alignment | Hold the phone portrait, then landscape, then rotate during detection. | Box stays on the plant in every orientation (no offset or rotation error). | | |
| PD-08 | Live detection is boxes only | Watch the live view. | Boxes and labels only; no segmentation mask is drawn (live mode does not claim masks). | | |
| PD-09 | Capture, one sapling | Frame one sapling, tap Capture. | Result screen shows the photo with outline, class and confidence aligned to the image. | | |
| PD-10 | Capture, several saplings | Frame 3 or more saplings, Capture. | Each has a numbered outline; count matches what is visible; Sapling 1, 2, 3 order is left-to-right, top-to-bottom. | | |
| PD-11 | Capture, no sapling | Capture a non-plant scene. | "No Calamansi Sapling Detected" sheet; nothing is saved to History. | | |
| PD-12 | Capture, blurry photo | Move the phone while capturing. | Blur error message offers retry; app stays responsive. | | |
| PD-13 | Mask alignment | On PD-09, compare outline with the leaf edge. | Outline follows the leaf; no shift, scale or rotation error. | | |
| PD-14 | Gallery upload | Scanner > Upload from gallery > choose a sapling photo. | Same result screen as capture; correct class and outline. | | |
| PD-15 | Gallery cancelled | Open the picker, then Back. | Returns to the scanner without error. | | |
| PD-16 | Gallery portrait photo (EXIF) | Pick a portrait photo taken with the phone camera. | Photo is upright and outlines line up (EXIF rotation handled). | | |
| PD-17 | Save to History | After PD-09, tap Done. | New entry in History with the same photo, class, confidence and outline; Home and Statistics counts increase by the same amount. | | |
| PD-18 | Notification banner | Complete a scan. | Banner text matches the result (count + class). | | |
| PD-19 | Restart persistence | Force-close the app and reopen. | Name, History, Statistics and theme are unchanged. | | |
| PD-20 | Interruption | During live detection press Home, wait 30 s, return. | Camera resumes; no crash or frozen preview. | | |
| PD-21 | Low light / glare | Repeat PD-04 indoors, then in direct sun. | Record whether detection still works; note failures (this is a limitation, not an automatic FAIL). | | |
| PD-22 | Sustained use | Run live detection for 5 minutes. | No crash; the phone does not become unusably hot; note battery drop. | | |
| PD-23 | Low storage | With little free space, capture and save. | App shows an error or falls back safely; no crash. | | |

## Measurements to record for the report (do not estimate)

| Measurement | How | Result |
|---|---|---|
| analyzeImage latency (median / p95) | `flutter drive` profile run, IT-PL-07 output | |
| Live frame rate shown | Count overlay updates over 30 s | |
| Peak memory during live detection | Android Studio Profiler | |
| App size (APK/AAB) | build output | |
