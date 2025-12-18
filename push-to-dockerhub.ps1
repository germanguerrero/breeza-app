# Script para subir la imagen a Docker Hub
# Uso: .\push-to-dockerhub.ps1 -DockerHubUser "tu_usuario"

param(
    [Parameter(Mandatory=$true)]
    [string]$DockerHubUser,
    [string]$ImageName = "breeza-app",
    [string]$Tag = "latest"
)

Write-Host "=== Subiendo imagen a Docker Hub ===" -ForegroundColor Cyan
Write-Host "Usuario: $DockerHubUser" -ForegroundColor Yellow
Write-Host "Imagen: $ImageName" -ForegroundColor Yellow
Write-Host "Tag: $Tag" -ForegroundColor Yellow
Write-Host ""

# 1. Login a Docker Hub
Write-Host "1. Iniciando sesión en Docker Hub..." -ForegroundColor Green
docker login
if ($LASTEXITCODE -ne 0) {
    Write-Host "Error: No se pudo iniciar sesión en Docker Hub" -ForegroundColor Red
    exit 1
}

# 2. Etiquetar la imagen
$FullImageName = "${DockerHubUser}/${ImageName}:${Tag}"
Write-Host "2. Etiquetando imagen como: $FullImageName" -ForegroundColor Green
docker tag ${ImageName}:${Tag} $FullImageName
if ($LASTEXITCODE -ne 0) {
    Write-Host "Error: No se pudo etiquetar la imagen" -ForegroundColor Red
    exit 1
}

# 3. Subir la imagen
Write-Host "3. Subiendo imagen a Docker Hub..." -ForegroundColor Green
docker push $FullImageName
if ($LASTEXITCODE -ne 0) {
    Write-Host "Error: No se pudo subir la imagen" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "¡Éxito! Imagen subida a Docker Hub" -ForegroundColor Green
Write-Host "Puedes descargarla con: docker pull $FullImageName" -ForegroundColor Cyan

