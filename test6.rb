require 'net/http'
require 'uri'
require 'json'
require_relative 'puzzle1'   # Tu clase Rfid para NFC

# Parámetros (IP y puerto opcionales)
SERVER_IP   = ARGV[0] || '172.20.10.3'
SERVER_PORT = (ARGV[1] || 3000).to_i

begin
  # 1) Leer UID por NFC
  puts "Acerca tu tarjeta NFC..."
  uid = Rfid.new.read_uid
  puts "→ UID leída: #{uid}"

  # 2) Fetch user usando /user/:uid
  uri = URI("http://#{SERVER_IP}:#{SERVER_PORT}/user/#{uid}")
  puts "Llamando a #{uri}..."
  res = Net::HTTP.get_response(uri) #Hace la solicitud HTTP y guarda la respuesta 

  # 3) Mostrar resultado
  if res.is_a?(Net::HTTPSuccess)
    user = JSON.parse(res.body)
    puts "Datos de usuario recibidos:"
    puts "  UID:  #{uid}"
    puts "  Name: #{user['name']}"
    # Si hay otros campos en el JSON:
    user.each do |k, v|
      next if k == 'name'
      puts "  #{k.capitalize}: #{v}"
    end
  else
    warn "Error al obtener usuario: #{res.code} #{res.message}"
    warn res.body
  end

rescue => e
  warn "¡Error!: #{e.class} - #{e.message}"
end