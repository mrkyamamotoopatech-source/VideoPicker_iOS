plugins {
    id("com.android.library")
    kotlin("android")
}

android {
    namespace = "com.example.videopickerscoring"
    compileSdk = 34

    defaultConfig {
        minSdk = 24
        externalNativeBuild {
            cmake {
                cppFlags += listOf("-std=c++17")
            }
        }
    }

    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
        }
    }
}

dependencies {
    implementation(kotlin("stdlib"))
}
