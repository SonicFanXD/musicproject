package com.aurora.player.adapters

import android.net.Uri
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.ImageButton
import android.widget.ImageView
import android.widget.TextView
import androidx.recyclerview.widget.DiffUtil
import androidx.recyclerview.widget.ListAdapter
import androidx.recyclerview.widget.RecyclerView
import coil.load
import com.aurora.player.R
import com.aurora.player.models.Song

class SongAdapter(
    private val onPlay: (Song) -> Unit,
    private val onLike: (Song) -> Unit,
    private val onMore: (Song, View) -> Unit
) : ListAdapter<Song, SongAdapter.VH>(DIFF) {

    companion object {
        val DIFF = object : DiffUtil.ItemCallback<Song>() {
            override fun areItemsTheSame(a: Song, b: Song) = a.id == b.id
            override fun areContentsTheSame(a: Song, b: Song) = a == b
        }
    }

    inner class VH(v: View) : RecyclerView.ViewHolder(v) {
        val art: ImageView = v.findViewById(R.id.songArtwork)
        val title: TextView = v.findViewById(R.id.songTitle)
        val sub: TextView = v.findViewById(R.id.songSubtitle)
        val dur: TextView = v.findViewById(R.id.songDuration)
        val like: ImageButton = v.findViewById(R.id.songLike)
        val more: ImageButton = v.findViewById(R.id.songMore)
    }

    override fun onCreateViewHolder(p: ViewGroup, t: Int): VH {
        val v = LayoutInflater.from(p.context).inflate(R.layout.item_song, p, false)
        return VH(v)
    }

    override fun onBindViewHolder(h: VH, pos: Int) {
        val s = getItem(pos)
        h.title.text = s.title
        h.sub.text = if (s.artist.isEmpty()) s.album else "${s.artist} · ${s.album}"
        h.dur.text = s.formattedDuration()
        if (s.artworkUri != null) h.art.load(Uri.parse(s.artworkUri)) {
            placeholder(R.drawable.ic_music_note); error(R.drawable.ic_music_note)
        } else h.art.setImageResource(R.drawable.ic_music_note)
        h.like.setImageResource(if (s.isLiked) R.drawable.ic_favorite else R.drawable.ic_favorite_border)
        h.like.contentDescription = h.itemView.context.getString(
            if (s.isLiked) R.string.action_unlike else R.string.action_like)
        h.itemView.setOnClickListener { onPlay(s) }
        h.like.setOnClickListener { onLike(s) }
        h.more.setOnClickListener { onMore(s, h.more) }
    }
}
