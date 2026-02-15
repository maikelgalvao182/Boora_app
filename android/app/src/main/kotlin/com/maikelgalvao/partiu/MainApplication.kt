package com.maikelgalvao.partiu

import android.app.Application
import android.util.Log
import com.tiktok.TikTokBusinessSdk

class MainApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        initializeTikTokSdk()
    }

    private fun initializeTikTokSdk() {
        if (TikTokBusinessSdk.isInitialized()) {
            return
        }

        val appId = BuildConfig.TIKTOK_APP_ID
        val appSecret = BuildConfig.TIKTOK_APP_SECRET

        if (appId.isBlank() || appSecret.isBlank()) {
            Log.w("MainApplication", "TikTok SDK não inicializado: configure tiktok.app.id e tiktok.app.secret no android/local.properties")
            return
        }

        val config = TikTokBusinessSdk.TTConfig(this, appSecret)
            .setAppId(appId)
            .setTTAppId(appId)
            .setLogLevel(TikTokBusinessSdk.LogLevel.NONE)

        TikTokBusinessSdk.initializeSdk(config)
        TikTokBusinessSdk.registerEDPLifecycleCallback(this)
    }
}
