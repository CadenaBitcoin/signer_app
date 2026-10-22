import java.security.KeyStore
import java.security.MessageDigest
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// ---- Release signing (Issue #72) ------------------------------------------------------------
// The release build type is signed in one of two modes, chosen EXPLICITLY by the environment
// variable CADENA_SIGNING:
//
//   unset / "validation"  The credential-free CI and compile validation: the release build is
//                         signed with the debug key. Such an artifact is NOT distributable and
//                         tool/verify_android_release.py refuses it as a release.
//   "release"             The artifact is signed with a keystore that is supplied from OUTSIDE the
//                         repository (see below). If anything is missing or wrong the build FAILS:
//                         there is no fallback to the debug key.
//   anything else         The build fails (a typo must never end in a debug-signed artifact).
//
// In "release" mode the credentials come from environment variables, optionally from a Java
// properties file whose path is CADENA_SIGNING_PROPERTIES (an environment variable wins over the
// file). The file and the keystore must live outside the repository directory.
//
//   CADENA_KEYSTORE_FILE / storeFile            path of the keystore
//   CADENA_KEY_ALIAS / keyAlias                 alias of the signing key
//   CADENA_KEYSTORE_PASSWORD / storePassword    keystore password
//   CADENA_KEY_PASSWORD / keyPassword           key password
//   CADENA_EXPECTED_CERT_SHA256                 REQUIRED: the SHA-256 fingerprint of the certificate
//                                               the artifact must be signed with. The build fails
//                                               before signing if the key's certificate differs.
//
// No value is ever printed, except the two public certificate fingerprints in the mismatch message.
// See docs/ANDROID_RELEASE.md.
val cadenaSigningMode: String = System.getenv("CADENA_SIGNING")?.takeIf { it.isNotEmpty() } ?: "validation"
if (cadenaSigningMode != "validation" && cadenaSigningMode != "release") {
    throw GradleException("CADENA_SIGNING must be unset, 'validation' or 'release' (got '$cadenaSigningMode'); refusing to guess a signing mode.")
}

/** The verified release signing credentials; throws a GradleException that names what is wrong (never a value). */
fun cadenaReleaseCredentials(repoRoot: File): Map<String, String> {
    val props = Properties()
    val propsPath = System.getenv("CADENA_SIGNING_PROPERTIES")?.takeIf { it.isNotEmpty() }
    if (propsPath != null) {
        val f = File(propsPath).canonicalFile
        if (!f.isFile) throw GradleException("CADENA_SIGNING_PROPERTIES does not name a file.")
        if (f.path.startsWith(repoRoot.path + File.separator)) {
            throw GradleException("The signing properties file must be outside the repository directory.")
        }
        f.inputStream().use { props.load(it) }
    }
    fun value(envName: String, key: String): String? =
        System.getenv(envName)?.takeIf { it.isNotEmpty() } ?: props.getProperty(key)?.takeIf { it.isNotEmpty() }
    val wanted = listOf(
        "storeFile" to "CADENA_KEYSTORE_FILE", "keyAlias" to "CADENA_KEY_ALIAS",
        "storePassword" to "CADENA_KEYSTORE_PASSWORD", "keyPassword" to "CADENA_KEY_PASSWORD",
    )
    val values = HashMap<String, String>()
    val missing = ArrayList<String>()
    for ((key, envName) in wanted) {
        val v = value(envName, key)
        if (v == null) missing.add("$key ($envName)") else values[key] = v
    }
    val expected = System.getenv("CADENA_EXPECTED_CERT_SHA256")?.takeIf { it.isNotEmpty() }
    if (expected == null) missing.add("the expected certificate fingerprint (CADENA_EXPECTED_CERT_SHA256)")
    if (missing.isNotEmpty()) {
        throw GradleException("CADENA_SIGNING=release, but the signing credentials are incomplete. Missing: " + missing.joinToString(", ") +
            ". The build does not fall back to the debug key.")
    }
    val keystoreFile = File(values.getValue("storeFile")).canonicalFile
    if (!keystoreFile.isFile) throw GradleException("The keystore file does not exist.")
    if (keystoreFile.path.startsWith(repoRoot.path + File.separator)) {
        throw GradleException("The keystore must be outside the repository directory.")
    }
    values["storeFile"] = keystoreFile.path
    // The certificate in the keystore must be the one that is expected, checked BEFORE anything is signed.
    val wantedHex = expected!!.replace(":", "").lowercase()
    if (!Regex("^[0-9a-f]{64}$").matches(wantedHex)) {
        throw GradleException("CADENA_EXPECTED_CERT_SHA256 must be a SHA-256 fingerprint (64 hex digits, colons optional).")
    }
    val keystore = try {
        KeyStore.getInstance(keystoreFile, values.getValue("storePassword").toCharArray())
    } catch (e: Exception) {
        throw GradleException("The keystore cannot be opened (wrong password or not a keystore): " + e.javaClass.simpleName)
    }
    val cert = keystore.getCertificate(values.getValue("keyAlias"))
        ?: throw GradleException("The keystore has no certificate under the given alias.")
    val actualHex = MessageDigest.getInstance("SHA-256").digest(cert.encoded).joinToString("") { "%02x".format(it) }
    if (actualHex != wantedHex) {
        throw GradleException("The signing certificate does not match the expected one. Expected SHA-256 $wantedHex, the keystore has $actualHex. Nothing was signed.")
    }
    return values
}

android {
    namespace = "com.app.cadenabitcoin"
    compileSdk = 36
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // The application ID of the app published on Google Play (Issue #72). It is deliberately
        // different from the Kotlin namespace above: the namespace names the source package
        // (R class, MainActivity) and stays; only the application ID is the app's identity on
        // devices and in Google Play. iOS has its own identifiers (ios/Flutter/Flavor-*.xcconfig).
        applicationId = "com.cadenabitcoin.mobile.signer"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Application identity. The flavor selects ONLY the platform identity (application
    // ID and launcher label). The environment (backend, network) is selected by
    // config/build/<environment>.json, and lib/config/build_config.dart fails the build
    // unless the flavor and APP_ENV agree. There is deliberately no default flavor:
    // build with `--flavor staging|production`. See docs/BUILD_CONFIGURATION.md.
    //
    // The per-flavor cmake argument is NOT functional (the CMake project is the empty
    // one Flutter adds only to make AGP download the NDK). Without a difference between
    // the flavors, AGP shares ONE native-build task between them and ties it to a single
    // flavor, so `assembleProductionRelease` would also run the staging Dart compile with
    // the production defines, which the flavor/environment check rightly rejects.
    flavorDimensions += "environment"
    productFlavors {
        // Keeps the existing production identity: defaultConfig's applicationId.
        create("production") {
            dimension = "environment"
            manifestPlaceholders["appLabel"] = "Cadena Bitcoin"
            externalNativeBuild { cmake { arguments("-DCADENA_FLAVOR=production") } }
        }
        // A separate application that installs next to production.
        create("staging") {
            dimension = "environment"
            applicationIdSuffix = ".staging"
            manifestPlaceholders["appLabel"] = "Cadena Signer STAGING"
            externalNativeBuild { cmake { arguments("-DCADENA_FLAVOR=staging") } }
        }
    }

    signingConfigs {
        if (cadenaSigningMode == "release") {
            val credentials = cadenaReleaseCredentials(rootProject.projectDir.parentFile.canonicalFile)
            register("cadenaRelease") {
                storeFile = File(credentials.getValue("storeFile"))
                storePassword = credentials.getValue("storePassword")
                keyAlias = credentials.getValue("keyAlias")
                keyPassword = credentials.getValue("keyPassword")
                enableV2Signing = true
                enableV3Signing = true
            }
        }
    }

    buildTypes {
        release {
            // "validation" (the default, credential-free CI): the debug key, never distributable.
            // "release": the verified keystore above. There is no path from a failed "release" to the debug key.
            signingConfig = if (cadenaSigningMode == "release") signingConfigs.getByName("cadenaRelease") else signingConfigs.getByName("debug")
        }
    }
}

// The production signing identity signs the PRODUCTION application only. Once the task graph is known,
// a "release" build that would run any task of the release variant of another flavor (staging, or a flavor
// added later) fails before anything is compiled or signed: `flutter build ... --flavor staging`,
// `./gradlew assembleStagingRelease` and the flavor-less `assembleRelease` (which assembles every flavor)
// are all refused. The flavor names are read from the declarations above, so a new flavor is covered
// without an edit here. Validation mode is unaffected: it holds no identity.
if (cadenaSigningMode == "release") {
    gradle.taskGraph.whenReady {
        val foreignReleaseVariants = android.productFlavors.names
            .filter { it != "production" }
            .map { it.replaceFirstChar { c -> c.uppercase() } + "Release" }
        val offending = allTasks
            .filter { it.project == project }
            .filter { task -> foreignReleaseVariants.any { task.name.contains(it) } }
            .map { it.name }
        if (offending.isNotEmpty()) {
            throw GradleException("CADENA_SIGNING=release signs the production application only; this build would also run " +
                offending.take(3).joinToString(", ") + " (a release variant of another flavor) with the production signing identity. " +
                "Nothing was signed. Build with --flavor production, or unset CADENA_SIGNING for a validation build.")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    // add dependency to enable Device Intelligence
    implementation("com.sumsub.sns:idensic-mobile-sdk-fisherman:1.42.0")
}