package com.example.market_radar

import android.content.pm.ApplicationInfo
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterShellArgs

class MainActivity : FlutterActivity() {
    override fun getFlutterShellArgs(): FlutterShellArgs =
        super.getFlutterShellArgs().also { args ->
            if (applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0) {
                args.add(FlutterShellArgs.ARG_ENABLE_SOFTWARE_RENDERING)
            }
        }
}
