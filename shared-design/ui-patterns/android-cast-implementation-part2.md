# 🎯 Implementación de Cast en Android (Parte 2: CastService)

## 📝 CastService.kt

```kotlin
package com.aurora.player.services

import android.content.Context
import android.net.Uri
import android.widget.Toast
import androidx.mediarouter.media.MediaRouter
import com.google.android.gms.cast.MediaInfo
import com.google.android.gms.cast.MediaMetadata
import com.google.android.gms.cast.framework.CastContext
import com.google.android.gms.cast.framework.CastSession
import com.google.android.gms.cast.framework.SessionManagerListener
import com.google.android.gms.common.images.WebImage
import com.aurora.player.models.Song

class CastService(private val context: Context) {
    
    private val castContext: CastContext = CastContext.getSharedInstance(context)
    private var castSession: CastSession? = null
    
    private val sessionManagerListener = object : SessionManagerListener<CastSession> {
        override fun onSessionStarted(session: CastSession, sessionId: String) {
            castSession = session
            showToast("Conectado a ${session.castDevice.friendlyName}")
        }
        
        override fun onSessionEnded(session: CastSession, error: Int) {
            castSession = null
            showToast("Desconectado del dispositivo")
        }
        
        override fun onSessionResumed(session: CastSession, wasSuspended: Boolean) {
            castSession = session
        }
    }
    
    init {
        castContext.sessionManager.addSessionManagerListener(
            sessionManagerListener,
            CastSession::class.java
        )
    }
    
    /**
     * Envía información de la canción al dispositivo Cast
     */
    fun sendSongInfo(song: Song) {
        val session = castSession ?: return
        
        val metadata = MediaMetadata(MediaMetadata.MEDIA_TYPE_MUSIC_TRACK).apply {
            putString(MediaMetadata.KEY_TITLE, song.title)
            putString(MediaMetadata.KEY_ARTIST, song.artist)
            putString(MediaMetadata.KEY_ALBUM_TITLE, song.album)
            
            // Imagen de portada
            song.artworkUrl?.let { url ->
                val image = WebImage(Uri.parse(url))
                addImage(image)
            }
        }
        
        val mediaInfo = MediaInfo.Builder(song.audioUrl)
            .setStreamType(MediaInfo.STREAM_TYPE_BUFFERED)
            .setContentType("audio/mpeg")
            .setMetadata(metadata)
            .setStreamDuration(song.duration * 1000) // convertir a ms
            .build()
        
        // Cargar media en el dispositivo Cast
        session.remoteMediaClient?.load(mediaInfo)
    }
    
    /**
     * Actualiza el estado de reproducción en el dispositivo Cast
     */
    fun updatePlaybackState(isPlaying: Boolean, position: Long) {
        val session = castSession ?: return
        val remoteMediaClient = session.remoteMediaClient ?: return
        
        if (isPlaying) {
            remoteMediaClient.play()
        } else {
            remoteMediaClient.pause()
        }
    }
    
    /**
     * Obtiene lista de dispositivos Cast disponibles
     */
    fun getAvailableDevices(): List<CastDeviceInfo> {
        val devices = mutableListOf<CastDeviceInfo>()
        val router = MediaRouter.getInstance(context)
        
        router.routes.forEach { route ->
            if (route.playbackType == MediaRouter.RouteInfo.PLAYBACK_ROUTE_REMOTE) {
                devices.add(
                    CastDeviceInfo(
                        id = route.id,
                        name = route.name,
                        isConnected = route.isSelected,
                        type = getDeviceType(route)
                    )
                )
            }
        }
        
        return devices
    }
    
    private fun getDeviceType(route: MediaRouter.RouteInfo): String {
        return when {
            route.name.contains("Chromecast", ignoreCase = true) -> "Chromecast"
            route.name.contains("Google Home", ignoreCase = true) -> "Google Home"
            route.name.contains("TV", ignoreCase = true) -> "Smart TV"
            else -> "Cast Device"
        }
    }
    
    fun cleanup() {
        castContext.sessionManager.removeSessionManagerListener(
            sessionManagerListener,
            CastSession::class.java
        )
    }
    
    private fun showToast(message: String) {
        Toast.makeText(context, message, Toast.LENGTH_SHORT).show()
    }
}

data class CastDeviceInfo(
    val id: String,
    val name: String,
    val isConnected: Boolean,
    val type: String
)
```

## 📱 Pruebas Recomendadas

### Dispositivos de Prueba
1. **Chromecast Ultra** - Cast básico
2. **Google Nest Audio** - Cast con pantalla
3. **Smart TV con Chromecast integrado**
4. **Android TV** - Experiencia completa

### Escenarios de Prueba
- [ ] Detección automática de dispositivos
- [ ] Conexión/desconexión
- [ ] Envío de metadata de canción
- [ ] Sincronización de estado
- [ ] Cambio dinámico de color del icono
- [ ] Manejo de errores de conexión

## 🔗 Referencias
- [MediaRouter API](https://developer.android.com/media/media3/exo_player/media-router)
- [Google Cast SDK](https://developers.google.com/cast)
- [Material Icons](https://fonts.google.com/icons)