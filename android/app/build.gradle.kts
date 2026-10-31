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
val preBetaLocalRequested = gradle.startParameter.taskNames.any {
    it.contains("PreBetaLocal", ignoreCase = true)
} || providers.gradleProperty("prebeta-local").orNull == "true"
val sparkLocalRequested = gradle.startParameter.taskNames.any {
    it.contains("SparkLocal", ignoreCase = true)
} || providers.gradleProperty("spark-local").orNull == "true"
val stagingRequested = gradle.startParameter.taskNames.any {
    it.contains("Staging", ignoreCase = true)
} || providers.gradleProperty("staging").orNull == "true"
val betaRequested = gradle.startParameter.taskNames.any {
    it.contains("Beta", ignoreCase = true) &&
        !it.contains("PreBetaLocal", ignoreCase = true)
} || providers.gradleProperty("beta").orNull == "true"
val supabasePilotRequested = gradle.startParameter.taskNames.any {
    it.contains("SupabasePilot", ignoreCase = true)
} || providers.gradleProperty("supabase-pilot").orNull == "true"
check(listOf(searchLocalRequested, preBetaLocalRequested, sparkLocalRequested, stagingRequested, betaRequested, supabasePilotRequested).count { it } <= 1) {
    "searchLocal, preBetaLocal, sparkLocal, staging, beta e supabasePilot são ambientes mutuamente exclusivos."
}
val stagingProjectId = providers.gradleProperty("STAGING_FIREBASE_PROJECT_ID")
    .orElse(providers.environmentVariable("STAGING_FIREBASE_PROJECT_ID")).orNull
val betaProjectId = providers.gradleProperty("BETA_FIREBASE_PROJECT_ID")
    .orElse(providers.environmentVariable("BETA_FIREBASE_PROJECT_ID")).orNull
val betaFirebaseConfig = file("src/beta/google-services.json")
val productionGoogleWebClientId = "801555679675-qvtghgv9sa65ipgls4usukru33uk3aec.apps.googleusercontent.com"

fun isIsolatedBetaProjectId(value: String): Boolean {
    val project = value.trim().lowercase()
    val forbiddenMarker = listOf(
        "tudo-aqui-macacu", "staging", "homolog", "production", "prod-", "demo-universal-search"
    ).any { project.contains(it) }
    val dedicatedBetaId = project.matches(Regex("^macacu-beta-[0-9]{6}-[a-f0-9]{6}$"))
    return !forbiddenMarker &&
        (dedicatedBetaId || project.endsWith("-beta") || project.endsWith("-testing")) &&
        project.matches(Regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$"))
}

fun verifyOptionalBetaProjectId() {
    val expected = betaProjectId?.trim().orEmpty()
    if (expected.isEmpty()) return
    check(isIsolatedBetaProjectId(expected)) {
        "BETA_FIREBASE_PROJECT_ID deve identificar um projeto isolado com sufixo -beta ou -testing."
    }
}

fun verifyBetaFirebaseConfiguration() {
    val expected = betaProjectId?.trim().orEmpty()
    check(isIsolatedBetaProjectId(expected)) {
        "BETA_FIREBASE_PROJECT_ID deve identificar um projeto isolado com sufixo -beta ou -testing."
    }
    check(betaFirebaseConfig.isFile) {
        "Beta conectado exige android/app/src/beta/google-services.json; não há fallback para produção."
    }
    val json = JsonSlurper().parse(betaFirebaseConfig) as Map<*, *>
    check((json["project_info"] as? Map<*, *>)?.get("project_id") == expected) {
        "A configuração Firebase Beta não corresponde ao projeto isolado declarado."
    }
    val clients = json["client"] as? List<*> ?: emptyList<Any>()
    val betaClient = clients.firstOrNull { value ->
        val info = (value as? Map<*, *>)?.get("client_info") as? Map<*, *>
        (info?.get("android_client_info") as? Map<*, *>)?.get("package_name") ==
            "br.com.tudoaquimacacu.tudo_aqui_macacu.beta"
    } as? Map<*, *>
    check(betaClient != null) {
        "A configuração Firebase não contém o pacote Android Beta esperado."
    }
    val projectInfo = json["project_info"] as? Map<*, *>
    val projectNumber = projectInfo?.get("project_number")?.toString().orEmpty()
    val betaClientInfo = betaClient["client_info"] as? Map<*, *>
    val mobileAppId = betaClientInfo?.get("mobilesdk_app_id")?.toString().orEmpty()
    check(projectNumber.matches(Regex("^\\d{8,15}$")) &&
        mobileAppId.startsWith("1:$projectNumber:android:")) {
        "O app ID Firebase Beta não corresponde ao número do projeto declarado."
    }
    val oauthClients = betaClient["oauth_client"] as? List<*> ?: emptyList<Any>()
    check(oauthClients.any { value ->
        val oauth = value as? Map<*, *>
        oauth?.get("client_type")?.toString() == "3" &&
            (oauth["client_id"] as? String)
                ?.matches(Regex("^\\d+-[A-Za-z0-9_-]+\\.apps\\.googleusercontent\\.com$")) == true
    }) { "A configuração Beta não contém um cliente OAuth web válido." }
    check(oauthClients.none { value ->
        val oauth = value as? Map<*, *>
        oauth?.get("client_type")?.toString() == "3" &&
            oauth["client_id"] == productionGoogleWebClientId
    }) { "A configuração Beta não pode reutilizar o cliente OAuth de produção." }
}

fun verifyStagingFirebaseConfiguration() {
    val expected = stagingProjectId?.trim().orEmpty()
    check(expected.isNotEmpty() && expected != "tudo-aqui-macacu" &&
        expected != "demo-universal-search" &&
        (expected.endsWith("-staging") || expected.endsWith("-homologacao")) &&
        expected.matches(Regex("^[a-z0-9][a-z0-9-]{4,62}[a-z0-9]$"))) {
        "Staging exige STAGING_FIREBASE_PROJECT_ID separado, com sufixo -staging ou -homologacao."
    }
    val config = file("src/staging/google-services.json")
    check(config.isFile) {
        "Staging exige android/app/src/staging/google-services.json; não há fallback para produção ou demo."
    }
    val json = JsonSlurper().parse(config) as Map<*, *>
    check((json["project_info"] as? Map<*, *>)?.get("project_id") == expected) {
        "A configuração Firebase de staging não corresponde ao projeto autorizado."
    }
    val clients = json["client"] as? List<*> ?: emptyList<Any>()
    check(clients.any {
        val info = (it as? Map<*, *>)?.get("client_info") as? Map<*, *>
        (info?.get("android_client_info") as? Map<*, *>)?.get("package_name") ==
            "br.com.tudoaquimacacu.tudo_aqui_macacu.staging"
    }) { "A configuração Firebase não corresponde ao pacote Android de staging." }
}

if (stagingRequested) verifyStagingFirebaseConfiguration()
if (betaRequested && betaFirebaseConfig.isFile) verifyBetaFirebaseConfiguration()
else if (betaRequested) verifyOptionalBetaProjectId()

// A previous local build can leave generated Google Services resources behind.
// Remove only this flavor's generated directory when its config is absent, so a
// later compile cannot accidentally reuse stale Firebase options.
val clearMissingBetaFirebaseResources = tasks.register("clearMissingBetaFirebaseResources") {
    onlyIf { betaRequested && !betaFirebaseConfig.isFile }
    doLast { delete(layout.buildDirectory.dir("generated/res/google-services/beta")) }
}
tasks.matching { it.name == "mergeBetaDebugResources" }.configureEach {
    dependsOn(clearMissingBetaFirebaseResources)
}

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
    check(!preBetaLocalRequested) { "Release proibida para preBetaLocal." }
    check(!sparkLocalRequested) { "Release proibida para sparkLocal." }
    check(!stagingRequested) { "Release proibida para staging." }
    check(!betaRequested) { "Release Beta exige autorização específica de distribuição." }
    check(!supabasePilotRequested) { "Release proibida para supabasePilot." }
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

    buildFeatures {
        buildConfig = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "br.com.tudoaquimacacu.tudo_aqui_macacu"
        manifestPlaceholders["stagingFirebaseProjectId"] = ""
        manifestPlaceholders["betaFirebaseProjectId"] = ""
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

    if (searchLocalRequested || preBetaLocalRequested || sparkLocalRequested || stagingRequested || betaRequested || supabasePilotRequested) {
        flavorDimensions += "environment"
        productFlavors {
            create("searchLocal") {
                dimension = "environment"
                applicationIdSuffix = ".searchlocal"
                versionNameSuffix = "-local"
            }
            create("preBetaLocal") {
                dimension = "environment"
                applicationIdSuffix = ".prebeta"
                versionNameSuffix = "-prebeta-local"
            }
            create("sparkLocal") {
                dimension = "environment"
                applicationIdSuffix = ".sparklocal"
                versionNameSuffix = "-spark-local"
            }
            create("staging") {
                dimension = "environment"
                applicationIdSuffix = ".staging"
                versionNameSuffix = "-staging"
                manifestPlaceholders["stagingFirebaseProjectId"] = stagingProjectId.orEmpty()
            }
            create("beta") {
                dimension = "environment"
                applicationIdSuffix = ".beta"
                versionNameSuffix = "-beta"
                manifestPlaceholders["betaFirebaseProjectId"] = betaProjectId.orEmpty()
            }
            create("supabasePilot") {
                dimension = "environment"
                applicationIdSuffix = ".supabasepilot"
                versionNameSuffix = "-supabase-pilot"
            }
        }
    }
}

if (preBetaLocalRequested) {
    // Reuse the same fail-closed gate/VPN and loopback network policy as searchLocal.
    // This flavor restores only the Android permission and VIEW intent filter needed
    // to exercise native reminders and internal links on a disposable AVD.
    android.sourceSets.getByName("preBetaLocal").res.srcDir("src/searchLocal/res")
    kotlin.sourceSets.getByName("preBetaLocal").kotlin.srcDir("src/searchLocal/kotlin")
}
if (sparkLocalRequested) {
    android.sourceSets.getByName("sparkLocal").res.srcDir("src/searchLocal/res")
    kotlin.sourceSets.getByName("sparkLocal").kotlin.srcDir("src/searchLocal/kotlin")
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

// Isolated/local variants never consume the root production configuration.
// Beta uses only its flavor-local google-services.json after Gradle validates it.
tasks.configureEach {
    if (name.endsWith("GoogleServices")) {
        if (name.contains("SearchLocal") || name.contains("PreBetaLocal") ||
            name.contains("SparkLocal") || name.contains("SupabasePilot")) {
            enabled = false
        }
        if (name.contains("Beta") && !betaFirebaseConfig.isFile) enabled = false
    }
}
if (searchLocalRequested) {
    androidComponents {
        beforeVariants(selector().withFlavor("environment" to "searchLocal")) {
            if (it.buildType != "debug") it.enable = false
        }
        beforeVariants(selector().withFlavor("environment" to "staging")) {
            it.enable = false
        }
        beforeVariants(selector().withFlavor("environment" to "preBetaLocal")) {
            it.enable = false
        }
        beforeVariants(selector().withFlavor("environment" to "beta")) {
            it.enable = false
        }
    }
}
if (stagingRequested) {
    androidComponents {
        beforeVariants(selector().withFlavor("environment" to "staging")) {
            if (it.buildType != "debug") it.enable = false
        }
        beforeVariants(selector().withFlavor("environment" to "searchLocal")) {
            it.enable = false
        }
        beforeVariants(selector().withFlavor("environment" to "preBetaLocal")) {
            it.enable = false
        }
        beforeVariants(selector().withFlavor("environment" to "beta")) {
            it.enable = false
        }
    }
}
if (supabasePilotRequested) {
    androidComponents {
        beforeVariants(selector().withFlavor("environment" to "supabasePilot")) {
            if (it.buildType != "debug") it.enable = false
        }
        beforeVariants(selector().withFlavor("environment" to "searchLocal")) {
            it.enable = false
        }
        beforeVariants(selector().withFlavor("environment" to "beta")) {
            it.enable = false
        }
        beforeVariants(selector().withFlavor("environment" to "staging")) {
            it.enable = false
        }
        beforeVariants(selector().withFlavor("environment" to "preBetaLocal")) {
            it.enable = false
        }
    }
}
if (betaRequested) {
    androidComponents {
        beforeVariants(selector().withFlavor("environment" to "beta")) {
            if (it.buildType != "debug") it.enable = false
        }
        beforeVariants(selector().withFlavor("environment" to "searchLocal")) {
            it.enable = false
        }
        beforeVariants(selector().withFlavor("environment" to "preBetaLocal")) {
            it.enable = false
        }
        beforeVariants(selector().withFlavor("environment" to "staging")) {
            it.enable = false
        }
        beforeVariants(selector().withFlavor("environment" to "supabasePilot")) {
            it.enable = false
        }
    }
}
if (preBetaLocalRequested) {
    androidComponents {
        beforeVariants(selector().withFlavor("environment" to "preBetaLocal")) {
            if (it.buildType != "debug") it.enable = false
        }
        beforeVariants(selector().withFlavor("environment" to "searchLocal")) {
            it.enable = false
        }
        beforeVariants(selector().withFlavor("environment" to "beta")) {
            it.enable = false
        }
        beforeVariants(selector().withFlavor("environment" to "staging")) {
            it.enable = false
        }
        beforeVariants(selector().withFlavor("environment" to "supabasePilot")) {
            it.enable = false
        }
        beforeVariants(selector().withFlavor("environment" to "beta")) {
            it.enable = false
        }
    }
}
if (sparkLocalRequested) {
    androidComponents {
        beforeVariants(selector().withFlavor("environment" to "sparkLocal")) {
            if (it.buildType != "debug") it.enable = false
        }
        beforeVariants(selector().withFlavor("environment" to "searchLocal")) { it.enable = false }
        beforeVariants(selector().withFlavor("environment" to "preBetaLocal")) { it.enable = false }
        beforeVariants(selector().withFlavor("environment" to "beta")) { it.enable = false }
        beforeVariants(selector().withFlavor("environment" to "staging")) { it.enable = false }
        beforeVariants(selector().withFlavor("environment" to "supabasePilot")) { it.enable = false }
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
