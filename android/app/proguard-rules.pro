# Regras para manter classes necessárias do uCrop (usado via image_cropper).
# Sem isso, o R8 pode renomear/reempacotar a UCropActivity e o AndroidManifest
# fica apontando para um nome que não existe, causando ActivityNotFoundException.

-keep class com.yalantis.ucrop.UCropActivity { *; }
-keep class com.yalantis.ucrop.** { *; }
-dontwarn com.yalantis.ucrop.**

-keep class com.tiktok.** { *; }
-dontwarn com.tiktok.**
-keep class androidx.lifecycle.** { *; }
-dontwarn androidx.lifecycle.**
