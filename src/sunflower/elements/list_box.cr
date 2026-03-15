require "./node"
require "./generic"

module Sunflower
  module Elements
    module Attributes
      class ListBox < Sunflower::Attributes::Base
      end
    end

    class ListBox < Generic
      getter kind : String = "ListBox"
      getter attributes : Hash(String, JSON::Any)

      def initialize(@attributes, @children = [] of Node)
        super(@kind, @attributes, @children)
      end

      def build_widget(parent : Gtk::Widget) : Gtk::Widget
        list_box = Attributes::ListBox.from_json(attributes.to_json)
        container_attributes = Sunflower::Attributes::Container.from_json(attributes.to_json)

        widget = Gtk::ListBox.new(name: list_box.id, halign: list_box.horizontal_alignment, valign: list_box.vertical_alignment)

        register_events(widget)
        containerize(parent, widget, container_attributes)
        add_class_to_css(widget, list_box.class_name)

        register_component(widget, list_box.class_name, @kind)
        widget
      end
    end
  end
end
