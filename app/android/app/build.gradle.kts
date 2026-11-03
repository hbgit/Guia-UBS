// ABIs empacotadas, derivadas do `--target-platform` que o `flutter build`
// passa ao Gradle como a propriedade `target-platform` (ADR-009, item 5).
//
// Um build por ABI, nunca `--split-per-abi`: com o split, o FlutterPlugin
// sobrescreve o versionCode com `abi*1000 + codigo` (FlutterPlugin.kt), e os
// artefatos da mesma tag sairiam com numeros diferentes.
//
// `ndk.abiFilters` decide o que e EMPACOTADO. Um filtro fixo em arm64-v8a
// cortaria a libflutter.so/libapp.so do build `android-arm`, e o APK 32-bit
// abriria e fecharia na hora. Sem a propriedade (o `appbundle` sem flag, ou o
// Android Studio), entram as duas ABIs de campo.
val flutterToAbi = mapOf(
    "android-arm64" to "arm64-v8a",
    "android-arm" to "armeabi-v7a",
    "android-x64" to "x86_64",
)
val packagedAbis: List<String> =
    (project.findProperty("target-platform") as String?)
        ?.split(",")
        ?.mapNotNull { flutterToAbi[it.trim()] }
        ?.takeIf { it.isNotEmpty() }
        ?: listOf("arm64-v8a", "armeabi-v7a")

// O shim nativo (llama.cpp) so e COMPILADO para arm64-v8a e x86_64 (emulador). armeabi-v7a sai SEM o shim: o llama.cpp 32-bit nao e
// suportado, e um aparelho 32-bit nao tem memoria para o modelo de ~806 MB. Ali
// a triagem roda pelo RuleOnlyEngine (INV-8), e o app nao oferece o download do
// modelo. A lista nunca fica vazia: com o filtro vazio, o CMake compilaria as
// quatro ABIs. Num build so armeabi-v7a, o shim arm64 e compilado e descartado,
// porque o `ndk.abiFilters` nao o empacota.
val shimAbis: List<String> =
    packagedAbis.filter { it == "arm64-v8a" || it == "x86_64" }
        .ifEmpty { listOf("arm64-v8a") }

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "br.com.prismrr.guiasaude"
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
        applicationId = "br.com.prismrr.guiasaude"
        // RNF-09 fixa Android 8.0 como piso, e o shim nativo e compilado para
        // android-26. Nao herdamos `flutter.minSdkVersion` (hoje 24): as duas
        // bases precisam bater, ou o `.so` nao carrega no aparelho mais antigo
        // que a Play Store deixaria instalar.
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // `packagedAbis` (topo do arquivo). O AGP faz UNIAO entre
        // defaultConfig e buildType, entao o que entrar aqui nao sai depois:
        // x86_64 e adicionado apenas no buildType `debug`, para emulador.
        //
        // `clear()` antes de adicionar e deliberado: sem isso a lista herda os
        // padroes do AGP.
        ndk {
            abiFilters.clear()
            abiFilters.addAll(packagedAbis)
        }

        externalNativeBuild {
            cmake {
                // Sem esta lista o CMake compila as QUATRO ABIs, ignorando o
                // filtro acima: `ndk.abiFilters` decide o que e EMPACOTADO,
                // este decide o que e COMPILADO. Nunca armeabi-v7a
                // (`shimAbis`, topo do arquivo).
                abiFilters.clear()
                abiFilters.addAll(shimAbis)

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
