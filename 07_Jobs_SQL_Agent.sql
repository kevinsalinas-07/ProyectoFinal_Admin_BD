/* -----------------------------------------------------------------------
   Proyecto de Cátedra - Administración de Bases de Datos (SQL Server)
   Script 07: automatización de backups con jobs de SQL Agent
   ----------------------------------------------------------------------*/

USE GimnasioDB;
GO

/* ---------------------------------------------------------------------
1. PROCEDIMIENTO DE BACKUP 
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dbo.usp_BackupGimnasio
    @tipo VARCHAR(4)
-- 'FULL' | 'DIFF' | 'LOG'
AS
BEGIN
    SET NOCOUNT ON;

    IF @tipo NOT IN ('FULL', 'DIFF', 'LOG')
        THROW 50001, 'Tipo invalido. Use FULL, DIFF o LOG.', 1;

    IF @tipo IN ('DIFF', 'LOG')
        AND NOT EXISTS (SELECT 1
        FROM msdb.dbo.backupset
        WHERE database_name = N'GimnasioDB' AND type = 'D')
        THROW 50002, 'No existe un backup FULL previo. Ejecute primero el job GimnasioDB_Backup_Full.', 1;

    IF @tipo = 'LOG' AND DATABASEPROPERTYEX(N'GimnasioDB', 'Recovery') <> 'FULL'
        THROW 50003, 'La base no esta en modelo de recuperacion FULL: no admite backups de log.', 1;

    DECLARE @sep NCHAR(1) = N'/';
    DECLARE @ruta NVARCHAR(260) = CAST(SERVERPROPERTY('InstanceDefaultBackupPath') AS NVARCHAR(260));
    IF @ruta LIKE N'%\%' SET @sep = N'\';
    IF RIGHT(@ruta, 1) NOT IN (N'/', N'\') SET @ruta += @sep;

    DECLARE @ts NVARCHAR(20) = CONVERT(CHAR(8), GETDATE(), 112) + N'_' + REPLACE(CONVERT(CHAR(8), GETDATE(), 108), ':', '');
    DECLARE @archivo NVARCHAR(400) = @ruta + N'GimnasioDB_' + @tipo + N'_' + @ts
                                   + CASE WHEN @tipo = 'LOG' THEN N'.trn' ELSE N'.bak' END;
    DECLARE @nombre NVARCHAR(128) = N'GimnasioDB - ' + @tipo + N' ' + @ts;

    IF @tipo = 'FULL'
        BACKUP DATABASE GimnasioDB TO DISK = @archivo
            WITH COMPRESSION, CHECKSUM, INIT, NAME = @nombre;
    ELSE IF @tipo = 'DIFF'
        BACKUP DATABASE GimnasioDB TO DISK = @archivo
            WITH DIFFERENTIAL, COMPRESSION, CHECKSUM, INIT, NAME = @nombre;
    ELSE
        BACKUP LOG GimnasioDB TO DISK = @archivo
            WITH COMPRESSION, CHECKSUM, INIT, NAME = @nombre;

    RESTORE VERIFYONLY FROM DISK = @archivo WITH CHECKSUM;

    PRINT 'Backup ' + @tipo + ' generado y verificado: ' + @archivo;
END
GO

/* ---------------------------------------------------------------------
   2. JOBS EN SQL AGENT 
   --------------------------------------------------------------------- */
USE msdb;
GO

-- 2.1 FULL: domingo 02:00
IF EXISTS (SELECT 1
FROM msdb.dbo.sysjobs
WHERE name = N'GimnasioDB_Backup_Full')
    EXEC msdb.dbo.sp_delete_job @job_name = N'GimnasioDB_Backup_Full', @delete_unused_schedule = 1;

EXEC msdb.dbo.sp_add_job
    @job_name = N'GimnasioDB_Backup_Full',
    @enabled = 1,
    @description = N'Backup completo semanal de GimnasioDB (base de la cadena de restauracion).',
    @owner_login_name = N'sa';
EXEC msdb.dbo.sp_add_jobstep
    @job_name = N'GimnasioDB_Backup_Full',
    @step_name = N'Backup FULL',
    @subsystem = N'TSQL',
    @database_name = N'GimnasioDB',
    @command = N'EXEC dbo.usp_BackupGimnasio @tipo = ''FULL'';',
    @retry_attempts = 1, @retry_interval = 5;
EXEC msdb.dbo.sp_add_jobschedule
    @job_name = N'GimnasioDB_Backup_Full',
    @name = N'Domingo 02:00',
    @freq_type = 8,                 -- semanal
    @freq_interval = 1,             -- domingo
    @freq_recurrence_factor = 1,    -- cada semana
    @active_start_time = 20000;
-- 02:00:00
EXEC msdb.dbo.sp_add_jobserver @job_name = N'GimnasioDB_Backup_Full', @server_name = N'(local)';
GO

-- 2.2 DIFERENCIAL: lunes a sábado 02:00
IF EXISTS (SELECT 1
FROM msdb.dbo.sysjobs
WHERE name = N'GimnasioDB_Backup_Diferencial')
    EXEC msdb.dbo.sp_delete_job @job_name = N'GimnasioDB_Backup_Diferencial', @delete_unused_schedule = 1;

EXEC msdb.dbo.sp_add_job
    @job_name = N'GimnasioDB_Backup_Diferencial',
    @enabled = 1,
    @description = N'Backup diferencial diario: acorta la cadena de restauracion.',
    @owner_login_name = N'sa';
EXEC msdb.dbo.sp_add_jobstep
    @job_name = N'GimnasioDB_Backup_Diferencial',
    @step_name = N'Backup DIFERENCIAL',
    @subsystem = N'TSQL',
    @database_name = N'GimnasioDB',
    @command = N'EXEC dbo.usp_BackupGimnasio @tipo = ''DIFF'';',
    @retry_attempts = 1, @retry_interval = 5;
EXEC msdb.dbo.sp_add_jobschedule
    @job_name = N'GimnasioDB_Backup_Diferencial',
    @name = N'Lunes a sabado 02:00',
    @freq_type = 8,                 -- semanal
    @freq_interval = 126,           -- lun(2)+mar(4)+mie(8)+jue(16)+vie(32)+sab(64)
    @freq_recurrence_factor = 1,
    @active_start_time = 20000;
EXEC msdb.dbo.sp_add_jobserver @job_name = N'GimnasioDB_Backup_Diferencial', @server_name = N'(local)';
GO

-- 2.3 LOG: cada 15 minutos 
IF EXISTS (SELECT 1
FROM msdb.dbo.sysjobs
WHERE name = N'GimnasioDB_Backup_Log')
    EXEC msdb.dbo.sp_delete_job @job_name = N'GimnasioDB_Backup_Log', @delete_unused_schedule = 1;

EXEC msdb.dbo.sp_add_job
    @job_name = N'GimnasioDB_Backup_Log',
    @enabled = 1,
    @description = N'Backup del log de transacciones cada 15 minutos (RPO = 15 min).',
    @owner_login_name = N'sa';
EXEC msdb.dbo.sp_add_jobstep
    @job_name = N'GimnasioDB_Backup_Log',
    @step_name = N'Backup LOG',
    @subsystem = N'TSQL',
    @database_name = N'GimnasioDB',
    @command = N'EXEC dbo.usp_BackupGimnasio @tipo = ''LOG'';';
EXEC msdb.dbo.sp_add_jobschedule
    @job_name = N'GimnasioDB_Backup_Log',
    @name = N'Cada 15 minutos',
    @freq_type = 4,                 -- diario
    @freq_interval = 1,
    @freq_subday_type = 4,          -- unidad: minutos
    @freq_subday_interval = 15,
    @active_start_time = 0;
-- desde 00:00:00
EXEC msdb.dbo.sp_add_jobserver @job_name = N'GimnasioDB_Backup_Log', @server_name = N'(local)';
GO