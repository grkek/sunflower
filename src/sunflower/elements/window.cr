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

      def build_widget(parent : Gtk::Application) : Gtk::Widget
        attributes["id"] = JSON::Any.new("Main")
        window_attributes = Attributes::Window.from_json(attributes.to_json)

        Log.debug { "Building ApplicationWindow (title: #{window_attributes.title}, #{window_attributes.width}x#{window_attributes.height})" }

        widget = Gtk::ApplicationWindow.new(
          name: "Main",
          application: parent,
          title: window_attributes.title,
          default_width: window_attributes.width,
          default_height: window_attributes.height,
          resizable: window_attributes.resizable?,
          decorated: window_attributes.decorated?
        )

        widget.destroy_signal.connect(->exit)
        finalize_widget(widget, window_attributes, "Main")

        widget
      end

      def build_widget(parent : Gtk::Widget) : Gtk::Widget
        window_attributes = Attributes::Window.from_json(attributes.to_json)
        window_id = attributes["id"]?.try(&.to_s) || window_attributes.id

        Log.debug { "Building Window '#{window_id}' (title: #{window_attributes.title}, #{window_attributes.width}x#{window_attributes.height})" }

        JavaScript::Engine.instance.register_window(window_id)

        widget = Gtk::Window.new(
          title: window_attributes.title,
          default_width: window_attributes.width,
          default_height: window_attributes.height,
          modal: window_attributes.modal?,
          resizable: window_attributes.resizable?,
          decorated: window_attributes.decorated?
        )
        widget.name = window_id

        if parent.is_a?(Gtk::Window)
          widget.transient_for = parent
        end

        finalize_widget(widget, window_attributes, window_id)

        widget
      end

      private def finalize_widget(widget : Gtk::Widget, attrs : Attributes::Window, window_id : String) : Nil
        register_events(widget)
        add_class_to_css(widget, attrs.class_name)
        register_window_bindings(widget, window_id)
      end

      private def register_window_bindings(widget : Gtk::Widget, window_id : String) : Nil
        Registry.instance.register_window(window_id, widget)

        sandbox = JavaScript::Engine.instance.sandbox
        path = "Runtime.windows[\"#{window_id}\"]"
        gtk_window = widget.as(Gtk::Window)

        bind_method(sandbox, path, window_id, "setTitle", 1) do |args|
          gtk_window.title = args[0].as_s
        end

        bind_method(sandbox, path, window_id, "maximize", 0) { gtk_window.maximize }
        bind_method(sandbox, path, window_id, "minimize", 0) { gtk_window.minimize }
        bind_method(sandbox, path, window_id, "close", 0) { gtk_window.close }
        bind_method(sandbox, path, window_id, "fullscreen", 0) { gtk_window.fullscreen }
        bind_method(sandbox, path, window_id, "unfullscreen", 0) { gtk_window.unfullscreen }

        sandbox.eval_mutex!("__installStateGetter(#{path});")
        sandbox.eval_mutex!(<<-JS)
          #{path}.on = {};
          Object.assign(#{path}.on, {
            press: function() {},
            release: function() {},
            keyPress: function() {},
            focusChange: function() {}
          });
        JS
      end

      private def bind_method(sandbox, path : String, window_id : String, name : String, arity : Int32, &block : Array(Medusa::ValueWrapper) -> _) : Nil
        binding_name = "__window_#{window_id}_#{name}"
        puts binding_name
        sandbox.bind(binding_name, arity) { |args| block.call(args) }
        sandbox.eval_mutex!("#{path}[\"#{name}\"] = #{binding_name};")
      end
    end
  end
end
