require "./node"
require "./generic"

module Sunflower
  module Elements
    module Attributes
      class Window < Sunflower::Attributes::Base
        include JSON::Serializable

        @[JSON::Field(key: "title")]
        property title : String = "Untitled"

        @[JSON::Field(key: "width")]
        property width : Int32 = 800

        @[JSON::Field(key: "height")]
        property height : Int32 = 600

        @[JSON::Field(key: "modal")]
        property? modal : Bool = false

        @[JSON::Field(key: "resizable")]
        property? resizable : Bool = true

        @[JSON::Field(key: "decorated")]
        property? decorated : Bool = true
      end
    end

    class Window < Generic
      Log = ::Log.for(self)

      getter kind : String = "Window"
      getter attributes : Hash(String, JSON::Any)

      def initialize(@attributes, @children = [] of Node)
        super(@kind, @attributes, @children)
      end

      # Main application window — parent is Gtk::Application.
      # Always registered as "Main" in the JS tree.
      def build_widget(parent : Gtk::Application) : Gtk::Widget
        attributes["id"] = JSON::Any.new("Main")
        window_attrs = Attributes::Window.from_json(attributes.to_json)

        Log.debug { "Building ApplicationWindow (title: #{window_attrs.title}, #{window_attrs.width}x#{window_attrs.height})" }

        widget = Gtk::ApplicationWindow.new(
          name: "Main",
          application: parent,
          title: window_attrs.title,
          default_width: window_attrs.width,
          default_height: window_attrs.height,
          resizable: window_attrs.resizable?,
          decorated: window_attrs.decorated?
        )

        widget.destroy_signal.connect(->exit)

        register_events(widget)
        add_class_to_css(widget, window_attrs.class_name)
        register_window_bindings(widget, "Main")

        widget
      end

      # Secondary window — parent is a Gtk::Widget (typically the main window).
      def build_widget(parent : Gtk::Widget) : Gtk::Widget
        window_attrs = Attributes::Window.from_json(attributes.to_json)
        window_id = attributes["id"]?.try(&.to_s) || window_attrs.id

        Log.debug { "Building Window '#{window_id}' (title: #{window_attrs.title}, #{window_attrs.width}x#{window_attrs.height})" }

        JavaScript::Engine.instance.register_window(window_id)

        widget = Gtk::Window.new(
          title: window_attrs.title,
          default_width: window_attrs.width,
          default_height: window_attrs.height,
          modal: window_attrs.modal?,
          resizable: window_attrs.resizable?,
          decorated: window_attrs.decorated?
        )
        widget.name = window_id

        case parent
        when Gtk::Window, Gtk::ApplicationWindow
          widget.transient_for = parent.as(Gtk::Window)
        end

        register_events(widget)
        add_class_to_css(widget, window_attrs.class_name)
        register_window_bindings(widget, window_id)

        widget
      end

      # Binds methods directly on $.windows["windowId"]
      # instead of creating a component. The window IS the namespace,
      # not a component inside it.
      #
      # JS usage:
      #   $.windows["Main"].setTitle("New Title");
      #   $.windows["Main"].maximize();
      private def register_window_bindings(widget : Gtk::Widget, window_id : String) : Nil
        # Track the window widget so state can be collected via __getState
        Registry.instance.register_window(window_id, widget)

        sandbox = JavaScript::Engine.instance.sandbox
        path = "$.windows[\"#{window_id}\"]"

        # setTitle
        binding_name = "__window_#{window_id}_setTitle"
        sandbox.bind(binding_name, 1) do |args|
          title = args[0].as_s
          case widget
          when Gtk::ApplicationWindow then widget.title = title
          when Gtk::Window            then widget.title = title
          end
          title
        end
        sandbox.eval_mutex!("#{path}[\"setTitle\"] = #{binding_name};")

        # maximize
        binding_name = "__window_#{window_id}_maximize"
        sandbox.bind(binding_name, 0) do |_args|
          case widget
          when Gtk::ApplicationWindow then widget.maximize
          when Gtk::Window            then widget.maximize
          end
          nil
        end
        sandbox.eval_mutex!("#{path}[\"maximize\"] = #{binding_name};")

        # minimize
        binding_name = "__window_#{window_id}_minimize"
        sandbox.bind(binding_name, 0) do |_args|
          case widget
          when Gtk::ApplicationWindow then widget.minimize
          when Gtk::Window            then widget.minimize
          end
          nil
        end
        sandbox.eval_mutex!("#{path}[\"minimize\"] = #{binding_name};")

        # close (secondary windows only — main window uses destroy_signal)
        binding_name = "__window_#{window_id}_close"
        sandbox.bind(binding_name, 0) do |_args|
          case widget
          when Gtk::Window then widget.close
          end
          nil
        end
        sandbox.eval_mutex!("#{path}[\"close\"] = #{binding_name};")

        # Install lazy state getter on the window object itself
        sandbox.eval_mutex!("__installStateGetter(#{path});")

        # Event handlers on the window object
        sandbox.eval_mutex!(
          "#{path}.on = {};\n" \
          "Object.assign(#{path}.on, {\n" \
          "  press: function() {},\n" \
          "  release: function() {},\n" \
          "  keyPress: function() {},\n" \
          "  focusChange: function() {}\n" \
          "});\n"
        )
      end
    end
  end
end
