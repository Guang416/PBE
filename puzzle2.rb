require "gtk3"
require "thread"
require_relative "puzzle1" # Usar como librería el puzzle1 para manejar la lectura NFC

# Método para aplicar estilos CSS a la interfaz
def apply_css
  css_provider = Gtk::CssProvider.new
  css_provider.load(path: "disseny.css") # Carga el archivo CSS con los estilos personalizados

  style_context = Gtk::StyleContext
  screen = Gdk::Screen.default

  # Aplica el CSS a toda la pantalla
  style_context.add_provider_for_screen(screen, css_provider, Gtk::StyleProvider::PRIORITY_USER)
end

# Clase principal que gestiona la interfaz y la interacción con el lector NFC
class NFCApp
  def initialize
    apply_css # Aplica los estilos CSS al iniciar la interfaz

    # Crear la ventana principal
    @window = Gtk::Window.new("Rfid Window")
    @window.set_size_request(400, 200) # Establecer el tamaño de la ventana
    @window.signal_connect("destroy") { Gtk.main_quit } # Cerrar la aplicación al cerrar la ventana

    # Contenedor vertical para organizar los elementos
    @vbox = Gtk::Box.new(:vertical, 10)
    @window.add(@vbox)

    # Etiqueta para mostrar mensajes
    @label = Gtk::Label.new("Please, login with your university card")
    @label.override_background_color(:normal, Gdk::RGBA.new(0, 0, 1, 1)) # Fondo azul
    @label.override_color(:normal, Gdk::RGBA.new(1, 1, 1, 1)) # Texto en blanco
    @vbox.pack_start(@label, expand: true, fill: true, padding: 10)

    # Botón para limpiar la pantalla y reiniciar la lectura
    @clear_button = Gtk::Button.new(label: "Clear")
    @clear_button.signal_connect("clicked") { clear_label } # Conectar el botón a la acción de limpiar
    @vbox.pack_start(@clear_button, expand: false, fill: true, padding: 10)

    @window.show_all # Mostrar todos los elementos de la ventana

    # Inicializar el lector NFC
    begin
      @rfid = Rfid.new
    rescue StandardError => e
      update_label("No NFC reader found: #{e.message}", 1, 0, 0) # Mostrar error si no se detecta lector
      return
    end

    # Iniciar la primera lectura NFC
    start_reading_thread
  end

  # Método para iniciar un hilo que realice la lectura NFC
  def start_reading_thread
    Thread.new do
      lectura
      Thread.exit # Terminar el hilo después de la lectura
    end
  end

  # Método que realiza la lectura NFC y actualiza la UI
  def lectura
    @uid = @rfid.read_uid # Leer el UID de la tarjeta NFC
    GLib::Idle.add { gestion_UI } # Llamar a gestion_UI en el hilo principal de GTK
  end

  # Método que actualiza la interfaz gráfica cuando se detecta un UID
  def gestion_UI
    if @uid && !@uid.empty?
      update_label("UID: #{@uid}", 1, 0, 0) # Muestra el UID en pantalla con fondo rojo
    end
  end

  # Método para actualizar el texto y color de la etiqueta
  def update_label(text, r, g, b)
    @label.set_text(text) # Cambia el texto del label
    @label.override_background_color(:normal, Gdk::RGBA.new(r, g, b, 1)) # Cambia el fondo del label
  end

  # Método que se activa al pulsar "Clear": limpia la pantalla y reinicia la lectura
  def clear_label
    @uid = "" # Borra el UID almacenado
    update_label("Por favor, acerca tu tarjeta de identidad de la uni", 0, 0, 1) # Vuelve al estado inicial con fondo azul
    start_reading_thread # Relanza la lectura de NFC
  end
end

Gtk.init # Inicializa GTK
NFCApp.new # Crea una nueva instancia de la aplicación y lanza la interfaz
Gtk.main # Mantiene la aplicación en ejecución
