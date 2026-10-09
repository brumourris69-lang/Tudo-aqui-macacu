package br.com.tudoaquimacacu.tudo_aqui_macacu

import android.app.Application

/** Firebase init providers are removed; no Flutter engine before the VPN gate. */
class SearchLocalApplication : Application() {
    override fun onCreate() {
        check(packageName == "br.com.tudoaquimacacu.tudo_aqui_macacu.searchlocal")
        super.onCreate()
    }
}
