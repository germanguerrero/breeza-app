from flask import Flask, render_template, request, flash, redirect, url_for, send_file, jsonify
import base64
from flask_sqlalchemy import SQLAlchemy
from datetime import date, datetime, timedelta
import requests
from google.oauth2.service_account import Credentials
from googleapiclient.discovery import build
import os
import logging
import io
import uuid

app = Flask(__name__)
app.secret_key = os.urandom(24)

# Configurar logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# === CONFIGURACIÓN ===
# Construir DATABASE_URL desde variables individuales o usar DATABASE_URL directamente
# Prioridad: DATABASE_URL > variables individuales (DB_HOST, DB_PORT, etc.) > default
if 'DATABASE_URL' in os.environ:
    database_uri = os.environ.get('DATABASE_URL')
else:
    # Construir desde variables individuales si están disponibles
    db_host = os.environ.get('DB_HOST', 'db')  # 'db' es el nombre del servicio en docker-compose
    db_port = os.environ.get('DB_PORT', '3306')
    db_name = os.environ.get('DB_NAME', 'breeza_db')
    db_user = os.environ.get('DB_USER', 'breeza_user')
    db_password = os.environ.get('DB_PASSWORD', 'breeza_pass_2025')
    database_uri = f'mysql+pymysql://{db_user}:{db_password}@{db_host}:{db_port}/{db_name}'

app.config['SQLALCHEMY_DATABASE_URI'] = database_uri



app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False
db = SQLAlchemy(app)

WEATHER_API_KEY = os.environ.get('WEATHER_API_KEY')
LAT = os.environ.get('LAT', '-34.6037')
LON = os.environ.get('LON', '-58.3816')
TIMEZONE = os.environ.get('TIMEZONE', 'America/Argentina/Buenos_Aires')
CALENDAR_ID = os.environ.get('CALENDAR_ID')
CREDENTIALS_FILE = '/app/credentials.json'

# === Modelo ===
class Booking(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    booking_date = db.Column(db.Date, nullable=False)
    slot = db.Column(db.Integer, nullable=False)
    name = db.Column(db.String(100), nullable=False)
    email = db.Column(db.String(120), nullable=False)
    phone = db.Column(db.String(50), nullable=False)

    __table_args__ = (db.UniqueConstraint('booking_date', 'slot', name='unique_date_slot'),)

# === Turnos fijos ===
SLOTS = [
    {"num": 1, "start": "12:00", "end": "13:00", "label": "12:00 - 13:00"},
    {"num": 2, "start": "13:10", "end": "14:10", "label": "13:10 - 14:10"},
    {"num": 3, "start": "14:20", "end": "15:20", "label": "14:20 - 15:20"},
    {"num": 4, "start": "15:30", "end": "16:30", "label": "15:30 - 16:30"},
]

# === Fechas ===
# Generar fechas desde hoy hasta 30 días adelante
def get_dates():
    start_date = date.today()
    end_date = start_date + timedelta(days=30)
    delta = timedelta(days=1)
    dates = []
    current = start_date
    while current <= end_date:
        dates.append(current)
        current += delta
    return dates, start_date, end_date

# === Clima (One Call 3.0 - 8 días adelante) ===
# === Clima (usando APIs gratuitas: forecast 5d/3h + UV forecast) ===
weather_cache = {}
uv_cache = {}

def get_weather_data():
    global weather_cache, uv_cache
    if weather_cache and uv_cache:
        return weather_cache, uv_cache  # Agregué uv_cache aquí (faltaba en la versión anterior)

    weather_cache = {}
    uv_cache = {}
    if not WEATHER_API_KEY:
        return weather_cache, uv_cache

    # Forecast 5 días / 3 horas (gratuito)
    forecast_url = f"https://api.openweathermap.org/data/2.5/forecast?lat={LAT}&lon={LON}&appid={WEATHER_API_KEY}&units=metric&lang=es"
    
    # UV forecast (gratuito, hasta 4 días)
    uvi_url = f"https://api.openweathermap.org/data/2.5/uvi/forecast?lat={LAT}&lon={LON}&appid={WEATHER_API_KEY}"

    try:
        forecast_r = requests.get(forecast_url).json()
        if 'list' in forecast_r:
            daily_data = {}
            for item in forecast_r['list']:
                dt = datetime.fromtimestamp(item['dt'])
                day = dt.date()
                if day not in daily_data:
                    daily_data[day] = {
                        'temps': [], 'clouds': [], 'descs': [], 'icons': []
                    }
                daily_data[day]['temps'].append(item['main']['temp'])
                daily_data[day]['clouds'].append(item['clouds']['all'])
                if item['weather']:
                    daily_data[day]['descs'].append(item['weather'][0]['description'].capitalize())
                    daily_data[day]['icons'].append(item['weather'][0]['icon'])

            # Agregar por día (promedio temp/nubosidad, desc/ícono más frecuente o del mediodía)
            for day, data in daily_data.items():
                avg_temp = round(sum(data['temps']) / len(data['temps']))
                avg_clouds = round(sum(data['clouds']) / len(data['clouds']))
                
                # Desc e ícono: el más común (o el primero si empate)
                most_common_desc = max(set(data['descs']), key=data['descs'].count)
                most_common_icon = max(set(data['icons']), key=data['icons'].count)
                
                weather_cache[day] = {
                    'temp': avg_temp,
                    'clouds': avg_clouds,
                    'desc': most_common_desc,
                    'icon': most_common_icon
                }

        # UV forecast
        uvi_r = requests.get(uvi_url).json()
        for item in uvi_r:
            day = datetime.fromtimestamp(item['date']).date()
            uv_cache[day] = round(item['value'], 1)

    except Exception as e:
        print("Error en APIs gratuitas:", e)

    return weather_cache, uv_cache


# === Funciones auxiliares ===
def generate_ics_content(booking_date, slot_info, name, email, phone, timezone, agenda_body):
    """Genera el contenido del archivo .ICS para la cita usando el template de agenda_body.md"""
    start_dt = datetime.combine(booking_date, datetime.strptime(slot_info['start'], "%H:%M").time())
    end_dt = datetime.combine(booking_date, datetime.strptime(slot_info['end'], "%H:%M").time())
    
    # Formato iCalendar requiere fechas en formato UTC sin separadores
    def format_ical_datetime(dt):
        return dt.strftime('%Y%m%dT%H%M%S')
    
    # Generar UID único
    uid = str(uuid.uuid4())
    
    # Escapar el contenido de la descripción para formato .ICS (reemplazar \n por \\n)
    description_escaped = agenda_body.replace('\n', '\\n').replace(',', '\\,')
    
    # Crear contenido .ICS
    ics_content = f"""BEGIN:VCALENDAR
VERSION:2.0
PRODID:-//Breeza//Cita Reservada//ES
BEGIN:VEVENT
UID:{uid}@breeza.german.com.ar
DTSTART:{format_ical_datetime(start_dt)}
DTEND:{format_ical_datetime(end_dt)}
SUMMARY:Prueba Breeza - {name}
DESCRIPTION:{description_escaped}
LOCATION:Breeza
STATUS:CONFIRMED
SEQUENCE:0
END:VEVENT
END:VCALENDAR"""
    
    return ics_content

def get_agenda_content(booking_date, slot_info, name, email, phone):
    """Lee el template de agenda_body.md y reemplaza las variables con los datos de la cita"""
    try:
        # Leer el template desde agenda_body.md
        if os.path.exists('agenda_body.md'):
            with open('agenda_body.md', 'r', encoding='utf-8') as f:
                template = f.read()
        else:
            # Si no existe, usar un template por defecto
            logger.warning("[AGENDA] agenda_body.md no existe, usando template por defecto")
            template = """Nombre: {name}
Email: {email}
Teléfono: {phone}
Fecha: {date}
Turno: {slot}
Reservado desde breeza.german.com.ar"""
        
        # Reemplazar variables en el template
        agenda_content = template.format(
            name=name,
            email=email,
            phone=phone,
            date=booking_date.strftime('%d/%m/%Y'),
            slot=slot_info['label'],
            booking_date=booking_date.strftime('%d/%m/%Y'),
            slot_start=slot_info['start'],
            slot_end=slot_info['end'],
            slot_label=slot_info['label']
        )
        
        logger.info(f"[AGENDA] Template cargado desde agenda_body.md")
        return agenda_content
    except Exception as e:
        logger.error(f"[AGENDA] Error al leer agenda_body.md: {e}", exc_info=True)
        # Retornar un contenido por defecto si hay error
        return f"Nombre: {name}\nEmail: {email}\nTeléfono: {phone}\nTurno: {slot_info['label']}\nReservado desde breeza.german.com.ar"


# === Rutas ===
@app.route('/health')
def health():
    return 'OK', 200
    
@app.route('/')
def index():
    logger.info("[INDEX] Iniciando renderizado de página principal")
    
    # Generar fechas dinámicamente (hoy + 30 días)
    dates, start_date, end_date = get_dates()
    logger.info(f"[INDEX] Rango de fechas: {start_date} hasta {end_date} ({len(dates)} días)")
    
    bookings = Booking.query.all()
    logger.info(f"[INDEX] Reservas encontradas en DB: {len(bookings)}")
    for b in bookings:
        logger.info(f"[INDEX] Reserva: fecha={b.booking_date}, slot={b.slot}, nombre={b.name}")
    
    taken = {}
    for b in bookings:
        taken.setdefault(b.booking_date, set()).add(b.slot)
    
    logger.info(f"[INDEX] Diccionario 'taken' construido: {len(taken)} días con reservas")
    for date_key, slots_set in taken.items():
        logger.info(f"[INDEX] Día {date_key}: slots ocupados = {slots_set}")

    weather_data, uv_data = get_weather_data()  # Ahora devuelve dos dicts
    logger.info(f"[INDEX] Datos del clima para template: {len(weather_data)} días")
    
    # Log de algunas fechas de ejemplo para verificar formato
    if dates:
        logger.info(f"[INDEX] Primera fecha: {dates[0]} (tipo: {type(dates[0])})")
        logger.info(f"[INDEX] Última fecha: {dates[-1]} (tipo: {type(dates[-1])})")

    return render_template('index.html',
                           dates=dates,
                           slots=SLOTS,
                           taken=taken,
                           weather_data=weather_data,
                           uv_data=uv_data,
                           start_date=start_date,
                           end_date=end_date)

@app.route('/book', methods=['POST'])
def book():
    logger.info("[BOOK] Nueva solicitud de reserva recibida")
    logger.info(f"[BOOK] Datos del formulario: {dict(request.form)}")
    
    is_ajax = request.headers.get('X-Requested-With') == 'XMLHttpRequest'
    
    try:
        booking_date = datetime.strptime(request.form['date'], '%Y-%m-%d').date()
        slot_num = int(request.form['slot'])
        name = request.form['name'].strip()
        email = request.form['email'].strip()
        phone = request.form['phone'].strip()
        
        logger.info(f"[BOOK] Datos parseados: fecha={booking_date}, slot={slot_num}, nombre={name}, email={email}, tel={phone}")
    except KeyError as e:
        logger.error(f"[BOOK] Campo faltante en formulario: {e}")
        if is_ajax:
            return jsonify({'success': False, 'message': 'Error: faltan datos en el formulario'}), 400
        flash('Error: faltan datos en el formulario', 'danger')
        return redirect(url_for('index'))
    except ValueError as e:
        logger.error(f"[BOOK] Error al parsear datos: {e}")
        if is_ajax:
            return jsonify({'success': False, 'message': 'Error: formato de datos inválido'}), 400
        flash('Error: formato de datos inválido', 'danger')
        return redirect(url_for('index'))

    if not all([name, email, phone]):
        logger.warning(f"[BOOK] Campos incompletos: name={bool(name)}, email={bool(email)}, phone={bool(phone)}")
        if is_ajax:
            return jsonify({'success': False, 'message': 'Todos los campos son obligatorios'}), 400
        flash('Todos los campos son obligatorios', 'danger')
        return redirect(url_for('index'))

    existing = Booking.query.filter_by(booking_date=booking_date, slot=slot_num).first()
    if existing:
        logger.warning(f"[BOOK] Turno ya ocupado: fecha={booking_date}, slot={slot_num}, por={existing.name}")
        if is_ajax:
            return jsonify({'success': False, 'message': 'Este turno ya está reservado'}), 400
        flash('Este turno ya está reservado', 'danger')
        return redirect(url_for('index'))

    # Guardar en DB
    logger.info(f"[BOOK] Guardando reserva en base de datos...")
    try:
        booking = Booking(booking_date=booking_date, slot=slot_num, name=name, email=email, phone=phone)
        db.session.add(booking)
        db.session.commit()
        logger.info(f"[BOOK] Reserva guardada exitosamente con ID: {booking.id}")
    except Exception as e:
        logger.error(f"[BOOK] Error al guardar en DB: {e}", exc_info=True)
        db.session.rollback()
        if is_ajax:
            return jsonify({'success': False, 'message': 'Error al guardar la reserva. Intenta nuevamente.'}), 500
        flash('Error al guardar la reserva. Intenta nuevamente.', 'danger')
        return redirect(url_for('index'))

    # Google Calendar
    logger.info(f"[BOOK] Verificando configuración de Google Calendar: CALENDAR_ID={bool(CALENDAR_ID)}, CREDENTIALS_FILE existe={os.path.exists(CREDENTIALS_FILE)}")
    
    # Google Calendar - ahora busca automáticamente el calendario "Breeza"
    # Google Calendar - VERSIÓN FINAL ULTRA-CONFIABLE (Calendar ID directo desde ENV)
    calendar_id = os.environ.get('CALENDAR_ID')
    if not calendar_id:
        logger.error("[GCAL] VARIABLE CALENDAR_ID NO CONFIGURADA EN DOCKER")
        if is_ajax:
            return jsonify({'success': False, 'message': 'Error interno: falta CALENDAR_ID'}), 500
        flash('Error interno: falta CALENDAR_ID', 'danger')
        return redirect(url_for('index'))

    if not os.path.exists(CREDENTIALS_FILE):
        logger.error("[GCAL] credentials.json NO ENCONTRADO")
        if is_ajax:
            return jsonify({'success': False, 'message': 'Error: credentials.json no encontrado'}), 500
        flash('Error: credentials.json no encontrado', 'danger')
        return redirect(url_for('index'))

    # Obtener información del slot (necesario para ICS y agenda)
    slot_info = SLOTS[slot_num - 1]

    # Obtener el contenido del template de agenda_body.md
    agenda_body = get_agenda_content(booking_date, slot_info, name, email, phone)

    try:
        logger.info(f"[GCAL] Usando Calendar ID directo: {calendar_id}")
        credentials = Credentials.from_service_account_file(
            CREDENTIALS_FILE,
            scopes=['https://www.googleapis.com/auth/calendar']
        )
        service = build('calendar', 'v3', credentials=credentials)
        start_dt = datetime.combine(booking_date, datetime.strptime(slot_info['start'], "%H:%M").time())
        end_dt = datetime.combine(booking_date, datetime.strptime(slot_info['end'], "%H:%M").time())

        event = {
            'summary': f'Prueba Breeza - {name}',
            'description': agenda_body,
            'start': {'dateTime': start_dt.isoformat(), 'timeZone': TIMEZONE},
            'end': {'dateTime': end_dt.isoformat(), 'timeZone': TIMEZONE},
            'reminders': {'useDefault': True},
        }

        logger.info(f"[GCAL] Creando evento en {calendar_id} → {start_dt} - {end_dt}")
        created_event = service.events().insert(calendarId=calendar_id, body=event).execute()

        logger.info(f"[GCAL] ¡ÉXITO TOTAL! Evento creado → ID: {created_event['id']}")
        logger.info(f"[GCAL] Link: {created_event.get('htmlLink')}")

        success_message = f'¡Reservado perfectamente! {slot_info["label"]} - {booking_date.strftime("%d/%m/%Y")} - Puedes agregar la cita en tu agenda abriendo el archivo que se descargo... ;)'
        flash(success_message, 'success')
        gcal_success = True

    except Exception as e:
        logger.error(f"[GCAL] ERROR al crear evento: {e}", exc_info=True)
        success_message = 'Turno guardado en web, pero falló Google Calendar → ver logs'
        flash(success_message, 'warning')
        gcal_success = False

    # Generar archivo .ICS
    try:
        ics_content = generate_ics_content(booking_date, slot_info, name, email, phone, TIMEZONE, agenda_body)
        
        # Nombre del archivo con fecha y nombre del cliente
        filename = f"cita_breeza_{booking_date.strftime('%Y%m%d')}_{name.replace(' ', '_')}.ics"
        
        logger.info(f"[ICS] Generando archivo .ICS: {filename}")
        
        # Si es una petición AJAX, devolver JSON con el archivo
        if is_ajax:
            ics_base64 = base64.b64encode(ics_content.encode('utf-8')).decode('utf-8')
            return jsonify({
                'success': True,
                'message': success_message,
                'filename': filename,
                'ics_content': ics_base64
            })
        else:
            # Comportamiento normal: descargar directamente
            ics_bytes = io.BytesIO(ics_content.encode('utf-8'))
            return send_file(
                ics_bytes,
                mimetype='text/calendar',
                as_attachment=True,
                download_name=filename
            )
    except Exception as e:
        logger.error(f"[ICS] Error al generar archivo .ICS: {e}", exc_info=True)
        if is_ajax:
            return jsonify({
                'success': False,
                'message': 'Cita guardada, pero hubo un error al generar el archivo .ICS'
            }), 500
        else:
            flash('Cita guardada, pero hubo un error al generar el archivo .ICS', 'warning')
            return redirect(url_for('index'))

# Crear tabla al arrancar
with app.app_context():
    db.create_all()
    dates_init, start_init, end_init = get_dates()
    logger.info("[INIT] Aplicación iniciada")
    logger.info(f"[INIT] Configuración: WEATHER_API_KEY={'***' if WEATHER_API_KEY else 'NO CONFIGURADA'}")
    logger.info(f"[INIT] LAT={LAT}, LON={LON}, TIMEZONE={TIMEZONE}")
    logger.info(f"[INIT] CALENDAR_ID={'***' if CALENDAR_ID else 'NO CONFIGURADA'}")
    logger.info(f"[INIT] CREDENTIALS_FILE existe: {os.path.exists(CREDENTIALS_FILE)}")
    logger.info(f"[INIT] Total de fechas disponibles: {len(dates_init)} (desde {start_init} hasta {end_init})")

if __name__ == '__main__':
    app.run(debug=True)