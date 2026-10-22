# Keep all ONNX Runtime classes — prevents ClassNotFoundException on release
-keep class ai.onnxruntime.** { *; }
-keepclassmembers class ai.onnxruntime.** { *; }
-dontwarn ai.onnxruntime.**
-keep class io.flutter.plugins.** { *; }
-keepclassmembers class io.flutter.plugins.** { *; }

# Keep Flutter
-keep class io.flutter.** { *; }
-dontwarn io.flutter.**
