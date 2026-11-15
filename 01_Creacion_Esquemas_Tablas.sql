/* ----------------------------------------------------------------------
   Proyecto de Cátedra - Administración de Bases de Datos (SQL Server)
   Escenario: Sistema de Reservas de Gimnasio
   Script 01: creación de la base de datos, esquemas y tablas
   ---------------------------------------------------------------------- */

USE master;
GO

IF DB_ID(N'GimnasioDB') IS NULL
    CREATE DATABASE GimnasioDB;
GO

USE GimnasioDB;
GO

/* ---------------------------------------------------------------------
   1. ESQUEMAS
   Gestion   : personas y catálogos de personal
   Operacion : clases, salas, sesiones y reservas
   Finanzas  : membresías, suscripciones y pagos
   --------------------------------------------------------------------- */
IF SCHEMA_ID(N'Gestion')   IS NULL EXEC(N'CREATE SCHEMA Gestion');
IF SCHEMA_ID(N'Operacion') IS NULL EXEC(N'CREATE SCHEMA Operacion');
IF SCHEMA_ID(N'Finanzas')  IS NULL EXEC(N'CREATE SCHEMA Finanzas');
GO

/* ---------------------------------------------------------------------
   2. ESQUEMA GESTION
   --------------------------------------------------------------------- */
CREATE TABLE Gestion.Socio
(
    id_socio INT IDENTITY(1,1) NOT NULL,
    nombre VARCHAR(50) NOT NULL,
    apellido VARCHAR(50) NOT NULL,
    documento_identidad VARCHAR(20) NOT NULL,
    email VARCHAR(100) NOT NULL,
    telefono VARCHAR(20) NULL,
    fecha_nacimiento DATE NOT NULL,
    fecha_registro DATE NOT NULL CONSTRAINT DF_Socio_fecha_registro DEFAULT (GETDATE()),
    estado VARCHAR(10) NOT NULL CONSTRAINT DF_Socio_estado DEFAULT ('Activo'),
    CONSTRAINT PK_Socio PRIMARY KEY (id_socio),
    CONSTRAINT UQ_Socio_documento UNIQUE (documento_identidad),
    CONSTRAINT UQ_Socio_email UNIQUE (email),
    CONSTRAINT CK_Socio_fecha_nacimiento CHECK (fecha_nacimiento < '2100-01-01' AND fecha_nacimiento > '1900-01-01'),
    CONSTRAINT CK_Socio_estado CHECK (estado IN ('Activo','Inactivo','Suspendido'))
);
GO

CREATE TABLE Gestion.Entrenador
(
    id_entrenador INT IDENTITY(1,1) NOT NULL,
    nombre VARCHAR(50) NOT NULL,
    apellido VARCHAR(50) NOT NULL,
    email VARCHAR(100) NOT NULL,
    telefono VARCHAR(20) NULL,
    fecha_contratacion DATE NOT NULL,
    estado VARCHAR(10) NOT NULL CONSTRAINT DF_Entrenador_estado DEFAULT ('Activo'),
    CONSTRAINT PK_Entrenador PRIMARY KEY (id_entrenador),
    CONSTRAINT UQ_Entrenador_email UNIQUE (email),
    CONSTRAINT CK_Entrenador_estado CHECK (estado IN ('Activo','Inactivo'))
);
GO

CREATE TABLE Gestion.Especialidad
(
    id_especialidad INT IDENTITY(1,1) NOT NULL,
    nombre VARCHAR(50) NOT NULL,
    CONSTRAINT PK_Especialidad PRIMARY KEY (id_especialidad),
    CONSTRAINT UQ_Especialidad_nombre UNIQUE (nombre)
);
GO

CREATE TABLE Gestion.EntrenadorEspecialidad
(
    id_entrenador INT NOT NULL,
    id_especialidad INT NOT NULL,
    CONSTRAINT PK_EntrenadorEspecialidad PRIMARY KEY (id_entrenador, id_especialidad),
    CONSTRAINT FK_EntEsp_Entrenador   FOREIGN KEY (id_entrenador)   REFERENCES Gestion.Entrenador (id_entrenador),
    CONSTRAINT FK_EntEsp_Especialidad FOREIGN KEY (id_especialidad) REFERENCES Gestion.Especialidad (id_especialidad)
);
GO

/* ---------------------------------------------------------------------
   3. ESQUEMA FINANZAS
   --------------------------------------------------------------------- */
CREATE TABLE Finanzas.Membresia
(
    id_membresia INT IDENTITY(1,1) NOT NULL,
    nombre VARCHAR(50) NOT NULL,
    descripcion VARCHAR(200) NULL,
    duracion_dias SMALLINT NOT NULL,
    precio DECIMAL(8,2) NOT NULL,
    CONSTRAINT PK_Membresia PRIMARY KEY (id_membresia),
    CONSTRAINT UQ_Membresia_nombre UNIQUE (nombre),
    CONSTRAINT CK_Membresia_duracion CHECK (duracion_dias > 0),
    CONSTRAINT CK_Membresia_precio CHECK (precio >= 0)
);
GO

CREATE TABLE Finanzas.MetodoPago
(
    id_metodo_pago INT IDENTITY(1,1) NOT NULL,
    nombre VARCHAR(30) NOT NULL,
    CONSTRAINT PK_MetodoPago PRIMARY KEY (id_metodo_pago),
    CONSTRAINT UQ_MetodoPago_nombre UNIQUE (nombre)
);
GO

CREATE TABLE Finanzas.Suscripcion
(
    id_suscripcion INT IDENTITY(1,1) NOT NULL,
    id_socio INT NOT NULL,
    id_membresia INT NOT NULL,
    fecha_inicio DATE NOT NULL,
    fecha_fin DATE NOT NULL,
    estado VARCHAR(10) NOT NULL,
    CONSTRAINT PK_Suscripcion PRIMARY KEY (id_suscripcion),
    CONSTRAINT FK_Suscripcion_Socio     FOREIGN KEY (id_socio)     REFERENCES Gestion.Socio (id_socio),
    CONSTRAINT FK_Suscripcion_Membresia FOREIGN KEY (id_membresia) REFERENCES Finanzas.Membresia (id_membresia),
    CONSTRAINT CK_Suscripcion_fechas CHECK (fecha_fin >= fecha_inicio),
    CONSTRAINT CK_Suscripcion_estado CHECK (estado IN ('Activa','Vencida','Cancelada'))
);
GO

CREATE TABLE Finanzas.Pago
(
    id_pago INT IDENTITY(1,1) NOT NULL,
    id_suscripcion INT NOT NULL,
    id_metodo_pago INT NOT NULL,
    fecha_pago DATETIME2(0) NOT NULL CONSTRAINT DF_Pago_fecha_pago DEFAULT (SYSDATETIME()),
    monto DECIMAL(8,2) NOT NULL,
    referencia VARCHAR(50) NULL,
    CONSTRAINT PK_Pago PRIMARY KEY (id_pago),
    CONSTRAINT FK_Pago_Suscripcion FOREIGN KEY (id_suscripcion) REFERENCES Finanzas.Suscripcion (id_suscripcion),
    CONSTRAINT FK_Pago_MetodoPago  FOREIGN KEY (id_metodo_pago) REFERENCES Finanzas.MetodoPago (id_metodo_pago),
    CONSTRAINT CK_Pago_monto CHECK (monto > 0)
);
GO

/* ---------------------------------------------------------------------
   4. ESQUEMA OPERACION
   --------------------------------------------------------------------- */
CREATE TABLE Operacion.Clase
(
    id_clase INT IDENTITY(1,1) NOT NULL,
    nombre VARCHAR(60) NOT NULL,
    descripcion VARCHAR(200) NULL,
    duracion_min SMALLINT NOT NULL,
    nivel VARCHAR(15) NOT NULL,
    CONSTRAINT PK_Clase PRIMARY KEY (id_clase),
    CONSTRAINT UQ_Clase_nombre UNIQUE (nombre),
    CONSTRAINT CK_Clase_duracion CHECK (duracion_min > 0),
    CONSTRAINT CK_Clase_nivel CHECK (nivel IN ('Principiante','Intermedio','Avanzado'))
);
GO

CREATE TABLE Operacion.Sala
(
    id_sala INT IDENTITY(1,1) NOT NULL,
    nombre VARCHAR(50) NOT NULL,
    capacidad SMALLINT NOT NULL,
    CONSTRAINT PK_Sala PRIMARY KEY (id_sala),
    CONSTRAINT UQ_Sala_nombre UNIQUE (nombre),
    CONSTRAINT CK_Sala_capacidad CHECK (capacidad > 0)
);
GO

CREATE TABLE Operacion.Sesion
(
    id_sesion INT IDENTITY(1,1) NOT NULL,
    id_clase INT NOT NULL,
    id_sala INT NOT NULL,
    id_entrenador INT NOT NULL,
    fecha DATE NOT NULL,
    hora_inicio TIME(0) NOT NULL,
    hora_fin TIME(0) NOT NULL,
    cupo_maximo SMALLINT NOT NULL,
    CONSTRAINT PK_Sesion PRIMARY KEY (id_sesion),
    CONSTRAINT FK_Sesion_Clase      FOREIGN KEY (id_clase)      REFERENCES Operacion.Clase (id_clase),
    CONSTRAINT FK_Sesion_Sala       FOREIGN KEY (id_sala)       REFERENCES Operacion.Sala (id_sala),
    CONSTRAINT FK_Sesion_Entrenador FOREIGN KEY (id_entrenador) REFERENCES Gestion.Entrenador (id_entrenador),
    CONSTRAINT UQ_Sesion_sala_horario UNIQUE (id_sala, fecha, hora_inicio),
    CONSTRAINT CK_Sesion_horas CHECK (hora_fin > hora_inicio),
    CONSTRAINT CK_Sesion_cupo CHECK (cupo_maximo > 0)
);
GO

CREATE TABLE Operacion.Reserva
(
    id_socio INT NOT NULL,
    id_sesion INT NOT NULL,
    fecha_reserva DATETIME2(0) NOT NULL CONSTRAINT DF_Reserva_fecha_reserva DEFAULT (SYSDATETIME()),
    estado VARCHAR(12) NOT NULL CONSTRAINT DF_Reserva_estado DEFAULT ('Confirmada'),
    asistio BIT NOT NULL CONSTRAINT DF_Reserva_asistio DEFAULT (0),
    CONSTRAINT PK_Reserva PRIMARY KEY (id_socio, id_sesion),
    CONSTRAINT FK_Reserva_Socio  FOREIGN KEY (id_socio)  REFERENCES Gestion.Socio (id_socio),
    CONSTRAINT FK_Reserva_Sesion FOREIGN KEY (id_sesion) REFERENCES Operacion.Sesion (id_sesion),
    CONSTRAINT CK_Reserva_estado CHECK (estado IN ('Confirmada','Cancelada','En espera'))
);
GO















