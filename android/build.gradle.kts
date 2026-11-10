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

            // Patch flutter_llama_bridge.cpp for KV cache clearing and stop sequences
            val bridgeFile = project.projectDir.resolve("src/main/cpp/flutter_llama_bridge.cpp")
            if (bridgeFile.exists()) {
                try {
                    var content = bridgeFile.readText()
                    var modified = false

                    if (!content.contains("llama_kv_cache_clear(g_context);")) {
                        val target = "llama_batch batch = llama_batch_get_one(prompt_tokens.data(), prompt_tokens.size());"
                        if (content.contains(target)) {
                            content = content.replace(
                                target,
                                "llama_kv_cache_clear(g_context);\n    $target"
                            )
                            modified = true
                        }
                    }

                    if (!content.contains("<|im_end|>")) {
                        val target = "result.append(token_str);"
                        if (content.contains(target)) {
                            val stopCheck = """
            std::string piece(token_str);
            if (piece.find("<|im_end|>") != std::string::npos ||
                piece.find("<|endoftext|>") != std::string::npos ||
                piece.find("<|im_start|>") != std::string::npos ||
                piece.find("<end_of_turn>") != std::string::npos ||
                piece.find("</s>") != std::string::npos ||
                piece.find("<eos>") != std::string::npos) {
                break;
            }
            result.append(token_str);
            if (result.find("<|im_end|>") != std::string::npos ||
                result.find("<|im_start|>") != std::string::npos ||
                result.find("<end_of_turn>") != std::string::npos) {
                break;
            }
                            """.trimIndent()
                            content = content.replaceFirst(target, stopCheck)
                            modified = true
                        }
                    }

                    if (modified) {
                        bridgeFile.writeText(content)
                        println("[flutter_llama] Successfully patched flutter_llama_bridge.cpp with KV cache clear and stop tokens.")
                    }
                } catch (e: Throwable) {
                    println("[flutter_llama] Warning: Could not patch flutter_llama_bridge.cpp: ${'$'}e")
                }
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
