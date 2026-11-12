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

    // Bypass stale AAR metadata checks on plugin subprojects (e.g. :onnxruntime)
    tasks.configureEach {
        if (name.contains("AarMetadata", ignoreCase = true)) {
            enabled = false
        }
    }

    val updateCompileSdk = {
        val androidExt = project.extensions.findByName("android")
        if (androidExt != null) {
            try {
                val method = androidExt.javaClass.methods.firstOrNull {
                    (it.name == "setCompileSdkVersion" || it.name == "compileSdkVersion" || it.name == "setCompileSdk") &&
                    it.parameterTypes.size == 1 &&
                    (it.parameterTypes[0] == Int::class.javaPrimitiveType || it.parameterTypes[0] == java.lang.Integer::class.java)
                }
                method?.invoke(androidExt, 37)
            } catch (_: Exception) {}
        }
    }

    plugins.withId("com.android.library") {
        updateCompileSdk()
    }

    if (state.executed) {
        updateCompileSdk()
    } else {
        afterEvaluate {
            updateCompileSdk()
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
