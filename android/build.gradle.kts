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

subprojects {
    if (project.name == "flutter_llama") {
        fun configureFlutterLlama() {
            val android = project.extensions.findByName("android")
            if (android != null) {
                try {
                    val defaultConfig = android.javaClass.getMethod("getDefaultConfig").invoke(android)
                    val externalNativeBuild = defaultConfig?.javaClass?.getMethod("getExternalNativeBuild")?.invoke(defaultConfig)
                    val cmake = externalNativeBuild?.javaClass?.getMethod("getCmake")?.invoke(externalNativeBuild)
                    val argumentsMethod = cmake?.javaClass?.methods?.firstOrNull {
                        it.name == "arguments" && it.parameterTypes.size == 1
                    }
                    argumentsMethod?.invoke(cmake, arrayOf("-DFLUTTER_LLAMA_ANDROID_VULKAN=OFF"))
                } catch (_: Throwable) {}
            }
        }

        if (project.state.executed) {
            configureFlutterLlama()
        } else {
            project.afterEvaluate {
                configureFlutterLlama()
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
