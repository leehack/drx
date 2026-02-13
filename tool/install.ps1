param(
  [string]$Repository = $env:DRX_REPO,
  [string]$Version = "latest",
  [string]$InstallDir = $(if ($env:DRX_INSTALL_DIR) { $env:DRX_INSTALL_DIR } else { Join-Path $HOME ".local\bin" })
)

$ErrorActionPreference = "Stop"

if (-not $Repository) {
  throw "Repository is required. Pass -Repository <owner/repo> or set DRX_REPO."
}

$arch = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString().ToLowerInvariant()
switch ($arch) {
  "x64" { $archToken = "x64" }
  "arm64" { $archToken = "arm64" }
  default { throw "Unsupported architecture: $arch" }
}

$asset = "drx-windows-$archToken.exe"

if ($Version -eq "latest") {
  $url = "https://github.com/$Repository/releases/latest/download/$asset"
} else {
  $url = "https://github.com/$Repository/releases/download/$Version/$asset"
}
$checksumUrl = "$url.sha256"

New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
$target = Join-Path $InstallDir "drx.exe"
$tmp = [System.IO.Path]::GetTempFileName()
$tmpSum = [System.IO.Path]::GetTempFileName()

try {
  Write-Host "Downloading $url"
  Invoke-WebRequest -Uri $url -OutFile $tmp

  Write-Host "Downloading $checksumUrl"
  Invoke-WebRequest -Uri $checksumUrl -OutFile $tmpSum

  $expectedLine = Get-Content -Path $tmpSum | Where-Object { $_.Trim() -ne '' } | Select-Object -First 1
  if (-not $expectedLine) {
    throw "Could not parse checksum file: $checksumUrl"
  }
  $expectedHash = ($expectedLine -split '\s+')[0].ToLowerInvariant()
  $actualHash = (Get-FileHash -Algorithm SHA256 $tmp).Hash.ToLowerInvariant()
  if ($expectedHash -ne $actualHash) {
    throw "Checksum verification failed for $asset. Expected $expectedHash, got $actualHash"
  }

  Move-Item -Path $tmp -Destination $target -Force
  Write-Host "Installed drx to $target"
  Write-Host "Run: $target --version"
} finally {
  if (Test-Path $tmp) {
    Remove-Item $tmp -Force
  }
  if (Test-Path $tmpSum) {
    Remove-Item $tmpSum -Force
  }
}
