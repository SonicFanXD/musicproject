# AuroraPlayer

Reproductor de música, disponible para **iOS** y **Android**.

## Estructura del repositorio

```
auroraplayer/
├── AuroraPlayer/            # 🍏 App iOS nativa (Swift, AVFoundation, AirPlay)
├── AuroraPlayerApp.swift    # Punto de entrada iOS (raíz del proyecto Swift)
├── android/                 # 🤖 App Android (Kotlin, ExoPlayer, Google Cast)
│   ├── build.gradle
│   ├── README.md            # Guía de la versión Android
│   └── app/…
└── shared-design/           # 🎨 Sistema de diseño compartido entre plataformas
    ├── style-guide/         #   colores, componentes, specs de audio/cast, iconos
    ├── assets/              #   mapeo de iconos SF Symbols → Material Icons
    ├── ui-patterns/         #   guías de implementación (Cast, referencia iOS→Android)
    └── porting-checklist.md #   checklist para portar una pantalla iOS → Android
```

## Cómo funcionan las dos apps

Son **dos proyectos nativos independientes** con los **mismos diseños**.
El diseño (colores, glassmorphism, tamaños, iconos) se define una sola vez en
`shared-design/` y cada plataforma lo implementa con su propia tecnología:

| | iOS | Android |
|---|-----|---------|
| Motor de audio | AVFoundation | ExoPlayer (`androidx.media3`) |
| Enviar a dispositivo | AirPlay | Google Cast |
| Archivos/biblioteca | FileManager + bookmarks | MediaStore + SAF |
| Estado | `ObservableObject` | `LiveData` / ViewModel |

**Regla de oro:** si cambias el diseño (un color, un icono, un espaciado),
lo actualizas en `shared-design/` **y después** en cada plataforma, para que
nunca diverjan.

## Empezar

- **iOS:** abre `AuroraPlayer/` con el editor de Swift (Vela / Borf).
- **Android:** abre `android/` con Android Studio (ver `android/README.md`).

El checklist de porting (`shared-design/porting-checklist.md`) lleva el
progreso de qué pantallas ya están traducidas y cuáles faltan.