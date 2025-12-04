# Base directories
$baseDir = "C:\Monitoring"
$promDir = "$baseDir\Prometheus"
$exporterDir = "$baseDir\windows_exporter"
$nssmDir = "$baseDir\nssm"

# URLs
$promUrl = "https://github.com/prometheus/prometheus/releases/download/v3.8.0/prometheus-3.8.0.windows-amd64.zip"
$exporterUrl = "https://github.com/prometheus-community/windows_exporter/releases/latest/download/windows_exporter-0.31.3-amd64.msi"
$nssmUrl = "https://nssm.cc/release/nssm-2.24.zip"

# Create directories
New-Item -ItemType Directory -Force -Path $promDir, $exporterDir, $nssmDir

# Download Prometheus
$promZip = "$baseDir\prometheus.zip"
Invoke-WebRequest -Uri $promUrl -OutFile $promZip
Expand-Archive -Path $promZip -DestinationPath $promDir -Force
Remove-Item $promZip

# Download windows_exporter
$exporterMsi = "$exporterDir\windows_exporter.msi"
Invoke-WebRequest -Uri $exporterUrl -OutFile $exporterMsi
Start-Process msiexec.exe -ArgumentList "/i `"$exporterMsi`" /qn" -Wait

# Download NSSM
$nssmZip = "$nssmDir\nssm.zip"
Invoke-WebRequest -Uri $nssmUrl -OutFile $nssmZip
Expand-Archive -Path $nssmZip -DestinationPath $nssmDir -Force
Remove-Item $nssmZip
$nssmExe = "$nssmDir\nssm-2.24\win64\nssm.exe"

# Unblock windows_exporter executable (common issue)
Unblock-File "C:\Program Files\windows_exporter\windows_exporter.exe"

# Delete existing service if exists
if (Get-Service windows_exporter -ErrorAction SilentlyContinue) {
    Stop-Service windows_exporter -Force -ErrorAction SilentlyContinue
    sc.exe delete windows_exporter
    Start-Sleep -Seconds 2
}

# Install windows_exporter as a service via NSSM
$exporterExe = "C:\Program Files\windows_exporter\windows_exporter.exe"
& $nssmExe install windows_exporter $exporterExe "--collectors.enabled cpu,logical_disk,net,os,system,memory"

# Configure logging for service
$nssmLogDir = "$baseDir\windows_exporter\logs"
New-Item -ItemType Directory -Force -Path $nssmLogDir
& $nssmExe set windows_exporter AppStdout "$nssmLogDir\stdout.log"
& $nssmExe set windows_exporter AppStderr "$nssmLogDir\stderr.log"
& $nssmExe set windows_exporter AppRotateFiles 1

# Start windows_exporter service
Start-Service windows_exporter

# Define Zerotier subnet
$ztSubnet = "10.100.33.0/24"

# Open Prometheus port 9090 only for Zerotier network
New-NetFirewallRule -DisplayName "Prometheus (Zerotier)" `
    -Direction Inbound -Action Allow -Protocol TCP -LocalPort 9090 `
    -RemoteAddress $ztSubnet

# Open Windows Exporter port 9182 only for Zerotier network
New-NetFirewallRule -DisplayName "Windows Exporter (Zerotier)" `
    -Direction Inbound -Action Allow -Protocol TCP -LocalPort 9182 `
    -RemoteAddress $ztSubnet


# Start Prometheus in background
$promExeDir = Get-ChildItem -Path $promDir -Directory | Where-Object Name -match "windows-amd64"
$promExe = "$($promExeDir.FullName)\prometheus.exe"

# Generate minimal prometheus.yml
$prometheusConfig = @"
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'windows'
    static_configs:
      - targets: ['localhost:9182']
"@

$configPath = "$($promExeDir.FullName)\prometheus.yml"
$prometheusConfig | Out-File -FilePath $configPath -Encoding ascii

# Run Prometheus detached
Start-Process $promExe -ArgumentList "--config.file=$configPath" -WindowStyle Hidden
