# Build do shim nativo (libgubs_llama).
#
# O llama.cpp é buscado por FetchContent com a tag FIXA abaixo. Nada de
# `master`: o pack e o modelo distribuídos são artefatos assinados e auditáveis,
# e a biblioteca que os interpreta precisa ter a mesma propriedade.
#
# Host (para testes e bench de referência):
#   cmake -S native/llama_shim -B build/shim -G Ninja -DCMAKE_BUILD_TYPE=Release
#   cmake --build build/shim
#
# Android arm64 (device alvo):
#   cmake -S native/llama_shim -B build/shim-arm64 -G Ninja \
#     -DCMAKE_TOOLCHAIN_FILE=$ANDROID_NDK/build/cmake/android.toolchain.cmake \
#     -DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM=android-26 \
#     -DCMAKE_BUILD_TYPE=Release

cmake_minimum_required(VERSION 3.22)
project(gubs_llama C CXX)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

set(GUBS_LLAMA_CPP_TAG "b6100" CACHE STRING
    "Tag do llama.cpp. Alterar exige rodar o bench de novo: latencia p95 e criterio de aceite do PRD.")

include(FetchContent)

# Só a biblioteca. Sem exemplos, sem servidor, sem ferramentas: cada binário a
# mais e superficie que teria de ser auditada e empacotada no APK.
set(LLAMA_BUILD_COMMON   OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_TESTS    OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_TOOLS    OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_SERVER   OFF CACHE BOOL "" FORCE)
set(LLAMA_CURL           OFF CACHE BOOL "" FORCE)
set(GGML_OPENMP          OFF CACHE BOOL "" FORCE)

FetchContent_Declare(
  llama_cpp
  GIT_REPOSITORY https://github.com/ggml-org/llama.cpp.git
  GIT_TAG        ${GUBS_LLAMA_CPP_TAG}
  GIT_SHALLOW    TRUE
)
FetchContent_MakeAvailable(llama_cpp)

add_library(gubs_llama SHARED gubs_llama.c)
target_include_directories(gubs_llama PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})
target_link_libraries(gubs_llama PRIVATE llama)

# O shim e a unica coisa que o Dart procura por nome. Manter o SONAME estavel
# entre plataformas evita ramificacao no lado Dart.
set_target_properties(gubs_llama PROPERTIES OUTPUT_NAME "gubs_llama")
