# Script para desplegar Breeza App en Azure Container Apps
# Requiere: Azure CLI instalado y autenticado (az login)

param(
    [Parameter(Mandatory=$true)]
    [string]$ResourceGroupName,
    
    [Parameter(Mandatory=$true)]
    [string]$EnvironmentName,
    
    [Parameter(Mandatory=$false)]
    [string]$Location = "eastus",
    
    [Parameter(Mandatory=$false)]
    [string]$ComposeFile = "docker-compose.azure.yml"
)

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Despliegue en Azure Container Apps" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Verificar si Azure CLI está instalado
if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    Write-Host "ERROR: Azure CLI no está instalado." -ForegroundColor Red
    Write-Host "Instálalo desde: https://aka.ms/installazurecliwindows" -ForegroundColor Yellow
    exit 1
}

# Verificar si la extensión de Container Apps está instalada
Write-Host "Verificando extensión de Container Apps..." -ForegroundColor Yellow
$extension = az extension list --query "[?name=='containerapp'].name" -o tsv
if (-not $extension) {
    Write-Host "Instalando extensión de Container Apps..." -ForegroundColor Yellow
    az extension add --name containerapp
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: No se pudo instalar la extensión de Container Apps" -ForegroundColor Red
        exit 1
    }
    Write-Host "✓ Extensión instalada" -ForegroundColor Green
} else {
    Write-Host "✓ Extensión ya instalada" -ForegroundColor Green
}

# Verificar si el archivo docker-compose existe
if (-not (Test-Path $ComposeFile)) {
    Write-Host "ERROR: No se encontró el archivo $ComposeFile" -ForegroundColor Red
    exit 1
}

# Verificar si el Resource Group existe
Write-Host ""
Write-Host "Verificando Resource Group..." -ForegroundColor Yellow
$rgExists = az group exists --name $ResourceGroupName -o tsv
if ($rgExists -eq "false") {
    Write-Host "Creando Resource Group: $ResourceGroupName" -ForegroundColor Cyan
    az group create --name $ResourceGroupName --location $Location
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: No se pudo crear el Resource Group" -ForegroundColor Red
        exit 1
    }
    Write-Host "✓ Resource Group creado" -ForegroundColor Green
} else {
    Write-Host "✓ Resource Group existe" -ForegroundColor Green
}

# Verificar si el Container Apps Environment existe
Write-Host ""
Write-Host "Verificando Container Apps Environment..." -ForegroundColor Yellow
$envExists = az containerapp env show --name $EnvironmentName --resource-group $ResourceGroupName --query "name" -o tsv 2>$null
if (-not $envExists) {
    Write-Host "Creando Container Apps Environment: $EnvironmentName" -ForegroundColor Cyan
    az containerapp env create `
        --name $EnvironmentName `
        --resource-group $ResourceGroupName `
        --location $Location
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: No se pudo crear el Container Apps Environment" -ForegroundColor Red
        exit 1
    }
    Write-Host "✓ Container Apps Environment creado" -ForegroundColor Green
} else {
    Write-Host "✓ Container Apps Environment existe" -ForegroundColor Green
}

# Verificar si ya existe un despliegue
Write-Host ""
Write-Host "Verificando despliegues existentes..." -ForegroundColor Yellow
$existingDeploy = az containerapp compose show --resource-group $ResourceGroupName --environment $EnvironmentName --query "name" -o tsv 2>$null

if ($existingDeploy) {
    Write-Host "Actualizando despliegue existente..." -ForegroundColor Cyan
    az containerapp compose update `
        --compose-file-path $ComposeFile `
        --resource-group $ResourceGroupName `
        --environment $EnvironmentName
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✓ Despliegue actualizado exitosamente" -ForegroundColor Green
    } else {
        Write-Host "ERROR: No se pudo actualizar el despliegue" -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "Creando nuevo despliegue..." -ForegroundColor Cyan
    az containerapp compose create `
        --compose-file-path $ComposeFile `
        --resource-group $ResourceGroupName `
        --environment $EnvironmentName
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✓ Despliegue creado exitosamente" -ForegroundColor Green
    } else {
        Write-Host "ERROR: No se pudo crear el despliegue" -ForegroundColor Red
        exit 1
    }
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "Despliegue completado" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Para ver el estado de los contenedores:" -ForegroundColor Cyan
Write-Host "az containerapp list --resource-group $ResourceGroupName --query '[].{Name:name, Status:properties.runningStatus}' -o table" -ForegroundColor White
Write-Host ""
Write-Host "Para ver los logs de la aplicación:" -ForegroundColor Cyan
Write-Host "az containerapp logs show --name breeza-app --resource-group $ResourceGroupName --follow" -ForegroundColor White
Write-Host ""
Write-Host "Para obtener la URL de la aplicación:" -ForegroundColor Cyan
Write-Host "az containerapp show --name breeza-app --resource-group $ResourceGroupName --query 'properties.configuration.ingress.fqdn' -o tsv" -ForegroundColor White
Write-Host ""

