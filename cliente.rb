require "gtk3"
require "thread"
require_relative 'LCDController'
require_relative 'puzzle1'
require 'json'
require 'net/http'


class MainWindow < Gtk::Window
  def initialize(lcd_controller)
    @lcd_controller = lcd_controller
    @window = Gtk::Window.new("course_manager.rb")
    @window.set_default_size(500, 200) # Configurar el tamaño de la ventana
    @thread = nil # Inicializar el hilo como nulo al principio

    # Conectar la señal "destroy" para cerrar la aplicación cuando se cierra la ventana
    @window.signal_connect("destroy") do
      Gtk.main_quit
      @thread.kill if @thread # Detiene la ejecución del thread
      Gtk.main_quit
    end

    ventana_inicio # Crear el contenido de la ventana_inicio
  end

  def ventana_inicio
    @lcd_controller.printCenter("Please, login with your university card") # Mostrar el mensaje inicial en la LCD

    @window.children.each { |widget| @window.remove(widget) } # Eliminar los widgets existentes

    # Crear un marco para enmarcar el mensaje
    @frame = Gtk::Frame.new
    @frame.set_border_width(10)
    @frame.override_background_color(:normal, Gdk::RGBA.new(0, 0, 1, 1)) # Color azul

    # Crear un contenedor Gtk::Box dentro del marco para organizar verticalmente
    box = Gtk::Box.new(:vertical, 5)
    @frame.add(box)

    # Mensaje antes de la autenticación
    @label = Gtk::Label.new("Please, login with your university card")
    @label.override_color(:normal, Gdk::RGBA.new(1, 1, 1, 1)) # Color blanco
    @label.set_halign(:center) # Centrar el texto horizontalmente en la etiqueta
    box.pack_start(@label, expand: true, fill: true, padding: 10)

    @window.add(@frame) # Agregar el marco a la ventana
    @window.show_all

    rfid # Poner en marcha la lectura RFID
  end

  def rfid
   #@rfid = SimuladorNFC.new # Cambiar aqu�: de Rfid a SimuladorNFC
    @rfid = Rfid.new # Crear una nueva instancia de la clase Rfid
    iniciar_lectura_rfid # Iniciar lectura RFID
  end

  def iniciar_lectura_rfid
    # Crea un thread para leer el uid
    @thread = Thread.new do
      @uid = @rfid.read_uid 

      puts "UID leído: #{@uid}" 

      GLib::Idle.add do
        autenticacion(@uid)
        false # Para detener la repetición de la llamada a la función
      end
    end
  end

  def autenticacion(uid)
    uri = URI("http://10.192.40.80:3000/students?student_id=#{uid}")
    begin
      response = Net::HTTP.get_response(uri)
      if response.is_a?(Net::HTTPSuccess)
        datos = JSON.parse(response.body)
      else
        puts "Error en la respuesta del servidor: #{response.code} - #{response.message}"
        @lcd_controller.printCenter("Error de autenticación.")
        @label.set_markup("Authentication error, please try again.")
        @frame.override_background_color(:normal, Gdk::RGBA.new(1, 0, 0, 1)) # Color rojo
        return
      end
  
      if datos.is_a?(Hash) && datos["students"].is_a?(Array) && !datos["students"].empty?
        student = datos["students"].first
        @nombre = student["name"]
        ventana_query
        puts student["name"]
      else
        @lcd_controller.printCenter("Authentication error, please try again.")
        @label.set_markup("Authentication error, please try again.")
        @frame.override_background_color(:normal, Gdk::RGBA.new(1, 0, 0, 1)) # Color rojo
        puts "Error: datos vacíos o sin estudiantes."
      end
    rescue JSON::ParserError => e
      puts "Error al parsear el JSON: #{e.message}"
    rescue StandardError => e
      puts "Error al conectar con el servidor: #{e.message}"
    end
  end
  

  def ventana_query
    iniciar_timeout # Empezar timeout
    ip = '10.192.40.80'
    @frame.destroy # Eliminar los widgets existentes de la ventana anterior
    @lcd_controller.printCenter("Welcome \n #{@nombre}") # Mostrar el mensaje en la LCD

    # Crear estructura de la ventana
    @table = Gtk::Table.new(2, 2, true)
    @table.set_column_spacing(300)
    @table.set_row_spacings(10)

    @nombre = Gtk::Label.new("Welcome \n #{@nombre}")
    @query_entry = Gtk::Entry.new
    @query_entry.set_placeholder_text("Ingrese query (timetables, tasks, marks)")

    @button = Gtk::Button.new(label: 'logout')
    @button.set_size_request(50, 50)
    @button.signal_connect('clicked') do
      ventana_inicio
      detener_timeout
    end

    # Colocar los widgets en la tabla
    @table.attach(@nombre, 0, 1, 0, 1, Gtk::AttachOptions::SHRINK, Gtk::AttachOptions::SHRINK, 10, 10)
    @table.attach(@button, 1, 2, 0, 1, Gtk::AttachOptions::SHRINK, Gtk::AttachOptions::SHRINK, 10, 10)
    @table.attach(@query_entry, 0, 2, 1, 2, Gtk::AttachOptions::FILL, Gtk::AttachOptions::EXPAND, 10, 10)

    # Manejar el evento 'activate' (presionar Enter)
    @query_entry.signal_connect("activate") do
      detener_timeout
      iniciar_timeout
      query = @query_entry.text.strip
      url = "http://%s:9000/" % ip + query
      mostrar_datos_json(url)
      @query_entry.text = "" # Limpiar el campo de entrada después de la consulta
    end

    @window.add(@table)
    @window.show_all
  end

  def mostrar_datos_json(url)
    # Obtener los datos JSON desde la URL
    uri = URI(url)
    json_content = Net::HTTP.get(uri)
    datos = JSON.parse(json_content)

    # Tratamiento de errores
    if datos["error"]
      puts "Consulta no valida"
      return
    end

    # Obtener el título y la lista de resultados
    titulo = datos.keys.first
    if datos[titulo].empty?
      puts "Query vacia"
      return
    end

    headers = datos[titulo][0].keys
    headers.pop # Eliminar el último elemento que no necesitamos mostrar
    lista = datos[titulo] # Obtener la lista correspondiente

    # Crear la ventana para mostrar los datos
    @tabla = Gtk::Window.new
    @tabla.set_title(titulo)
    @tabla.set_default_size(400, 300)

    grid = Gtk::Grid.new
    grid.set_row_spacing(5)
    grid.set_column_spacing(5)
    @tabla.add(grid)

    # Encabezados de la tabla
    headers.each_with_index do |encabezado, index|
      header_label = Gtk::Label.new(encabezado)
      header_label.override_background_color(:normal, Gdk::RGBA.new(0.95, 0.95, 0.5, 1.0)) # amarillo
      grid.attach(header_label, index, 0, 1, 1)
      header_label.hexpand = true
    end

    # Mostrar los datos
    lista.each_with_index do |item, row_index|
      item.each_with_index do |(key, value), column_index|
        next if column_index == item.size - 1
        tarea_label = Gtk::Label.new(value.to_s)
        grid.attach(tarea_label, column_index, row_index + 1, 1, 1)
        tarea_label.hexpand = true
        if row_index % 2 == 0
          tarea_label.override_background_color(:normal, Gdk::RGBA.new(0.7, 0.7, 1.0, 1.0)) # Azul claro
        else
          tarea_label.override_background_color(:normal, Gdk::RGBA.new(0.5, 0.5, 1.0, 1.0)) # Azul
        end
      end
    end
    @tabla.show_all # Mostrar todo
  end

  def iniciar_timeout
    @timeout_id = GLib::Timeout.add_seconds(120) do
      puts "Se han superado los 15 segundos."
      ventana_inicio
      @tabla.hide
      false # Para que el temporizador no se repita
    end
  end

  def detener_timeout
    GLib::Source.remove(@timeout_id) if @timeout_id
  end
end

lcd_controller = LCDController.new # Crear una instancia de LCDController
MainWindow.new(lcd_controller) # Ejecutar la aplicación
Gtk.main
