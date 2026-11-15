/* ---------------------------------------------------------------------
   Proyecto de Cátedra - Administración de Bases de Datos
   Script 05: Consultas avanzadas (funciones ventana) e índices de apoyo
   --------------------------------------------------------------------- */

USE GimnasioDB;
GO

/* ---------------------------------------------------------------------
   1. CONSULTAS AVANZADAS COMO FUNCIONES 
   --------------------------------------------------------------------- */

-- Q1: Ranking de clases por mes (RANK + SUM OVER)
CREATE OR ALTER FUNCTION dbo.fn_ranking_clases_mes (@desde DATE, @hasta DATE)
RETURNS TABLE AS RETURN
(
    WITH
    m
    AS
    (
        SELECT YEAR(s.fecha) AS anio, MONTH(s.fecha) AS mes, c.nombre AS clase, COUNT(*) AS reservas
        FROM Operacion.Reserva r
            JOIN Operacion.Sesion s ON s.id_sesion = r.id_sesion
            JOIN Operacion.Clase  c ON c.id_clase  = s.id_clase
        WHERE r.estado = 'Confirmada' AND s.fecha >= @desde AND s.fecha < @hasta
        GROUP BY YEAR(s.fecha), MONTH(s.fecha), c.nombre
    )
    SELECT anio, mes, clase, reservas,
    RANK() OVER (PARTITION BY anio, mes ORDER BY reservas DESC) AS ranking,
    CAST(100.0 * reservas / SUM(reservas) OVER (PARTITION BY anio, mes) AS DECIMAL(5,2)) AS pct_mes
FROM m
);
GO

-- Q2: Ingresos mensuales, acumulado anual y variación vs mes anterior.
CREATE OR ALTER FUNCTION dbo.fn_ingresos_mensuales (@desde DATE, @hasta DATE)
RETURNS TABLE AS RETURN
(
    WITH
    i
    AS
    (
        SELECT YEAR(fecha_pago) AS anio, MONTH(fecha_pago) AS mes, SUM(monto) AS total, COUNT(*) AS pagos
        FROM Finanzas.Pago
        WHERE fecha_pago >= @desde AND fecha_pago < @hasta
        GROUP BY YEAR(fecha_pago), MONTH(fecha_pago)
    )
    SELECT anio, mes, total, pagos,
    SUM(total) OVER (PARTITION BY anio ORDER BY mes ROWS UNBOUNDED PRECEDING) AS acumulado_anio,
    LAG(total) OVER (ORDER BY anio, mes) AS mes_anterior,
    CAST(100.0 * (total - LAG(total) OVER (ORDER BY anio, mes))
                / NULLIF(LAG(total) OVER (ORDER BY anio, mes), 0) AS DECIMAL(7,2)) AS variacion_pct
FROM i
);
GO

-- Q3: Socios activos por cuartil de asistencia
CREATE OR ALTER FUNCTION dbo.fn_socios_cuartil_asistencia (@desde DATE, @hasta DATE)
RETURNS TABLE AS RETURN
(
    WITH
    a
    AS
    (
        SELECT r.id_socio, COUNT(*) AS asistencias
        FROM Operacion.Reserva r
            JOIN Operacion.Sesion s ON s.id_sesion = r.id_sesion
        WHERE r.asistio = 1 AND s.fecha >= @desde AND s.fecha < @hasta
        GROUP BY r.id_socio
    ),
    b
    AS
    (
        SELECT so.id_socio, so.nombre + ' ' + so.apellido AS socio, COALESCE(a.asistencias, 0) AS asistencias
        FROM Gestion.Socio so
            LEFT JOIN a ON a.id_socio = so.id_socio
        WHERE so.estado = 'Activo'
    )
    SELECT id_socio, socio, asistencias,
    NTILE(4) OVER (ORDER BY asistencias DESC) AS cuartil,
    ROW_NUMBER() OVER (ORDER BY asistencias DESC, id_socio) AS posicion
FROM b
);
GO

/* ---------------------------------------------------------------------
   2. ÍNDICES DE APOYO PARA OPTIMIZACIÓN
   --------------------------------------------------------------------- */

DROP INDEX IF EXISTS IX_Sesion_Fecha   ON Operacion.Sesion;
DROP INDEX IF EXISTS IX_Reserva_Sesion ON Operacion.Reserva;
DROP INDEX IF EXISTS IX_Pago_Fecha     ON Finanzas.Pago;
DROP INDEX IF EXISTS IX_Socio_Estado   ON Gestion.Socio;
GO

CREATE NONCLUSTERED INDEX IX_Sesion_Fecha   ON Operacion.Sesion  (fecha)      INCLUDE (id_clase);
CREATE NONCLUSTERED INDEX IX_Reserva_Sesion ON Operacion.Reserva (id_sesion)  INCLUDE (id_socio, estado, asistio);
CREATE NONCLUSTERED INDEX IX_Pago_Fecha     ON Finanzas.Pago     (fecha_pago) INCLUDE (monto);
CREATE NONCLUSTERED INDEX IX_Socio_Estado   ON Gestion.Socio     (estado)     INCLUDE (nombre, apellido);
GO

UPDATE STATISTICS Operacion.Sesion;
UPDATE STATISTICS Operacion.Reserva;
UPDATE STATISTICS Finanzas.Pago;
UPDATE STATISTICS Gestion.Socio;
GO