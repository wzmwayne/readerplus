allprojects {
    repositories {
        google()
        mavenCentral()
        // sherpa-onnx 语音合成：F-Droid 允许从可信 Maven 仓库（含 JitPack）解析
        // 许可自由的预编译产物，因此这里作为**依赖**引入，而不是把 .so 提交进源码树。
        maven(url = "https://jitpack.io") {
            content { includeGroup("com.github.k2-fsa") }
        }
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
