require "gtk3"
require "thread"
require "net/http"
require "json"
require_relative "puzzle1"   # Tu clase Rfid para NFC
require_relative "LCDController"

BLUE   = Gdk::RGBA.new(0, 0, 1, 1)
RED    = Gdk::RGBA.new(1, 0, 0, 1)
WHITE  = Gdk::RGBA.new(1, 1, 1, 1)
CSS    = "disseny.css"       # Tu archivo de estilos

# Aplicar CSS a toda la app 
def apply_css
  provider = Gtk::CssProvider.new
  provider.load(path: CSS)
  screen = Gdk::Screen.default
  Gtk::StyleContext.add_provider_for_screen(
    screen, provider, Gtk::StyleProvider::PRIORITY_USER
  )
end

class NFCApp
  def initialize
    apply_css
    build_login_window
    Gtk.init
    Gtk.main
  end

  # Ventana de login NFC 
  def build_login_window
    @login_win = Gtk::Window.new("Login NFC")
    @login_win.set_size_request(400, 200)
    @login_win.signal_connect("destroy") { Gtk.main_quit }

    vbox = Gtk::Box.new(:vertical, 10)
    @login_win.add(vbox)

    @label = Gtk::Label.new("Please, login with your university card")
    @label.override_background_color(:normal, BLUE)
    @label.override_color(:normal, WHITE)
    vbox.pack_start(@label, expand: true, fill: true, padding: 20)

    # Iniciar lectura NFC en hilo
    begin
      @rfid = Rfid.new
      start_read_thread { |uid| on_login(uid) }
    rescue => e
      @label.set_text("Error: #{e.message}")
      @label.override_background_color(:normal, RED)
    end

    @login_win.show_all
  end

  # Tras login, montamos la ventana principal 
  def on_login(uid)
    # Aquí podrías consultar al servidor para validar y obtener nombre:
    student = "UID: #{uid}"
    Gtk::Idle.add do
      @login_win.destroy
      build_main_window(student)
    end
  end

  # Ventana principal 
  def build_main_window(student_name)
    @main_win = Gtk::Window.new("Course Manager")
    @main_win.set_size_request(600, 400)
    @main_win.signal_connect("destroy") { Gtk.main_quit }

    vbox = Gtk::Box.new(:vertical, 5)
    @main_win.add(vbox)

    # Bienvenida
    welcome = Gtk::Label.new("Welcome #{student_name}")
    vbox.pack_start(welcome, expand: false, fill: true, padding: 10)

    # Entrada + Go
    hbox = Gtk::Box.new(:horizontal, 5)
    @entry = Gtk::Entry.new
    @go_btn = Gtk::Button.new(label: "Go")
    hbox.pack_start(@entry, expand: true, fill: true, padding: 0)
    hbox.pack_start(@go_btn, expand: false, fill: false, padding: 0)
    vbox.pack_start(hbox, expand: false, fill: true, padding: 5)

    # TreeView para resultados
    @store = Gtk::ListStore.new
    @tree  = Gtk::TreeView.new(@store)
    scrolled = Gtk::ScrolledWindow.new
    scrolled.set_policy(:automatic, :automatic)
    scrolled.add(@tree)
    vbox.pack_start(scrolled, expand: true, fill: true, padding: 5)

    # Logout
    @logout_btn = Gtk::Button.new(label: "Logout")
    vbox.pack_start(@logout_btn, expand: false, fill: false, padding: 10)

    # Señales
    @go_btn.signal_connect("clicked")    { perform_query }
    @logout_btn.signal_connect("clicked") { logout }

    @main_win.show_all
    reset_inactivity_timer
  end

  # Lectura NFC en hilo, una sola vez 
  def start_read_thread(&handler)
    Thread.new do
      uid = @rfid.read_uid
      handler.call(uid) if handler
      Thread.exit
    end
  end

  # Enviar consulta HTTP y poblar tabla 
  def perform_query
    reset_inactivity_timer
    query = @entry.text.strip
    Thread.new do
      begin
        data = fetch_data(query)
        GLib::Idle.add { populate_tree(data) }
      rescue => e
        GLib::Idle.add { show_error("Error: #{e.message}") }
      end
    end
  end

  def fetch_data(path)
    uri = URI("http://SERVIDOR/#{path}")
    res = Net::HTTP.get_response(uri)
    raise "HTTP #{res.code}" unless res.is_a?(Net::HTTPSuccess)
    JSON.parse(res.body)  # Espera Array de Hashes
  end

  #  Crear columnas y filas dinámicamente 
  def populate_tree(arr)
    @store.clear
    return if arr.empty?

    # Primera vez: columnas
    if @tree.columns.empty?
      keys  = arr.first.keys
      types = arr.first.values.map{ String }  # todo a String
      @store = Gtk::ListStore.new(*types)
      @tree.model = @store
      keys.each_with_index do |k,i|
        r = Gtk::CellRendererText.new
        c = Gtk::TreeViewColumn.new(k.capitalize, r, text: i)
        @tree.append_column(c)
      end
    end

    # Filas
    arr.each do |row|
      iter = @store.append
      row.values.each_with_index { |v,i| iter[i] = v.to_s }
    end
  end

  #  Dialogo de error 
  def show_error(msg)
    dlg = Gtk::MessageDialog.new(
      parent: @main_win,
      flags:   :modal,
      type:    :error,
      buttons: :close,
      message: msg
    )
    dlg.run; dlg.destroy
  end

  #  Inactividad 
  def reset_inactivity_timer
    GLib::Source.remove(@timer) if @timer
    @timer = GLib::Timeout.add(2*60*1000) { logout; false }
  end

  #  Logout  volver a login NFC 
  def logout
    @main_win.destroy
    build_login_window
  end
end

# Arranque de la app 
NFCApp.new
