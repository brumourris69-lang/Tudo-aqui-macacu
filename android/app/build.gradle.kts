import java.security.KeyStore
import java.security.MessageDigest
import java.util.Base64
import groovy.json.JsonSlurper

plugins {
    id("com.android.application")
    id("com.google.gms.google-services")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Preserve unflavored production builds and their existing artifact names.
val searchLocalRequested = gradle.startParameter.taskNames.any {
    it.contains("SearchLocal", ignoreCase = true)
} || providers.gradleProperty("search-local").orNull == "true"

// Credentials are supplied only by a trusted, explicitly authorized release job.
// Debug never loads key.properties or consumes a production signing key.
val releaseStore = providers.environmentVariable("ANDROID_RELEASE_STORE_FILE").orNull
val releaseStorePassword = providers.environmentVariable("ANDROID_RELEASE_STORE_PASSWORD").orNull
val releaseAlias = providers.environmentVariable("ANDROID_RELEASE_KEY_ALIAS").orNull
val releaseKeyPassword = providers.environmentVariable("ANDROID_RELEASE_KEY_PASSWORD").orNull
val releaseFingerprint = providers.environmentVariable("ANDROID_RELEASE_CERT_SHA256").orNull

fun verifyReleaseAuthorization() {
    check(providers.environmentVariable("ANDROID_RELEASE_AUTHORIZED").orNull == "true") {
        "Release não autorizada: ANDROID_RELEASE_AUTHORIZED deve ser true em ambiente confiável."
    }
    check(!searchLocalRequested) { "Release proibida para searchLocal." }
    val defines = (findProperty("dart-defines") as? String).orEmpty().split(",").filter { it.isNotEmpty() }
        .map { String(Base64.getDecoder().decode(it), Charsets.UTF_8) }
    check(defines.none { it.substringBefore("=").startsWith("LOCAL_SEARCH_") }) {
        "Release não aceita flags LOCAL_SEARCH_."
    }
    check(listOf(releaseStore, releaseStorePassword, releaseAlias, releaseKeyPassword, releaseFingerprint)
        .all { !it.isNullOrBlank() }) {
        "Release exige credenciais ANDROID_RELEASE_* e certificado SHA-256 autorizado; sem fallback debug."
    }
    val expected = releaseFingerprint!!.replace(":", "").uppercase()
    check(expected.matches(Regex("[0-9A-F]{64}"))) { "Certificado release autorizado inválido." }
    val store = file(releaseStore!!)
    check(store.isFile && !store.name.equals("debug.keystore", true) && !releaseAlias.equals("androiddebugkey", true)) {
        "Keystore release ausente ou identidade debug recusada."
    }
    try {
        val keys = KeyStore.getInstance(store, releaseStorePassword!!.toCharArray())
        check(keys.isKeyEntry(releaseAlias) && keys.getKey(releaseAlias, releaseKeyPassword!!.toCharArray()) != null)
        val certificate = keys.getCertificate(releaseAlias) as java.security.cert.X509Certificate
        certificate.checkValidity()
        check(!certificate.subjectX500Principal.name.contains("Android Debug", true))
        val actual = MessageDigest.getInstance("SHA-256").digest(certificate.encoded)
            .joinToString("") { "%02X".format(it) }
        check(actual == expected)
    } catch (_: Exception) {
        throw GradleException("Assinatura release recusada: credenciais/certificado não autorizados ou inválidos.")
    }
    val config = file("google-services.json")
    check(config.isFile) { "Release exige configuração Firebase oficial." }
    val json = JsonSlurper().parse(config) as Map<*, *>
    check((json["project_info"] as? Map<*, *>)?.get("project_id") == "tudo-aqui-macacu") {
        "Release exige o projeto Firebase oficial; configuração demo recusada."
    }
    val clients = json["client"] as? List<*> ?: emptyList<Any>()
    check(clients.any {
        val info = (it as? Map<*, *>)?.get("client_info") as? Map<*, *>
        (info?.get("android_client_info") as? Map<*, *>)?.get("package_name") ==
            "br.com.tudoaquimacacu.tudo_aqui_macacu"
    }) { "Configuração Firebase não corresponde ao aplicativo oficial." }
}

android {
    namespace = "br.com.tudoaquimacacu.tudo_aqui_macacu"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "br.com.tudoaquimacacu.tudo_aqui_macacu"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("authorizedRelease") {
            storeFile = releaseStore?.let { file(it) }
            storePassword = releaseStorePassword
            keyAlias = releaseAlias
            keyPassword = releaseKeyPassword
        }
    }
    buildTypes {
        debug {
            signingConfig = signingConfigs.getByName("debug")
        }
        release {
            isDebuggable = false
            signingConfig = signingConfigs.getByName("authorizedRelease")
        }
    }

    if (searchLocalRequested) {
        flavorDimensions += "environment"
        productFlavors {
            create("searchLocal") {
                dimension = "environment"
                applicationIdSuffix = ".searchlocal"
                versionNameSuffix = "-local"
            }
        }
    }
}

tasks.register("verifyReleaseConfiguration") {
    group = "verification"
    description = "Valida autorização release sem compilar ou assinar um artefato."
    doLast { verifyReleaseAuthorization() }
}
// Also covers aggregate tasks (build/assemble), rather than just CLI task names.
gradle.taskGraph.whenReady {
    if (allTasks.any { it.project == project && it.name.contains("Release", ignoreCase = true) &&
            it.name != "verifyReleaseConfiguration" }) {
        verifyReleaseAuthorization()
    }
}

// A local variant has no google-services.json and must never consume the root
// production configuration. Firebase is initialized explicitly with demo IDs.
tasks.configureEach {
    if (name.contains("SearchLocal") && name.endsWith("GoogleServices")) enabled = false
}
if (searchLocalRequested) {
    androidComponents {
        beforeVariants(selector().withFlavor("environment" to "searchLocal")) {
            if (it.buildType != "debug") it.enable = false
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
