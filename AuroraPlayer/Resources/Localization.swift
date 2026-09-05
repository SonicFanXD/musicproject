import Foundation

enum Localization {
    enum Language: Int {
        case spanish = 0
        case english = 1
    }

    static var currentLanguage: Language {
        get {
            let lang = UserDefaults.standard.integer(forKey: "com.aurora.language")
            return Language(rawValue: lang) ?? .spanish
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "com.aurora.language")
        }
    }

    static func localized(_ key: String) -> String {
        let strings: [String: [Language: String]] = [
            // Configuración / Settings
            "settings.title": [.spanish: "Configuración", .english: "Settings"],
            "settings.library": [.spanish: "Biblioteca", .english: "Library"],
            "settings.audio": [.spanish: "Audio", .english: "Audio"],
            "settings.appearance": [.spanish: "Apariencia", .english: "Appearance"],
            "settings.playback": [.spanish: "Reproducción", .english: "Playback"],
            "settings.customization": [.spanish: "Personalización", .english: "Customization"],
            "settings.advanced": [.spanish: "Avanzado", .english: "Advanced"],
            "settings.about": [.spanish: "Acerca de", .english: "About"],

            // Biblioteca / Library
            "settings.musicFolders": [.spanish: "Carpetas de música", .english: "Music Folders"],
            "settings.updateLibrary": [.spanish: "Actualizar biblioteca", .english: "Update Library"],
            "settings.scanning": [.spanish: "Escaneando...", .english: "Scanning..."],
            "settings.rescanFolders": [.spanish: "Rescanear carpetas", .english: "Rescan Folders"],

            // Audio
            "settings.equalizer": [.spanish: "Equalizador", .english: "Equalizer"],
            "settings.crossfade": [.spanish: "Crossfade", .english: "Crossfade"],
            "settings.crossfadeDuration": [.spanish: "Duración del crossfade", .english: "Crossfade Duration"],
            "settings.crossfadeTransition": [.spanish: "Transición de", .english: "Transition of"],
            "settings.crossfadeDisabled": [.spanish: "Desactivado", .english: "Disabled"],
            "settings.crossfadeEnabled": [.spanish: "Activado", .english: "Enabled"],

            // Apariencia / Appearance
            "settings.theme": [.spanish: "Tema", .english: "Theme"],
            "settings.accentColor": [.spanish: "Color de acento", .english: "Accent Color"],
            "settings.dynamicColor": [.spanish: "Color dinámico", .english: "Dynamic Color"],
            "settings.dynamicColorSubtitle": [.spanish: "Extrae el color dominante de la portada", .english: "Extract dominant color from artwork"],
            "settings.artworkCorners": [.spanish: "Esquinas del artwork", .english: "Artwork Corners"],
            "settings.reduceTransparency": [.spanish: "Reducir transparencia", .english: "Reduce Transparency"],
            "settings.reduceTransparencySubtitle": [.spanish: "Menos desenfoques, más rendimiento", .english: "Less blur, better performance"],
            "settings.language": [.spanish: "Idioma", .english: "Language"],

            // Reproducción / Playback
            "settings.visualizer": [.spanish: "Visualizador de audio", .english: "Audio Visualizer"],
            "settings.visualizerSubtitle": [.spanish: "Animación de barras en Reproduciendo", .english: "Bar animation in Now Playing"],
            "settings.haptics": [.spanish: "Respuesta táctil", .english: "Haptic Feedback"],
            "settings.hapticsSubtitle": [.spanish: "Vibración al tocar los controles", .english: "Vibration on touch controls"],
            "settings.keepScreenOn": [.spanish: "Mantener pantalla encendida", .english: "Keep Screen On"],
            "settings.keepScreenOnSubtitle": [.spanish: "Evita que se bloquee mientras se reproduce", .english: "Prevent screen lock during playback"],
            "settings.autoPlayOnStart": [.spanish: "Reproducir al iniciar", .english: "Auto Play on Start"],
            "settings.autoPlayOnStartSubtitle": [.spanish: "Reanudar reproducción al abrir la app", .english: "Resume playback when opening app"],

            // Personalización / Customization
            "settings.animationSpeed": [.spanish: "Velocidad de animación", .english: "Animation Speed"],
            "settings.hapticIntensity": [.spanish: "Intensidad táctil", .english: "Haptic Intensity"],

            // Avanzado / Advanced
            "settings.showLyricsByDefault": [.spanish: "Mostrar letras por defecto", .english: "Show Lyrics by Default"],
            "settings.showLyricsByDefaultSubtitle": [.spanish: "Abrir vista de letras al iniciar reproducción", .english: "Open lyrics view when playback starts"],
            "settings.showVisualizerInBar": [.spanish: "Visualizador en barra", .english: "Visualizer in Bar"],
            "settings.showVisualizerInBarSubtitle": [.spanish: "Mostrar visualizador en el player bar", .english: "Show visualizer in player bar"],
            "settings.compactPlayerBar": [.spanish: "Barra compacta", .english: "Compact Player Bar"],
            "settings.compactPlayerBarSubtitle": [.spanish: "Reducir altura del player bar", .english: "Reduce player bar height"],

            // Acerca de / About
            "settings.title": [.spanish: "Ajustes", .english: "Settings"],
            "settings.subtitle": [.spanish: "Configura Aurora Player a tu gusto", .english: "Customize Aurora Player"],
            "settings.description": [.spanish: "Reproductor de música Hi-Fi optimizado para iOS con soporte de alta fidelidad, ecualizador de 10 bandas, crossfade ajustable y gestión avanzada de carpetas locales.", .english: "Hi-Fi music player optimized for iOS with high-fidelity support, 10-band equalizer, adjustable crossfade and advanced local folder management."],
            "settings.version": [.spanish: "Versión", .english: "Version"],
            "settings.build": [.spanish: "Build", .english: "Build"],
            "settings.logs": [.spanish: "Registros", .english: "Logs"],
            "settings.logsSubtitle": [.spanish: "Ver registros de la app", .english: "View app logs"],

            // Controles comunes / Common controls
            "play": [.spanish: "Reproducir", .english: "Play"],
            "pause": [.spanish: "Pausar", .english: "Pause"],
            "next": [.spanish: "Siguiente", .english: "Next"],
            "previous": [.spanish: "Anterior", .english: "Previous"],
            "shuffle": [.spanish: "Aleatorio", .english: "Shuffle"],
            "repeat": [.spanish: "Repetir", .english: "Repeat"],
            "repeatAll": [.spanish: "Repetir todo", .english: "Repeat All"],
            "repeatOne": [.spanish: "Repetir uno", .english: "Repeat One"],
            "repeatOff": [.spanish: "Sin repetición", .english: "Repeat Off"],

            // Vista Now Playing
            "nowPlaying.title": [.spanish: "Reproduciendo", .english: "Now Playing"],
            "nowPlaying.queue": [.spanish: "Cola", .english: "Queue"],
            "nowPlaying.lyrics": [.spanish: "Letras", .english: "Lyrics"],
            "nowPlaying.addQueue": [.spanish: "Añadir a cola", .english: "Add to Queue"],
            "nowPlaying.addToFavorites": [.spanish: "Añadir a favoritos", .english: "Add to Favorites"],
            "nowPlaying.removeFromFavorites": [.spanish: "Eliminar de favoritos", .english: "Remove from Favorites"],

            // Librería / Library
            "library.songs": [.spanish: "Canciones", .english: "Songs"],
            "library.albums": [.spanish: "Álbumes", .english: "Albums"],
            "library.artists": [.spanish: "Artistas", .english: "Artists"],
            "library.favorites": [.spanish: "Favoritos", .english: "Favorites"],
            "library.playlists": [.spanish: "Listas", .english: "Playlists"],
            "library.history": [.spanish: "Historial", .english: "History"],
            "library.sort": [.spanish: "Ordenar", .english: "Sort"],
            "library.sortAscending": [.spanish: "Ascendente", .english: "Ascending"],
            "library.sortDescending": [.spanish: "Descendente", .english: "Descending"],
            "library.noPlaylists": [.spanish: "No hay listas disponibles", .english: "No playlists available"],

            // App name
            "app.name": [.spanish: "Aurora Player", .english: "Aurora Player"],

            // Playlists
            "playlists.title": [.spanish: "Listas de Reproducción", .english: "Playlists"],
            "playlists.yourPlaylists": [.spanish: "Tus Listas", .english: "Your Playlists"],
            "playlists.subtitle": [.spanish: "Crea y gestiona tus listas de reproducción personalizadas", .english: "Create and manage your custom playlists"],
            "playlists.newPlaylist": [.spanish: "Nueva Lista", .english: "New Playlist"],
            "playlists.newPlaylistSubtitle": [.spanish: "Crea una nueva lista de reproducción personalizada", .english: "Create a new custom playlist"],
            "playlists.name": [.spanish: "Nombre", .english: "Name"],
            "playlists.description": [.spanish: "Descripción", .english: "Description"],
            "playlists.descriptionOptional": [.spanish: "Descripción (opcional)", .english: "Description (optional)"],
            "playlists.createPlaylist": [.spanish: "Crear Lista", .english: "Create Playlist"],
            "playlists.placeholderName": [.spanish: "Mi lista", .english: "My playlist"],
            "playlists.placeholderDescription": [.spanish: "Descripción de la lista", .english: "Playlist description"],
            "playlists.empty": [.spanish: "No hay listas", .english: "No playlists"],
            "playlists.emptySubtitle": [.spanish: "Crea tu primera lista de reproducción", .english: "Create your first playlist"],
            "playlists.emptySubtitle2": [.spanish: "Crea tu primera lista para organizar tu música", .english: "Create your first list to organize your music"],

            // Indexing / Escaneo
            "indexing.updating": [.spanish: "Actualizando...", .english: "Updating..."],
            "indexing.indexingLibrary": [.spanish: "Indexando tu biblioteca", .english: "Indexing your library"],
            "indexing.progress": [.spanish: "de", .english: "of"],
            "indexing.preparing": [.spanish: "Preparando tu música…", .english: "Preparing your music…"],
            "indexing.processed": [.spanish: "Indexando…", .english: "Indexing…"],

            // Actions
            "actions.addFolder": [.spanish: "Agregar carpeta de música", .english: "Add music folder"],
            "actions.done": [.spanish: "Listo", .english: "Done"],
            "actions.clearQueue": [.spanish: "Limpiar cola", .english: "Clear queue"],
            "actions.play": [.spanish: "Reproducir", .english: "Play"],
            "actions.like": [.spanish: "Me Gusta", .english: "Like"],
            "actions.unlike": [.spanish: "Quitar de Me Gusta", .english: "Remove from Likes"],
            "actions.addToQueue": [.spanish: "Añadir a cola", .english: "Add to Queue"],
            "actions.addToPlaylist": [.spanish: "Añadir a lista", .english: "Add to Playlist"],

            // Queue
            "queue.title": [.spanish: "Cola de Reproducción", .english: "Play Queue"],
            "queue.nextUp": [.spanish: "Siguiente", .english: "Next Up"],
            "queue.history": [.spanish: "Historial", .english: "History"],
            "queue.empty": [.spanish: "Cola vacía", .english: "Queue empty"],
            "queue.emptyHistory": [.spanish: "Sin historial", .english: "No history"],
            "queue.nowPlaying": [.spanish: "Reproduciendo ahora", .english: "Now Playing"],
            "queue.emptyQueue": [.spanish: "No hay canciones en cola", .english: "No songs in queue"],
            "queue.emptyQueueMessage": [.spanish: "Las próximas canciones aparecerán aquí", .english: "Upcoming songs will appear here"],
            "queue.upNext": [.spanish: "A continuación", .english: "Up Next"],
            "queue.remove": [.spanish: "Eliminar", .english: "Remove"],
            "queue.historyTitle": [.spanish: "Historial de reproducción", .english: "Playback History"],

            // Lyrics
            "lyrics.noLyrics": [.spanish: "No hay letras disponibles", .english: "No lyrics available"],
            "lyrics.noLyricsSubtitle": [.spanish: "Esta canción no tiene información de letras en su metadata.", .english: "This song has no lyrics information in its metadata."],

            // Album/Artist Details
            "details.songs": [.spanish: "Canciones", .english: "Songs"],
            "details.albums": [.spanish: "Álbumes", .english: "Albums"],
            "details.play": [.spanish: "Reproducir", .english: "Play"],
            "details.shuffle": [.spanish: "Aleatorio", .english: "Shuffle"],
            "details.disc": [.spanish: "Disco", .english: "Disc"],
            "details.unknownArtist": [.spanish: "Artista desconocido", .english: "Unknown Artist"],
            "details.unknownAlbum": [.spanish: "Álbum desconocido", .english: "Unknown Album"],
            "details.albumsStat": [.spanish: "álbumes", .english: "albums"],

            // Accessibility
            "accessibility.previousSong": [.spanish: "Canción anterior", .english: "Previous song"],
            "accessibility.nextSong": [.spanish: "Siguiente canción", .english: "Next song"],
            "accessibility.playPause": [.spanish: "Reproducir/Pausar", .english: "Play/Pause"],

            // Equalizer
            "equalizer.title": [.spanish: "Ecualizador", .english: "Equalizer"],
            "equalizer.bandTitle": [.spanish: "Ecualizador de 10 Bandas", .english: "10-Band Equalizer"],
            "equalizer.active": [.spanish: "Activo", .english: "Active"],
            "equalizer.disabled": [.spanish: "Desactivado", .english: "Disabled"],
            "equalizer.presets": [.spanish: "Presets", .english: "Presets"],
            "equalizer.frequencies": [.spanish: "Frecuencias", .english: "Frequencies"],

            // Otros / Others
            "folders": [.spanish: "carpetas", .english: "folders"],
            "songs": [.spanish: "canciones", .english: "songs"],
            "seconds": [.spanish: "s", .english: "s"],
            "search": [.spanish: "Buscar", .english: "Search"],
            "emptyLibrary": [.spanish: "Biblioteca vacía", .english: "Empty Library"],
            "emptyLibrarySubtitle": [.spanish: "Añade carpetas de música para comenzar", .english: "Add music folders to get started"],
        ]

        if let langStrings = strings[key], let translation = langStrings[currentLanguage] {
            return translation
        }
        return key
    }
}
