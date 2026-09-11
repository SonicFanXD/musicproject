# AuroraPlayer — Android (Kotlin + Android TV LYA / MFEST)

Versión Android de AuroraPlayer, desarrollada en **Kotlin** con el stack de
**Android UI / TV** (LYA + MFEST + Lifecycle ViewModel). Es la traducción 1:1
de la app iOS (`AuroraPlayer/`), con los **mismos diseños** pero adaptada a las
APIs de Android.

## Dónde viven las diferencias vs iOS

| Capa | iOS (Swift) | Android (Kotlin) |
|------|-------------|------------------|
| Motor de audio | AVFoundation | **ExoPlayer** (`androidx.media3`) |
| Cast / escribir a dispositivo | AirPlay (`AVRoutePickerView`) | **Google Cast** (`MediaRouteButton`) |
| Acceso a archivos | `FileManager` + bookmarks | **MediaStore** + SAF (`DocumentFile`) |
| Iconos | SF Symbols | Material Icons (drawables `@drawable/ic_*`) |
| Estado reactivo | `ObservableObject` / `@Published` | `LiveData` / `MutableLiveData` |
| Almacenamiento | `@AppStorage` | `SharedPreferences` + JSON cache |

**El diseño compartido** (colores, tamaños, glassmorphism, mapeo de iconos y
checklist de porting) vive en `../shared-design/`.

## Estructura

```
android/
├── build.gradle              # Build raíz (AGP 8 + Kotlin)
├── gradle.properties
├── settings.gradle
└── app/
    ├── build.gradle          # Dependencias (ExoPlayer, Cast, Coil, RecyclerView…)
    └── src/main/
        ├── AndroidManifest.xml   # Permisos, activities, servicio de audio, Cast
        ├── java/com/aurora/player/
        │   ├── AuroraPlayerApp.kt
        │   ├── adapters/      # RecyclerView adapters (Song, Album, Artist, Playlist)
        │   ├── models/        # Song, Album, Artist, Playlist, Lyrics, enums
        │   ├── services/      # AudioEngine, FileAccessService, ThemeManager, Localization, Cast
        │   ├── viewmodels/    # LibraryViewModel (LiveData)
        │   └── views/         # MainActivity, NowPlayingActivity, SettingsActivity
        └── res/
            ├── layout/        # activity_*.xml, item_song, item_album, player_bar
            ├── values/        # colors.xml, strings.xml, themes.xml
            ├── drawable/      # iconos + fondos (glass, artwork, buttons)
            └── menu/          # menu_main.xml
```

## Requisitos para abrirlo / compilarlo

1. **Android Studio** (o IntelliJ con plugins Kotlin + Android).
2. **Android SDK** target 34 con el plugin `com.android.application` 8.1+.
3. Generar/crear `app/src/main/res/mipmap-*/ic_launcher*` (iconos de la app).
4. Para firmar Android TV necesitas un `android keystore` (ver
   `com.android.application` signing). Localmente puedes usar el
   certificado de desarrollo de Google Chromecast.

## Notas de porting activas

- El color de acento dinámico se extrae con `androidx.palette` (equivalente al
  algoritmo de `ThemeManager.swift`).
- El escaneo usa el catálogo `MediaStore.Audio.Media` con permiso
  `READ_MEDIA_AUDIO` (target 34) y `READ_EXTERNAL_STORAGE` en SDK < 33.
- El botón de Cast es un `MediaRouteButton` configurado con el
  `Default Media Receiver` (no requiere App ID propio). Implementación
  completa en `../shared-design/ui-patterns/android-cast-implementation*.md`.

## Audio completo (equivalente a AudioEngine.swift)

El motor usa **ExoPlayer** con ajustes de audio replicados 1:1 del iOS:

| Ajuste | iOS | Android |
|--------|-----|---------|
| Ecualizador | `AVAudioUnitEQ` (10 bandas) | `android.media.Equalizer` (10 bandas) |
| Presets | `EQPreset.swift` | `EQPreset` en `models/Song.kt` |
| Audio Mono | `setPreferredOutputNumberOfChannels(1)` | `AudioManager.setPreferredOutputNumberOfChannels(1)` |
| Salida Hi-Res | bit-perfect sin re-muestrear | ExoPlayer no re-muestrea (bit-perfect) |
| Info de salida | `outputSampleRate` / `audioQualityInfo` | `audioQualityInfo` LiveData |

Pantallas añadidas:
- `views/EqualizerActivity` — switch del EQ + presets (mismo diseño glassmorphism).
- `views/SettingsActivity` — sección Audio (ecualizador, mono), Rendimiento
  (calidad de salida, dispositivo), Personalización (color de acento) y
  Estadísticas (canciones, álbumes, artistas).

## Apariencia y extras portados

| Ajuste | Estado |
|--------|--------|
| Tema claro/oscuro dinámico | ✅ `ThemeManager.setThemeMode` (Sistema/Claro/Oscuro) |
| Acento desde carátula | ✅ `ThemeManager.accentFromArtwork` |
| Color de acento manual (7 colores) | ✅ `ThemeManager.setAccentIndex` (misma tabla que iOS) |
| Estadísticas | ✅ canciones / álbumes / artistas en `SettingsActivity` |
| Dispositivo / salida | ✅ `Build.MODEL` + `audioQualityInfo` |
| Idioma Español/English | ✅ chips en Apariencia + `Localization` (textos en vivo) |
| Reducir transparencia | ✅ toggle → tarjetas opacas (`opaque_background`) |
| Esquinas de carátula | ✅ slider 0-44pt → `clipToOutline` en NowPlaying |
| Visualizador de audio | ✅ `AudioVisualizerView` (barras al acento, toggle) |
| Letras sincronizadas | ✅ `LyricsActivity` (archivos `.lrc` junto al audio) |
| Logs y Acerca de | ✅ `Logger` + `LogsActivity` + diálogo de versión |

## Extras portados (última tanda)

- **Selector de idioma**: chips Español/English en Apariencia; al cambiar se
  persiste en `SharedPreferences` y las secciones de Ajustes se re-renderizan
  vía `Localization` (equivalente a `Localization.shared` en iOS).
- **Reducir transparencia**: cuando está activo, todas las tarjetas con fondo
  `glass_background` se repintan a `opaque_background` (recorrido recursivo de
  vistas), igual que el ajuste de iOS.
- **Esquinas de carátula**: slider 0-44pt (paso 2, como iOS); NowPlaying
  recorta la portada con `ViewOutlineProvider` y lo re-aplica en `onResume`.
- **Visualizador**: `AudioVisualizerView` dibuja 24 barras animadas mientras
  suena música, coloreadas con el acento dinámico (no requiere permisos).
- **Letras sincronizadas**: `LyricsActivity` busca un archivo `.lrc` junto al
  audio (`Song.filePath` del MediaStore), lo parsea con `LyricsParser`
  (mismo modelo que iOS), resalta la línea activa y hace scroll automático.
  El toggle "Letras por defecto" abre la pantalla al reproducir.
- **Logs y Acerca de**: `Logger` (buffer circular de 400 entradas) registra
  escaneos, reproducción y NowPlaying; `LogsActivity` los muestra con fuente
  monoespaciada y botón de limpiar. "Acerca de" muestra la versión en un diálogo.

## Tema claro/oscuro (equivalente a `preferredColorScheme` en iOS)

Android resuelve el tema con **recursos night-qualified** (la forma idiomática):

| iOS | Android |
|-----|---------|
| `preferredColorScheme(.light/.dark/nil)` | `AppCompatDelegate.setDefaultNightMode(...)` |
| `@AppStorage("com.aurora.uiTheme")` | `SharedPreferences("aurora_theme").theme_mode` |
| `colorScheme == .dark ? ... : ...` | `res/values/` (claro) vs `res/values-night/` (oscuro) |

Archivos que lo implementan:
- `res/values/colors.xml` — paleta clara (`#F2F2F7` fondo, texto negro)
- `res/values-night/colors.xml` — paleta oscura (`#000000` fondo, texto blanco)
- `res/values/themes.xml` — tema DayNight + status bar clara
- `res/values-night/themes.xml` — override con status bar oscura
- `ThemeManager.setThemeMode(0|1|2)` — aplica `MODE_NIGHT_FOLLOW_SYSTEM/NO/YES`
- `AuroraPlayerApp.onCreate` — restaura el modo guardado antes de inflar la UI
- `SettingsActivity` — chips Sistema (claro/oscuro) / Claro / Oscuro

Detalle fino: los iconos sobre el botón morado de Play usan el color fijo
`icon_on_accent` (`#FFFFFF` siempre), mientras los iconos de controles usan
`control_icon` (negro en claro, blanco en oscuro) — igual que iOS, donde el
botón de Play mantiene el icono blanco sobre el acento en ambos modos.

**Nota honorífica sobre Hi-Res:** iOS y Android comparten el mismo principio:
el PCM del archivo se envía al sistema sin re-muestreo forzado, así que cada
canción suena a su tasa/bit nativos (FLAC 24-bit/192kHz se reproduce tal cual).
En Android, ExoPlayer ya ejecuta esta passthrough transparente.