require "gtk3"
require_relative "LCDController"
require_relative "Rfid"
require "json"
require "net/http"

CSS_FILE     = "disseny.css"
LOGIN_MSG    = "Please,\nlogin with\nyour card"
AUTH_ERR_MSG = "Authentication\nerror"
API_BASE     = "http://10.192.40.80:3000"
TIMEOUT_SEC  = 120

# Aplica CSS global
def apply_css
  provider = Gtk::CssProvider.new
  provider.load(path: CSS_FILE)
  Gtk::StyleContext.add_provider_for_screen(
    Gdk::Screen.default,
    provider,
    Gtk::StyleProvider::PRIORITY_USER
  )
end

# Encapsula la lectura de NFC en un solo hilo y handler
class RfidReader
  def initialize(on_success, on_error = nil)
    @on_success = on_success
    @on_error   = on_error
    @thread     = nil
  end

  def start
    stop
    @thread = Thread.new do
      begin
        uid = Rfid.new.read_uid
        GLib::Idle.add { @on_success.call(uid); false }
      rescue => ex
        GLib::Idle.add { @on_error&.call(ex); false }
      end
    end
  end

  def stop
    @thread&.kill
    @thread = nil
  end
end

# Encapsula petición HTTP GET y parseo JSON
class HttpRequest
  def initialize(path, on_complete)
    @path         = path
    @on_complete  = on_complete
    @thread       = Thread.new { perform }
  end

  def perform
    begin
      uri = URI("#{API_BASE}#{@path}")
      res = Net::HTTP.get_response(uri)
      raise "HTTP #{res.code}" unless res.is_a?(Net::HTTPSuccess)
      json = JSON.parse(res.body)
      GLib::Idle.add { @on_complete.call(json, nil); false }
    rescue => ex
      GLib::Idle.add { @on_complete.call(nil, ex); false }
    end
  end
end

class MainWindow
  def initialize(lcd)
    apply_css
    @lcd          = lcd
    @rfid_reader  = nil
    @timeout_id   = nil
    @window       = Gtk::Window.new("Course Manager")
    @window.set_default_size(500, 200)
    @window.signal_connect("destroy") { cleanup_and_quit }

    show_login
    Gtk.main
  end

  private

  def cleanup_and_quit
    @rfid_reader&.stop
    Gtk.main_quit
  end

  def clear_window
    @window.children.each { |w| @window.remove(w) }
  end

  # — Pantalla de login NFC —
  def show_login
    clear_timeout
    clear_window
    @lcd.printCenter(LOGIN_MSG)

    @frame = Gtk::Frame.new
    @frame.set_border_width(10)
    @frame.override_background_color(:normal, blue)
    @window.add(@frame)

    vbox = Gtk::Box.new(:vertical, 5)
    @frame.add(vbox)

    @label = Gtk::Label.new("Please, login with your university card")
    @label.override_color(:normal, white)
    @label.set_halign(:center)
    vbox.pack_start(@label, expand: true, fill: true, padding: 10)

    @window.show_all
    @rfid_reader = RfidReader.new(method(:authenticate), method(:show_reader_error))
    @rfid_reader.start
  end

  def show_reader_error(ex)
    @label.text = "Reader error: #{ex.message}"
    @frame.override_background_color(:normal, red)
    @lcd.printCenter("Reader\nerror")
    # reintentar
    GLib::Timeout.add_seconds(2) { @rfid_reader.start; false }
  end

  # — Autenticación genérica vía HttpRequest —
  def authenticate(uid)
    HttpRequest.new("/students?student_id=#{uid}", lambda do |data, err|
      if err || !data["students"].is_a?(Array) || data["students"].empty?
        show_auth_error
      else
        @student_name = data["students"].first["name"]
        @uid = uid
        show_query_screen
      end
    end)
  end

  def show_auth_error
    @label.text = "Authentication error, try again"
    @frame.override_background_color(:normal, red)
    @lcd.printCenter(AUTH_ERR_MSG)
    # reintentar NFC
    GLib::Timeout.add_seconds(2) { @rfid_reader.start; false }
  end

  # — Pantalla de consulta genérica —
  def show_query_screen
    clear_window
    @lcd.printCenter("Welcome\n#{@student_name}")

    vbox = Gtk::Box.new(:vertical, 5)
    vbox.margin = 10
    @window.add(vbox)

    # Título
    label = Gtk::Label.new("Welcome #{@student_name}")
    label.override_color(:normal, white)
    vbox.pack_start(label, expand: false, fill: false, padding: 5)

    # Entrada de tabla
    @entry = Gtk::Entry.new
    @entry.set_placeholder_text("timetables, tasks o marks")
    @entry.signal_connect("activate") { perform_query }
    vbox.pack_start(@entry, expand: false, fill: true, padding: 5)

    # ScrolledWindow para resultados
    @sw = Gtk::ScrolledWindow.new
    @sw.set_policy(:automatic, :automatic)
    @sw.set_vexpand(true)
    vbox.pack_start(@sw, expand: true, fill: true, padding: 5)

    # Logout
    logout = Gtk::Button.new(label: "Logout")
    logout.signal_connect("clicked") { show_login }
    vbox.pack_start(logout, expand: false, fill: false, padding: 5)

    @window.show_all
    start_timeout
  end

  # — Ejecuta Query genérico —
  def perform_query
    reset_timeout
    table = @entry.text.strip
    path  = "/user/#{@uid}/#{table}"
    HttpRequest.new(path, lambda do |data, err|
      if err
        show_error(err.message)
      else
        populate_tree(data)
      end
    end)
  end

  # — Pinta el TreeView genérico —
  def populate_tree(arr)
    @sw.remove(@sw.child) if @sw.child
    return if arr.nil? || arr.empty?

    store = Gtk::ListStore.new(*Array.new(arr.first.size, String))
    tree  = Gtk::TreeView.new(store)
    arr.first.keys.each_with_index do |k,i|
      col = Gtk::TreeViewColumn.new(k.capitalize, Gtk::CellRendererText.new, text: i)
      tree.append_column(col)
    end
    arr.each do |row|
      iter = store.append
      row.values.each_with_index { |v,i| iter[i] = v.to_s }
    end
    @sw.add(tree)
    tree.show_all
  end

  def show_error(msg)
    dlg = Gtk::MessageDialog.new(
      parent: @window,
      flags:   :modal,
      type:    :error,
      buttons: :close,
      message: msg
    )
    dlg.run; dlg.destroy
  end

  # — Timeout automático —
  def start_timeout
    clear_timeout
    @timeout_id = GLib::Timeout.add_seconds(TIMEOUT_SEC) {
      show_login; false
    }
  end

  def reset_timeout
    clear_timeout; start_timeout
  end

  def clear_timeout
    GLib::Source.remove(@timeout_id) if @timeout_id
  end

  # — Helpers color —
  def blue()  = Gdk::RGBA.new(0,0,1,1)
  def red()   = Gdk::RGBA.new(1,0,0,1)
  def white() = Gdk::RGBA.new(1,1,1,1)
end

# Arranque de la app
lcd = LCDController.new
MainWindow.new(lcd)
