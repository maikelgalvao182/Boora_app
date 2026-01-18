package com.maikelgalvao.partiu

import android.content.pm.PackageManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
	private val channel = "com.example.partiu/google_maps"

	override fun onNewIntent(intent: android.content.Intent) {
		super.onNewIntent(intent)
		// Necessário para deep links quando launchMode != standard (singleTop)
		setIntent(intent)
	}

	override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
		super.configureFlutterEngine(flutterEngine)

		MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channel).setMethodCallHandler { call, result ->
			when (call.method) {
				"getManifestApiKey" -> {
					try {
						val appInfo = applicationContext.packageManager.getApplicationInfo(
							applicationContext.packageName,
							PackageManager.GET_META_DATA
						)

						val apiKey = appInfo.metaData?.getString("com.google.android.geo.API_KEY")
						result.success(apiKey)
					} catch (e: Exception) {
						result.error("MANIFEST_API_KEY_ERROR", e.message, null)
					}
				}

				// Compat: o Dart chama setApiKey, mas no Android a chave vem do Manifest.
				"setApiKey" -> {
					result.success("ok")
				}

				else -> result.notImplemented()
			}
		}
	}
}
