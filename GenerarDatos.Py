#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Generador de datos para GimnasioDB (Proyecto de Cátedra - Administración de BD)

Genera un CSV por tabla, en el mismo orden de columnas que el script
01_creacion_gimnasio.sql, listos para cargarse con BULK INSERT (02_carga_datos.sql).

Reglas de coherencia que respeta el generador:
  - Un socio solo reserva sesiones que caen dentro de una suscripción vigente.
  - Reservas 'Confirmada' por sesión <= cupo_maximo; cupo_maximo <= capacidad de la sala.
  - Un entrenador solo imparte clases de sus especialidades y no se solapa consigo mismo.
  - Una sala no tiene dos sesiones a la misma hora.
  - Un socio no tiene dos reservas a la misma hora.
  - Pagos coherentes con el precio de la membresía (suma de cuotas = precio).
"""
import argparse
import os
import unicodedata
from datetime import date, datetime, timedelta

import numpy as np
import pandas as pd
from faker import Faker

# ----------------------------------------------------------------------------
# Parámetros generales
# ----------------------------------------------------------------------------
SEED = 42
HOY = date(2026, 11, 10)          # fecha de referencia fija 
REG_INICIO = date(2023, 7, 1)     # primeras altas de socios
SESIONES_INICIO = date(2024, 1, 1)
FIN_DATOS = date(2026, 11, 9)     # último día con datos
N_SOCIOS = 20000
N_ENTRENADORES = 40

# Estacionalidad: más actividad en enero y septiembre, menos en diciembre y verano
MES = {1: 1.25, 2: 1.10, 3: 1.00, 4: 0.95, 5: 0.95, 6: 0.90,
       7: 0.85, 8: 0.90, 9: 1.20, 10: 1.05, 11: 0.95, 12: 0.70}

# Horarios: (hora de inicio, peso de demanda)
HORAS_SEMANA = [(6, 1.10), (7, 1.25), (8, 0.80), (9, 0.60), (10, 0.50),
                (12, 0.70), (17, 1.20), (18, 1.50), (19, 1.40), (20, 0.90)]
HORAS_SABADO = [(7, 1.20), (8, 1.30), (9, 1.10), (10, 0.90), (12, 0.50)]
HORAS_DOMINGO = [(8, 1.00), (9, 1.00), (10, 0.70)]

# ----------------------------------------------------------------------------
# Catálogos
# ----------------------------------------------------------------------------
ESPECIALIDADES = ["Spinning", "Yoga", "Pilates", "Baile", "Funcional", "CrossFit", "Boxeo"]

# (nombre, descripción, duración_min, nivel, especialidad, salas permitidas, popularidad)
CLASES = [
    ("Spinning", "Ciclismo indoor con música y ritmo", 45, "Intermedio", "Spinning", [3], 1.30),
    ("Yoga Vinyasa", "Secuencias fluidas de posturas y respiración", 60, "Principiante", "Yoga", [4], 1.00),
    ("Pilates Mat", "Fortalecimiento del core en colchoneta", 55, "Principiante", "Pilates", [4], 0.90),
    ("Zumba", "Baile aeróbico con ritmos latinos", 60, "Principiante", "Baile", [5], 1.20),
    ("HIIT", "Intervalos de alta intensidad", 45, "Avanzado", "Funcional", [1, 2], 1.10),
    ("CrossFit", "Entrenamiento funcional de alta exigencia", 60, "Avanzado", "CrossFit", [1, 2], 0.90),
    ("Funcional Total Body", "Circuito de cuerpo completo", 50, "Intermedio", "Funcional", [1, 2], 1.00),
    ("Boxeo Fitness", "Técnica de boxeo y acondicionamiento", 60, "Intermedio", "Boxeo", [6], 0.80),
    ("Kickboxing", "Combinaciones de golpes y patadas", 60, "Avanzado", "Boxeo", [6], 0.50),
    ("Stretching", "Estiramiento y movilidad", 45, "Principiante", "Yoga", [4], 0.60),
    ("GAP", "Glúteos, abdomen y piernas", 45, "Principiante", "Funcional", [1, 2], 0.90),
    ("Yoga Restaurativo", "Relajación profunda con apoyos", 60, "Principiante", "Yoga", [4], 0.40),
]

SALAS = [("Sala Funcional A", 30), ("Sala Funcional B", 30), ("Sala Spinning", 25),
         ("Sala Mind & Body", 20), ("Sala Baile", 40), ("Sala Combate", 20)]

# (nombre, descripción, duración_días, precio, probabilidad de elegirla)
MEMBRESIAS = [
    ("Mensual", "Acceso total por 30 días", 30, 30.00, 0.45),
    ("Trimestral", "Acceso total por 90 días", 90, 80.00, 0.22),
    ("Semestral", "Acceso total por 180 días", 180, 150.00, 0.10),
    ("Anual", "Acceso total por 365 días", 365, 270.00, 0.15),
    ("Estudiante Mensual", "Tarifa estudiantil por 30 días", 30, 22.00, 0.08),
]
# Cuotas posibles por plan: ([n_cuotas], [probabilidades])
CUOTAS = {1: ([1], [1.0]), 2: ([1, 3], [0.65, 0.35]), 3: ([1, 2, 3], [0.5, 0.3, 0.2]),
          4: ([1, 2, 4, 12], [0.35, 0.25, 0.25, 0.15]), 5: ([1], [1.0])}

METODOS = ["Efectivo", "Tarjeta de débito", "Tarjeta de crédito", "Transferencia"]
P_METODO = [0.38, 0.22, 0.28, 0.12]


def limpiar(txt):
    """Minúsculas, sin acentos ni espacios (para correos)."""
    t = unicodedata.normalize("NFKD", txt).encode("ascii", "ignore").decode()
    return "".join(c for c in t.lower() if c.isalnum())


def telefono(rng):
    return f"{rng.choice([6, 7])}{rng.integers(100, 1000)}-{rng.integers(1000, 10000)}"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--salida", default="csv_gimnasio")
    ap.add_argument("--socios", type=int, default=N_SOCIOS)
    args = ap.parse_args()
    os.makedirs(args.salida, exist_ok=True)

    rng = np.random.default_rng(SEED)
    Faker.seed(SEED)
    fake = Faker("es_MX")
    n = args.socios

    # ------------------------------------------------------------------
    # 1. Catálogos pequeños
    # ------------------------------------------------------------------
    df_esp = pd.DataFrame({"id_especialidad": range(1, len(ESPECIALIDADES) + 1), "nombre": ESPECIALIDADES})
    esp_id = {e: i + 1 for i, e in enumerate(ESPECIALIDADES)}

    df_mem = pd.DataFrame([(i + 1, m[0], m[1], m[2], m[3]) for i, m in enumerate(MEMBRESIAS)],
                          columns=["id_membresia", "nombre", "descripcion", "duracion_dias", "precio"])
    mem_dias = {i + 1: m[2] for i, m in enumerate(MEMBRESIAS)}
    mem_precio = {i + 1: m[3] for i, m in enumerate(MEMBRESIAS)}
    mem_prob = np.array([m[4] for m in MEMBRESIAS])
    mem_prob = mem_prob / mem_prob.sum()
    mem_ids = np.arange(1, len(MEMBRESIAS) + 1)

    df_met = pd.DataFrame({"id_metodo_pago": range(1, len(METODOS) + 1), "nombre": METODOS})

    df_cla = pd.DataFrame([(i + 1, c[0], c[1], c[2], c[3]) for i, c in enumerate(CLASES)],
                          columns=["id_clase", "nombre", "descripcion", "duracion_min", "nivel"])
    df_sal = pd.DataFrame([(i + 1, s[0], s[1]) for i, s in enumerate(SALAS)],
                          columns=["id_sala", "nombre", "capacidad"])
    sala_cap = {i + 1: s[1] for i, s in enumerate(SALAS)}

    # ------------------------------------------------------------------
    # 2. Entrenadores y especialidades
    # ------------------------------------------------------------------
    ent_rows, ent_esp_rows = [], []
    ent_esp = {}                       # id_entrenador -> set de id_especialidad
    ent_baja = {}                      # id_entrenador -> fecha de baja (solo inactivos)
    inactivos = set(rng.choice(np.arange(N_ENTRENADORES // 2, N_ENTRENADORES + 1), size=3, replace=False).tolist())
    for i in range(1, N_ENTRENADORES + 1):
        nom, ape = fake.first_name(), f"{fake.last_name()} {fake.last_name()}"
        contr = date(2018, 1, 1) + timedelta(days=int(rng.integers(0, 365 * 5)))
        estado = "Inactivo" if i in inactivos else "Activo"
        if i in inactivos:
            ent_baja[i] = date(2025, 3, 1) + timedelta(days=int(rng.integers(0, 450)))
        tel = telefono(rng)
        ent_rows.append((i, nom, ape, f"{limpiar(nom)}.{limpiar(ape)}{i}@fitzone.com", tel, contr, estado))
        esps = {(i - 1) % len(ESPECIALIDADES) + 1}
        if rng.random() < 0.4:
            esps.add(int(rng.integers(1, len(ESPECIALIDADES) + 1)))
        ent_esp[i] = esps
        ent_esp_rows += [(i, e) for e in sorted(esps)]
    df_ent = pd.DataFrame(ent_rows, columns=["id_entrenador", "nombre", "apellido", "email",
                                             "telefono", "fecha_contratacion", "estado"])
    df_ee = pd.DataFrame(ent_esp_rows, columns=["id_entrenador", "id_especialidad"])
    esp_trainers = {e: [t for t, s in ent_esp.items() if e in s] for e in esp_id.values()}

    # ------------------------------------------------------------------
    # 3. Socios 
    # ------------------------------------------------------------------
    print("Generando socios...")
    n_dias = (FIN_DATOS - REG_INICIO).days + 1
    fechas_reg_pos = [REG_INICIO + timedelta(days=i) for i in range(n_dias)]
    peso = np.array([MES[f.month] * (1 + 0.6 * i / n_dias) for i, f in enumerate(fechas_reg_pos)])
    peso /= peso.sum()
    idx = np.sort(rng.choice(n_dias, size=n, p=peso))
    reg = [fechas_reg_pos[i] for i in idx]

    dui = rng.choice(100_000_000, size=n, replace=False)
    dominios = ["gmail.com", "hotmail.com", "outlook.com", "yahoo.com"]
    socios = []
    for i in range(n):
        sid = i + 1
        nom, ape = fake.first_name(), f"{fake.last_name()} {fake.last_name()}"
        edad = float(np.clip(rng.normal(32, 10), 16, 70))
        nac = reg[i] - timedelta(days=int(edad * 365.25))
        tel = "" if rng.random() < 0.04 else telefono(rng)      # algunos NULL
        email = f"{limpiar(nom)}.{limpiar(ape)}{sid}@{dominios[int(rng.integers(0, 4))]}"
        doc = f"{dui[i]:08d}-{rng.integers(0, 10)}"
        socios.append([sid, nom, ape, doc, email, tel, nac, reg[i], "Activo"])
    df_soc = pd.DataFrame(socios, columns=["id_socio", "nombre", "apellido", "documento_identidad", "email",
                                           "telefono", "fecha_nacimiento", "fecha_registro", "estado"])

    # ------------------------------------------------------------------
    # 4. Suscripciones y pagos
    # ------------------------------------------------------------------
    print("Generando suscripciones y pagos...")
    retencion = rng.beta(3.0, 1.5, size=n)
    subs, pagos = [], []
    sub_id = 0
    pago_id = 0
    for i in range(n):
        sid = i + 1
        inicio = reg[i]
        plan = int(rng.choice(mem_ids, p=mem_prob))
        while True:
            dur = mem_dias[plan]
            fin = inicio + timedelta(days=dur - 1)
            cancelada = rng.random() < 0.04
            if cancelada:
                fin = inicio + timedelta(days=int(rng.integers(3, max(4, dur))))
                estado = "Cancelada"
            elif fin < HOY:
                estado = "Vencida"
            else:
                estado = "Activa"
            sub_id += 1
            subs.append((sub_id, sid, plan, inicio, fin, estado))

            # Pagos de esta suscripción
            opc, prob = CUOTAS[plan]
            ncuotas = int(rng.choice(opc, p=prob))
            precio = mem_precio[plan]
            cuota = round(precio / ncuotas, 2)
            for k in range(ncuotas):
                f_pago = inicio + timedelta(days=int(round(k * dur / ncuotas)))
                if f_pago > min(fin, FIN_DATOS):
                    break
                monto = cuota if k < ncuotas - 1 else round(precio - cuota * (ncuotas - 1), 2)
                met = int(rng.choice(np.arange(1, 5), p=P_METODO))
                prefijo = "REC-" if met == 1 else "TRX-"
                ref = f"{prefijo}{rng.integers(100000, 99999999)}"
                hora = timedelta(seconds=int(rng.integers(8 * 3600, 20 * 3600)))
                pago_id += 1
                pagos.append((pago_id, sub_id, met, datetime.combine(f_pago, datetime.min.time()) + hora, monto, ref))

            if estado in ("Activa", "Cancelada") or fin >= HOY:
                break
            if rng.random() > retencion[i]:
                break
            hueco = 0 if rng.random() < 0.7 else int(rng.integers(1, 45))
            inicio = fin + timedelta(days=1 + hueco)
            if inicio > FIN_DATOS:
                break
            if rng.random() < 0.2:
                plan = int(rng.choice(mem_ids, p=mem_prob))

    df_sub = pd.DataFrame(subs, columns=["id_suscripcion", "id_socio", "id_membresia",
                                         "fecha_inicio", "fecha_fin", "estado"])
    df_pag = pd.DataFrame(pagos, columns=["id_pago", "id_suscripcion", "id_metodo_pago",
                                          "fecha_pago", "monto", "referencia"])

    # ------------------------------------------------------------------
    # 5. Sesiones y reservas (se generan juntas, día por día)
    # ------------------------------------------------------------------
    print("Generando sesiones y reservas (puede tardar un minuto)...")
    s_start = df_sub["fecha_inicio"].to_numpy(dtype="datetime64[D]")
    s_end = df_sub["fecha_fin"].to_numpy(dtype="datetime64[D]")
    s_soc = df_sub["id_socio"].to_numpy()
    reg64 = np.array(reg, dtype="datetime64[s]")


    prop = np.minimum(rng.lognormal(0, 0.8, size=n), 3.0)   
    dormido = rng.random(n) < 0.15
    prop[dormido] *= 0.05

    clase_pop = np.array([c[6] for c in CLASES])
    clase_p = clase_pop / clase_pop.sum()

    ses_rows = []
    r_soc, r_ses, r_fec, r_est, r_asi = [], [], [], [], []
    ses_id = 0
    dia = SESIONES_INICIO
    while dia <= FIN_DATOS:
        dow = dia.weekday()
        horas, base = ((HORAS_SEMANA, 3.2) if dow < 5 else (HORAS_SABADO, 3.8) if dow == 5 else (HORAS_DOMINGO, 3.5))
        d64 = np.datetime64(dia)
        pool = s_soc[(s_start <= d64) & (s_end >= d64)]
        w = prop[pool - 1]
        pw = w / w.sum() if len(pool) else None
        for hora, hw in horas:
            n_ses = int(np.clip(round(rng.normal(base * hw, 0.8)), 1, 6))
            salas_libres = set(range(1, len(SALAS) + 1))
            usados = set()
            slot = []   # sesiones de esta franja: (id_sesion, n_conf, n_esp, n_can)
            for _ in range(n_ses):
                for _intento in range(12):
                    c = int(rng.choice(len(CLASES), p=clase_p))
                    nombre_c, _d, dur, _niv, esp, salas_ok, pop = CLASES[c]
                    libres = [s for s in salas_ok if s in salas_libres]
                    cand = [t for t in esp_trainers[esp_id[esp]]
                            if t not in usados and (t not in ent_baja or dia < ent_baja[t])]
                    if libres and cand:
                        break
                else:
                    continue
                sala = int(rng.choice(libres))
                ent = int(rng.choice(cand))
                salas_libres.discard(sala)
                usados.add(ent)
                cap = sala_cap[sala]
                cupo = cap - (int(rng.integers(1, 5)) if rng.random() < 0.3 else 0)
                ini = datetime(dia.year, dia.month, dia.day, hora, 0)
                fin_h = ini + timedelta(minutes=dur)
                ses_id += 1
                ses_rows.append((ses_id, c + 1, sala, ent, dia, ini.strftime("%H:%M:%S"),
                                 fin_h.strftime("%H:%M:%S"), cupo))
                # Demanda de la sesión
                f = float(np.clip(0.50 * pop * hw * MES[dia.month] * rng.lognormal(0, 0.25), 0.08, 1.30))
                conf = min(cupo, int(round(f * cupo)))
                espera = int(round((f - 1.0) * cupo)) if f > 1.0 else 0
                canc = int(rng.binomial(conf, 0.08))
                slot.append((ses_id, ini, conf, espera, canc))

            total = sum(s[2] + s[3] + s[4] for s in slot)
            total = min(total, len(pool))
            if total == 0:
                continue
            elegidos = pool[rng.choice(len(pool), size=total, replace=False, p=pw)]
            pos = 0
            for sid_, ini, conf, espera, canc in slot:
                for estado, cant in (("Confirmada", conf), ("En espera", espera), ("Cancelada", canc)):
                    cant = min(cant, total - pos)
                    if cant <= 0:
                        continue
                    grupo = elegidos[pos:pos + cant]
                    pos += cant
                    antes = np.clip(rng.exponential(20, cant) + 1, 1, 96)
                    ses_dt = np.datetime64(ini, "s")
                    fr = ses_dt - (antes * 3600).astype("timedelta64[s]")
                    fr = np.maximum(fr, reg64[grupo - 1])
                    if estado == "Confirmada":
                        p_asis = np.where(dormido[grupo - 1], 0.5, 0.9)
                        asi = (rng.random(cant) < p_asis).astype(int)
                    else:
                        asi = np.zeros(cant, dtype=int)
                    r_soc.append(grupo)
                    r_ses.append(np.full(cant, sid_))
                    r_fec.append(fr)
                    r_est.append(np.full(cant, estado))
                    r_asi.append(asi)
        dia += timedelta(days=1)

    df_ses = pd.DataFrame(ses_rows, columns=["id_sesion", "id_clase", "id_sala", "id_entrenador",
                                             "fecha", "hora_inicio", "hora_fin", "cupo_maximo"])
    df_res = pd.DataFrame({
        "id_socio": np.concatenate(r_soc),
        "id_sesion": np.concatenate(r_ses),
        "fecha_reserva": np.concatenate(r_fec),
        "estado": np.concatenate(r_est),
        "asistio": np.concatenate(r_asi),
    })
    df_res["fecha_reserva"] = pd.to_datetime(df_res["fecha_reserva"]).dt.strftime("%Y-%m-%d %H:%M:%S")

    # ------------------------------------------------------------------
    # 6. Estado final del socio (coherente con sus suscripciones y reservas)
    # ------------------------------------------------------------------
    activos = set(df_sub.loc[df_sub["estado"] == "Activa", "id_socio"])
    ultima_res = (df_res.assign(f=df_res["fecha_reserva"].str[:10])
                  .groupby("id_socio")["f"].max())
    estado = []
    for sid in df_soc["id_socio"]:
        estado.append("Activo" if sid in activos else "Inactivo")
    df_soc["estado"] = estado
    cand = [s for s in activos if ultima_res.get(s, "0000") < "2026-10-01"]
    if cand:
        k = int(len(activos) * 0.03)
        susp = set(rng.choice(cand, size=min(k, len(cand)), replace=False).tolist())
        df_soc.loc[df_soc["id_socio"].isin(susp), "estado"] = "Suspendido"

    # ------------------------------------------------------------------
    # 7. Verificaciones rápidas de coherencia
    # ------------------------------------------------------------------
    print("Verificando coherencia...")
    assert df_soc["email"].is_unique and df_soc["documento_identidad"].is_unique
    assert not df_res.duplicated(["id_socio", "id_sesion"]).any(), "reservas duplicadas"
    conf = df_res[df_res["estado"] == "Confirmada"].groupby("id_sesion").size()
    cupo = df_ses.set_index("id_sesion")["cupo_maximo"]
    assert (conf <= cupo.loc[conf.index]).all(), "confirmadas exceden el cupo"
    cap_s = df_ses["id_sala"].map(sala_cap)
    assert (df_ses["cupo_maximo"] <= cap_s).all(), "cupo > capacidad"
    assert not df_ses.duplicated(["id_sala", "fecha", "hora_inicio"]).any(), "sala doble"
    assert not df_ses.duplicated(["id_entrenador", "fecha", "hora_inicio"]).any(), "entrenador doble"
    assert (df_sub["fecha_fin"] >= df_sub["fecha_inicio"]).all()
    assert (df_pag["monto"] > 0).all()

    # ------------------------------------------------------------------
    # 8. Exportación a CSV (UTF-8, cabecera, saltos de línea \n)
    # ------------------------------------------------------------------
    salidas = {
        "especialidad": df_esp, "entrenador": df_ent, "entrenador_especialidad": df_ee,
        "membresia": df_mem, "metodo_pago": df_met, "clase": df_cla, "sala": df_sal,
        "socio": df_soc, "suscripcion": df_sub, "pago": df_pag, "sesion": df_ses, "reserva": df_res,
    }
    print("\nArchivos generados en:", os.path.abspath(args.salida))
    for nombre, df in salidas.items():
        ruta = os.path.join(args.salida, f"{nombre}.csv")
        df.to_csv(ruta, index=False, encoding="utf-8", lineterminator="\n", float_format="%.2f")
        print(f"  {nombre + '.csv':32s} {len(df):>9,d} filas")


if __name__ == "__main__":
    main()