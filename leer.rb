require 'ruby-nfc'

class Rfid
  def initialize
    @readers = NFC::Reader.all
    if @readers.empty?
      puts "No se encontraron lectores NFC."
      exit
    end
  end

  def read_uid
    @readers[0].poll(Mifare::Classic::Tag) do |tag|
      begin
        return tag.uid_hex.upcase
      rescue StandardError => e
        puts "Error al leer la tarjeta: #{e.message}"
        return nil
      end
    end
    nil
  end
end

if __FILE__ == $0
  rf = Rfid.new
  puts "Acerque la tarjeta NFC..."
  uid = rf.read_uid

  if uid
    puts "UID de la tarjeta: #{uid}"
  else
    puts "Error al leer la tarjeta."
  end
end