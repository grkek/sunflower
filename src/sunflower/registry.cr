module Sunflower
  class Registry
    @@instance = new

    def self.instance
      @@instance
    end

    property registered_components : Helpers::Synchronized(Hash(String, Sunflower::Component)) = Helpers::Synchronized(Hash(String, Sunflower::Component)).new
    property registered_windows : Helpers::Synchronized(Hash(String, Gtk::Widget)) = Helpers::Synchronized(Hash(String, Gtk::Widget)).new

    def register_window(id : String, widget : Gtk::Widget) : Nil
      registered_windows[id] = widget
    end

    def unregister_window(id : String) : Nil
      registered_windows.delete(id)
    end

    def register(component : Sunflower::Component) : Nil
      registered_components[component.id] = component

      # Set up default (no-op) event handlers on the `on` object.
      # User scripts override these:
      #   $.findComponentById("myButton").on.press = function() { ... }
      sandbox = JavaScript::Engine.instance.sandbox
      sandbox.eval_mutex!(
        "Object.assign(#{component.path}.on, {\n" \
        "  press: function() {},\n" \
        "  release: function() {},\n" \
        "  keyPress: function() {},\n" \
        "  motionNotify: function() {},\n" \
        "  focusChange: function() {}\n" \
        "});\n"
      )
    end

    def unregister(id : String) : Nil
      component = registered_components.delete(id)
      return unless component

      sandbox = JavaScript::Engine.instance.sandbox
      sandbox.eval_mutex!("delete #{component.path};")
    end

    # Returns the current GTK widget state as a JSON string.
    # Called by the __getState binding when JS reads component.state.
    def collect_state(id : String) : String
      Log.debug { "collect_state: id=#{id}, windows=#{registered_windows.keys}, components=#{registered_components.keys}" }

      # Check windows first
      if window_widget = registered_windows[id]?
        state = {} of String => JSON::Any
        collect_widget_state(window_widget, state)

        case window_widget
        when Gtk::ApplicationWindow
          collect_window_state(window_widget, state)
        when Gtk::Window
          collect_plain_window_state(window_widget, state)
        end

        return state.to_json
      end

      # Then components
      component = registered_components[id]? || return "{}"
      state = {} of String => JSON::Any

      collect_widget_state(component.widget, state)

      case component.kind
      when "Box"    then collect_box_state(component.widget.as(Gtk::Box), state)
      when "Button" then collect_button_state(component.widget.as(Gtk::Button), state)
      when "Entry"  then collect_entry_state(component.widget.as(Gtk::Entry), state)
      when "Image"  then collect_image_state(component.widget.as(Gtk::Picture), state)
      when "Label"  then collect_label_state(component.widget.as(Gtk::Label), state)
      when "Frame", "ListBox", "ScrolledWindow", "Switch", "Tab", "TextView"
        # Common state only
      end

      state.to_json
    end

    def self.enum_json(value) : JSON::Any
      JSON.parse({"id" => value.to_i, "name" => value.to_s}.to_json)
    end

    # -------------------------------------------------------------------------
    # State collectors — build a plain Hash, return it as JSON string
    # -------------------------------------------------------------------------

    private def collect_widget_state(widget : Gtk::Widget, state : Hash(String, JSON::Any)) : Nil
      state["horizontalAlignment"] = self.class.enum_json(widget.halign)
      state["verticalAlignment"] = self.class.enum_json(widget.valign)
      state["accessibleRole"] = self.class.enum_json(widget.accessible_role)
      state["canFocus"] = JSON::Any.new(widget.can_focus)
      state["canTarget"] = JSON::Any.new(widget.can_target)
      state["cssClasses"] = JSON.parse(widget.css_classes.to_json)
      state["cssName"] = JSON::Any.new(widget.css_name)
      state["focusOnClick"] = JSON::Any.new(widget.focus_on_click)
      state["focusable"] = JSON::Any.new(widget.focusable)
      state["hasDefault"] = JSON::Any.new(widget.has_default)
      state["hasFocus"] = JSON::Any.new(widget.has_focus)
      state["hasTooltip"] = JSON::Any.new(widget.has_tooltip)
      state["heightRequest"] = JSON::Any.new(widget.height_request.to_i64)
      state["horizontalExpand"] = JSON::Any.new(widget.hexpand)
      state["horizontalExpandSet"] = JSON::Any.new(widget.hexpand_set)
      state["marginBottom"] = JSON::Any.new(widget.margin_bottom.to_i64)
      state["marginEnd"] = JSON::Any.new(widget.margin_end.to_i64)
      state["marginStart"] = JSON::Any.new(widget.margin_start.to_i64)
      state["marginTop"] = JSON::Any.new(widget.margin_top.to_i64)
      state["name"] = JSON::Any.new(widget.name)
      state["opacity"] = JSON::Any.new(widget.opacity)
      state["overflow"] = self.class.enum_json(widget.overflow)
      state["parent"] = widget.parent.try { |p| JSON::Any.new(p.name) } || JSON::Any.new(nil)
      state["receivesDefault"] = JSON::Any.new(widget.receives_default)
      state["scaleFactor"] = JSON::Any.new(widget.scale_factor.to_i64)
      state["sensitive"] = JSON::Any.new(widget.sensitive)
      state["tooltipMarkup"] = JSON::Any.new(widget.tooltip_markup)
      state["tooltipText"] = JSON::Any.new(widget.tooltip_text)
      state["verticalExpand"] = JSON::Any.new(widget.vexpand)
      state["verticalExpandSet"] = JSON::Any.new(widget.vexpand_set)
      state["visible"] = JSON::Any.new(widget.visible)
      state["widthRequest"] = JSON::Any.new(widget.width_request.to_i64)
    end

    private def collect_box_state(box : Gtk::Box, state : Hash(String, JSON::Any)) : Nil
      state["baselinePosition"] = self.class.enum_json(box.baseline_position)
      state["homogeneous"] = JSON::Any.new(box.homogeneous)
      state["orientation"] = self.class.enum_json(box.orientation)
      state["spacing"] = JSON::Any.new(box.spacing.to_i64)
      state["children"] = JSON.parse(observe_child_names(box).to_json)
    end

    private def collect_button_state(button : Gtk::Button, state : Hash(String, JSON::Any)) : Nil
      state["actionName"] = JSON::Any.new(button.action_name)
      state["iconName"] = JSON::Any.new(button.icon_name)
      state["text"] = JSON::Any.new(button.label)
      state["useUnderline"] = JSON::Any.new(button.use_underline)
    end

    private def collect_entry_state(entry : Gtk::Entry, state : Hash(String, JSON::Any)) : Nil
      state["text"] = JSON::Any.new(entry.text)
      state["placeholderText"] = JSON::Any.new(entry.placeholder_text)
      state["maxLength"] = JSON::Any.new(entry.max_length.to_i64)
      state["visibility"] = JSON::Any.new(entry.visibility)
      state["hasFrame"] = JSON::Any.new(entry.has_frame)
      state["activatesDefault"] = JSON::Any.new(entry.activates_default)
    end

    private def collect_image_state(image : Gtk::Picture, state : Hash(String, JSON::Any)) : Nil
      state["resourcePath"] = JSON::Any.new(image.file.try(&.to_s))
    rescue
      state["resourcePath"] = JSON::Any.new(nil)
    end

    private def collect_label_state(label : Gtk::Label, state : Hash(String, JSON::Any)) : Nil
      state["ellipsize"] = self.class.enum_json(label.ellipsize)
      state["justify"] = self.class.enum_json(label.justify)
      state["text"] = JSON::Any.new(label.label)
      state["lines"] = JSON::Any.new(label.lines.to_i64)
      state["maxWidthCharacters"] = JSON::Any.new(label.max_width_chars.to_i64)
      state["mnemonicWidget"] = label.mnemonic_widget.try { |w| JSON::Any.new(w.name) } || JSON::Any.new(nil)
      state["naturalWrapMode"] = self.class.enum_json(label.natural_wrap_mode)
      state["selectable"] = JSON::Any.new(label.selectable)
      state["singleLineMode"] = JSON::Any.new(label.single_line_mode)
      state["useUnderline"] = JSON::Any.new(label.use_underline)
      state["widthCharacters"] = JSON::Any.new(label.width_chars.to_i64)
      state["wrap"] = JSON::Any.new(label.wrap)
      state["wrapMode"] = self.class.enum_json(label.wrap_mode)
      state["xAlign"] = JSON::Any.new(label.xalign.to_f64)
      state["yAlign"] = JSON::Any.new(label.yalign.to_f64)
    end

    private def collect_window_state(window : Gtk::ApplicationWindow, state : Hash(String, JSON::Any)) : Nil
      state["title"] = JSON::Any.new(window.title)
      state["maximized"] = JSON::Any.new(window.maximized?)
      state["minimized"] = JSON::Any.new(nil)
    end

    private def collect_plain_window_state(window : Gtk::Window, state : Hash(String, JSON::Any)) : Nil
      state["title"] = JSON::Any.new(window.title)
      state["maximized"] = JSON::Any.new(window.maximized?)
      state["modal"] = JSON::Any.new(window.modal?)
      state["resizable"] = JSON::Any.new(window.resizable?)
      state["decorated"] = JSON::Any.new(window.decorated?)
    end

    private def observe_child_names(widget : Gtk::Widget) : Array(String)
      children = [] of String
      index = 0_u32
      while item = widget.observe_children.item(index)
        children << item.as(Gtk::Widget).name
        index += 1
      end
      children
    end
  end
end
