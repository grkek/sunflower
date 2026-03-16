module Sunflower
  module JavaScript
    module StandardLibrary
      class Widget < Module
        def register(sandbox : Medusa::Sandbox, engine : Engine) : Nil
          register_text_methods(sandbox)
          register_visibility_methods(sandbox)
          register_css_methods(sandbox)
          register_container_methods(sandbox)
          register_entry_methods(sandbox)
          register_window_methods(sandbox)
          register_list_methods(sandbox)
          register_label_methods(sandbox)
          register_image_methods(sandbox, engine)

          install_js_wrappers(sandbox)
        end

        private def register_text_methods(sandbox) : Nil
          sandbox.bind("__widget_setText", 2) do |args|
            id, text = args[0].as_s, args[1].as_s
            comp = Registry.instance.registered_components[id]?
            next nil unless comp
            case comp.widget
            when Gtk::Label  then comp.widget.as(Gtk::Label).text = text
            when Gtk::Button then comp.widget.as(Gtk::Button).label = text
            when Gtk::Entry  then comp.widget.as(Gtk::Entry).text = text
            end
            text
          end

          sandbox.bind("__widget_setLabel", 2) do |args|
            id, text = args[0].as_s, args[1].as_s
            comp = Registry.instance.registered_components[id]?
            next nil unless comp
            comp.widget.as?(Gtk::Label).try(&.label = text)
            text
          end

          sandbox.bind("__widget_getText", 1) do |args|
            comp = Registry.instance.registered_components[args[0].as_s]?
            next "" unless comp
            case comp.widget
            when Gtk::Entry then comp.widget.as(Gtk::Entry).text
            when Gtk::Label then comp.widget.as(Gtk::Label).text
            else                 ""
            end
          end
        end

        private def register_visibility_methods(sandbox) : Nil
          sandbox.bind("__widget_setVisible", 2) do |args|
            comp = Registry.instance.registered_components[args[0].as_s]?
            next nil unless comp
            comp.widget.visible = args[1].as_bool
            args[1].as_bool
          end
        end

        private def register_css_methods(sandbox) : Nil
          sandbox.bind("__widget_addCssClass", 2) do |args|
            comp = Registry.instance.registered_components[args[0].as_s]?
            next nil unless comp
            comp.widget.add_css_class(args[1].as_s)
            nil
          end

          sandbox.bind("__widget_removeCssClass", 2) do |args|
            comp = Registry.instance.registered_components[args[0].as_s]?
            next nil unless comp
            comp.widget.remove_css_class(args[1].as_s)
            nil
          end
        end

        private def register_container_methods(sandbox) : Nil
          sandbox.bind("__widget_append", 2) do |args|
            comp = Registry.instance.registered_components[args[0].as_s]?
            child = Registry.instance.registered_components[args[1].as_s]?
            next false unless comp && child
            comp.widget.as?(Gtk::Box).try(&.append(child.widget)) ? true : false
          end

          sandbox.bind("__widget_destroyChildren", 1) do |args|
            comp = Registry.instance.registered_components[args[0].as_s]?
            next nil unless comp
            if box = comp.widget.as?(Gtk::Box)
              box.children.each { |child| box.remove(child) }
            end
            nil
          end
        end

        private def register_entry_methods(sandbox) : Nil
          sandbox.bind("__widget_isPassword", 2) do |args|
            comp = Registry.instance.registered_components[args[0].as_s]?
            next nil unless comp
            comp.widget.as?(Gtk::Entry).try(&.visibility = !args[1].as_bool)
            args[1].as_bool
          end
        end

        private def register_window_methods(sandbox) : Nil
          sandbox.bind("__widget_setTitle", 2) do |args|
            comp = Registry.instance.registered_components[args[0].as_s]?
            next nil unless comp
            comp.widget.as?(Gtk::ApplicationWindow).try(&.title = args[1].as_s)
            args[1].as_s
          end

          sandbox.bind("__widget_maximize", 1) do |args|
            comp = Registry.instance.registered_components[args[0].as_s]?
            next nil unless comp
            comp.widget.as?(Gtk::ApplicationWindow).try(&.maximize)
            nil
          end

          sandbox.bind("__widget_minimize", 1) do |args|
            comp = Registry.instance.registered_components[args[0].as_s]?
            next nil unless comp
            comp.widget.as?(Gtk::ApplicationWindow).try(&.minimize)
            nil
          end
        end

        private def register_list_methods(sandbox) : Nil
          sandbox.bind("__widget_removeAll", 1) do |args|
            comp = Registry.instance.registered_components[args[0].as_s]?
            next nil unless comp
            comp.widget.as?(Gtk::ListBox).try(&.remove_all)
            nil
          end
        end

        private def register_label_methods(sandbox) : Nil
          sandbox.bind("__widget_setWrap", 2) do |args|
            comp = Registry.instance.registered_components[args[0].as_s]?
            next nil unless comp
            comp.widget.as?(Gtk::Label).try(&.wrap = args[1].as_bool)
            args[1].as_bool
          end

          sandbox.bind("__widget_setEllipsize", 2) do |args|
            comp = Registry.instance.registered_components[args[0].as_s]?
            next nil unless comp
            comp.widget.as?(Gtk::Label).try(&.ellipsize = Pango::EllipsizeMode.parse(args[1].as_s))
            args[1].as_s
          end

          sandbox.bind("__widget_setXAlign", 2) do |args|
            comp = Registry.instance.registered_components[args[0].as_s]?
            next nil unless comp
            comp.widget.as?(Gtk::Label).try(&.xalign = args[1].as_f64.to_f32)
            args[1].as_f64
          end

          sandbox.bind("__widget_setYAlign", 2) do |args|
            comp = Registry.instance.registered_components[args[0].as_s]?
            next nil unless comp
            comp.widget.as?(Gtk::Label).try(&.yalign = args[1].as_f64.to_f32)
            args[1].as_f64
          end
        end

        private def register_image_methods(sandbox, engine) : Nil
          sandbox.bind("__widget_setResourcePath", 2) do |args|
            id, url = args[0].as_s, args[1].as_s
            promise_id = Random::Secure.hex(8)
            comp = Registry.instance.registered_components[id]?
            unless comp
              engine.resolve_promise(promise_id)
              next promise_id
            end
            image = comp.widget.as(Gtk::Picture)
            if url.starts_with?("http")
              spawn do
                begin
                  resolved_url = url
                  5.times do
                    response = ::HTTP::Client.get(resolved_url)
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
                engine.resolve_promise(promise_id)
              end
            else
              image.file = Gio::File.new_for_path(url)
              engine.resolve_promise(promise_id)
            end
            promise_id
          end

          sandbox.bind("__widget_setContentFit", 2) do |args|
            comp = Registry.instance.registered_components[args[0].as_s]?
            next nil unless comp
            if image = comp.widget.as?(Gtk::Picture)
              image.content_fit = case args[1].as_s.downcase
                                  when "fill"    then Gtk::ContentFit::Fill
                                  when "contain" then Gtk::ContentFit::Contain
                                  when "cover"   then Gtk::ContentFit::Cover
                                  else                Gtk::ContentFit::Contain
                                  end
            end
            args[1].as_s
          end
        end

        private def install_js_wrappers(sandbox) : Nil
          sandbox.eval_mutex!(
            "globalThis.__installMethods = function(comp) {\n" \
            "  var id = comp.id;\n" \
            "  var kind = comp.kind;\n" \
            "  comp.setVisible = function(v) { return __widget_setVisible(id, v); };\n" \
            "  comp.addCssClass = function(c) { return __widget_addCssClass(id, c); };\n" \
            "  comp.removeCssClass = function(c) { return __widget_removeCssClass(id, c); };\n" \
            "  if (kind === 'LABEL') {\n" \
            "    comp.setText = function(t) { return __widget_setText(id, t); };\n" \
            "    comp.setLabel = function(t) { return __widget_setLabel(id, t); };\n" \
            "    comp.setWrap = function(w) { return __widget_setWrap(id, w); };\n" \
            "    comp.setEllipsize = function(m) { return __widget_setEllipsize(id, m); };\n" \
            "    comp.setXAlign = function(a) { return __widget_setXAlign(id, a); };\n" \
            "    comp.setYAlign = function(a) { return __widget_setYAlign(id, a); };\n" \
            "    comp.getText = function() { return __widget_getText(id); };\n" \
            "  }\n" \
            "  if (kind === 'BUTTON') {\n" \
            "    comp.setText = function(t) { return __widget_setText(id, t); };\n" \
            "  }\n" \
            "  if (kind === 'ENTRY') {\n" \
            "    comp.setText = function(t) { return __widget_setText(id, t); };\n" \
            "    comp.getText = function() { return __widget_getText(id); };\n" \
            "    comp.isPassword = function(v) { return __widget_isPassword(id, v); };\n" \
            "  }\n" \
            "  if (kind === 'BOX') {\n" \
            "    comp.append = function(childId) { return __widget_append(id, childId); };\n" \
            "    comp.destroyChildren = function() { return __widget_destroyChildren(id); };\n" \
            "  }\n" \
            "  if (kind === 'IMAGE') {\n" \
            "    comp.setResourcePath = function(path) {\n" \
            "      var pid = __widget_setResourcePath(id, path);\n" \
            "      return __createPromise(pid);\n" \
            "    };\n" \
            "    comp.setContentFit = function(f) { return __widget_setContentFit(id, f); };\n" \
            "  }\n" \
            "  if (kind === 'WINDOW') {\n" \
            "    comp.setTitle = function(t) { return __widget_setTitle(id, t); };\n" \
            "    comp.maximize = function() { return __widget_maximize(id); };\n" \
            "    comp.minimize = function() { return __widget_minimize(id); };\n" \
            "  }\n" \
            "  if (kind === 'LISTBOX') {\n" \
            "    comp.removeAll = function() { return __widget_removeAll(id); };\n" \
            "  }\n" \
            "};\n"
          )
        end
      end
    end
  end
end
