# android/app/proguard-rules.pro
# Fixes: FAILURE: Build failed - :app:minifyReleaseWithR8
# ERROR: Missing class com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions
#        Missing class com.google.mlkit.vision.text.korean.KoreanTextRecognizerOptions
#
# Why: google_mlkit_text_recognition references ALL language models
# (Latin, Chinese, Korean, Japanese, Devanagari) but only Latin is
# bundled by default. R8 treats those missing optional classes as fatal
# in release builds. These rules tell R8: don't warn, don't strip ML Kit.

# --- ML Kit: keep everything, don't warn about missing optional languages ---
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_text.** { *; }
-dontwarn com.google.mlkit.**
-dontwarn com.google.android.gms.internal.mlkit_vision_text.**

# Specifically keep the text recognizer entry points R8 was complaining about
-keep class com.google.mlkit.vision.text.TextRecognizer { *; }
-keep class com.google.mlkit.vision.text.TextRecognition { *; }
-keep class com.google.mlkit.vision.text.latin.TextRecognizerOptions { *; }
-keep class com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions { *; }
-keep class com.google.mlkit.vision.text.korean.KoreanTextRecognizerOptions { *; }
-keep class com.google.mlkit.vision.text.japanese.JapaneseTextRecognizerOptions { *; }
-keep class com.google.mlkit.vision.text.devanagari.DevanagariTextRecognizerOptions { *; }

# --- Flutter / generic: keep what R8 usually strips too aggressively ---
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.**
