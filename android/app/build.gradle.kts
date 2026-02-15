plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    id("com.google.firebase.crashlytics")
    // END: FlutterFire Configuration
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Import necessário para Properties
import java.util.Properties
import java.io.FileInputStream

val localPropertiesFile = rootProject.file("local.properties")
val localProperties = Properties().apply {
    if (localPropertiesFile.exists()) {
        load(FileInputStream(localPropertiesFile))
    }
}

val tikTokAppId = (localProperties.getProperty("tiktok.app.id")
    ?: System.getenv("TIKTOK_APP_ID")
    ?: "").trim()
val tikTokAppSecret = (localProperties.getProperty("tiktok.app.secret")
    ?: System.getenv("TIKTOK_APP_SECRET")
    ?: "").trim()

android {
    namespace = "com.maikelgalvao.partiu"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    buildFeatures {
        buildConfig = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.maikelgalvao.partiu"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true
        buildConfigField("String", "TIKTOK_APP_ID", "\"$tikTokAppId\"")
        buildConfigField("String", "TIKTOK_APP_SECRET", "\"$tikTokAppSecret\"")
    }

    // Configuração de assinatura
    val keystorePropertiesFile = rootProject.file("key.properties")
    val keystoreProperties = Properties()
    
    if (keystorePropertiesFile.exists()) {
        keystoreProperties.load(FileInputStream(keystorePropertiesFile))
    }
    
    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = rootProject.file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            // Release builds must be signed with the upload keystore (Play Console upload key).
            // If it's missing, fail fast instead of accidentally producing a debug-signed bundle.
            check(keystorePropertiesFile.exists()) {
                "Missing android/key.properties. Configure release signing (upload keystore) to build a Play-ready AAB."
            }
            signingConfig = signingConfigs.getByName("release")

            // O Flutter (release) está gerando mapping.txt => R8 está ativo.
            // Precisamos incluir regras para manter a UCropActivity (image_cropper),
            // senão ela pode ser renomeada/reempacotada e o Manifest não encontra.
            isMinifyEnabled = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation("com.google.android.gms:play-services-maps:18.2.0")
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
    
    // AppsFlyer SDK
    implementation("com.appsflyer:af-android-sdk:6.14.2")
    
    // Google Play Install Referrer (melhora precisão de atribuição do AppsFlyer)
    implementation("com.android.installreferrer:installreferrer:2.2")

    implementation("com.github.tiktok:tiktok-business-android-sdk:1.5.0")
    implementation("androidx.lifecycle:lifecycle-process:2.8.7")
}
