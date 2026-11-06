# flutter_local_notifications stores scheduled notifications with Gson.
-keep class com.dexterous.** { *; }
-keep class com.google.gson.reflect.TypeToken { *; }
-keep class * extends com.google.gson.reflect.TypeToken
-keepattributes Signature

# ML Kit text recognition: only the Latin model is bundled. The plugin also
# refers to the Chinese, Devanagari, Japanese and Korean recognisers, which
# are deliberately not included.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
