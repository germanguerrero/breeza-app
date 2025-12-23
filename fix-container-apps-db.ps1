# Script para obtener el FQDN del Container App de MySQL y actualizar la configuración
# Ejecuta este script DESPUÉS de desplegar con docker-compose

param(
    [Parameter(Mandatory=$true)]
    [string]$ResourceGroupName,
    
    [Parameter(Mandatory=$false)]
    [string]$DbContainerAppName = "breeza-mysql",
    
    [Parameter(Mandatory=$false)]
    [string]$AppContainerAppName = "breeza-app"
)

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Configuración de conexión DB para Container Apps" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Obtener el FQDN del Container App de MySQL
Write-Host "Obteniendo FQDN del Container App de MySQL..." -ForegroundColor Yellow
$dbFqdn = az containerapp show `
    --name $DbContainerAppName `
    --resource-group $ResourceGroupName `
    --query "properties.configuration.ingress.fqdn" `
    -o tsv 2>$null

if (-not $dbFqdn -or $dbFqdn -eq "") {
    Write-Host "ERROR: No se pudo obtener el FQDN del Container App de MySQL" -ForegroundColor Red
    Write-Host "Verifica que el Container App '$DbContainerAppName' existe y tiene ingress configurado" -ForegroundColor Yellow
    exit 1
}

Write-Host "✓ FQDN de MySQL: $dbFqdn" -ForegroundColor Green
Write-Host ""

# Actualizar la variable de entorno DB_HOST en el Container App de la aplicación
Write-Host "Actualizando variable de entorno DB_HOST en el Container App de la aplicación..." -ForegroundColor Yellow

# Obtener las variables de entorno actuales
$currentEnv = az containerapp show `
    --name $AppContainerAppName `
    --resource-group $ResourceGroupName `
    --query "properties.template.containers[0].env" `
    -o json

# Convertir a objeto PowerShell
$envVars = $currentEnv | ConvertFrom-Json

# Buscar si DB_HOST ya existe
$dbHostExists = $false
foreach ($envVar in $envVars) {
    if ($envVar.name -eq "DB_HOST") {
        $envVar.value = $dbFqdn
        $dbHostExists = $true
        break
    }
}

# Si no existe, agregarlo
if (-not $dbHostExists) {
    $newEnvVar = @{
        name = "DB_HOST"
        value = $dbFqdn
    }
    $envVars += $newEnvVar
}

# Actualizar el Container App
$envJson = $envVars | ConvertTo-Json -Compress

az containerapp update `
    --name $AppContainerAppName `
    --resource-group $ResourceGroupName `
    --set-env-vars $envJson `
    --output none

if ($LASTEXITCODE -eq 0) {
    Write-Host "✓ Variable DB_HOST actualizada exitosamente" -ForegroundColor Green
} else {
    Write-Host "⚠ Error al actualizar. Intenta manualmente:" -ForegroundColor Yellow
    Write-Host "az containerapp update --name $AppContainerAppName --resource-group $ResourceGroupName --set-env-vars DB_HOST=$dbFqdn" -ForegroundColor White
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "Configuración completada" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "El Container App de la aplicación ahora se conectará a MySQL usando:" -ForegroundColor Cyan
Write-Host "DB_HOST=$dbFqdn" -ForegroundColor White
Write-Host ""
Write-Host "Nota: Puede tomar unos minutos para que los cambios surtan efecto." -ForegroundColor Yellow
Write-Host ""

