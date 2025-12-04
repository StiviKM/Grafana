# Base directories
$baseDir = "C:\Monitoring"
$promDir = "$baseDir\Prometheus"
$exporterDir = "$baseDir\windows_exporter"
$nssmDir = "$baseDir\nssm"

# URLs
$promUrl = "https://github.com/prometheus/prometheus/releases/download/v3.8.0/prometheus-3.8.0.windows-amd64.zip"
$exporterUrl = "https://github.com/prometheus-community/windows_exporter/releases/latest/download/windows_exporter-0.31.3-amd64.msi"
$nssmUrl = "https://nssm.cc/release/nssm-2.24.zip"

# Zerotier subnet
$ztSubnet = "10.100.33.0/24"

# Create directories
New-Item -ItemType Directory -Force -Path $promDir, $exporterDir, $nssmDir

# -------------------------
# Download & Install Prometheus
# -------------------------
$promExeDir = Get-ChildItem -Path $promDir -Directory | Where-Object Name -match "windows-amd64"
if (-not $promExeDir) {
    Write-Host "Downloading Prometheus..."
    $promZip = "$baseDir\prometheus.zip"
    Invoke-WebRequest -Uri $promUrl -OutFile $promZip
    Expand-Archive -Path $promZip -DestinationPath $promDir -Force
    Remove-Item $promZip
    $promExeDir = Get-ChildItem -Path $promDir -Directory | Where-Object Name -match "windows-amd64"
}
$promExe = "$($promExeDir.FullName)\prometheus.exe"

# Generate minimal prometheus.yml if not exists
$configPath = "$($promExeDir.FullName)\prometheus.yml"
if (-not (Test-Path $configPath)) {
    $prometheusConfig = @"
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'windows'
    static_configs:
      - targets: ['localhost:9182']
"@
    $prometheusConfig | Out-File -FilePath $configPath -Encoding ascii
}

# -------------------------
# Download & Install windows_exporter
# -------------------------
$exporterExe = "C:\Program Files\windows_exporter\windows_exporter.exe"
if (-not (Test-Path $exporterExe)) {
    Write-Host "Downloading and installing windows_exporter..."
    $exporterMsi = "$exporterDir\windows_exporter.msi"
    Invoke-WebRequest -Uri $exporterUrl -OutFile $exporterMsi
    Start-Process msiexec.exe -ArgumentList "/i `"$exporterMsi`" /qn" -Wait
    Remove-Item $exporterMsi
}

# Unblock in case of execution block
if (Test-Path $exporterExe) { Unblock-File $exporterExe }

# -------------------------
# Download NSSM
# -------------------------
$nssmExe = "$nssmDir\nssm-2.24\win64\nssm.exe"
if (-not (Test-Path $nssmExe)) {
    Write-Host "Downloading NSSM..."
    $nssmZip = "$nssmDir\nssm.zip"
    Invoke-WebRequest -Uri $nssmUrl -OutFile $nssmZip
    Expand-Archive -Path $nssmZip -DestinationPath $nssmDir -Force
    Remove-Item $nssmZip
}

# -------------------------
# Install services via NSSM
# -------------------------

# windows_exporter service
if (-not (Get-Service windows_exporter -ErrorAction SilentlyContinue)) {
    & $nssmExe install windows_exporter $exporterExe "--collectors.enabled cpu,logical_disk,net,os,system,memory"
    & $nssmExe set windows_exporter Start SERVICE_AUTO_START

    # Logging
    $nssmLogDir = "$baseDir\windows_exporter\logs"
    New-Item -ItemType Directory -Force -Path $nssmLogDir
    & $nssmExe set windows_exporter AppStdout "$nssmLogDir\stdout.log"
    & $nssmExe set windows_exporter AppStderr "$nssmLogDir\stderr.log"
    & $nssmExe set windows_exporter AppRotateFiles 1

    Start-Service windows_exporter
} else {
    Write-Host "windows_exporter service already installed."
}

# Prometheus service
if (-not (Get-Service prometheus -ErrorAction SilentlyContinue)) {
    & $nssmExe install prometheus $promExe "--config.file=$configPath"
    & $nssmExe set prometheus Start SERVICE_AUTO_START

    # Logging
    $promLogDir = "$baseDir\Prometheus\logs"
    New-Item -ItemType Directory -Force -Path $promLogDir
    & $nssmExe set prometheus AppStdout "$promLogDir\stdout.log"
    & $nssmExe set prometheus AppStderr "$promLogDir\stderr.log"
    & $nssmExe set prometheus AppRotateFiles 1

    Start-Service prometheus
} else {
    Write-Host "Prometheus service already installed."
}

# -------------------------
# Firewall rules
# -------------------------
$firewallRules = @(
    @{Name="Prometheus (Zerotier)"; Port=9090},
    @{Name="Windows Exporter (Zerotier)"; Port=9182}
)

foreach ($rule in $firewallRules) {
    if (-not (Get-NetFirewallRule -DisplayName $rule.Name -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -DisplayName $rule.Name `
            -Direction Inbound -Action Allow -Protocol TCP -LocalPort $rule.Port `
            -RemoteAddress $ztSubnet
    } else {
        Write-Host "Firewall rule $($rule.Name) already exists."
    }
}

Write-Host "Installation complete. Both services are running and persistent."

# -------------------------
# Extra: Replace port 9090 with 9182 in prometheus.yml
# -------------------------
(Get-Content "C:\Monitoring\Prometheus\prometheus-3.8.0.windows-amd64\prometheus.yml") -replace '9090', '9182' |
    Set-Content "C:\Monitoring\Prometheus\prometheus-3.8.0.windows-amd64\prometheus.yml"

Get-Content "C:\Monitoring\Prometheus\prometheus-3.8.0.windows-amd64\prometheus.yml"

Restart-Service prometheus
