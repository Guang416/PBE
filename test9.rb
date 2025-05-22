require 'net/http'
require 'uri'
require 'json'
require_relative 'puzzle1' # Tu librería NFC

SERVER_IP = '172.20.10.3'
SERVER_PORT = 3000

def fetch_data(endpoint, params = {})
  uri = URI("http://#{SERVER_IP}:#{SERVER_PORT}#{endpoint}")
  uri.query = URI.encode_www_form(params) if params.any?
  response = Net::HTTP.get_response(uri)
  JSON.parse(response.body) if response.is_a?(Net::HTTPSuccess)
end

begin
  # 1. Leer UID del NFC
  puts "Acerca tu tarjeta NFC..."
  uid = Rfid.new.read_uid
  puts " UID: #{uid}"

  # 2. Obtener datos del estudiante
  student = fetch_data("/students/#{uid}")
  puts "\n Estudiante: #{student['name']}" if student
  
  # 3. Obtener notas
  marks = fetch_data("/user/#{uid}/marks", { uid: uid })
  if marks&.any?
    puts "\nCalificaciones:"
    marks.each { |m| puts "  #{m['subject']}: #{m['value']}" }
  else
    puts "\nNo se encontraron calificaciones"
  end


  rescue => e
  puts " Error: #{e.message}"
end