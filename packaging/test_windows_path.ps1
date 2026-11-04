#Requires -Version 7.4
<# Shared test helpers for MSI-owned PATH entries; no registry values are changed. #>
function Get-TestMachinePath {
    $key = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey('SYSTEM\CurrentControlSet\Control\Session Manager\Environment')
    try {
        return [string]$key.GetValue('Path', '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
    } finally {
        $key.Dispose()
    }
}

function Assert-TestToolPath {
    param(
        [Parameter(Mandatory)][string]$Directory,
        [Parameter(Mandatory)][string]$Before,
        [switch]$Removed
    )
    $current = Get-TestMachinePath
    if ($Removed) {
        if ($current -cne $Before) {
            throw 'Uninstall changed an unrelated machine PATH entry or retained its own entry.'
        }
        return
    }
    $parts = @($current.Split(';') | Where-Object { $_ })
    $matching = @($parts | Where-Object { [Environment]::ExpandEnvironmentVariables($_).TrimEnd('\') -ieq $Directory.TrimEnd('\') })
    if ($matching.Count -ne 1) {
        throw 'The machine PATH must contain the installed tool directory exactly once.'
    }
    $original = @($Before.Split(';') | Where-Object { $_ })
    if ($parts.Count -ne $original.Count + 1) {
        throw 'Installation changed unrelated PATH members.'
    }
    for ($index = 0; $index -lt $original.Count; $index++) {
        if ($parts[$index] -cne $original[$index]) {
            throw 'Installation changed the order or contents of existing PATH members.'
        }
    }
}

function Assert-TestToolDiscovery {
    param(
        [Parameter(Mandatory)][string]$Executable,
        [Parameter(Mandatory)][string]$WorkingDirectory
    )
    $name = [IO.Path]::GetFileName($Executable)
    $quotedName = $name.Replace("'", "''")
    $commands = @{
        cmd  = @('/d', '/c', 'where.exe', $name)
        pwsh = @('-NoProfile', '-NonInteractive', '-Command', "(Get-Command '$quotedName' -CommandType Application -All -ErrorAction Stop).Source")
    }
    foreach ($shell in @('cmd', 'pwsh')) {
        $file = if ($shell -eq 'cmd') {
            Join-Path $env:SystemRoot 'System32/cmd.exe'
        } else {
            (Get-Process -Id $PID).Path
        }
        $start = [Diagnostics.ProcessStartInfo]::new($file)
        $start.WorkingDirectory = $WorkingDirectory
        $start.UseShellExecute = $false
        $start.RedirectStandardOutput = $true
        $start.RedirectStandardError = $true
        # A long-running test process has a stale inherited environment. Model a
        # restarted shell/service using current machine and user values, without
        # placing the executable's directory in the working directory or args.
        $start.Environment['PATH'] = [Environment]::GetEnvironmentVariable('PATH', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('PATH', 'User')
        foreach ($argument in $commands[$shell]) {
            $start.ArgumentList.Add($argument)
        }
        $process = [Diagnostics.Process]::Start($start)
        try {
            $stdout = $process.StandardOutput.ReadToEndAsync()
            $stderr = $process.StandardError.ReadToEndAsync()
            if (!$process.WaitForExit(30000)) {
                $process.Kill($true)
                throw 'Tool discovery timed out.'
            }
            $output = $stdout.GetAwaiter().GetResult()
            $null = $stderr.GetAwaiter().GetResult()
            $found = @($output -split '\r?\n' | Where-Object { $_.TrimEnd('\') -ieq $Executable.TrimEnd('\') })
            if ($process.ExitCode -ne 0 -or $found.Count -eq 0) {
                throw "The installed tool is not discoverable in a restarted $shell shell."
            }
        } finally {
            $process.Dispose()
        }
    }
}
