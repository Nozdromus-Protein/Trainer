plugins {
    id("com.google.gms.google-services") version "4.3.15" apply false
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// Wyłączenie `lintVital*` w podprojektach (moduły pluginów Fluttera).
//
// AGP 9 uruchamia lint na wydaniu, a jego analizator Kotlina (K2) wywraca się
// na `SharedPreferencesPlugin.kt` z `shared_preferences_android`:
// „Unexpected failure during lint analysis (this is a bug in lint or one of the
// libraries it depends on)". To błąd narzędzi w KODZIE ZALEŻNOŚCI — nie da się
// go naprawić po naszej stronie, a blokuje `flutter build apk --release`.
// Wyłączamy wyłącznie ten krok; kompilacja, testy i `flutter analyze` naszego
// kodu zostają bez zmian. Do usunięcia, gdy AGP/Kotlin to naprawią.
subprojects {
    tasks.matching { it.name.startsWith("lintVital") }.configureEach {
        enabled = false
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
