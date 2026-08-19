plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "br.gov.exemplo.guia_ubs"
    // Fixado em 36: os plugins do onboarding (file_picker, workmanager)
    // exigem compilacao contra API 36+. Herdar `flutter.compileSdkVersion`
    // deixaria o build refem da versao que o SDK do Flutter escolher.
    // compileSdk NAO afeta em quais aparelhos o app instala — isso e o minSdk.
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "br.gov.exemplo.guia_ubs"
        // RNF-09 fixa Android 8.0 como piso, e o shim nativo e compilado para
        // android-26. Nao herdamos `flutter.minSdkVersion` (hoje 24): as duas
        // bases precisam bater, ou o `.so` nao carrega no aparelho mais antigo
        // que a Play Store deixaria instalar.
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // Somente arm64-v8a (RNF-09). O AGP faz UNIAO entre defaultConfig e
        // buildType, entao o que entrar aqui nao sai depois: x86_64 e
        // adicionado apenas no buildType `debug`, para emulador.
        //
        // `clear()` antes de adicionar e deliberado: sem isso a lista herda os
        // padroes e o build tenta armeabi-v7a, alvo 32 bits que a espec nao
        // suporta e cuja compilacao do llama.cpp quebra.
        ndk {
            abiFilters.clear()
            abiFilters.add("arm64-v8a")
        }

        externalNativeBuild {
            cmake {
                // Sem esta lista o CMake compila as QUATRO ABIs, ignorando o
                // filtro acima: `ndk.abiFilters` decide o que e EMPACOTADO,
                // este decide o que e COMPILADO.
                abiFilters.clear()
                abiFilters.add("arm64-v8a")

                // libgubs_llama e libllama sao duas bibliotecas compartilhadas
                // que usam a mesma libc++. Com o `c++_static` padrao, cada uma
                // levaria sua propria copia da STL e o comportamento em runtime
                // fica indefinido.
                arguments += listOf("-DANDROID_STL=c++_shared")
            }
        }
    }

    // Fronteira nativa (stack.md ADR-002). O CMakeLists busca o llama.cpp por
    // FetchContent numa tag fixa, entao o primeiro build precisa de rede.
    externalNativeBuild {
        cmake {
            path = file("../../../native/llama_shim/CMakeLists.txt")
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }

        // x86_64 so no debug, para rodar em emulador. Medido: deixar esta ABI
        // no `defaultConfig` colocava ~4 MB de libs nativas no APK de release
        // que nenhum aparelho de campo executa — e `--target-platform=
        // android-arm64` NAO as remove, porque filtra apenas as libs do
        // Flutter, nao as do externalNativeBuild.
        debug {
            ndk {
                abiFilters.add("x86_64")
            }
            externalNativeBuild {
                cmake {
                    abiFilters.add("x86_64")
                }
            }
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
