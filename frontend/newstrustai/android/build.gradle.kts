buildscript {
    // This is the line that fixes the "Unresolved reference" errors
    val kotlin_version by extra("2.1.0") 
    
    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        classpath("com.android.tools.build:gradle:8.9.1")
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:$kotlin_version")
    }
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

// Force old plugin modules (e.g. google_mlkit_commons) to compile their resources
// against a modern SDK. Their bundled compileSdk is < 31, so release resource
// verification fails with "resource android:attr/lStar not found" (lStar was added
// in API 31). The app itself already compiles at SDK 36, so match that here.
// afterEvaluate is registered BEFORE evaluationDependsOn so it is queued before
// the dependency triggers evaluation.
subprojects {
    afterEvaluate {
        val androidExt = extensions.findByName("android") as? com.android.build.gradle.BaseExtension
        if (androidExt != null && project.name != "app") {
            androidExt.compileSdkVersion(36)
        }
    }
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}