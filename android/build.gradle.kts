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
    if (project.name == "onnxruntime") {
        fun updateCompileSdk() {
            val android = project.extensions.findByName("android")
            if (android != null) {
                try {
                    val compileSdkMethod = android.javaClass.methods.firstOrNull {
                        it.name == "compileSdkVersion" && it.parameterTypes.size == 1 &&
                        (it.parameterTypes[0] == Int::class.javaPrimitiveType || it.parameterTypes[0] == Integer::class.java)
                    }
                    compileSdkMethod?.invoke(android, 37)
                } catch (_: Throwable) {}
            }
        }

        if (project.state.executed) {
            updateCompileSdk()
        } else {
            project.afterEvaluate {
                updateCompileSdk()
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
