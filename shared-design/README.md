# 🎨 AuroraPlayer - Sistema de Diseño Compartido

Este directorio contiene las especificaciones de diseño compartidas para mantener consistencia visual entre las versiones de iOS y Android de AuroraPlayer.

## 📁 Estructura del Directorio

```
shared-design/
├── style-guide/                    # Guías de estilo compartidas
│   ├── colors.json                    # Paleta de colores y temas
│   ├── ui-components.json             # Especificaciones de componentes UI
│   ├── audio-platform-specs.json      # Especificaciones de audio por plataforma
│   ├── android-project-structure.json # Estructura del proyecto Android
│   └── casting-specs.json             # Especificaciones de AirPlay/Cast
├── assets/                         # Recursos compartidos
│   └── icon-mapping.json              # Mapeo de iconos iOS SF Symbols → Android Material Icons
├── ui-patterns/                    # Patrones de implementación
│   ├── android-cast-implementation-part1.md  # Cast: Configuración y UI
│   ├── android-cast-implementation-part2.md  # Cast: CastService.kt
│   ├── ios-to-android-quick-reference-part1.md  # Referencia UI
│   └── ios-to-android-quick-reference-part2.md  # Referencia Audio/Animaciones
├── porting-checklist.md            # Checklist de porteo iOS → Android
└── README.md                       # Este archivo
```

## 🎯 Objetivo

Mantener una experiencia de usuario **idéntica** en ambas plataformas, donde solo cambie:

- ✅ Motor de audio (AVFoundation → ExoPlayer/MediaPlayer)
- ✅ Estructura de carpetas (Swift → Kotlin/Java)
- ✅ Información de dispositivos de audio (AirPlay → Cast/Chromecast)
- ✅ Permisos específicos de plataforma

## 🔑 Principios de Diseño

### 1. Consistencia Visual
- Mismos colores, tipografías y espaciados
- Mismos efectos visuales (glassmorphism, sombras)
- Mismas animaciones y transiciones

### 2. Fidelidad a la Plataforma
- iOS: Seguir Human Interface Guidelines
- Android: Seguir Material Design 3
- Adaptar componentes nativos cuando sea necesario

### 3. Código Compartido
- Lógica de negocio idéntica
- Mismos algoritmos (extracción de color, búsqueda, etc.)
- Misma estructura de datos

## 🎨 Colores Principales

| Color | Valor | Uso |
|-------|-------|-----|
| Acento (dinámico) | `#AF52DE` | Color principal, extraído de carátula |
| Fondo primario | `#000000` | Fondo principal |
| Fondo secundario | `#1C1C1E` | Cards y superficies |
| Texto primario | `#FFFFFF` | Títulos |
| Texto secundario | `#EBEBF599` | Subtítulos |
| Glass material | `rgba(255,255,255,0.08)` | Fondos translúcidos |

## 📱 Componentes Equivalentes

| iOS (SwiftUI) | Android (Kotlin/XML) |
|---------------|---------------------|
| View | Activity / Fragment |
| NavigationStack | Navigation Component |
| List | RecyclerView |
| VStack | LinearLayout (vertical) |
| HStack | LinearLayout (horizontal) |
| ZStack | FrameLayout |
| AppStorage | SharedPreferences |
| ObservableObject | ViewModel + LiveData |

## 🔊 Diferencias de Audio

### iOS
- **Framework**: AVFoundation
- **Casting**: AirPlay (AVRoutePickerView)
- **Detección**: AVAudioSessionRouteChange

### Android
- **Framework**: ExoPlayer (recomendado)
- **Casting**: Google Cast (MediaRouteButton)
- **Detección**: AudioManager.registerAudioDeviceCallback

## 📚 Archivos de Referencia Rápida

### Implementación de Cast
1. **[Parte 1](ui-patterns/android-cast-implementation-part1.md)** - Configuración, XML layouts, NowPlayingActivity
2. **[Parte 2](ui-patterns/android-cast-implementation-part2.md)** - CastService.kt completo

### Referencia iOS → Android
1. **[Parte 1](ui-patterns/ios-to-android-quick-reference-part1.md)** - UI, Layout, Estilos, Estado
2. **[Parte 2](ui-patterns/ios-to-android-quick-reference-part2.md)** - Audio, Animaciones, Archivos

### Checklist
- **[Porting Checklist](porting-checklist.md)** - Seguimiento de progreso del porteo

## 🚀 Próximos Pasos

1. [x] Crear sistema de diseño compartido
2. [ ] Crear proyecto Android en Android Studio
3. [ ] Implementar sistema de colores dinámicos
4. [ ] Desarrollar componentes UI equivalentes
5. [ ] Integrar ExoPlayer para audio
6. [ ] Implementar Cast SDK para reemplazar AirPlay
7. [ ] Sincronizar lógica de negocio

## 📝 Convenciones

### Nombres de Archivos
- **iOS**: `CamelCase.swift` (ej: `NowPlayingView.swift`)
- **Android**: `CamelCase.kt` (ej: `NowPlayingActivity.kt`)

### Nombres de Paquetes Android
```
com.aurora.player/
├── views/          # Activities y Fragments
├── services/       # Lógica de negocio
├── models/         # Modelos de datos
├── adapters/       # RecyclerView adapters
└── viewmodels/    # ViewModels (MVVM)
```

### Recursos Android
```
res/
├── layout/         # XML layouts
├── values/         # colors.xml, strings.xml, styles.xml
├── drawable/       # Iconos y backgrounds
└── mipmap-*/       # Iconos de la app
```

## 🎯 Recomendación para Empezar

1. **Empieza por el diseño**: Revisa `colors.json` y `ui-components.json`
2. **Configura el proyecto Android**: Usa `android-project-structure.json` como guía
3. **Implementa primero AudioEngine.kt**: Es el corazón de la app
4. **Luego las pantallas**: ContentView → NowPlayingView → SettingsView
5. **Finalmente Cast**: Reemplaza AirPlay con Cast

## 📞 Dudas Frecuentes

### ¿Mantengo los dos proyectos en el mismo repositorio?
**Sí**, usa esta estructura:
```
auroraplayer/
├── iOS/              # Tu proyecto Swift actual
├── android/          # Nuevo proyecto Android
├── shared-design/    # Este directorio
└── README.md
```

### ¿Cómo manejo los iconos?
Usa `assets/icon-mapping.json` para convertir SF Symbols a Material Icons.

### ¿Cómo aseguro que los diseños sean iguales?
Sigue las especificaciones en `ui-components.json` para tamaños, espaciados y colores.

---

**Versión**: 1.0.0  
**Última actualización**: 2026-09-09  
**Autor**: AuroraPlayer Team