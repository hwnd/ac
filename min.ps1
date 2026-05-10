[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
chcp 65001 > $null
Add-Type -AssemblyName System.Windows.Forms

$host.UI.RawUI.WindowTitle = "AC Recording Rules"
Clear-Host
Write-Host "starting" -ForegroundColor Cyan

$t = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"

$d = "$env:USERPROFILE\Desktop\AC-REC-OUTPUT"
$n = "OUTPUT-$t"

$o = Join-Path $d $n
$z = "$o.7z"

$l = Join-Path $d "7z"
$e = Join-Path $l "7za.exe"

New-Item -ItemType Directory -Path $o -Force | Out-Null
New-Item -ItemType Directory -Path $l -Force | Out-Null

if (!(Test-Path $e))
{
	Invoke-WebRequest -Uri "https://www.7-zip.org/a/7zr.exe" -OutFile $e
}

$c = @("app","newui","oldui","volt","xeno")

$p = Get-Process -ErrorAction SilentlyContinue
$f = @()
$r = @()

foreach ($a in $c)
{
	foreach ($b in $p)
	{
		if ($b.Name -ieq $a)
		{
			$m = $b.Name
			if ($b.Name -ieq "app") { $m = "matcha" }

			$f += $m
			$r += ("[{0}] {1} | pid: {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $m, $b.Id)
		}
	}
}

if ($f.Count -gt 0)
{
	[System.Windows.Forms.MessageBox]::Show(
		("detected processes: " + ($f -join ", ")),
		"warning",
		[System.Windows.Forms.MessageBoxButtons]::OK,
		[System.Windows.Forms.MessageBoxIcon]::Warning
	) | Out-Null
}

if ($r.Count -gt 0)
{
	$r | Out-File (Join-Path $o "cheats_dtc.txt") -Encoding utf8
}

$g = @()

try
{
	$g += "SecureBoot: " + (Confirm-SecureBootUEFI)
}
catch
{
	$g += "SecureBoot: unsupported or unavailable"
}

try
{
	$v = Get-CimInstance -Namespace "root\Microsoft\Windows\DeviceGuard" -ClassName "Win32_DeviceGuard"
	$g += "VBS: $($v.VirtualizationBasedSecurityStatus)"
}
catch
{
	$g += "CoreIsolation: unavailable"
}

$g | Out-File (Join-Path $o "security.txt") -Encoding utf8

tasklist /v | Out-File (Join-Path $o "tasklist.txt") -Encoding utf8
Get-CimInstance Win32_Process | Select-Object ProcessId, Name, ExecutablePath, CommandLine | Out-File (Join-Path $o "processes_cim.txt") -Encoding utf8
Get-Service | Sort-Object Status, Name | Out-File (Join-Path $o "services.txt") -Encoding utf8
driverquery /v | Out-File (Join-Path $o "drivers.txt") -Encoding utf8
netstat -abno | Out-File (Join-Path $o "network.txt") -Encoding utf8

$s = @("DPS","SysMain","PcaSvc","bam")
$u = @()

foreach ($i in $s)
{
	$v = Get-Service -Name $i -ErrorAction SilentlyContinue
	$x = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\$i" -ErrorAction SilentlyContinue).Start

	$a = if ($v) { $v.Status } else { "NotFound" }

	$b = switch ($x)
	{
		0 { "Boot" }
		1 { "System" }
		2 { "Automatic" }
		3 { "Manual" }
		4 { "Disabled" }
		default { "Unknown" }
	}

	$u += "$i | Status: $a | Startup: $b"
}

$u | Out-File (Join-Path $o "required_services.txt") -Encoding utf8

$l2 = Join-Path $o "logs"
New-Item -ItemType Directory -Path $l2 -Force | Out-Null

$pt = "C:\Windows\Prefetch"

if (Test-Path $pt)
{
	Copy-Item -Path $pt -Destination (Join-Path $l2 "Prefetch") -Recurse -Force -ErrorAction SilentlyContinue
}

$uj = Join-Path $o "journal.txt"

try
{
	$lines = fsutil usn readjournal C:
	$blk = @()

	foreach ($ln in $lines)
	{
		if ([string]::IsNullOrWhiteSpace($ln))
		{
			$j = $blk -join "`r`n"

			if ($j -match "\.exe")
			{
				Add-Content $uj $j -Encoding utf8
				Add-Content $uj ""
			}

			$blk = @()
			continue
		}

		$blk += $ln
	}
}
catch
{
	"usn journal dump failed" | Out-File $uj -Encoding utf8
}

$mui = @(
	"HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\MuiCache",
	"HKCU:\Software\Microsoft\Windows\ShellNoRoam\MUICache"
)

$m = @()

foreach ($h in $mui)
{
	if (Test-Path $h)
	{
		$m += "=== $h ==="
		try { $m += (Get-ItemProperty -Path $h | Out-String) } catch { $m += "failed" }
	}
}

$m | Out-File (Join-Path $o "muicache.txt") -Encoding utf8

$rp = "$env:APPDATA\Microsoft\Windows\Recent"

if (Test-Path $rp)
{
	Copy-Item -Path $rp -Destination (Join-Path $l2 "Recent") -Recurse -Force -ErrorAction SilentlyContinue
}

if (Test-Path $z) { Remove-Item $z -Force }

Start-Process $e -ArgumentList @(
	"a",
	"-t7z",
	"-mx=9",
	"-m0=lzma2",
	"-ms=on",
	"`"$z`"",
	"`"$o\*`""
) -NoNewWindow -Wait

Remove-Item $o -Recurse -Force -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "finished:" -ForegroundColor Green
Write-Host "  $z" -ForegroundColor White
Write-Host ""
