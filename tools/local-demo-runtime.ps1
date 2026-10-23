function Get-SearchLocalRuntime {
    param([Parameter(Mandatory = $true)][string]$AppRoot)

    $codexWork = Join-Path (Split-Path $AppRoot -Parent) 'work'
    $nodeCandidates = @(
        (Join-Path $codexWork 'hot-reload-runtimes/node-v22.23.0-win-x64/node.exe'),
        (Get-Command node -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -ErrorAction SilentlyContinue)
    ) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }
    $node = $null
    foreach ($candidate in $nodeCandidates) {
        $version = (& $candidate --version 2>$null | Select-Object -First 1)
        if ($version -match '^v22\.') { $node = $candidate; break }
    }
    if (!$node) { throw 'Node.js 22 existente não foi encontrado; nenhuma ferramenta será instalada.' }

    $firebaseCandidates = @(
        (Join-Path $codexWork 'firebase-tools.exe'),
        (Get-Command firebase -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -ErrorAction SilentlyContinue)
    ) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }
    $firebase = $null
    foreach ($candidate in $firebaseCandidates) {
        if ((& $candidate --version 2>$null | Select-Object -First 1) -eq '15.32.1') {
            $firebase = $candidate; break
        }
    }
    if (!$firebase) { throw 'Firebase CLI 15.32.1 existente não foi encontrado; nenhuma ferramenta será instalada.' }

    $java = Join-Path $codexWork 'search-emulator-tools/jdk-21.0.12.1+1-jre/bin/java.exe'
    if (!(Test-Path -LiteralPath $java)) {
        $javaCommand = Get-Command java -ErrorAction SilentlyContinue
        if ($javaCommand) { $java = $javaCommand.Source }
    }
    if (!(Test-Path -LiteralPath $java)) { throw 'Java existente não foi encontrado.' }
    $javaVersion = (& $java -version 2>&1) -join "`n"
    if ($javaVersion -notmatch '21\.0\.12\.1') { throw 'O Emulator exige o Java portátil 21.0.12.1 já disponível.' }

    $flutterCommand = Get-Command flutter -ErrorAction SilentlyContinue
    if (!$flutterCommand) { throw 'Flutter existente não foi encontrado; nenhuma ferramenta será instalada.' }
    $adb = Join-Path $env:LOCALAPPDATA 'Android/Sdk/platform-tools/adb.exe'
    if (!(Test-Path -LiteralPath $adb)) { throw 'Android SDK/ADB já configurado não foi encontrado.' }

    $cache = Join-Path $env:USERPROFILE '.cache/firebase'
    $firestoreJar = Join-Path $cache 'emulators/cloud-firestore-emulator-v1.22.0.jar'
    $authCode = Join-Path $cache 'tools/lib/node_modules/firebase-tools/lib/emulator/auth/server.js'
    if (!(Test-Path -LiteralPath $firestoreJar) -or !(Test-Path -LiteralPath $authCode)) {
        throw 'Componente necessário do Emulator não está no cache; o inicializador não fará download.'
    }
    $functionDependencies = Join-Path $AppRoot 'functions/node_modules/firebase-functions'
    if (!(Test-Path -LiteralPath $functionDependencies)) {
        throw 'Dependências existentes das Functions não estão disponíveis; nada será instalado.'
    }

    [pscustomobject]@{
        Node = $node
        Firebase = $firebase
        Java = $java
        Flutter = $flutterCommand.Source
        Adb = $adb
    }
}

function Set-SearchLocalRuntimeEnvironment {
    param([Parameter(Mandatory = $true)]$Runtime)
    $env:JAVA_HOME = Split-Path (Split-Path $Runtime.Java -Parent) -Parent
    $env:Path = "$(Split-Path $Runtime.Node -Parent);$(Split-Path $Runtime.Java -Parent);$env:Path"
}

function Test-SearchLocalTcpPort {
    param([Parameter(Mandatory = $true)][int]$Port)
    $client = [Net.Sockets.TcpClient]::new()
    try {
        $client.Connect('127.0.0.1', $Port)
        return $true
    } catch {
        return $false
    } finally {
        $client.Dispose()
    }
}
