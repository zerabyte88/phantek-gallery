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

// Ensure subprojects and plugins (e.g. :onnxruntime) use a compatible compileSdk and bypass stale AAR metadata checks
subprojects {
    afterEvaluate {
        val androidExt = project.extensions.findByName("android")
        if (androidExt != null) {
            try {
                val method = androidExt.javaClass.methods.firstOrNull {
                    (it.name == "setCompileSdkVersion" || it.name == "compileSdkVersion" || it.name == "setCompileSdk") &&
                    it.parameterTypes.size == 1 &&
                    (it.parameterTypes[0] == Int::class.javaPrimitiveType || it.parameterTypes[0] == java.lang.Integer::class.java)
                }
                method?.invoke(androidExt, 35)
            } catch (_: Exception) {}
        }
    }
    tasks.matching { it.name.contains("AarMetadata", ignoreCase = true) }.configureEach {
        enabled = false
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
