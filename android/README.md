# Сборка APK для Android

Это проект Gradle вокруг игры из папки `godot/`. Godot для Android берётся готовой библиотекой из Maven Central (`org.godotengine:godot`), а файлы игры при сборке копируются внутрь APK.

Обычно APK собирает Claude по просьбе «собери APK». Чтобы собрать самому, нужны JDK 17+, Android SDK (platform 35, build-tools 35) и Gradle 8.13+:

```
cd android
gradle assembleRelease
```

Готовый файл: `android/app/build/outputs/apk/release/app-release.apk`. Он подписан отладочным ключом, поэтому ставится на телефон вручную. Для Google Play понадобится свой ключ.
