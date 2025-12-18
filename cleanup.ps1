# Script para limpiar archivos innecesarios del proyecto
# Esto reducirá el tamaño del proyecto eliminando archivos que no deberían estar en el repositorio

Write-Host "Limpiando proyecto..." -ForegroundColor Yellow

# Eliminar mysql-data del índice de git si está rastreado
Write-Host "`nVerificando mysql-data en git..." -ForegroundColor Cyan
$mysqlDataTracked = git ls-files mysql-data/ 2>$null
if ($mysqlDataTracked) {
    Write-Host "Eliminando mysql-data del índice de git..." -ForegroundColor Yellow
    git rm -r --cached mysql-data/ 2>$null
    Write-Host "mysql-data eliminado del índice de git" -ForegroundColor Green
} else {
    Write-Host "mysql-data no está rastreado por git" -ForegroundColor Green
}

# Eliminar archivos Python compilados
Write-Host "`nLimpiando archivos Python compilados..." -ForegroundColor Cyan
Get-ChildItem -Recurse -Include __pycache__,*.pyc,*.pyo,*.pyd -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
Write-Host "Archivos Python compilados eliminados" -ForegroundColor Green

# Eliminar archivos temporales
Write-Host "`nLimpiando archivos temporales..." -ForegroundColor Cyan
Get-ChildItem -Recurse -Include *.log,*.tmp,*.swp,*.swo,*~ -Force -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
Write-Host "Archivos temporales eliminados" -ForegroundColor Green

# Calcular tamaño final
Write-Host "`nCalculando tamaño del proyecto..." -ForegroundColor Cyan
$totalSize = (Get-ChildItem -Recurse -File -ErrorAction SilentlyContinue | 
    Where-Object { $_.FullName -notmatch '\\mysql-data\\' } | 
    Measure-Object -Property Length -Sum).Sum
$sizeMB = [math]::Round($totalSize / 1MB, 2)

Write-Host "`n========================================" -ForegroundColor Green
Write-Host "Tamaño del proyecto (sin mysql-data): $sizeMB MB" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green

if ($sizeMB -lt 250) {
    Write-Host "`n✓ El proyecto ahora ocupa menos de 250MB!" -ForegroundColor Green
} else {
    Write-Host "`n⚠ El proyecto aún ocupa más de 250MB. Revisa otros archivos grandes." -ForegroundColor Yellow
}

Write-Host "`nNota: mysql-data/ sigue existiendo localmente pero ya no está en el repositorio." -ForegroundColor Cyan
Write-Host "Si quieres eliminarlo completamente, ejecuta: Remove-Item -Recurse -Force mysql-data" -ForegroundColor Cyan

