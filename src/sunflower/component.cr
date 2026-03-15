module Sunflower
  class Component
    Log = ::Log.for(self)

    getter id : String
    getter class_name : String
    getter kind : String
    getter widget : Gtk::Widget
    getter window_id : String

    private getter engine : JavaScript::Engine = JavaScript::Engine.instance

    def initialize(@id : String, @class_name : String, @kind : String, @widget : Gtk::Widget, @window_id : String)
      register_js_object
    end

    # The full JS path: $.windows["windowId"].components["id"]
    def path : String
      "$.windows[\"#{window_id}\"].components[\"#{id}\"]"
    end

    # Called from Crystal to dispatch a GTK event to JS handlers.
    # Uses the __dispatch function which looks up `component.on[eventName]`
    # and calls it directly — no string eval of user code.
    def dispatch_event(event_name : String, event_data : String? = nil) : Nil
      source_code = if event_data
                      "__dispatch(\"#{id}\", \"#{event_name}\", #{event_data})"
                    else
                      "__dispatch(\"#{id}\", \"#{event_name}\")"
                    end

      engine.sandbox.eval_mutex!(source_code)
    rescue ex : Medusa::Exceptions::InternalException
      Log.error(exception: ex) { "Event #{event_name} on #{id}: #{ex.message}" }
    end

    # -------------------------------------------------------------------------
    # JS Object Registration
    #
    # Creates a component at $.windows[windowId].components[id]:
    # {
    #   isMounted: true,
    #   id: "...",
    #   className: "...",
    #   kind: "BUTTON",
    #   on: {},           ← event handlers (user-assigned JS functions)
    #   state: <lazy>,    ← Object.defineProperty getter, reads from Crystal on access
    #   setText(), ...    ← bound Crystal methods
    # }
    # -------------------------------------------------------------------------

    private def register_js_object : Nil
      sandbox = engine.sandbox

      # Create the base object with `on` for event handlers
      sandbox.eval_mutex!(
        "#{path} = {\n" \
        "  isMounted: true,\n" \
        "  id: \"#{id}\",\n" \
        "  windowId: \"#{window_id}\",\n" \
        "  className: \"#{class_name}\",\n" \
        "  kind: \"#{kind.upcase}\",\n" \
        "  on: {}\n" \
        "};\n"
      )

      # Install lazy state getter — state is fetched from Crystal on demand
      sandbox.eval_mutex!("__installStateGetter(#{path});")

      # Register widget-specific methods (setText, append, etc.)
      register_widget_callbacks(sandbox)
    end

    private def register_widget_callbacks(sandbox : Medusa::Sandbox) : Nil
      case kind
      when "Box"     then register_box_callbacks(sandbox)
      when "Button"  then register_button_callbacks(sandbox)
      when "Entry"   then register_entry_callbacks(sandbox)
      when "Image"   then register_image_callbacks(sandbox)
      when "Label"   then register_label_callbacks(sandbox)
      when "ListBox" then register_list_box_callbacks(sandbox)
      when "Window"  then register_window_callbacks(sandbox)
      end
    end

    # Binds a Crystal block as a method on this component's JS object.
    private def bind_method(sandbox : Medusa::Sandbox, name : String, arg_count : Int32, &block : Array(Medusa::ValueWrapper) -> _) : Nil
      binding_name = "__component_#{id}_#{name}"
      sandbox.bind(binding_name, arg_count, &block)
      sandbox.eval_mutex!("#{path}[\"#{name}\"] = #{binding_name};")
    end

    # -------------------------------------------------------------------------
    # Widget-specific callbacks
    # -------------------------------------------------------------------------

    private def register_box_callbacks(sandbox : Medusa::Sandbox) : Nil
      box = widget.as(Gtk::Box)

      bind_method(sandbox, "append", 1) do |args|
        child_id = args[0].as_s
        if child = Registry.instance.registered_components[child_id]?
          box.append(child.widget)
          true
        else
          false
        end
      end

      bind_method(sandbox, "destroyChildren", 0) do |_args|
        box.children.each { |child| box.remove(child) }
        nil
      end
    end

    private def register_button_callbacks(sandbox : Medusa::Sandbox) : Nil
      button = widget.as(Gtk::Button)

      bind_method(sandbox, "setText", 1) do |args|
        button.label = args[0].as_s
        args[0].as_s
      end
    end

    private def register_entry_callbacks(sandbox : Medusa::Sandbox) : Nil
      entry = widget.as(Gtk::Entry)

      bind_method(sandbox, "setText", 1) do |args|
        entry.text = args[0].as_s
        args[0].as_s
      end

      bind_method(sandbox, "getText", 0) do |_args|
        entry.text
      end
    end

    private def register_image_callbacks(sandbox : Medusa::Sandbox) : Nil
      image = widget.as(Gtk::Picture)
      component_path = path

      bind_method(sandbox, "_setResourcePath", 1) do |args|
        url = args[0].as_s
        promise_id = Random::Secure.hex(8)

        if url.starts_with?("http")
          spawn do
            begin
              resolved_url = url
              5.times do
                response = HTTP::Client.get(resolved_url)
                if response.status.redirection? && (location = response.headers["Location"]?)
                  resolved_url = location
                else
                  if response.success?
                    bytes = response.body.to_slice
                    glib_bytes = GLib::Bytes.new(bytes.to_unsafe, bytes.size)
                    texture = Gdk::Texture.new_from_bytes(glib_bytes)
                    image.paintable = texture
                  end
                  break
                end
              end
            rescue ex
              Log.error { "Failed to load image #{url}: #{ex.message}" }
            end

            JavaScript::Engine.instance.resolve_promise(promise_id)
          end
        else
          image.file = Gio::File.new_for_path(url)
          JavaScript::Engine.instance.resolve_promise(promise_id)
        end

        promise_id
      end

      # Wrap _setResourcePath to return a Promise
      sandbox.eval_mutex!(
        "#{component_path}.setResourcePath = function(path) {\n" \
        "  var id = this._setResourcePath(path);\n" \
        "  return __createPromise(id);\n" \
        "};\n"
      )

      bind_method(sandbox, "setContentFit", 1) do |args|
        fit = case args[0].as_s.downcase
              when "fill"    then Gtk::ContentFit::Fill
              when "contain" then Gtk::ContentFit::Contain
              when "cover"   then Gtk::ContentFit::Cover
              when "none"    then Gtk::ContentFit::ScaleDown
              else                Gtk::ContentFit::Contain
              end
        image.content_fit = fit
        args[0].as_s
      end
    end

    private def register_label_callbacks(sandbox : Medusa::Sandbox) : Nil
      label = widget.as(Gtk::Label)

      bind_method(sandbox, "setLabel", 1) do |args|
        label.label = args[0].as_s
        args[0].as_s
      end

      bind_method(sandbox, "setText", 1) do |args|
        label.text = args[0].as_s
        args[0].as_s
      end

      bind_method(sandbox, "setEllipsize", 1) do |args|
        label.ellipsize = Pango::EllipsizeMode.parse(args[0].as_s)
        args[0].as_s
      end

      bind_method(sandbox, "setJustify", 1) do |args|
        label.justify = Gtk::Justification.parse(args[0].as_s)
        args[0].as_s
      end

      bind_method(sandbox, "setLines", 1) do |args|
        label.lines = args[0].as_i
        args[0].as_i
      end

      bind_method(sandbox, "setMaxWidthChars", 1) do |args|
        label.max_width_chars = args[0].as_i
        args[0].as_i
      end

      bind_method(sandbox, "setNaturalWrapMode", 1) do |args|
        label.natural_wrap_mode = Gtk::NaturalWrapMode.parse(args[0].as_s)
        args[0].as_s
      end

      bind_method(sandbox, "setIsSelectable", 1) do |args|
        label.selectable = args[0].as_bool
        args[0].as_bool
      end

      bind_method(sandbox, "setIsSingleLineMode", 1) do |args|
        label.single_line_mode = args[0].as_bool
        args[0].as_bool
      end

      bind_method(sandbox, "setUseMarkup", 1) do |args|
        label.use_markup = args[0].as_bool
        args[0].as_bool
      end

      bind_method(sandbox, "setUseUnderline", 1) do |args|
        label.use_underline = args[0].as_bool
        args[0].as_bool
      end

      bind_method(sandbox, "setWidthChars", 1) do |args|
        label.width_chars = args[0].as_i
        args[0].as_i
      end

      bind_method(sandbox, "setWrap", 1) do |args|
        label.wrap = args[0].as_bool
        args[0].as_bool
      end

      bind_method(sandbox, "setWrapMode", 1) do |args|
        label.wrap_mode = Pango::WrapMode.parse(args[0].as_s)
        args[0].as_s
      end

      bind_method(sandbox, "setXAlign", 1) do |args|
        label.xalign = args[0].as_f64.to_f32
        args[0].as_f64
      end

      bind_method(sandbox, "setYAlign", 1) do |args|
        label.yalign = args[0].as_f64.to_f32
        args[0].as_f64
      end
    end

    private def register_list_box_callbacks(sandbox : Medusa::Sandbox) : Nil
      list_box = widget.as(Gtk::ListBox)

      bind_method(sandbox, "removeAll", 0) do |_args|
        list_box.remove_all
        nil
      end
    end

    private def register_window_callbacks(sandbox : Medusa::Sandbox) : Nil
      window = widget.as(Gtk::ApplicationWindow)

      bind_method(sandbox, "setTitle", 1) do |args|
        window.title = args[0].as_s
        args[0].as_s
      end

      bind_method(sandbox, "maximize", 0) do |_args|
        window.maximize
        nil
      end

      bind_method(sandbox, "minimize", 0) do |_args|
        window.minimize
        nil
      end
    end
  end
end
