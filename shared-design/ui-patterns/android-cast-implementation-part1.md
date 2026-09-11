# 🎯 Implementación de Cast en Android (Parte 1: Configuración)

Este documento muestra cómo implementar el botón de Cast en Android como reemplazo directo del botón de AirPlay en iOS.

## 📋 Diferencias Clave

| Característica | iOS (AirPlay) | Android (Cast) |
|---------------|---------------|----------------|
| Framework | AVKit | MediaRouter + Cast SDK |
| Clase UI | AVRoutePickerView | MediaRouteButton |
| Icono | airplay.audio | ic_cast |
| Dispositivos | Apple TV, HomePod, Altavoces AirPlay | Chromecast, Google Home, Android TV |

## 🔧 Configuración Inicial

### 1. Dependencias (app/build.gradle)

```gradle
dependencies {
    implementation 'androidx.mediarouter:mediarouter:1.4.0'
    implementation 'com.google.android.gms:play-services-cast-framework:21.3.0'
    implementation 'com.google.android.material:material:1.9.0'
}
```

### 2. Permisos (AndroidManifest.xml)

```xml
<uses-permission android:name="android.permission.BLUETOOTH" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
<uses-permission android:name="android.permission.MODIFY_AUDIO_SETTINGS" />
<uses-permission android:name="android.permission.ACCESS_WIFI_STATE" />
<uses-permission android:name="android.permission.CHANGE_WIFI_STATE" />
```

## 🎨 Implementación del Botón de Cast

### XML Layout (res/layout/activity_now_playing.xml)

```xml
<androidx.mediarouter.app.MediaRouteButton
    android:id="@+id/media_route_button"
    android:layout_width="44dp"
    android:layout_height="44dp"
    android:layout_margin="16dp"
    android:contentDescription="@string/cast_button_description"
    android:background="@drawable/glass_background"
    android:padding="10dp"
    app:mediaRouteButtonTint="@color/accent_dynamic" />
```

### Drawable Glass Background (res/drawable/glass_background.xml)

```xml
<?xml version="1.0" encoding="utf-8"?>
<shape xmlns:android="http://schemas.android.com/apk/res/android"
    android:shape="rectangle">
    <solid android:color="#14FFFFFF" /> <!-- 8% opacidad blanco -->
    <corners android:radius="22dp" />
</shape>
```

## 📝 Kotlin Implementation

### NowPlayingActivity.kt

```kotlin
package com.aurora.player.views

import android.os.Bundle
import androidx.appcompat.app.AppCompatActivity
import androidx.mediarouter.app.MediaRouteButton
import androidx.mediarouter.media.MediaControlIntent
import androidx.mediarouter.media.MediaRouteSelector
import com.aurora.player.R
import com.aurora.player.services.CastService
import com.aurora.player.services.ThemeManager

class NowPlayingActivity : AppCompatActivity() {
    
    private lateinit var mediaRouteButton: MediaRouteButton
    private lateinit var castService: CastService
    private lateinit var themeManager: ThemeManager
    
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_now_playing)
        
        themeManager = ThemeManager.getInstance(this)
        castService = CastService(this)
        
        setupCastButton()
        observeThemeChanges()
    }
    
    private fun setupCastButton() {
        mediaRouteButton = findViewById(R.id.media_route_button)
        
        val selector = MediaRouteSelector.Builder()
            .addControlCategory(MediaControlIntent.CATEGORY_LIVE_AUDIO)
            .addControlCategory(MediaControlIntent.CATEGORY_REMOTE_PLAYBACK)
            .build()
        
        mediaRouteButton.setRouteSelector(selector)
        updateCastButtonColor()
    }
    
    private fun observeThemeChanges() {
        themeManager.accentColor.observe(this) { color ->
            updateCastButtonColor()
        }
    }
    
    private fun updateCastButtonColor() {
        val accentColor = themeManager.getCurrentAccentColor()
        mediaRouteButton.setColorFilter(accentColor)
    }
    
    override fun onDestroy() {
        super.onDestroy()
        castService.cleanup()
    }
}
```

**Continúa en Parte 2: CastService.kt** →