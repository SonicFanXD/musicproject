package com.aurora.player

import android.app.Application
import com.aurora.player.services.ThemeManager
import com.google.android.gms.cast.framework.CastContext

class AuroraPlayerApp : Application() {
    override fun onCreate() {
        super.onCreate()
        // ✅ Tema claro/oscuro: aplicar el modo guardado ANTES de que se
        // infle la primera Activity (equivale a preferredColorScheme en iOS).
        ThemeManager.getInstance(this).applySavedThemeMode()
        try { CastContext.getSharedInstance(this) } catch (e: Exception) { }
    }
}
