package com.aurora.player.views

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.view.View
import android.widget.PopupMenu
import android.widget.SeekBar
import androidx.activity.viewModels
import androidx.appcompat.app.AppCompatActivity
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.recyclerview.widget.LinearLayoutManager
import coil.load
import com.aurora.player.R
import com.aurora.player.adapters.AlbumAdapter
import com.aurora.player.adapters.ArtistAdapter
import com.aurora.player.adapters.PlaylistAdapter
import com.aurora.player.adapters.SongAdapter
import com.aurora.player.databinding.ActivityMainBinding
import com.aurora.player.models.Album
import com.aurora.player.models.Artist
import com.aurora.player.models.LibraryCategory
import com.aurora.player.models.Playlist
import com.aurora.player.models.Song
import com.aurora.player.viewmodels.LibraryViewModel
import com.google.android.material.tabs.TabLayout

class MainActivity : AppCompatActivity() {
    private lateinit var binding: ActivityMainBinding
    private val vm: LibraryViewModel by viewModels()
    private lateinit var songAdapter: SongAdapter
    private lateinit var albumAdapter: AlbumAdapter
    private lateinit var artistAdapter: ArtistAdapter
    private lateinit var playlistAdapter: PlaylistAdapter
    private var scrubbing = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityMainBinding.inflate(layoutInflater)
        setContentView(binding.root)
        setSupportActionBar(binding.toolbar)
        requestAudioPermission()
        setupTabs()
        setupAdapters()
        setupSearch()
        setupPlayerBar()
        observe()
        vm.refresh()
    }

    private fun requestAudioPermission() {
        val perm = if (Build.VERSION.SDK_INT >= 33) Manifest.permission.READ_MEDIA_AUDIO
        else Manifest.permission.READ_EXTERNAL_STORAGE
        if (ContextCompat.checkSelfPermission(this, perm) != PackageManager.PERMISSION_GRANTED) {
            ActivityCompat.requestPermissions(this, arrayOf(perm), 100)
        }
    }

    override fun onRequestPermissionsResult(rc: Int, p: Array<out String>, r: IntArray) {
        super.onRequestPermissionsResult(rc, p, r)
        if (rc == 100 && r.firstOrNull() == PackageManager.PERMISSION_GRANTED) vm.refresh()
    }

    private fun setupTabs() {
        LibraryCategory.entries.forEach {
            binding.categoryTabs.addTab(binding.categoryTabs.newTab().setText(it.displayName))
        }
        binding.categoryTabs.addOnTabSelectedListener(object : TabLayout.OnTabSelectedListener {
            override fun onTabSelected(t: TabLayout.Tab) {
                vm.setCategory(LibraryCategory.entries[t.position]); refreshList()
            }
            override fun onTabUnselected(t: TabLayout.Tab) {}
            override fun onTabReselected(t: TabLayout.Tab) { refreshList() }
        })
    }

    private fun setupAdapters() {
        binding.recyclerSongs.layoutManager = LinearLayoutManager(this)
        songAdapter = SongAdapter({ vm.play(it) }, { vm.toggleLike(it); refreshList() },
            { song, anchor -> showSongMenu(song, anchor) })
        albumAdapter = AlbumAdapter({ /* TODO detalle álbum */ })
        artistAdapter = ArtistAdapter({ /* TODO detalle artista */ })
        playlistAdapter = PlaylistAdapter({ /* TODO detalle playlist */ })
        binding.recyclerSongs.adapter = songAdapter
    }

    private fun showSongMenu(song: Song, anchor: View) {
        val popup = PopupMenu(this, anchor)
        popup.menu.add(getString(R.string.action_play_now)).setOnMenuItemClickListener { vm.play(song); true }
        val likeTitle = if (song.isLiked) getString(R.string.action_unlike) else getString(R.string.action_like)
        popup.menu.add(likeTitle).setOnMenuItemClickListener { vm.toggleLike(song); refreshList(); true }
        popup.menu.add(getString(R.string.action_play_next)).setOnMenuItemClickListener {
            vm.playNext(song); true
        }
        popup.show()
    }
private fun setupSearch() {
        binding.searchView.setOnQueryTextListener(object : androidx.appcompat.widget.SearchView.OnQueryTextListener {
            override fun onQueryTextSubmit(q: String?) = false
            override fun onQueryTextChange(q: String?): Boolean {
                vm.setQuery(q.orEmpty()); refreshList(); return true
            }
        })
    }

    private fun setupPlayerBar() {
        val bar = binding.includedPlayerBarRoot
        bar.barToggle.setOnClickListener { vm.audioEngine.togglePlayPause() }
        bar.barProgress.setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
            override fun onProgressChanged(s: SeekBar?, p: Int, fromUser: Boolean) {}
            override fun onStartTrackingTouch(s: SeekBar?) { scrubbing = true }
            override fun onStopTrackingTouch(s: SeekBar?) {
                scrubbing = false
                val dur = vm.audioEngine.duration.value ?: 0L
                vm.audioEngine.seekTo(((s?.progress ?: 0) / 1000f * dur).toLong())
            }
        })
        bar.setOnClickListener { startActivity(Intent(this, NowPlayingActivity::class.java)) }
    }

    private fun observe() {
        val bar = binding.includedPlayerBarRoot
        vm.songs.observe(this) { refreshList() }
        vm.audioEngine.currentSong.observe(this) { song ->
            bar.barTitle.text = song?.title ?: ""
            bar.barArtist.text = song?.artist ?: ""
            if (song?.artworkUri != null) bar.barArtwork.load(song.artworkUri)
            else bar.barArtwork.setImageResource(R.drawable.ic_music_note)
            bar.visibility = if (song == null) View.GONE else View.VISIBLE
        }
        vm.audioEngine.isPlaying.observe(this) { playing ->
            bar.barToggle.setImageResource(
                if (playing == true) R.drawable.ic_pause else R.drawable.ic_play)
        }
        vm.audioEngine.currentTime.observe(this) { pos ->
            if (!scrubbing) {
                val dur = vm.audioEngine.duration.value ?: 0L
                bar.barProgress.progress = if (dur > 0) (pos * 1000L / dur).toInt() else 0
            }
        }
    }

    private fun refreshList() {
        switch (vm.category.value) {
            LibraryCategory.SONGS -> songAdapter.submitList(vm.filteredSongs())
            LibraryCategory.ALBUMS -> albumAdapter.submitList(vm.filteredAlbums())
            LibraryCategory.ARTISTS -> artistAdapter.submitList(vm.filteredArtists())
            LibraryCategory.PLAYLISTS -> playlistAdapter.submitList(vm.filteredPlaylists())
        }
        binding.recyclerSongs.adapter = switch (vm.category.value) {
            LibraryCategory.ALBUMS -> albumAdapter
            LibraryCategory.ARTISTS -> artistAdapter
            LibraryCategory.PLAYLISTS -> playlistAdapter
            else -> songAdapter
        }
    }

    override fun onCreateOptionsMenu(menu: android.view.Menu): Boolean {
        menuInflater.inflate(R.menu.menu_main, menu)
        return true
    }

    override fun onOptionsItemSelected(item: android.view.MenuItem): Boolean {
        return when (item.itemId) {
            R.id.action_settings -> {
                startActivity(Intent(this, SettingsActivity::class.java)); true
            }
            R.id.action_refresh -> { vm.refresh(); true }
            else -> super.onOptionsItemSelected(item)
        }
    }
}