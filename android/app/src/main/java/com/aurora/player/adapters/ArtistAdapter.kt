package com.aurora.player.adapters

import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.ImageView
import android.widget.TextView
import androidx.recyclerview.widget.DiffUtil
import androidx.recyclerview.widget.ListAdapter
import androidx.recyclerview.widget.RecyclerView
import com.aurora.player.R
import com.aurora.player.models.Artist

class ArtistAdapter(
    private val onOpen: (Artist) -> Unit
) : ListAdapter<Artist, ArtistAdapter.VH>(DIFF) {
    companion object {
        val DIFF = object : DiffUtil.ItemCallback<Artist>() {
            override fun areItemsTheSame(a: Artist, b: Artist) = a.id == b.id
            override fun areContentsTheSame(a: Artist, b: Artist) = a == b
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
        h.title.text = a.name
        h.sub.text = "${a.albumCount} albums · ${a.songCount} songs"
        h.dur.text = ""
        h.art.setImageResource(R.drawable.ic_music_note)
        h.itemView.setOnClickListener { onOpen(a) }
    }
}
