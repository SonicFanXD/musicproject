package com.aurora.player.viewmodels

import android.app.Application
import android.content.SharedPreferences
import androidx.core.content.edit
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.LiveData
import androidx.lifecycle.MutableLiveData
import androidx.lifecycle.Transformations
import com.aurora.player.models.*
import com.aurora.player.services.AudioEngine
import com.aurora.player.services.FileAccessService

class LibraryViewModel(app: Application) : AndroidViewModel(app) {

    // ✅ Singleton compartido: MainActivity y NowPlayingActivity deben usar
    // la MISMA instancia de AudioEngine para que los controles estén
    // sincronizados. Sin esto, cada Activity crearía su propio ExoPlayer.
    companion object {
        @Volatile private var sharedAudioEngine: AudioEngine? = null
        @Volatile private var sharedFileAccess: FileAccessService? = null
        fun sharedAudio(app: Application): AudioEngine {
            return sharedAudioEngine ?: synchronized(this) {
                sharedAudioEngine ?: AudioEngine(app.applicationContext).also { sharedAudioEngine = it }
            }
        }
        fun sharedFiles(app: Application): FileAccessService {
            return sharedFileAccess ?: synchronized(this) {
                sharedFileAccess ?: FileAccessService(app.applicationContext).also { sharedFileAccess = it }
            }
        }
    }

    val fileAccess: FileAccessService = sharedFiles(app)
    val audioEngine: AudioEngine = sharedAudio(app)

    val songs: LiveData<List<Song>> = fileAccess.songs
    val isScanning = fileAccess.isScanning
    val scanProcessed = fileAccess.scanProcessed
    val scanTotal = fileAccess.scanTotal
    val playlists = fileAccess.playlists
    private val prefs: SharedPreferences =
        app.getSharedPreferences("aurora_ui", Application.MODE_PRIVATE)

    private val _category = MutableLiveData(LibraryCategory.SONGS)
    val category: LiveData<LibraryCategory> = _category
    private val _query = MutableLiveData("")
    val query: LiveData<String> = _query
    private val _sort = MutableLiveData(
        try { SortOption.valueOf(prefs.getString("sort", "TITLE") ?: "TITLE") }
        catch (e: Exception) { SortOption.TITLE }
    )
    val sort: LiveData<SortOption> = _sort
    private val _ascending = MutableLiveData(prefs.getBoolean("ascending", true))
    val ascending: LiveData<Boolean> = _ascending

    val albums: LiveData<List<Album>> = Transformations.map(songs) { list ->
        list.groupBy { "${it.album}|${it.preferredArtist}" }.map { (k, v) ->
            Album(k, v.firstOrNull()?.album ?: "Unknown", v.firstOrNull()?.preferredArtist ?: "", 0, null, v)
        }.sortedBy { it.title.lowercase() }
    }

    val artists: LiveData<List<Artist>> = Transformations.map(songs) { list ->
        list.groupBy { it.preferredArtist.ifEmpty { "Unknown" } }.map { (name, v) ->
            Artist(name, name, null, emptyList(), v)
        }.sortedBy { it.name.lowercase() }
    }

    fun setCategory(c: LibraryCategory) { _category.value = c }
    fun setQuery(q: String) { _query.value = q }
    fun setSort(s: SortOption) {
        _sort.value = s
        prefs.edit { putString("sort", s.name) }
    }
    fun toggleOrder() {
        val v = !(_ascending.value ?: true)
        _ascending.value = v
        prefs.edit { putBoolean("ascending", v) }
    }

    fun filteredSongs(): List<Song> {
        var list = songs.value.orEmpty()
        val q = _query.value.orEmpty().trim().lowercase()
        if (q.isNotEmpty()) list = list.filter {
            it.title.lowercase().contains(q) || it.artist.lowercase().contains(q) || it.album.lowercase().contains(q)
        }
        val asc = _ascending.value ?: true
        list = when (_sort.value ?: SortOption.TITLE) {
            SortOption.TITLE -> list.sortedBy { it.title.lowercase() }
            SortOption.ARTIST -> list.sortedBy { it.preferredArtist.lowercase() }
            SortOption.ALBUM -> list.sortedBy { it.album.lowercase() }
            SortOption.DURATION -> list.sortedBy { it.duration }
            SortOption.DATE_ADDED -> list
        }
        return if (asc) list else list.reversed()
    }

    fun filteredAlbums(): List<Album> {
        var list = albums.value.orEmpty()
        val q = _query.value.orEmpty().trim().lowercase()
        if (q.isNotEmpty()) list = list.filter {
            it.title.lowercase().contains(q) || it.artist.lowercase().contains(q)
        }
        return list.sortedBy { it.title.lowercase() }
    }

    fun filteredArtists(): List<Artist> {
        var list = artists.value.orEmpty()
        val q = _query.value.orEmpty().trim().lowercase()
        if (q.isNotEmpty()) list = list.filter { it.name.lowercase().contains(q) }
        return list.sortedBy { it.name.lowercase() }
    }

    fun filteredPlaylists(): List<Playlist> {
        var list = playlists.value.orEmpty()
        // Playlist virtual "Me Gusta" como en iOS
        val liked = songs.value.orEmpty().filter { it.isLiked }
        val likedPlaylist = Playlist(id = "liked", name = "Me Gusta",
            songIds = liked.map { it.id })
        val all = listOf(likedPlaylist) + list
        val q = _query.value.orEmpty().trim().lowercase()
        if (q.isNotEmpty()) return all.filter { it.name.lowercase().contains(q) }
        return all
    }

    fun songsForAlbum(album: Album): List<Song> = album.songs

    fun songsForArtist(artist: Artist): List<Song> =
        songs.value.orEmpty().filter { it.preferredArtist == artist.name }
            .sortedWith(compareBy({ it.album.lowercase() }, { it.trackNumber }))

    fun songsForPlaylist(playlist: Playlist): List<Song> {
        if (playlist.id == "liked") return songs.value.orEmpty().filter { it.isLiked }
        val map = songs.value.orEmpty().associateBy { it.id }
        return playlist.songIds.mapNotNull { map[it] }
    }

    fun play(song: Song) {
        val list = filteredSongs()
        audioEngine.play(song, list.ifEmpty { songs.value.orEmpty() })
    }
    fun playNext(song: Song) = audioEngine.playNext(song)
    fun refresh() = fileAccess.refreshAllFolders()
    fun toggleLike(s: Song) = fileAccess.toggleLike(s)
}

