# Script para configurar Azure File Shares para Breeza App
# Requiere: Azure CLI instalado y autenticado (az login)

param(
    [Parameter(Mandatory=$true)]
    [string]$StorageAccountName,
    
    [Parameter(Mandatory=$false)]
    [string]$ResourceGroupName,
    
    [Parameter(Mandatory=$false)]
    [string]$StorageAccountKey,
    
    [Parameter(Mandatory=$false)]
    [string]$Location = "eastus"
)

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Configuración de Azure File Shares" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Verificar si Azure CLI está instalado
if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    Write-Host "ERROR: Azure CLI no está instalado." -ForegroundColor Red
    Write-Host "Instálalo desde: https://aka.ms/installazurecliwindows" -ForegroundColor Yellow
    exit 1
}

# Obtener Storage Account Key si no se proporcionó
if (-not $StorageAccountKey) {
    if (-not $ResourceGroupName) {
        Write-Host "ERROR: Se requiere ResourceGroupName si no se proporciona StorageAccountKey" -ForegroundColor Red
        exit 1
    }
    
    Write-Host "Obteniendo clave de acceso del Storage Account..." -ForegroundColor Yellow
    $keys = az storage account keys list --account-name $StorageAccountName --resource-group $ResourceGroupName --query "[0].value" -o tsv
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: No se pudo obtener la clave del Storage Account" -ForegroundColor Red
        exit 1
    }
    $StorageAccountKey = $keys
    Write-Host "✓ Clave obtenida" -ForegroundColor Green
}

# Nombres de los File Shares
$mysqlShareName = "breeza-mysql-data"
$appDataShareName = "breeza-app-data"

Write-Host ""
Write-Host "Creando Azure File Shares..." -ForegroundColor Yellow

# Crear File Share para MySQL
Write-Host "Creando File Share para MySQL: $mysqlShareName" -ForegroundColor Cyan
az storage share create `
    --name $mysqlShareName `
    --account-name $StorageAccountName `
    --account-key $StorageAccountKey `
    --quota 10 `
    --output none

if ($LASTEXITCODE -eq 0) {
    Write-Host "✓ File Share '$mysqlShareName' creado exitosamente" -ForegroundColor Green
} else {
    Write-Host "⚠ El File Share '$mysqlShareName' ya existe o hubo un error" -ForegroundColor Yellow
}

# Crear File Share para datos de la aplicación
Write-Host "Creando File Share para datos de la app: $appDataShareName" -ForegroundColor Cyan
az storage share create `
    --name $appDataShareName `
    --account-name $StorageAccountName `
    --account-key $StorageAccountKey `
    --quota 5 `
    --output none

if ($LASTEXITCODE -eq 0) {
    Write-Host "✓ File Share '$appDataShareName' creado exitosamente" -ForegroundColor Green
} else {
    Write-Host "⚠ El File Share '$appDataShareName' ya existe o hubo un error" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Subiendo archivos al File Share..." -ForegroundColor Yellow

# Subir credentials.json
if (Test-Path "credentials.json") {
    Write-Host "Subiendo credentials.json..." -ForegroundColor Cyan
    az storage file upload `
        --share-name $appDataShareName `
        --source ./credentials.json `
        --path credentials.json `
        --account-name $StorageAccountName `
        --account-key $StorageAccountKey `
        --output none
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✓ credentials.json subido exitosamente" -ForegroundColor Green
    } else {
        Write-Host "⚠ Error al subir credentials.json" -ForegroundColor Yellow
    }
} else {
    Write-Host "⚠ credentials.json no encontrado en el directorio actual" -ForegroundColor Yellow
}

# Subir archivos estáticos
if (Test-Path "static") {
    Write-Host "Creando directorio static en el File Share..." -ForegroundColor Cyan
    az storage directory create `
        --share-name $appDataShareName `
        --name static `
        --account-name $StorageAccountName `
        --account-key $StorageAccountKey `
        --output none
    
    Write-Host "Subiendo archivos estáticos..." -ForegroundColor Cyan
    az storage file upload-batch `
        --destination $appDataShareName/static `
        --source ./static `
        --account-name $StorageAccountName `
        --account-key $StorageAccountKey `
        --output none
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✓ Archivos estáticos subidos exitosamente" -ForegroundColor Green
    } else {
        Write-Host "⚠ Error al subir archivos estáticos" -ForegroundColor Yellow
    }
} else {
    Write-Host "⚠ Directorio static no encontrado" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "Configuración completada" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Próximos pasos:" -ForegroundColor Cyan
Write-Host "1. Actualiza docker-compose.azure.yml con:" -ForegroundColor Yellow
Write-Host "   - Storage Account Name: $StorageAccountName" -ForegroundColor White
Write-Host "   - Storage Account Key: [tu clave]" -ForegroundColor White
Write-Host ""
Write-Host "2. O mejor aún, usa Managed Identity y elimina storage_account_key del archivo" -ForegroundColor Yellow
Write-Host ""
Write-Host "3. Para desplegar en Azure Container Instances:" -ForegroundColor Yellow
Write-Host "   az container create --resource-group <rg> --file docker-compose.azure.yml" -ForegroundColor White
Write-Host ""

