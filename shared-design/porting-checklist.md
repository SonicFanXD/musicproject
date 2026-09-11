# ✅ Checklist: Portar AuroraPlayer de iOS a Android

Use esta lista para seguir el progreso al portar funcionalidades de iOS a Android.

## 📋 Configuración Inicial

- [ ] Crear proyecto Android en Android Studio
- [ ] Configurar estructura de carpetas (ver `android-project-structure.json`)
- [ ] Agregar dependencias de MediaRouter y Cast SDK
- [ ] Configurar permisos en AndroidManifest.xml
- [ ] Crear sistema de colores dinámicos (equivalente a ThemeManager)

## 🎨 Sistema de Diseño

- [ ] Implementar paleta de colores (`colors.json`)
- [ ] Crear drawables glassmorphism para fondos
- [ ] Implementar sistema de colores dinámicos desde carátula
- [ ] Crear estilos de texto equivalentes
- [ ] Configurar temas dark/light

## 📱 Pantallas Principales

### ContentView → MainActivity
- [ ] NavigationStack → NavHostFragment
- [ ] CategoryPicker → TabLayout / BottomNavigation
- [ ] SearchBar → SearchView / TextInputEditText
- [ ] List → RecyclerView con SongAdapter
- [ ] Implementar pull-to-refresh

### NowPlayingView → NowPlayingActivity
- [ ] Portada de álbum con sombras
- [ ] Barra de progreso (Slider)
- [ ] Botones de reproducción (play, pause, next, previous)
- [ ] Botón de Cast (reemplazo de AirPlay)
- [ ] Visualizador de audio
- [ ] Letras (LyricsView)

### SettingsView → SettingsFragment
- [x] Toggle para acento dinámico desde carátula (`SettingsActivity`)
- [x] Ecualizador (button → `EqualizerActivity`) + presets
- [x] Audio mono (toggle → `AudioEngine.toggleMonoAudio`)
- [x] Calidad de salida Hi-Res (info row → `audioQualityInfo`)
- [x] Dispositivo / modelo (info row → `Build.MODEL`)
- [x] Color de acento manual (7 colores, `ThemeManager.setAccentIndex`)
- [x] Tema claro/oscuro dinámico (`ThemeManager.setThemeMode` + `values-night/`,
      selector Sistema/Claro/Oscuro en Settings, aplicado al arrancar en `AuroraPlayerApp`)
- [x] Estadísticas: canciones/álbumes/artistas (`vm.songs/albums/artists`)
- [x] Mantener pantalla encendida (toggle)
- [x] Visualizador de audio (`AudioVisualizerView` + toggle, barras al acento)
- [x] Ajustes de letras (`LyricsActivity` sincronizada + "lyrics by default")
- [x] Reducir transparencia (toggle → fondos opacos `opaque_background`)
- [x] Esquinas de carátula ajustable (slider 0-44pt → `clipToOutline`)
- [x] Idioma (Español/English, chips + `Localization` + textos en vivo)
- [x] Logs y Acerca de (`Logger.kt`, `LogsActivity`, diálogo de versión)

### QueueView → QueueFragment
- [ ] RecyclerView con reordenamiento drag & drop
- [ ] Swipe to dismiss
- [ ] Indicador de canción actual

### LyricsView → LyricsFragment
- [ ] Sincronización con tiempo de reproducción
- [ ] Scroll automático
- [ ] Resaltado de línea actual

## 🔊 Servicios de Audio

### AudioEngine → AudioEngine.kt
- [ ] Integrar ExoPlayer
- [ ] Implementar play, pause, next, previous
- [ ] Implementar seek (barra de progreso)
- [ ] Implementar shuffle y repeat modes
- [ ] Detección de dispositivos de audio
- [ ] Manejo de interrupciones (llamadas, etc.)

### FileAccessService → FileAccessService.kt
- [ ] Escaneo de archivos de audio
- [ ] Lectura de metadata (ID3 tags)
- [ ] Carga de carátulas
- [ ] Sistema de favoritos
- [ ] Sistema de playlists

### LibrarySearch → LibrarySearch.kt
- [ ] Búsqueda por título, artista, álbum
- [ ] Filtros por categoría
- [ ] Ordenamiento (título, artista, fecha, etc.)

### LyricsParser → LyricsParser.kt
- [ ] Parseo de archivos LRC
- [ ] Sincronización de tiempo

## 🎯 Casting (Reemplazo de AirPlay)

- [ ] Implementar CastService
- [ ] Crear botón MediaRouteButton
- [ ] Conexión con Chromecast/Google Home
- [ ] Envío de metadata al dispositivo
- [ ] Sincronización de estado
- [ ] Detección de dispositivos disponibles

## 🎵 Extras

### Ecualizador
- [x] Integrar Equalizer de Android (`android.media.Equalizer`, 10 bandas)
- [x] Interfaz visual de presets + switch principal (`EqualizerActivity`)
- [x] Presets (Flat, Bass, Treble, Vocal, Clásica, Electrónica, Pop, Rock, Jazz)

### Audio Mono y Salida Hi-Res
- [x] Audio mono con downmix a 1 canal (`toggleMonoAudio` + AudioManager)
- [x] Salida de alta resolución sin re-muestreo (ExoPlayer bit-perfect)
- [x] Info de calidad de salida (sample rate, canales, Hi-Res)

### Visualizador de Audio
- [ ] Visualización de ondas
- [ ] Colores dinámicos

### Haptics
- [ ] Vibración en controles (Android Haptic Feedback)

## 🧪 Testing

- [ ] Unit tests para servicios
- [ ] UI tests para pantallas principales
- [ ] Pruebas en múltiples dispositivos Android
- [ ] Pruebas de conexión Cast
- [ ] Pruebas de rendimiento con bibliotecas grandes

## 📦 Publicación

- [ ] Configurar signing de app
- [ ] Generar APK/AAB
- [ ] Crear Store Listing en Play Store
- [ ] Screenshots y videos
- [ ] Descripción y metadata

## 📊 Progreso Estimado

| Fase | Progreso |
|------|----------|
| Configuración | ⬜⬜⬜⬜⬜ 0% |
| Diseño | ⬜⬜⬜⬜⬜ 0% |
| Pantallas | ⬜⬜⬜⬜⬜ 0% |
| Audio | ⬜⬜⬜⬜⬜ 0% |
| Casting | ⬜⬜⬜⬜⬜ 0% |
| Testing | ⬜⬜⬜⬜⬜ 0% |
| **Total** | **⬜⬜⬜⬜⬜ 0%** |

---

**Nota**: Marca cada casilla `[ ]` con `[x]` cuando completes la funcionalidad.