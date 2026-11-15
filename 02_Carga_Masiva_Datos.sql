
/* ----------------------------------------------------------------------
   Proyecto de Cátedra - Administración de Bases de Datos (SQL Server)
   Script 02: Carga masiva de datos (BULK INSERT desde CSV) y Backup
  -----------------------------------------------------------------------*/

USE GimnasioDB;
GO

SET NOCOUNT ON;
GO

/* ---------------------------------------------------------------------
1. CARGA MASIVA (orden de dependencias)
   --------------------------------------------------------------------- */
DECLARE @ruta NVARCHAR(260) = N'/var/opt/mssql/backup_data/';

DECLARE @cargas TABLE (orden INT PRIMARY KEY,
    tabla SYSNAME,
    archivo NVARCHAR(100));
INSERT INTO @cargas
    (orden, tabla, archivo)
VALUES
    ( 1, N'Gestion.Especialidad', N'especialidad.csv'),
    ( 2, N'Gestion.Entrenador', N'entrenador.csv'),
    ( 3, N'Gestion.EntrenadorEspecialidad', N'entrenador_especialidad.csv'),
    ( 4, N'Finanzas.Membresia', N'membresia.csv'),
    ( 5, N'Finanzas.MetodoPago', N'metodo_pago.csv'),
    ( 6, N'Operacion.Clase', N'clase.csv'),
    ( 7, N'Operacion.Sala', N'sala.csv'),
    ( 8, N'Gestion.Socio', N'socio.csv'),
    ( 9, N'Finanzas.Suscripcion', N'suscripcion.csv'),
    (10, N'Finanzas.Pago', N'pago.csv'),
    (11, N'Operacion.Sesion', N'sesion.csv'),
    (12, N'Operacion.Reserva', N'reserva.csv');

DECLARE @i INT = 1, @n INT = (SELECT COUNT(*)
FROM @cargas);
DECLARE @tabla SYSNAME, @archivo NVARCHAR(100), @sql NVARCHAR(MAX), @t0 DATETIME2(3);

BEGIN TRY
    WHILE @i <= @n
    BEGIN
    SELECT @tabla = tabla, @archivo = archivo
    FROM @cargas
    WHERE orden = @i;

    SET @sql = N'BULK INSERT ' + @tabla + N'
            FROM ''' + @ruta + @archivo + N'''
            WITH (
                FORMAT = ''CSV'',
                FIRSTROW = 2,
                FIELDTERMINATOR = '','',
                ROWTERMINATOR = ''0x0a'',
                KEEPIDENTITY,
                KEEPNULLS,
                CHECK_CONSTRAINTS,
                TABLOCK,
                BATCHSIZE = 100000
            );';

    SET @t0 = SYSDATETIME();
    PRINT 'Cargando ' + @tabla + ' <- ' + @archivo;
    EXEC sys.sp_executesql @sql;
    PRINT '     listo en ' + CAST(DATEDIFF(MILLISECOND, @t0, SYSDATETIME()) AS VARCHAR(12)) + ' ms';

    SET @i += 1;
END
END TRY
BEGIN CATCH
    PRINT 'ERROR cargando ' + ISNULL(@tabla, '?') + ': ' + ERROR_MESSAGE();
    THROW;
END CATCH
GO

/* ---------------------------------------------------------------------
2. POST-CARGA: 
   --------------------------------------------------------------------- */
ALTER DATABASE GimnasioDB SET RECOVERY FULL;
GO

BACKUP DATABASE GimnasioDB
TO DISK = N'/var/opt/mssql/data/GimnasioDB_postcarga.bak'
WITH INIT, COMPRESSION, STATS = 10;
GO

PRINT 'Carga masiva y respaldo completados con éxito.';
GO