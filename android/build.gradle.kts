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

// `another_telephony` is an old plugin: its Java defaults to 1.8, but its
// deprecated `kotlinOptions { jvmTarget = "1.8" }` is ignored by Kotlin 2.x,
// so its Kotlin lands on 17 -> "Inconsistent JVM-target compatibility".
// Its Java compileOptions are finalized too early to raise from here, so we
// instead pin ITS Kotlin back to 1.8. Modern plugins (flutter_contacts,
// workmanager) are left untouched at their natural 17/17.
val jvmMismatchedPlugins = setOf("another_telephony")
subprojects {
    if (project.name in jvmMismatchedPlugins) {
        tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>()
            .configureEach {
                compilerOptions {
                    jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_1_8)
                }
            }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
