package com.aurora.player.adapters

import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.ImageView
import android.widget.TextView
import androidx.recyclerview.widget.DiffUtil
import androidx.recyclerview.widget.ListAdapter
import androidx.recyclerview.widget.RecyclerView
import coil.load
import com.aurora.player.R
import com.aurora.player.models.Album

class AlbumAdapter(
    private val onOpen: (Album) -> Unit
) : ListAdapter<Album, AlbumAdapter.VH>(DIFF) {
    companion object {
        val DIFF = object : DiffUtil.ItemCallback<Album>() {
            override fun areItemsTheSame(a: Album, b: Album) = a.id == b.id
            override fun areContentsTheSame(a: Album, b: Album) = a == b
        }
    }
    inner class VH(v: View) : RecyclerView.ViewHolder(v) {
        val art: ImageView = v.findViewById(R.id.albumArtwork)
        val title: TextView = v.findViewById(R.id.albumTitle)
        val sub: TextView = v.findViewById(R.id.albumSubtitle)
        val dur: TextView = v.findViewById(R.id.albumDuration)
    }
    override fun onCreateViewHolder(p: ViewGroup, t: Int): VH {
        return VH(LayoutInflater.from(p.context).inflate(R.layout.item_album, p, false))
    }
    override fun onBindViewHolder(h: VH, pos: Int) {
        val a = getItem(pos)
        h.title.text = a.title
        h.sub.text = "${a.artist} · ${a.songCount} songs"
        h.dur.text = a.formattedDuration()
        if (a.artworkUri != null) h.art.load(a.artworkUri) {
            placeholder(R.drawable.ic_music_note); error(R.drawable.ic_music_note)
        } else h.art.setImageResource(R.drawable.ic_music_note)
        h.itemView.setOnClickListener { onOpen(a) }
    }
}
