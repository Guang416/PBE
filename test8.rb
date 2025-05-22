require 'net/http'
require 'uri'
require 'json'
require_relative 'puzzle1'

SERVER_IP   = '172.20.10.3'
SERVER_PORT = 3000

def fetch_data(endpoint)
  uri      = URI("http://#{SERVER_IP}:#{SERVER_PORT}#{endpoint}")
  response = Net::HTTP.get_response(uri)
  JSON.parse(response.body) if response.is_a?(Net::HTTPSuccess)
end

def display_timetable(timetables)
  puts "\n HORARIO ACADÉMICO"
  puts "═" * 50

  # Agrupar por día
  by_day = timetables.group_by { |t| t['day'] }

  # Mostrar para cada día de lunes a viernes

  %w[Mon Tue Wed Thu Fri].each do |day|
    next unless by_day[day]

    puts "\n#{day_to_spanish(day)}:"
    puts "-" * 30
    #Ordena las clases del día por hora y las imprime
    by_day[day]
      .sort_by { |t| t['hour'] }
      .each do |entry|
        puts " #{entry['hour']} │ #{entry['subject']}"
        puts " #{entry['room']}  │ #{entry['teacher']}"
        puts "-" * 30
      end
  end
end

# Función auxiliar para traducir los días de inglés a español
def day_to_spanish(day)
  {
    'Mon' => 'Lunes',
    'Tue' => 'Martes',
    'Wed' => 'Miércoles',
    'Thu' => 'Jueves',
    'Fri' => 'Viernes'
  }[day] || day
end
# Bloque principal del programa
begin
  puts " Acerca tu tarjeta NFC..."
  uid = Rfid.new.read_uid
  puts " UID: #{uid}"

  # Obtener datos básicos
  user = fetch_data("/user/#{uid}")
  puts "\n Estudiante: #{user['name']}" if user

  # Obtener horario académico
  timetables = fetch_data("/timetables")
  display_timetable(timetables) if timetables

  # Obtener calificaciones
  marks = fetch_data("/user/#{uid}/marks")
  if marks&.any?
    puts "\nCalificaciones:"
    marks.each do |m|
      puts "  #{m['subject']}: #{m['value']}"
    end
  else
    puts "\nNo se encontraron calificaciones"
  end

rescue => e
  puts " Error: #{e.message}"
end