/* ----------------------------------------------------------------------
   Proyecto de Cátedra - Administración de Bases de Datos
   Script 03: logins, usuarios, roles por función y permisos por esquema 
   ----------------------------------------------------------------------- */

/* 1. Logins (nivel servidor) */
USE master;
GO
IF SUSER_ID('login_recepcion')   IS NULL CREATE LOGIN login_recepcion   WITH PASSWORD = 'Password_Recep2026*',   CHECK_POLICY = ON, CHECK_EXPIRATION = OFF;
IF SUSER_ID('login_entrenador')  IS NULL CREATE LOGIN login_entrenador  WITH PASSWORD = 'Password_Entren2026*',  CHECK_POLICY = ON, CHECK_EXPIRATION = OFF;
IF SUSER_ID('login_contabilidad') IS NULL CREATE LOGIN login_contabilidad WITH PASSWORD = 'Password_Conta2026*',   CHECK_POLICY = ON, CHECK_EXPIRATION = OFF;
IF SUSER_ID('login_gerencia')    IS NULL CREATE LOGIN login_gerencia    WITH PASSWORD = 'Password_Geren2026*',   CHECK_POLICY = ON, CHECK_EXPIRATION = OFF;
GO

/* 2. Usuarios de base de datos */
USE GimnasioDB;
GO
IF USER_ID('usr_recepcion')    IS NULL CREATE USER usr_recepcion    FOR LOGIN login_recepcion;
IF USER_ID('usr_entrenador')   IS NULL CREATE USER usr_entrenador   FOR LOGIN login_entrenador;
IF USER_ID('usr_contabilidad') IS NULL CREATE USER usr_contabilidad FOR LOGIN login_contabilidad;
IF USER_ID('usr_gerencia')     IS NULL CREATE USER usr_gerencia     FOR LOGIN login_gerencia;
GO

/* 3. Roles por función */
IF DATABASE_PRINCIPAL_ID('rol_recepcion')    IS NULL CREATE ROLE rol_recepcion;
IF DATABASE_PRINCIPAL_ID('rol_entrenador')   IS NULL CREATE ROLE rol_entrenador;
IF DATABASE_PRINCIPAL_ID('rol_contabilidad') IS NULL CREATE ROLE rol_contabilidad;
IF DATABASE_PRINCIPAL_ID('rol_gerencia')     IS NULL CREATE ROLE rol_gerencia;
GO

/* 4. Permisos (mínimo privilegio, sin DELETE para nadie) */

-- Recepción: gestiona socios y reservas; no ve finanzas
GRANT SELECT, INSERT, UPDATE ON SCHEMA::Gestion   TO rol_recepcion;
GRANT SELECT, INSERT, UPDATE ON SCHEMA::Operacion TO rol_recepcion;
DENY  SELECT, INSERT, UPDATE ON SCHEMA::Finanzas  TO rol_recepcion;

-- Entrenador: consulta la operación, marca asistencia y ve solo nombre del socio
GRANT SELECT ON SCHEMA::Operacion TO rol_entrenador;
GRANT SELECT ON Gestion.Socio (id_socio, nombre, apellido) TO rol_entrenador;
GRANT UPDATE ON Operacion.Reserva (asistio) TO rol_entrenador;
DENY  SELECT ON SCHEMA::Finanzas TO rol_entrenador;

-- Contabilidad: gestiona finanzas; de los socios solo ve identificación básica
GRANT SELECT, INSERT, UPDATE ON SCHEMA::Finanzas TO rol_contabilidad;
GRANT SELECT ON Gestion.Socio (id_socio, nombre, apellido) TO rol_contabilidad;

-- Gerencia: solo lectura en todo el negocio
GRANT SELECT ON SCHEMA::Gestion   TO rol_gerencia;
GRANT SELECT ON SCHEMA::Operacion TO rol_gerencia;
GRANT SELECT ON SCHEMA::Finanzas  TO rol_gerencia;
GO

/* 5. Asignar usuarios a roles */
ALTER ROLE rol_recepcion    ADD MEMBER usr_recepcion;
ALTER ROLE rol_entrenador   ADD MEMBER usr_entrenador;
ALTER ROLE rol_contabilidad ADD MEMBER usr_contabilidad;
ALTER ROLE rol_gerencia     ADD MEMBER usr_gerencia;
GO