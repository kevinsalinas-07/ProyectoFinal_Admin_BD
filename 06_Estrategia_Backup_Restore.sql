/* ------------------------------------------------------------------------
   Proyecto de Cátedra - Administración de Bases de Datos 
   Script 06: Estrategia de Backup y Cadena de Restauración 
    ----------------------------------------------------------------------*/

USE master;
GO

-- 1. Asegurar el modelo de recuperación adecuado para backups de transacciones
ALTER DATABASE GimnasioDB SET RECOVERY FULL;
GO

/* ---------------------------------------------------------------------
   2. CONFIGURACIÓN DE RUTAS DINÁMICAS
   --------------------------------------------------------------------- */
DECLARE @sep NCHAR(1) = N'/';
DECLARE @ruta  NVARCHAR(260) = CAST(SERVERPROPERTY('InstanceDefaultBackupPath') AS NVARCHAR(260));
DECLARE @dpath NVARCHAR(260) = CAST(SERVERPROPERTY('InstanceDefaultDataPath')   AS NVARCHAR(260));
DECLARE @lpath NVARCHAR(260) = CAST(SERVERPROPERTY('InstanceDefaultLogPath')    AS NVARCHAR(260));

IF @ruta LIKE N'%\%' SET @sep = N'\';
IF RIGHT(@ruta,  1) NOT IN (N'/', N'\') SET @ruta  += @sep;
IF RIGHT(@dpath, 1) NOT IN (N'/', N'\') SET @dpath += @sep;
IF RIGHT(@lpath, 1) NOT IN (N'/', N'\') SET @lpath += @sep;

DECLARE @full NVARCHAR(400) = @ruta + N'GimnasioDB_FULL.bak';
DECLARE @dif  NVARCHAR(400) = @ruta + N'GimnasioDB_DIFF.bak';
DECLARE @log1 NVARCHAR(400) = @ruta + N'GimnasioDB_LOG1.trn';
DECLARE @log2 NVARCHAR(400) = @ruta + N'GimnasioDB_LOG2.trn';
DECLARE @mdf  NVARCHAR(400) = @dpath + N'GimnasioDB_Restore.mdf';
DECLARE @ldf  NVARCHAR(400) = @lpath + N'GimnasioDB_Restore_log.ldf';

DECLARE @ln_datos SYSNAME = (SELECT name
FROM sys.master_files
WHERE database_id = DB_ID(N'GimnasioDB') AND type = 0);
DECLARE @ln_log   SYSNAME = (SELECT name
FROM sys.master_files
WHERE database_id = DB_ID(N'GimnasioDB') AND type = 1);

/* ---------------------------------------------------------------------
   3. EJECUCIÓN MANUAL DE LA ESTRATEGIA (Automatizado vía SQL Agent)
   --------------------------------------------------------------------- */
-- Backup Completo (Ejecutado domingos)
BACKUP DATABASE GimnasioDB TO DISK = @full
    WITH COMPRESSION, CHECKSUM, INIT, NAME = N'GimnasioDB - FULL';

-- Backup Diferencial (Ejecutado lunes a sábado)
BACKUP DATABASE GimnasioDB TO DISK = @dif
    WITH DIFFERENTIAL, COMPRESSION, CHECKSUM, INIT, NAME = N'GimnasioDB - DIFF';

-- Backups de Log (Ejecutado cada 15 minutos para cumplir RPO)
BACKUP LOG GimnasioDB TO DISK = @log1
    WITH COMPRESSION, CHECKSUM, INIT, NAME = N'GimnasioDB - LOG 1';

BACKUP LOG GimnasioDB TO DISK = @log2
    WITH COMPRESSION, CHECKSUM, INIT, NAME = N'GimnasioDB - LOG 2';

/* ---------------------------------------------------------------------
   4. CADENA DE RESTAURACIÓN POINT-IN-TIME 
   --------------------------------------------------------------------- */
-- Definir el instante exacto al que se desea regresar (antes del fallo)
DECLARE @t_recuperacion DATETIME = DATEADD(minute, -5, GETDATE());

-- Verificar la integridad del backup base
RESTORE VERIFYONLY FROM DISK = @full WITH CHECKSUM;

-- 4.1 Restaurar Full 
RESTORE DATABASE GimnasioDB_Restore FROM DISK = @full
    WITH MOVE @ln_datos TO @mdf, MOVE @ln_log TO @ldf, 
    NORECOVERY, REPLACE, STATS = 50;

-- 4.2 Restaurar último Diferencial
RESTORE DATABASE GimnasioDB_Restore FROM DISK = @dif WITH NORECOVERY;

-- 4.3 Restaurar cadena de logs hasta el momento del fallo 
RESTORE LOG GimnasioDB_Restore FROM DISK = @log1 WITH NORECOVERY;
RESTORE LOG GimnasioDB_Restore FROM DISK = @log2 WITH STOPAT = @t_recuperacion, RECOVERY;
GO