[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
chcp 65001 > $null

Add-Type -AssemblyName System.Windows.Forms

$host.UI.RawUI.WindowTitle = "AC Recording Rules"

Clear-Host
Write-Host "starting" -ForegroundColor Cyan

$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"

$output_dir = "$env:USERPROFILE\Desktop\AC-REC-OUTPUT"
$output_name = "OUTPUT-$timestamp"

$output_path = Join-Path $output_dir $output_name
$zip_path = "$output_path.7z"

$s_zip_dir = Join-Path $output_dir "7z"
$s_zip_exe = Join-Path $s_zip_dir "7za.exe"

New-Item -ItemType Directory -Path $output_path -Force | Out-Null
New-Item -ItemType Directory -Path $s_zip_dir -Force | Out-Null

if (!(Test-Path $s_zip_exe))
{
	Invoke-WebRequest `
		-Uri "https://www.7-zip.org/a/7zr.exe" `
		-OutFile $s_zip_exe
}

$cheat_process_names = @(
	"app",
	"newui",
	"oldui",
	"volt",
	"xeno"
)

function Show-Warn
{
	param([string]$text)

	for ($i = 0; $i -lt 3; $i++)
	{
		[System.Windows.Forms.MessageBox]::Show(
			$text,
			"warning",
			[System.Windows.Forms.MessageBoxButtons]::OK,
			[System.Windows.Forms.MessageBoxIcon]::Warning
		) | Out-Null
	}
}

function Save-Text
{
	param
	(
		[string]$name,
		[string]$data
	)

	$data | Out-File -FilePath (Join-Path $output_path $name) -Encoding utf8
}

function Save-Command
{
	param
	(
		[string]$name,
		[string]$command
	)

	try
	{
		Invoke-Expression $command | Out-File -FilePath (Join-Path $output_path $name) -Encoding utf8
	}
	catch
	{
		"failed:`r`n$command" | Out-File -FilePath (Join-Path $output_path $name) -Encoding utf8
	}
}

$running_processes = Get-Process -ErrorAction SilentlyContinue
$found_cheats = @()
$detected_log = @()

foreach ($cheat in $cheat_process_names)
{
	foreach ($proc in $running_processes)
	{
		if ($proc.Name -ieq $cheat)
		{
			$display_name = $proc.Name

			if ($proc.Name -ieq "app")
			{
				$display_name = "matcha"
			}

			$found_cheats += $display_name

			$detected_log += (
				"[{0}] {1} | pid: {2}" -f `
				(Get-Date -Format "yyyy-MM-dd HH:mm:ss"),
				$display_name,
				$proc.Id
			)
		}
	}
}

if ($found_cheats.Count -gt 0)
{
	Show-Warn ("detected processes: " + ($found_cheats -join ", "))
}

if ($detected_log.Count -gt 0)
{
	$detected_log | Out-File `
		-FilePath (Join-Path $output_path "cheats_dtc.txt") `
		-Encoding utf8
}

function Dump-Journal
{
	$usn_file = Join-Path $output_path "journal.txt"

	try
	{
		$lines = fsutil usn readjournal C:

		$block = @()

		foreach ($line in $lines)
		{
			if ([string]::IsNullOrWhiteSpace($line))
			{
				$joined = $block -join "`r`n"

				if ($joined -match "\.exe")
				{
					$joined | Add-Content $usn_file -Encoding utf8
					"" | Add-Content $usn_file
				}

				$block = @()
				continue
			}

			$block += $line
		}
	}
	catch
	{
		"usn journal dump failed" | Out-File $usn_file -Encoding utf8
	}
}

$security_info = @()

try
{
	$secure_boot = Confirm-SecureBootUEFI
	$security_info += "SecureBoot: $secure_boot"
}
catch
{
	$security_info += "SecureBoot: unsupported or unavailable"
}

try
{
	$core_iso = Get-CimInstance -Namespace "root\Microsoft\Windows\DeviceGuard" -ClassName "Win32_DeviceGuard"

	$security_info += "VBS: $($core_iso.VirtualizationBasedSecurityStatus)"
}
catch
{
	$security_info += "CoreIsolation: unavailable"
}

Save-Text "security.txt" ($security_info -join "`r`n")

Save-Command "tasklist.txt" "tasklist /v"
Save-Command "processes_cim.txt" "Get-CimInstance Win32_Process | Select-Object ProcessId, Name, ExecutablePath, CommandLine"
Save-Command "services.txt" "Get-Service | Sort-Object Status, Name"
Save-Command "drivers.txt" "driverquery /v"
Save-Command "network.txt" "netstat -abno"

$service_names = @(
	"DPS",
	"SysMain",
	"PcaSvc",
	"bam"
)

$service_output = @()

foreach ($service_name in $service_names)
{
	$service = Get-Service -Name $service_name -ErrorAction SilentlyContinue

	$reg_path = "HKLM:\SYSTEM\CurrentControlSet\Services\$service_name"

	try
	{
		$start_value = (Get-ItemProperty -Path $reg_path).Start
	}
	catch
	{
		$start_value = -1
	}

	$status = if ($service) { $service.Status } else { "NotFound" }

	$startup = switch ($start_value)
	{
		0 { "Boot" }
		1 { "System" }
		2 { "Automatic" }
		3 { "Manual" }
		4 { "Disabled" }
		default { "Unknown" }
	}

	$service_output += "$service_name | Status: $status | Startup: $startup"
}

Save-Text "required_services.txt" ($service_output -join "`r`n")

$log_dir = Join-Path $output_path "logs"

New-Item -ItemType Directory -Path $log_dir -Force | Out-Null

$copy_targets = @(
	"C:\Windows\Prefetch"
)

foreach ($target in $copy_targets)
{
	if (Test-Path $target)
	{
		$folder_name = Split-Path $target -Leaf

		Copy-Item `
			-Path $target `
			-Destination (Join-Path $log_dir $folder_name) `
			-Recurse `
			-Force `
			-ErrorAction SilentlyContinue
	}
}

Dump-Journal

$mui_paths = @(
	"HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\MuiCache",
	"HKCU:\Software\Microsoft\Windows\ShellNoRoam\MUICache"
)

$mui_output = @()

foreach ($mui_path in $mui_paths)
{
	if (Test-Path $mui_path)
	{
		$mui_output += "=== $mui_path ==="

		try
		{
			$mui_output += (Get-ItemProperty -Path $mui_path | Out-String)
		}
		catch
		{
			$mui_output += "failed"
		}
	}
}

Save-Text "muicache.txt" ($mui_output -join "`r`n")

$recent_path = "$env:APPDATA\Microsoft\Windows\Recent"

if (Test-Path $recent_path)
{
	Copy-Item `
		-Path $recent_path `
		-Destination (Join-Path $log_dir "Recent") `
		-Recurse `
		-Force `
		-ErrorAction SilentlyContinue
}

if (Test-Path $zip_path)
{
	Remove-Item $zip_path -Force
}

Start-Process `
	-FilePath $s_zip_exe `
	-ArgumentList @(
		"a",
		"-t7z",
		"-mx=9",
		"-m0=lzma2",
		"-ms=on",
		"`"$zip_path`"",
		"`"$output_path\*`""
	) `
	-NoNewWindow `
	-Wait

Remove-Item `
	-Path $output_path `
	-Recurse `
	-Force `
	-ErrorAction SilentlyContinue

Write-Host ""
Write-Host "finished:" -ForegroundColor Green
Write-Host "  $zip_path" -ForegroundColor White
Write-Host ""