require "gtk3"
require "thread"
require_relative "LCDController"
require_relative "puzzle1"
require "json"
require "net/http"

CSS_FILE       = "disseny.css"
LOGIN_MESSAGE  = "Please,\nlogin with\nyour card"
AUTH_ERROR_MSG = "Authentication\nerror"
API_BASE       = "http://10.192.40.80:3000"
TIMEOUT_SEC    = 120

def apply_css
  provider = Gtk::CssProvider.new
  provider.load(path: CSS_FILE)
  Gtk::StyleContext.add_provider_for_screen(
    Gdk::Screen.default,
    provider,
    Gtk::StyleProvider::PRIORITY_USER
  )
end

class MainWindow
  def initialize(lcd)
    apply_css
    @lcd = lcd
    @rfid_thread = nil
    @timeout_id  = nil

    @window = Gtk::Window.new("Course Manager")
    @window.set_default_size(500, 200)
    @window.signal_connect("destroy") { cleanup_and_quit }

    show_login
    Gtk.main
  end

  private

  def cleanup_and_quit
    @rfid_thread&.kill
    Gtk.main_quit
  end

  def clear_window
    @window.children.each { |w| @window.remove(w) }
  end

  # — Login screen —
  def show_login
    clear_window
    @lcd.printCenter(LOGIN_MESSAGE)

    @frame = Gtk::Frame.new
    @frame.set_border_width(10)
    @frame.override_background_color(:normal, blue)

    vbox = Gtk::Box.new(:vertical, 5)
    @frame.add(vbox)

    # Aquí creamos directamente el label sin build_label
    @label = Gtk::Label.new("Please, login with your university card")
    @label.override_color(:normal, white)
    @label.set_halign(:center)
    vbox.pack_start(@label, expand: true, fill: true, padding: 10)

    @window.add(@frame)
    @window.show_all

    start_rfid_read
  end

  def start_rfid_read
    @rfid_thread&.kill
    @rfid_thread = Thread.new do
      begin
        rfid = Rfid.new
        uid  = rfid.read_uid
        puts "UID leído: #{uid}"
        GLib::Idle.add { authenticate(uid); false }
      rescue => e
        GLib::Idle.add { show_reader_error(e.message); false }
      end
    end
  end

  def show_reader_error(msg)
    @label.text = "Reader error: #{msg}"
    @frame.override_background_color(:normal, red)
    @lcd.printCenter("Reader\nerror")
  end

  # — Authentication —
  def authenticate(uid)
    response = Net::HTTP.get_response(URI("#{API_BASE}/students?student_id=#{uid}"))
    if response.is_a?(Net::HTTPSuccess)
      data = JSON.parse(response.body) rescue {}
      students = data["students"]
      if students.is_a?(Array) && !students.empty?
        @student_name = students.first["name"]
        show_query_screen
      else
        show_auth_error
      end
    else
      show_auth_error
    end
  rescue
    show_auth_error
  end

  def show_auth_error
    @label.text = "Authentication error, please try again."
    @frame.override_background_color(:normal, red)
    @lcd.printCenter(AUTH_ERROR_MSG)
  end

  # — Query screen —
  def show_query_screen
    clear_timeout
    clear_window
    @frame&.destroy
    @lcd.printCenter("Welcome\n#{@student_name}")

    vbox = Gtk::Box.new(:vertical, 5)
    @window.add(vbox)

    welcome_label = Gtk::Label.new("Welcome #{@student_name}")
    welcome_label.override_color(:normal, white)
    welcome_label.set_halign(:start)
    vbox.pack_start(welcome_label, expand: false, fill: true, padding: 10)

    # Entry + Go
    hbox = Gtk::Box.new(:horizontal, 5)
    @entry  = Gtk::Entry.new.tap { |e| e.set_placeholder_text("timetables, tasks, marks") }
    @go_btn = Gtk::Button.new(label: "Go")
    @go_btn.signal_connect("clicked") { perform_query }
    hbox.pack_start(@entry, expand: true, fill: true, padding: 0)
    hbox.pack_start(@go_btn, expand: false, fill: false, padding: 0)
    vbox.pack_start(hbox, expand: false, fill: true, padding: 5)

    # Results TreeView
    @store = Gtk::ListStore.new
    @tree  = Gtk::TreeView.new(@store)
    scrolled = Gtk::ScrolledWindow.new
    scrolled.set_policy(:automatic, :automatic)
    scrolled.add(@tree)
    vbox.pack_start(scrolled, expand: true, fill: true, padding: 5)

    # Logout
    btn_logout = Gtk::Button.new(label: "Logout")
    btn_logout.signal_connect("clicked") do
      clear_timeout
      show_login
    end
    vbox.pack_start(btn_logout, expand: false, fill: false, padding: 10)

    @window.show_all
    start_timeout
  end

  def perform_query
    reset_timeout
    query = @entry.text.strip
    Thread.new do
      begin
        data = fetch_data(query)
        GLib::Idle.add { populate_tree(data); false }
      rescue => e
        GLib::Idle.add { show_error("Error: #{e.message}"); false }
      end
    end
  end

  def fetch_data(path)
    uri = URI("#{API_BASE}/#{path}")
    res = Net::HTTP.get_response(uri)
    raise "HTTP #{res.code}" unless res.is_a?(Net::HTTPSuccess)
    JSON.parse(res.body)
  end

  def populate_tree(arr)
    @store.clear
    return if arr.empty?

    if @tree.columns.empty?
      keys = arr.first.keys
      @store = Gtk::ListStore.new(*Array.new(keys.size, String))
      @tree.model = @store
      keys.each_with_index do |k, i|
        col = Gtk::TreeViewColumn.new(k.capitalize, Gtk::CellRendererText.new, text: i)
        @tree.append_column(col)
      end
    end

    arr.each do |row|
      iter = @store.append
      row.values.each_with_index { |v, i| iter[i] = v.to_s }
    end
  end

  def show_error(msg)
    dlg = Gtk::MessageDialog.new(
      parent: @window,
      flags:   :modal,
      type:    :error,
      buttons: :close,
      message: msg
    )
    dlg.run
    dlg.destroy
  end

  # — Timeout management —
  def start_timeout
    @timeout_id = GLib::Timeout.add_seconds(TIMEOUT_SEC) do
      show_login
      false
    end
  end

  def reset_timeout
    clear_timeout
    start_timeout
  end

  def clear_timeout
    GLib::Source.remove(@timeout_id) if @timeout_id
  end

  # — Color helpers —
  def blue()  = Gdk::RGBA.new(0, 0, 1, 1)
  def red()   = Gdk::RGBA.new(1, 0, 0, 1)
  def white() = Gdk::RGBA.new(1, 1, 1, 1)
end

# Arranque
lcd = LCDController.new
MainWindow.new(lcd)
