# 🚀 Referencia Rápida: iOS → Android (Parte 2: Audio y Animaciones)

## 🎵 Audio

### Reproducción

**iOS (Swift):**
```swift
let player = AVPlayer(url: audioURL)
player.play()
```

**Android (Kotlin con ExoPlayer):**
```kotlin
val player = ExoPlayer.Builder(context).build()
val mediaItem = MediaItem.fromUri(audioURL)
player.setMediaItem(mediaItem)
player.prepare()
player.play()
```

### Detección de Dispositivos de Audio

**iOS (Swift):**
```swift
NotificationCenter.default.addObserver(
    forName: AVAudioSession.routeChangeNotification,
    object: nil,
    queue: .main
) { _ in
    // Manejar cambio de ruta
}
```

**Android (Kotlin):**
```kotlin
val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager

val deviceCallback = object : AudioDeviceCallback() {
    override fun onAudioDevicesAdded(addedDevices: Array<out AudioDeviceInfo>?) {
        // Dispositivo conectado
    }
    
    override fun onAudioDevicesRemoved(removedDevices: Array<out AudioDeviceInfo>?) {
        // Dispositivo desconectado
    }
}

audioManager.registerAudioDeviceCallback(deviceCallback, null)
```

### Ecualizador

**iOS (Swift):**
```swift
let equalizer = AVAudioUnitEQ(numberOfBands: 5)
```

**Android (Kotlin):**
```kotlin
val equalizer = Equalizer(0, audioSessionId)
equalizer.enabled = true
// Bandas: equalizer.numberOfBands
```

## 🎭 Animaciones

### Spring Animation

**iOS (Swift):**
```swift
.animation(.spring(response: 0.32, dampingFraction: 0.88), value: isVisible)
```

**Android (Kotlin):**
```kotlin
// En res/anim/spring_animation.xml
// O programáticamente:
val springAnimation = SpringAnimation(view, DynamicAnimation.TRANSLATION_Y, 0f).apply {
    spring.stiffness = SpringForce.STIFFNESS_LOW
    spring.dampingRatio = SpringForce.DAMPING_RATIO_MEDIUM_BOUNCY
}
springAnimation.start()
```

### withAnimation

**iOS (Swift):**
```swift
withAnimation(.easeInOut(duration: 0.3)) {
    isExpanded.toggle()
}
```

**Android (Kotlin):**
```kotlin
view.animate()
    .alpha(if (isExpanded) 1f else 0f)
    .setDuration(300)
    .setInterpolator(FastOutSlowInInterpolator())
    .start()
```

## 📂 Archivos y Recursos

### Acceso a Archivos

**iOS (Swift):**
```swift
let documentsPath = FileManager.default.urls(for: .documentDirectory, 
                                             in: .userDomainMask)[0]
```

**Android (Kotlin):**
```kotlin
val filesDir = context.filesDir
val cacheDir = context.cacheDir
```

### UserDefaults → SharedPreferences

**iOS (Swift):**
```swift
UserDefaults.standard.set(true, forKey: "hasSeenOnboarding")
let value = UserDefaults.standard.bool(forKey: "hasSeenOnboarding")
```

**Android (Kotlin):**
```kotlin
val prefs = context.getSharedPreferences("aurora_prefs", Context.MODE_PRIVATE)
prefs.edit().putBoolean("has_seen_onboarding", true).apply()
val value = prefs.getBoolean("has_seen_onboarding", false)
```

## 🔔 Notificaciones

### Local Notifications

**iOS (Swift):**
```swift
let content = UNMutableNotificationContent()
content.title = "Canción terminada"
```

**Android (Kotlin):**
```kotlin
val notification = NotificationCompat.Builder(context, CHANNEL_ID)
    .setContentTitle("Canción terminada")
    .setSmallIcon(R.drawable.ic_notification)
    .build()
```

## 📝 Notas Importantes

1. **Hilos**: En Android, las operaciones de red/IO deben hacerse en background thread
2. **Permisos**: Android requiere solicitar permisos en runtime (API 23+)
3. **Ciclo de vida**: Android tiene Activity/Fragment lifecycle más complejo
4. **Tamaños**: Usar `dp` para dimensiones, `sp` para textos
5. **Densidad**: Proveer recursos para múltiples densidades (mdpi, hdpi, xhdpi, etc.)

## 🔗 Referencias Adicionales

- [Android Developers](https://developer.android.com)
- [Material Design 3](https://m3.material.io)
- [ExoPlayer](https://developer.android.com/media/media3/exoplayer)
- [Android Kotlin Guides](https://developer.android.com/kotlin)