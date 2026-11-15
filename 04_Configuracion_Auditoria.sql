/* ----------------------------------------------------------------------
   Proyecto de Cátedra - Administración de Bases de Datos
   Script 04: Configuración de auditoría con SQL Server Audit
   ---------------------------------------------------------------------*/

--1. Limpieza para poder re-ejecutar 
USE GimnasioDB;
GO
IF EXISTS (SELECT 1
FROM sys.database_audit_specifications
WHERE name = 'Auditoria_Gimnasio_BD')
BEGIN
    ALTER DATABASE AUDIT SPECIFICATION Auditoria_Gimnasio_BD WITH (STATE = OFF);
    DROP DATABASE AUDIT SPECIFICATION Auditoria_Gimnasio_BD;
END
GO

USE master;
GO
IF EXISTS (SELECT 1
FROM sys.server_audit_specifications
WHERE name = 'Auditoria_Gimnasio_Servidor')
BEGIN
    ALTER SERVER AUDIT SPECIFICATION Auditoria_Gimnasio_Servidor WITH (STATE = OFF);
    DROP SERVER AUDIT SPECIFICATION Auditoria_Gimnasio_Servidor;
END

IF EXISTS (SELECT 1
FROM sys.server_audits
WHERE name = 'Auditoria_Gimnasio')
BEGIN
    ALTER SERVER AUDIT Auditoria_Gimnasio WITH (STATE = OFF);
    DROP SERVER AUDIT Auditoria_Gimnasio;
END
GO

/* 2. Server Audit: destino = archivos .sqlaudit en la ruta de datos de la instancia */
DECLARE @ruta NVARCHAR(260) = CAST(SERVERPROPERTY('InstanceDefaultDataPath') AS NVARCHAR(260));
IF RIGHT(@ruta, 1) NOT IN (N'/', N'\') SET @ruta += CASE WHEN @ruta LIKE N'%\%' THEN N'\' ELSE N'/' END;

DECLARE @sql NVARCHAR(MAX) = N'CREATE SERVER AUDIT Auditoria_Gimnasio
    TO FILE (FILEPATH = N''' + @ruta + N''', MAXSIZE = 50 MB, MAX_ROLLOVER_FILES = 5)
    WITH (QUEUE_DELAY = 1000, ON_FAILURE = CONTINUE);';
EXEC (@sql);
GO
ALTER SERVER AUDIT Auditoria_Gimnasio WITH (STATE = ON);
GO

/* 3. Especificación a nivel servidor: inicios de sesión fallidos y cambios de roles de servidor */
CREATE SERVER AUDIT SPECIFICATION Auditoria_Gimnasio_Servidor
FOR SERVER AUDIT Auditoria_Gimnasio
    ADD (FAILED_LOGIN_GROUP),
    ADD (SERVER_ROLE_MEMBER_CHANGE_GROUP)
WITH (STATE = ON);
GO

/* 4. Especificación a nivel base: datos sensibles (pagos, suscripciones, socios) y cambios de estructura/permisos */
USE GimnasioDB;
GO
CREATE DATABASE AUDIT SPECIFICATION Auditoria_Gimnasio_BD
FOR SERVER AUDIT Auditoria_Gimnasio
    ADD (INSERT, UPDATE, DELETE ON OBJECT::Finanzas.Pago         BY public),
    ADD (INSERT, UPDATE, DELETE ON OBJECT::Finanzas.Suscripcion  BY public),
    ADD (UPDATE, DELETE         ON OBJECT::Gestion.Socio         BY public),
    ADD (SCHEMA_OBJECT_CHANGE_GROUP),
    ADD (DATABASE_PERMISSION_CHANGE_GROUP),
    ADD (DATABASE_ROLE_MEMBER_CHANGE_GROUP)
WITH (STATE = ON);
GO