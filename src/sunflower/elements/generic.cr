require "./node"

module Sunflower
  module Elements
    class Generic < Node
      include JSON::Serializable

      getter kind : String
      getter attributes : Hash(String, JSON::Any)

      def initialize(@kind, @attributes, @children = [] of Node)
        attributes.merge!({"id" => JSON::Any.new(Helpers::Randomizer.random_string)}) unless attributes["id"]?
      end

      private def register_events(widget : Gtk::Widget) : Nil
        legacy = Gtk::EventControllerLegacy.new

        legacy.event_signal.connect(after: true) do |event|
          case event.event_type
          when Gdk::EventType::KeyPress, Gdk::EventType::KeyRelease
            # Handled by the key controller below
          else
            event_name = event.event_type.to_s.camelcase(lower: true)

            case event_name
            when "buttonPress"   then handle_event(widget.name, "press")
            when "buttonRelease" then handle_event(widget.name, "release")
            when "motionNotify"  then handle_event()
            else                      handle_event(widget.name, event_name)
            end
          end

          false
        end

        widget.add_controller(legacy)

        key_controller = Gtk::EventControllerKey.new

        key_controller.key_pressed_signal.connect(->(key_value : UInt32, _key_code : UInt32, _modifier_type : Gdk::ModifierType) {
          handle_event(widget.name, "keyPress", key_value.to_json)
          true
        })

        widget.add_controller(key_controller)
      end

      private def register_component(widget : Gtk::Widget, class_name : String, kind : String, window_id : String? = nil) : Nil
        window_id = window_id || attributes.["windowId"].to_s

        Registry.instance.register(
          Component.new(id: widget.name, class_name: class_name, kind: kind, widget: widget, window_id: window_id)
        )
      end

      # Dispatches GTK events through the component's Runtime.dispatch path.
      # No string eval of user code, no eager state refresh.
      private def handle_event(id : String, event_name : String, event_data : String? = nil) : Nil
        component = Registry.instance.registered_components[id]?
        return unless component

        component.dispatch_event(event_name, event_data)
      end

      private def handle_event
        # TODO: Currently the motionNotify is ignored because it produces noise
      end

      private def add_class_to_css(widget : Gtk::Widget, class_name : String?) : Nil
        return unless class_name
        widget.style_context.add_class(class_name)
      end

      private def containerize(parent : Gtk::Widget, component : Gtk::Widget, container_attributes) : Nil
        component.hexpand = container_attributes.expand?
        component.vexpand = container_attributes.expand?

        margin = container_attributes.padding

        component.margin_top = margin
        component.margin_bottom = margin
        component.margin_start = margin
        component.margin_end = margin

        case parent
        when Gtk::Notebook
          label = container_attributes.container_label
          parent.append_page(component, label ? Gtk::Label.new(label: label) : nil)
        when Gtk::Box
          parent.append(component)
        when Gtk::ScrolledWindow, Gtk::Frame
          parent.child = component
        when Gtk::ListBox
          parent.insert(component, 1_000_000)
        when Gtk::ApplicationWindow
          parent.child = component
        end
      end
    end
  end
end
