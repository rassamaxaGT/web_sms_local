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

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

// Исправление для старых плагинов (Namespace и уже выполненные проекты)
subprojects {
    val fixNamespace: Project.() -> Unit = {
        // Проверяем, есть ли у проекта расширение "android"
        val android = extensions.findByName("android") as? com.android.build.gradle.BaseExtension
        if (android != null && android.namespace == null) {
            // Устанавливаем namespace вручную
            android.namespace = if (name == "telephony") {
                "com.shounakmulay.telephony"
            } else {
                "com.fix.${name.replace("-", ".")}"
            }
            // Также на всякий случай поднимем версию SDK для этого плагина
            android.compileSdkVersion(34)
        }
    }

    // Если проект уже прошел стадию конфигурации — применяем сразу
    if (state.executed) {
        fixNamespace()
    } else {
        // Если нет — подписываемся на окончание конфигурации
        afterEvaluate {
            fixNamespace()
        }
    }
}