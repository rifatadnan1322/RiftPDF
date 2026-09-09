# RiftPDF — Windows setup.
#   powershell -ExecutionPolicy Bypass -File .\setup_windows.ps1
# Creates a private environment, installs dependencies, reports what this
# machine can do, and optionally builds RiftPDF.exe.

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $root

function Find-Python {
    # The bare "python" command is often Microsoft's Store stub, which is not
    # a Python at all, so ask the py launcher first and verify what we get.
    foreach ($candidate in @("py -3.12", "py -3.11", "py -3.10", "py -3", "python")) {
        $parts = $candidate.Split(" ")
        $exe = $parts[0]
        $args = @($parts[1..($parts.Length - 1)]) + @("-c", "import sys; print(sys.version_info[0], sys.version_info[1])")
        try {
            $out = & $exe $args 2>$null
            if ($LASTEXITCODE -eq 0 -and $out) {
                $nums = $out.Trim().Split(" ")
                if ([int]$nums[0] -eq 3 -and [int]$nums[1] -ge 10) { return $candidate }
            }
        } catch { }
    }
    return $null
}

$python = Find-Python
if (-not $python) {
    Write-Host ""
    Write-Host "No usable Python found (3.10 or newer is required)." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Install it with:"
    Write-Host "    winget install --id Python.Python.3.12 -e" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Then CLOSE this window, open a new PowerShell, and run this script again."
    Write-Host "(A new window is needed so PATH picks up the new install.)"
    exit 1
}
Write-Host "Using $python" -ForegroundColor Green

$parts = $python.Split(" ")
$exe = $parts[0]
$pyArgs = @($parts[1..($parts.Length - 1)])

Write-Host "Creating the environment..."
& $exe @pyArgs -m venv .venv
$venv = Join-Path $root ".venv\Scripts\python.exe"

Write-Host "Installing dependencies (PySide6 is large, this takes a few minutes)..."
& $venv -m pip install --upgrade pip --quiet
& $venv -m pip install -r qt\requirements.txt --quiet

Write-Host ""
Write-Host "What this machine can do:" -ForegroundColor Green
& $venv engine\riftpdf_engine.py --selftest
Write-Host ""
Write-Host "Ghostscript, qpdf, Tesseract and LibreOffice all reading false is normal"
Write-Host "on Windows, and nothing needs fetching to fix it. Compression works"
Write-Host "without them, and OCR uses the recogniser built into Windows when"
Write-Host "windowsocr reads true. Only Word conversion still wants LibreOffice."
Write-Host ""

Write-Host "Run it now with:   .\.venv\Scripts\python.exe qt\main.py" -ForegroundColor Cyan
$build = Read-Host "Build RiftPDF.exe as well? (y/N)"
if ($build -eq "y" -or $build -eq "Y") {
    & $venv -m pip install pyinstaller --quiet
    & $venv qt\build_windows.py
    Write-Host ""
    Write-Host "Built: dist\RiftPDF\RiftPDF.exe" -ForegroundColor Green
}
