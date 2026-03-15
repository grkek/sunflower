require "./node"
require "./generic"

module Sunflower
  module Elements
    module Attributes
      class Image < Sunflower::Attributes::Base
      end
    end

    class Image < Generic
      getter kind : String = "Image"
      getter attributes : Hash(String, JSON::Any)

      def initialize(@attributes, @children = [] of Node)
        super(@kind, @attributes, @children)
      end

      def build_widget(parent : Gtk::Widget) : Gtk::Widget
        image = Attributes::Image.from_json(attributes.to_json)
        container_attributes = Sunflower::Attributes::Container.from_json(attributes.to_json)

        widget = Gtk::Picture.new

        widget.name = image.id
        widget.halign = image.horizontal_alignment
        widget.valign = image.vertical_alignment
        widget.hexpand = true
        widget.vexpand = true
        widget.content_fit = Gtk::ContentFit::Contain

        register_events(widget)
        containerize(parent, widget, container_attributes)
        add_class_to_css(widget, image.class_name)

        register_component(widget, image.class_name, @kind)
        widget
      end
    end
  end
end
