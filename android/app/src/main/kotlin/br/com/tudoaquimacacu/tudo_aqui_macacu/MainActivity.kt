package br.com.tudoaquimacacu.tudo_aqui_macacu

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "macacu/local-isolation")
            .setMethodCallHandler { call, result ->
                if (call.method == "environment") {
                    val local = packageName.endsWith(".searchlocal")
                    val staging = packageName.endsWith(".staging")
                    val isolated = if (local) Class.forName("br.com.tudoaquimacacu.tudo_aqui_macacu.SearchLocalVpnService")
                        .getMethod("isIsolated").invoke(null) as Boolean else false
                    val expectedProject = if (staging) {
                        applicationInfo.metaData?.getString("macacu.stagingFirebaseProjectId")
                    } else null
                    result.success(mapOf("local" to local, "staging" to staging,
                        "isolated" to isolated, "package" to packageName,
                        "expectedProject" to expectedProject))
                } else result.notImplemented()
            }
    }
}
