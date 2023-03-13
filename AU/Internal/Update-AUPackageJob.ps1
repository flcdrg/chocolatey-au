param (
    [string]
    $package_name,
    [string]
    $package_path,
    [string]
    $tmp_dir,
    [System.Collections.Specialized.OrderedDictionary]
    $Options
)
function repeat_ignore([ScriptBlock] $Action) {
    # requires $Options
    $run_no = 0
    $run_max = if ($Options.RepeatOn) { if (!$Options.RepeatCount) { 2 } else { $Options.RepeatCount + 1 } } else { 1 }

    :main while ($run_no -lt $run_max) {
        $run_no++
        try {
            $res = & $Action 6> $out
            break main
        }
        catch {
            if ($run_no -ne $run_max) {
                foreach ($msg in $Options.RepeatOn) {
                    if ($_.Exception -notlike "*${msg}*") { continue }
                    Write-Warning "Repeating package_name ($run_no): $($_.Exception)"
                    if ($Options.RepeatSleep) { Write-Warning "Sleeping $($Options.RepeatSleep) seconds before repeating"; Start-Sleep $Options.RepeatSleep }
                    continue main
                }
            }
            foreach ($msg in $Options.IgnoreOn) {
                if ($_.Exception -notlike "*${msg}*") { continue }
                Write-Warning "Ignoring $package_name ($run_no): $($_.Exception)"
                "AU ignored on: $($_.Exception)" | Out-File -Append $out
                $res = 'ignore'
                break main
            }
            $type = if ($res) { $res.GetType() }
            if ( "$type" -eq 'AUPackage') { $res.Error = $_ } else { throw }
        }
    }
    $res
}

Set-Location $package_path
$out = (Join-Path $tmp_dir $package_name)

$global:au_Timeout = $Options.Timeout
$global:au_Force = $Options.Force
$global:au_WhatIf = $Options.WhatIf
$global:au_Result = 'pkg'
$global:au_NoCheckChocoVersion = $Options.NoCheckChocoVersion

if ($Options.BeforeEach) {
    $s = [Scriptblock]::Create( $Options.BeforeEach )
    . $s $package_name $Options
}

$pkg = repeat_ignore { ./update.ps1 }
if (!$pkg) { throw "'$package_name' update script returned nothing" }
if (($pkg -eq 'ignore') -or ($pkg[-1] -eq 'ignore')) { return 'ignore' }

$pkg = $pkg[-1]
$type = $pkg.GetType()
if ( "$type" -ne 'AUPackage') { throw "'$package_name' update script didn't return AUPackage but: $type" }

if ($pkg.Updated -and $Options.Push) {
    $res = repeat_ignore {
        $r = Push-Package -All:$Options.PushAll
        if ($LastExitCode -eq 0) { return $r } else { throw $r }
    }
    if (($res -eq 'ignore') -or ($res[-1] -eq 'ignore')) { return 'ignore' }

    if ($res -is [System.Management.Automation.ErrorRecord]) {
        $pkg.Error = "Push ERROR`n" + $res
    }
    else {
        $pkg.Pushed = $true
        $pkg.Result += $res
    }
}

if ($Options.AfterEach) {
    $s = [Scriptblock]::Create( $Options.AfterEach )
    . $s $package_name $Options
}

$pkg.Serialize()
