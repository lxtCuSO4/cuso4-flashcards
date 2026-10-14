param(
    [string]$FlutterRoot = "D:\dev\flutter",
    [string]$JavaRoot = "D:\Android\Android Studio\jbr",
    [string]$GradleExecutable = "D:\gradle-cache\wrapper\dists\gradle-9.3.1-all\9ot9r568e8zfvvd4mn8rbu1j0\gradle-9.3.1\bin\gradle.bat",
    [switch]$Offline
)

$ErrorActionPreference = "Stop"
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$localBuildRoot = Join-Path $projectRoot "build"
$pluginCopy = Join-Path $localBuildRoot "flutter-gradle-plugin"
$localGradleHome = Join-Path $localBuildRoot "gradle-home"
$sourcePlugin = Join-Path $FlutterRoot "packages\flutter_tools\gradle"
foreach ($required in @($GradleExecutable, (Join-Path $JavaRoot "bin\java.exe"),
    (Join-Path $sourcePlugin "build.gradle.kts"), (Join-Path $projectRoot "android\local.properties"))) {
    if (-not (Test-Path -LiteralPath $required)) { throw "Required build file missing: $required" }
}

# Use the already-installed Gradle executable: the wrapper can download even
# when --offline is specified. All new build caches stay inside this project.
New-Item -ItemType Directory -Force -Path $pluginCopy, $localGradleHome | Out-Null
foreach ($entry in Get-ChildItem -LiteralPath $sourcePlugin -Force) {
    if ($entry.Name -in @("build", ".gradle")) { continue }
    Copy-Item -LiteralPath $entry.FullName -Destination $pluginCopy -Recurse -Force
}

$savedJava = $env:JAVA_HOME
$savedGradle = $env:GRADLE_USER_HOME
try {
    $env:JAVA_HOME = $JavaRoot
    $env:GRADLE_USER_HOME = $localGradleHome
    $arguments = @(
        "--project-dir", (Join-Path $projectRoot "android"),
        "--project-cache-dir", (Join-Path $projectRoot "android\.gradle"),
        "--no-daemon", "--max-workers=2", "--console=plain",
        "-Dcuso4.flutterGradleDir=$pluginCopy",
        "-Dorg.gradle.jvmargs=-Xmx2g -XX:MaxMetaspaceSize=1g",
        "-Pandroid.builder.sdkDownload=false",
        # Pub's C-drive sources and the D-drive project cannot be relativized
        # by Kotlin's incremental cache. Keep the workaround local to this run.
        "-Pkotlin.incremental=false",
        "-Pkotlin.compiler.execution.strategy=in-process",
        "app:assembleDebug"
    )
    if ($Offline) { $arguments += "--offline" }
    & $GradleExecutable @arguments
    if ($LASTEXITCODE -ne 0) { throw "Android build failed (exit $LASTEXITCODE). Local caches are preserved for retry." }
} finally {
    $env:JAVA_HOME = $savedJava
    $env:GRADLE_USER_HOME = $savedGradle
}
