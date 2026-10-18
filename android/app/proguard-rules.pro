# Keep all ONNX Runtime classes — prevents ClassNotFoundException on release
-keep class ai.onnxruntime.** { *; }
-keepclassmembers class ai.onnxruntime.** { *; }
-dontwarn ai.onnxruntime.**

# Keep Flutter
-keep class io.flutter.** { *; }
-dontwarn io.flutter.**