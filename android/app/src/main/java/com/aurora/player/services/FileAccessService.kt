package com.aurora.player.services

import android.content.Context
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.provider.MediaStore
import androidx.lifecycle.LiveData
import androidx.lifecycle.MutableLiveData
import com.aurora.player.models.MusicFolder
import com.aurora.player.models.Playlist
import com.aurora.player.models.Song
import com.google.gson.Gson
import com.google.gson.reflect.TypeToken
import kotlinx.coroutines.*
import java.io.File

class FileAccessService(private val context: Context) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val gson = Gson()
    private val _songs = MutableLiveData<List<Song>>(emptyList())
    val songs: LiveData<List<Song>> = _songs
    private val _folders = MutableLiveData<List<MusicFolder>>(emptyList())
    val folders: LiveData<List<MusicFolder>> = _folders
    private val _playlists = MutableLiveData<List<Playlist>>(emptyList())
    val playlists: LiveData<List<Playlist>> = _playlists
    private val _isScanning = MutableLiveData(false)
    val isScanning: LiveData<Boolean> = _isScanning
    private val _scanProcessed = MutableLiveData(0)
    val scanProcessed: LiveData<Int> = _scanProcessed
    private val _scanTotal = MutableLiveData(0)
    val scanTotal: LiveData<Int> = _scanTotal
    private val likedIds = mutableSetOf<String>()
    private val cacheFile: File get() = File(context.filesDir, "library-metadata-v1.json")
    private val prefs by lazy { context.getSharedPreferences("aurora_library", Context.MODE_PRIVATE) }

    init { loadCache(); loadPlaylists() }

    fun refreshAllFolders() {
        if (_isScanning.value == true) return
        Logger.info("library", "Escaneando biblioteca…")
        scope.launch {
            withContext(Dispatchers.Main) { _isScanning.value = true; _scanProcessed.value = 0 }
            val found = scanMediaStore()
            withContext(Dispatchers.Main) {
                _songs.value = found.sortedBy { it.title.lowercase() }
                _isScanning.value = false
            }
            try { cacheFile.writeText(gson.toJson(found)) } catch (e: Exception) { }
        }
    }

    private fun scanMediaStore(): List<Song> {
        val result = mutableListOf<Song>()
        val collection = if (android.os.Build.VERSION.SDK_INT >= 29) {
            MediaStore.Audio.Media.getContentUri(MediaStore.VOLUME_EXTERNAL)
        } else {
            MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
        }
        val projection = arrayOf(
            MediaStore.Audio.Media._ID, MediaStore.Audio.Media.TITLE,
            MediaStore.Audio.Media.ARTIST, MediaStore.Audio.Media.ALBUM,
            MediaStore.Audio.Media.DURATION, MediaStore.Audio.Media.TRACK,
            MediaStore.Audio.Media.YEAR, MediaStore.Audio.Media.DATA
        )
        val selection = "${MediaStore.Audio.Media.IS_MUSIC} != 0"
        try {
            context.contentResolver.query(collection, projection, selection, null,
                "${MediaStore.Audio.Media.TITLE} ASC")?.use { cursor ->
                val idCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media._ID)
                val titleCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.TITLE)
                val artistCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.ARTIST)
                val albumCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.ALBUM)
                val durCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DURATION)
                val trackCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.TRACK)
                val yearCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.YEAR)
                val pathCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DATA)
                _scanTotal.postValue(cursor.count)
                var processed = 0
                while (cursor.moveToNext()) {
                    val id = cursor.getLong(idCol)
                    val uri = Uri.withAppendedPath(collection, id.toString()).toString()
                    result.add(Song(id.toString(),
                        cursor.getString(titleCol) ?: "Unknown",
                        cursor.getString(artistCol) ?: "",
                        cursor.getString(albumCol) ?: "", "",
                        cursor.getLong(durCol), cursor.getInt(trackCol),
                        cursor.getInt(yearCol), uri, null, "",
                        isLiked = likedIds.contains(id.toString()),
                        filePath = cursor.getString(pathCol) ?: ""))
                    processed++
                    if (processed % 20 == 0) _scanProcessed.postValue(processed)
                }
                _scanProcessed.postValue(processed)
            }
        } catch (e: Exception) { }
        return result
    }
    fun extractArtworkBytes(audioUriString: String): ByteArray? {
        return try {
            val mmr = MediaMetadataRetriever()
            mmr.setDataSource(context, Uri.parse(audioUriString))
            val art = mmr.embeddedPicture
            mmr.release()
            art
        } catch (e: Exception) { null }
    }

    /** Busca un archivo .lrc junto al audio (letras sincronizadas, como iOS). */
    fun findLyricsFile(song: Song): File? {
        if (song.filePath.isBlank()) return null
        val base = song.filePath.substringBeforeLast('.', song.filePath)
        val lrc = File("$base.lrc")
        return if (lrc.exists()) lrc else null
    }

    fun toggleLike(song: Song) {
        if (likedIds.contains(song.id)) likedIds.remove(song.id) else likedIds.add(song.id)
        prefs.edit().putStringSet("liked", likedIds).apply()
        _songs.value = _songs.value.orEmpty().map {
            if (it.id == song.id) it.copy(isLiked = likedIds.contains(it.id)) else it
        }
    }

    fun isLiked(songId: String): Boolean = likedIds.contains(songId)

    fun createPlaylist(name: String) {
        val list = _playlists.value.orEmpty().toMutableList()
        list.add(Playlist(id = java.util.UUID.randomUUID().toString(), name = name))
        _playlists.value = list
        prefs.edit().putString("playlists", gson.toJson(list)).apply()
    }

    fun addSongToPlaylist(song: Song, playlist: Playlist) {
        val list = _playlists.value.orEmpty().map {
            if (it.id == playlist.id) it.copy(songIds = it.songIds + song.id) else it
        }
        _playlists.value = list
        prefs.edit().putString("playlists", gson.toJson(list)).apply()
    }

    private fun loadPlaylists() {
        try {
            likedIds.addAll(prefs.getStringSet("liked", emptySet()).orEmpty())
            val json = prefs.getString("playlists", null) ?: run {
                _playlists.value = emptyList()
                return
            }
            val type = object : TypeToken<List<Playlist>>() {}.type
            _playlists.value = gson.fromJson(json, type) ?: emptyList()
        } catch (e: Exception) { }
    }

    private fun loadCache() {
        scope.launch {
            try {
                if (!cacheFile.exists()) return@launch
                val type = object : TypeToken<List<Song>>() {}.type
                val cached: List<Song> = gson.fromJson(cacheFile.readText(), type) ?: return@launch
                withContext(Dispatchers.Main) { _songs.value = cached }
            } catch (e: Exception) { }
        }
    }

    fun songById(id: String): Song? = _songs.value?.firstOrNull { it.id == id }
}
