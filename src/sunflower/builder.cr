module Sunflower
  class Builder
    include Elements

    Log = ::Log.for(self)

    @base_dir : String = Dir.current

    @application : Gtk::Application? = nil
    @window : Gtk::ApplicationWindow? = nil

    def initialize
    end

    def build_from_file(file_path : String) : Nil
      Log.info { "Loading file: #{file_path}" }

      @base_dir = File.dirname(file_path)
      source = File.read(file_path)

      build_from_string(source)
    end

    def build_from_string(string : String) : Nil
      raise Exceptions::EmptyComponentException.new if string.empty?

      Log.debug { "Parsing #{string.bytesize} bytes of markup" }

      tokenizer = Parser::Tokenizer.new(string)
      nodes = tokenizer.parse_nodes

      Log.debug { "Parsed #{nodes.size} top-level node(s)" }

      root = nodes.first

      unless root.is_a?(Application)
        raise "The first component must always be an `<Application></Application>`."
      end

      application_id = root.as(Generic).attributes["applicationId"]?.try(&.to_s) ||
                       "com.sunflower.untitled"

      Log.info { "Application ID: #{application_id}" }

      application = Gtk::Application.new(application_id: application_id)

      application.activate_signal.connect do
        Log.debug { "Application activated" }

        build_window(root, application)
      end

      application.run
    end

    # Window building — extracted so hot-reload can call it again
    private def build_window(root : Node, application : Gtk::Application) : Nil
      load_top_level_stylesheets(root)

      window_node = root.children.find { |c| c.kind == "Window" }
      raise "No <Window> found inside <Application>." unless window_node

      window_element = window_node.as(Window)

      Log.info { "Registering main window" }
      JavaScript::Engine.instance.register_window("Main")

      Log.debug { "Building window widget" }
      window = window_element.build_widget(application)

      Log.debug { "Transpiling #{window_element.children.size} child component(s)" }
      transpile_components(window_element, window, "Main")

      run_top_level_scripts(root)

      window.close_request_signal.connect do
        begin
          JavaScript::Engine.instance.sandbox.eval_mutex!("if ($.onExit) $.onExit();")
        rescue
        end

        JavaScript::Engine.instance.close
        false # return false to allow the window to close
      end

      window.try(&.show)
      Log.info { "Window displayed" }

      JavaScript::Engine.instance.job_drain
      JavaScript::Engine.instance.flush_ready
    end

    # Component transpilation
    private def transpile_component(child, widget : Gtk::Widget, window_id : String) : Nil
      case child
      when Box, Frame, Tab, ListBox, ScrolledWindow
        Log.debug { "Transpiling container: #{child.kind} (id: #{child.attributes["id"]?})" }

        child.attributes["windowId"] = JSON::Any.new(window_id)
        container = child.build_widget(widget)
        child.children.each { |c| transpile_component(c, container, window_id) }
      when Button, Label, Entry, HorizontalSeparator, VerticalSeparator, Switch, Image
        Log.debug { "Transpiling widget: #{child.kind} (id: #{child.attributes["id"]?})" }

        child.attributes["windowId"] = JSON::Any.new(window_id)
        child.build_widget(widget)
      when Script
        Log.debug { "Executing script (src: #{child.attributes["src"]? || "inline"})" }

        child.attributes["windowId"] = JSON::Any.new(window_id)
        child.base_dir = @base_dir
        child.execute
      when Export
        Log.debug { "Export block with #{child.children.size} child(ren)" }
        child.children.each { |c| transpile_component(c, widget, window_id) }
      else
        Log.debug { "Skipping unknown element: #{child.kind}" } if child.responds_to?(:kind)
      end
    end

    private def transpile_components(parent, widget : Gtk::Widget, window_id : String) : Nil
      recursive_stylesheet_processing(parent)
      parent.children.each { |child| transpile_component(child, widget, window_id) }
    end

    # Stylesheets
    private def recursive_stylesheet_processing(parent) : Nil
      parent.children.each do |child|
        case child
        when StyleSheet then process_stylesheet(child)
        else                 recursive_stylesheet_processing(child)
        end
      end
    end

    private def process_stylesheet(child) : Nil
      css_provider = Gtk::CssProvider.new

      if child.children.size > 0
        first = child.children.first
        if first.is_a?(Text)
          Log.debug { "Loading inline stylesheet (#{first.content.bytesize} bytes)" }
          css_provider.load_from_data(first.content, first.content.size.to_i64)
        end
      end

      if path = child.attributes["src"]?
        Log.debug { "Loading stylesheet: #{path}" }
        css_provider.load_from_path(path.to_s)
      end

      if display = Gdk::Display.default
        Gtk::StyleContext.add_provider_for_display(
          display, css_provider,
          Gtk::STYLE_PROVIDER_PRIORITY_APPLICATION.to_u32
        )
      end
    end

    # Top-level components
    private def load_top_level_stylesheets(document) : Nil
      document.children.each do |child|
        case child
        when StyleSheet
          Log.debug { "Processing top-level stylesheet" }
          process_stylesheet(child)
        end
      end
    end

    private def run_top_level_scripts(document) : Nil
      document.children.each do |child|
        case child
        when Script
          Log.debug { "Executing top-level script (src: #{child.attributes["src"]? || "inline"})" }
          child.base_dir = @base_dir
          child.execute
        end
      end
    end
  end
end
