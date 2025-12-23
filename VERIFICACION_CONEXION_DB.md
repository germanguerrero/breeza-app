# Verificación de Conexión a Base de Datos

## Configuración Actual

### FQDN Interno de MySQL
```
db.internal.gentleflower-2dc849cd.eastus.azurecontainerapps.io
```

### Variables de Entorno Configuradas
- `DB_HOST`: db.internal.gentleflower-2dc849cd.eastus.azurecontainerapps.io
- `DB_PORT`: 3306
- `DB_NAME`: breeza_db
- `DB_USER`: breeza_user
- `DB_PASSWORD`: breeza_pass_2025

### Cómo funciona app.py

El archivo `app.py` construye automáticamente la `DATABASE_URL` desde estas variables:

```python
db_host = os.environ.get('DB_HOST', 'db')
db_port = os.environ.get('DB_PORT', '3306')
db_name = os.environ.get('DB_NAME', 'breeza_db')
db_user = os.environ.get('DB_USER', 'breeza_user')
db_password = os.environ.get('DB_PASSWORD', 'breeza_pass_2025')
database_uri = f'mysql+pymysql://{db_user}:{db_password}@{db_host}:{db_port}/{db_name}'
```

Esto generará:
```
mysql+pymysql://breeza_user:breeza_pass_2025@db.internal.gentleflower-2dc849cd.eastus.azurecontainerapps.io:3306/breeza_db
```

## Verificación

### 1. Verificar que el Container App de MySQL tiene ingress interno

```powershell
az containerapp show --name breeza-mysql --resource-group <tu-rg> --query "properties.configuration.ingress"
```

Deberías ver:
- `external: false`
- `targetPort: 3306`
- `transport: tcp`

### 2. Verificar que la app tiene las variables de entorno correctas

```powershell
az containerapp show --name breeza-app --resource-group <tu-rg> --query "properties.template.containers[0].env[?name=='DB_HOST']"
```

Debería mostrar:
```json
{
  "name": "DB_HOST",
  "value": "db.internal.gentleflower-2dc849cd.eastus.azurecontainerapps.io"
}
```

### 3. Verificar conexión desde los logs

```powershell
az containerapp logs show --name breeza-app --resource-group <tu-rg> --follow
```

Busca mensajes como:
- `[INIT] Aplicación iniciada` - indica que la app arrancó
- Errores de conexión a MySQL - si los hay, aparecerán aquí

### 4. Probar conexión manualmente (opcional)

Si necesitas probar la conexión desde dentro del contenedor:

```powershell
# Ejecutar comando en el contenedor de la app
az containerapp exec --name breeza-app --resource-group <tu-rg> --command "/bin/bash"

# Dentro del contenedor, probar conexión:
mysql -h db.internal.gentleflower-2dc849cd.eastus.azurecontainerapps.io -u breeza_user -pbreeza_pass_2025 breeza_db
```

## Solución de Problemas

### Error: "Name or service not known"
- Verifica que el FQDN esté correcto
- Asegúrate de que MySQL tenga ingress interno configurado
- Verifica que ambos Container Apps estén en el mismo Environment

### Error: "Connection refused"
- Verifica que MySQL esté corriendo y saludable
- Verifica que el puerto 3306 esté abierto en el ingress interno
- Revisa los logs de MySQL: `az containerapp logs show --name breeza-mysql --resource-group <tu-rg>`

### Error: "Access denied"
- Verifica las credenciales (usuario, contraseña)
- Verifica que el usuario tenga permisos en la base de datos

## Notas Importantes

1. **FQDN Interno**: El formato es `<service-name>.internal.<environment-name>.<region>.azurecontainerapps.io`
2. **Ingress Interno**: Solo es accesible desde otros Container Apps en el mismo Environment
3. **Puerto**: MySQL usa el puerto 3306 por defecto
4. **Seguridad**: El ingress interno usa TCP, no HTTP, por lo que `allowInsecure: true` es necesario

