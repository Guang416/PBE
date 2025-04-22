require "gtk3"
require "thread"
require_relative "LCDController"
require_relative "puzzle1"
require "json"
require "net/http"

def apply_css
  css_provider = Gtk::CssProvider.new
  css_provider.load(path: "disseny.css") # Carga el archivo CSS con los estilos personalizados

  style_context = Gtk::StyleContext
  screen = Gdk::Screen.default

  # Aplica el CSS a toda la pantalla
  style_context.add_provider_for_screen(screen, css_provider, Gtk::StyleProvider::PRIORITY_USER)
end

class MainWindow
  TIMEOUT_SECONDS = 120

  def initialize(lcd_controller)
    apply_css
    @lcd_controller = lcd_controller
    @thread = nil

    @window = Gtk::Window.new("course_manager.rb")
    @window.set_default_size(500, 200)
    @window.signal_connect("destroy") { cleanup_and_quit }

    ventana_inicio
    Gtk.main
  end

  def cleanup_and_quit
    @thread&.kill
    Gtk.main_quit
  end

  def ventana_inicio
    @lcd_controller.printCenter("Please,\nlogin with\nyour card")

    @window.each { |w| @window.remove(w) }

    @frame = Gtk::Frame.new
    @frame.set_border_width(10)
    @frame.override_background_color(:normal, Gdk::RGBA.new(0, 0, 1, 1))

    box = Gtk::Box.new(:vertical, 5)
    @frame.add(box)

    @label = Gtk::Label.new("Please, login with your university card")
    @label.override_color(:normal, Gdk::RGBA.new(1, 1, 1, 1))
    @label.set_halign(:center)
    box.pack_start(@label, expand: true, fill: true, padding: 10)

    @window.add(@frame)
    @window.show_all

    iniciar_rfid
  end

  def iniciar_rfid
    @rfid = Rfid.new
    @thread = Thread.new do
      uid = @rfid.read_uid
      puts "UID leído: #{uid}"
      GLib::Idle.add do
        autenticacion(uid)
        false
      end
    end
  rescue StandardError => e
    @label.set_text("Reader error: #{e.message}")
    @frame.override_background_color(:normal, Gdk::RGBA.new(1, 0, 0, 1))
    @lcd_controller.printCenter("Reader\nerror")
  end

  def autenticacion(uid)
    uri = URI("http://10.192.40.80:3000/students?student_id=#{uid}")
    response = Net::HTTP.get_response(uri)

    unless response.is_a?(Net::HTTPSuccess)
      autent_fail; return
    end

    datos = JSON.parse(response.body)
    students = datos["students"] rescue nil

    if students.is_a?(Array) && !students.empty?
      @nombre = students.first["name"]
      ventana_query
    else
      autent_fail
    end
  rescue StandardError => e
    puts "Auth error: #{e.message}"
    autent_fail
  end

  def autent_fail
    @lcd_controller.printCenter("Authentication\nerror")
    @label.set_markup("Authentication error,\nplease try again.")
    @frame.override_background_color(:normal, Gdk::RGBA.new(1, 0, 0, 1))
  end

  def ventana_query
    iniciar_timeout
    @frame.destroy
    @lcd_controller.printCenter("Welcome\n#{@nombre}")

    @table = Gtk::Table.new(2, 2, true)
    @table.set_column_spacing(300)
    @table.set_row_spacings(10)

    lbl_name = Gtk::Label.new("Welcome\n#{@nombre}")
    lbl_name.set_halign(:start)

    @query_entry = Gtk::Entry.new
    @query_entry.set_placeholder_text("timetables, tasks, marks")

    btn_logout = Gtk::Button.new(label: "Logout")
    btn_logout.signal_connect("clicked") do
      detener_timeout
      ventana_inicio
    end

    @table.attach(lbl_name, 0, 1, 0, 1, :SHRINK, :SHRINK, 10, 10)
    @table.attach(btn_logout, 1, 2, 0, 1, :SHRINK, :SHRINK, 10, 10)
    @table.attach(@query_entry, 0, 2, 1, 2, :FILL, :EXPAND, 10, 10)

    @query_entry.signal_connect("activate") do
      detener_timeout
      iniciar_timeout
      url = "http://10.192.40.80:3000/#{@query_entry.text.strip}"
      mostrar_datos_json(url)
      @query_entry.text = ""
    end

    @window.add(@table)
    @window.show_all
  end

  def mostrar_datos_json(url)
    datos = JSON.parse(Net::HTTP.get(URI(url))) rescue nil
    return puts("Consulta no valida") if datos.nil? || datos["error"]

    titulo = datos.keys.first
    lista  = datos[titulo]
    return puts("Query vacía") if lista.nil? || lista.empty?

    headers = lista.first.keys[0..-2]

    @tabla = Gtk::Window.new
    @tabla.set_title(titulo)
    @tabla.set_default_size(400, 300)

    grid = Gtk::Grid.new
    grid.set_row_spacing(5)
    grid.set_column_spacing(5)
    @tabla.add(grid)

    headers.each_with_index do |h, i|
      header = Gtk::Label.new(h)
      header.override_background_color(:normal, Gdk::RGBA.new(0.95, 0.95, 0.5, 1.0))
      grid.attach(header, i, 0, 1, 1)
    end

    lista.each_with_index do |item, r|
      item.values[0..-2].each_with_index do |v, c|
        cell = Gtk::Label.new(v.to_s)
        color = r.even? ? Gdk::RGBA.new(0.7, 0.7, 1, 1) : Gdk::RGBA.new(0.5, 0.5, 1, 1)
        cell.override_background_color(:normal, color)
        grid.attach(cell, c, r + 1, 1, 1)
      end
    end

    @tabla.show_all
  end

  def iniciar_timeout
    @timeout_id = GLib::Timeout.add_seconds(TIMEOUT_SECONDS) do
      puts "Timeout: volviendo al login"
      ventana_inicio
      @tabla&.hide
      false
    end
  end

  def detener_timeout
    GLib::Source.remove(@timeout_id) if @timeout_id
  end
end

# Arranque
lcd = LCDController.new
MainWindow.new(lcd)
