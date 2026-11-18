/* --------------------------------------------------------------------
   Proyecto de Cátedra - Administración de Bases de Datos
   Script 08: Medición de almacenamiento real para el dimensionamiento
   -------------------------------------------------------------------- */

USE GimnasioDB;
GO

/* ---------------------------------------------------------------------
   1. RESUMEN GENERAL DE LA BASE DE DATOS
   Obtiene el tamaño total asignado y el espacio no asignado
   --------------------------------------------------------------------- */
PRINT '=== TAMAÑO TOTAL DE LA BASE DE DATOS ===';
EXEC sp_spaceused;
GO

/* ---------------------------------------------------------------------
   2. TAMAÑO FÍSICO DE LOS ARCHIVOS (.mdf y .ldf)
   --------------------------------------------------------------------- */
PRINT '=== TAMAÑO FÍSICO POR ARCHIVO ===';
SELECT
   name AS archivo,
   type_desc AS tipo,
   CAST(size * 8 / 1024.0 AS DECIMAL(10,2)) AS tamano_MB,
   physical_name AS ruta_fisica
FROM sys.master_files
WHERE database_id = DB_ID('GimnasioDB');
GO

/* ---------------------------------------------------------------------
   3. DESGLOSE DEL TAMAÑO POR TABLA E ÍNDICES*/
PRINT '=== TAMAÑO REAL RESERVADO POR TABLA E ÍNDICES ===';
SELECT
   s.name + '.' + t.name AS tabla,
   SUM(CASE WHEN ps.index_id IN (0, 1) THEN ps.row_count END) AS filas,
   CAST(SUM(CASE WHEN ps.index_id IN (0, 1) THEN ps.reserved_page_count ELSE 0 END) * 8 / 1024.0 AS DECIMAL(10, 2)) AS MB_datos,
   CAST(SUM(CASE WHEN ps.index_id > 1 THEN ps.reserved_page_count ELSE 0 END) * 8 / 1024.0 AS DECIMAL(10, 2)) AS MB_indices,
   CAST(SUM(ps.reserved_page_count) * 8 / 1024.0 AS DECIMAL(10, 2)) AS MB_total
FROM sys.dm_db_partition_stats ps
   JOIN sys.tables t ON t.object_id = ps.object_id
   JOIN sys.schemas s ON s.schema_id = t.schema_id
WHERE s.name IN ('Gestion', 'Operacion', 'Finanzas')
GROUP BY s.name, t.name
ORDER BY MB_total DESC;
GO