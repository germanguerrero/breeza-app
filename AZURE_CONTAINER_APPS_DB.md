# Solución para conexión a MySQL en Azure Container Apps

## Problema asasasasasasasas

En Azure Container Apps, cuando usas `docker-compose`, cada servicio se despliega como un **Container App independiente**. A diferencia de Docker Compose local, **NO hay resolución DNS automática** por nombre de servicio.

El error `Can't connect to MySQL server on 'db' ([Errno -2] Name or service not known)` ocurre porque el nombre `db` no se resuelve en Azure Container Apps.

## Soluciones

### Solución 1: Usar Ingress Interno (Recomendada)

1. **MySQL debe tener ingress interno configurado** (ya está en `docker-compose.azure.yml`)

2. **Después del despliegue**, obtén el FQDN del Container App de MySQL:
```powershell
az containerapp show --name breeza-mysql --resource-group <tu-rg> --query "properties.configuration.ingress.fqdn" -o tsv
```

3. **Actualiza la variable DB_HOST** en el Container App de la aplicación:
```powershell
az containerapp update --name breeza-app --resource-group <tu-rg> --set-env-vars DB_HOST=<fqdn-obtenido>
```

O usa el script automático:
```powershell
.\fix-container-apps-db.ps1 -ResourceGroupName <tu-rg>
```

### Solución 2: Usar Azure Database for MySQL (Más robusta)

En lugar de MySQL en un contenedor, usa **Azure Database for MySQL Flexible Server**:

1. Crea una instancia de Azure Database for MySQL
2. Actualiza `DATABASE_URL` con la cadena de conexión de Azure:
```
mysql+pymysql://usuario:password@<server-name>.mysql.database.azure.com:3306/breeza_db
```

### Solución 3: Configurar en docker-compose antes del despliegue

Si conoces el nombre que Azure asignará, puedes usar variables de entorno:

```yaml
environment:
  - DB_HOST=${DB_CONTAINER_APP_FQDN}
```

Y luego configurar la variable antes del despliegue.

## Pasos Inmediatos

1. **Verifica que MySQL tenga ingress interno**:
```powershell
az containerapp show --name breeza-mysql --resource-group <tu-rg> --query "properties.configuration.ingress"
```

2. **Obtén el FQDN de MySQL**:
```powershell
$dbFqdn = az containerapp show --name breeza-mysql --resource-group <tu-rg> --query "properties.configuration.ingress.fqdn" -o tsv
echo $dbFqdn
```

3. **Actualiza DB_HOST en la app**:
```powershell
az containerapp update --name breeza-app --resource-group <tu-rg> --set-env-vars DB_HOST=$dbFqdn
```

4. **Verifica la conexión** revisando los logs:
```powershell
az containerapp logs show --name breeza-app --resource-group <tu-rg> --follow
```

## Nota Importante

El `app.py` ya está configurado para usar `DB_HOST` de las variables de entorno, así que solo necesitas actualizar esa variable después del despliegue.

