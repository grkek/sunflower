module Sunflower
  module JavaScript
    class Engine
      Log = ::Log.for(self)

      # Queue of promise {id, value} pairs to resolve. The job drain timer
      # picks these up on the GTK main thread.
      @@pending_resolves = [] of {String, String}
      @@resolve_mutex = Mutex.new

      @@instance : Engine = Engine.new

      @mutex : Mutex

      getter server : UNIXServer
      getter sandbox : Medusa::Sandbox

      property paths : Helpers::Synchronized(Array(String)) = Helpers::Synchronized(Array(String)).new

      def self.instance : Engine
        @@instance
      end

      def initialize
        @mutex = Mutex.new(:reentrant)

        @server = UNIXServer.new("/tmp/#{UUID.random}.sock")
        @sandbox = Medusa::Sandbox.new

        Log.info { "Engine initialized (socket: #{@server.path})" }

        bootstrap_app_object
        register_core_bindings

        spawn accept_connections
      end

      def load!(path : String) : Nil
        Log.info { "Loading file: #{path}" }

        @mutex.synchronize do
          @sandbox.load_auto!(path)
        end
      end

      def load_bytecode!(path : String) : Nil
        Log.info { "Loading bytecode: #{path}" }

        @mutex.synchronize do
          bytecode = File.read(path).to_slice
          @sandbox.load_bytecode(bytecode)
        end
      end

      def bind(name : String, arg_count : Int32 = 0, &block : Array(Medusa::ValueWrapper) -> _) : Nil
        Log.debug { "Binding function: #{name} (#{arg_count} args)" }

        @mutex.synchronize do
          @sandbox.bind(name, arg_count, &block)
        end
      end

      def set_global(name : String, value) : Nil
        Log.debug { "Setting global: #{name}" }
        @sandbox.set_global(name, value)
      end

      def register_window(window_id : String) : Nil
        Log.info { "Registering window: #{window_id}" }

        @sandbox.eval_mutex!(
          "$.windows[\"#{window_id}\"] = {\n" \
          "  id: \"#{window_id}\",\n" \
          "  components: {},\n" \
          "  isMounted: true,\n" \
          "  properties: {}\n" \
          "};\n"
        )
      end

      def close : Nil
        Log.info { "Shutting down engine" }

        @server.close rescue nil
        @sandbox.close
      end

      private def bootstrap_app_object : Nil
        Log.debug { "Bootstrapping Application object" }
        @sandbox.eval_mutex!(
          "globalThis.$ = {\n" \
          "  windows: {},\n" \
          "\n" \
          "  get mainWindow() {\n" \
          "    return this.windows['Main'] || null;\n" \
          "  },\n" \
          "\n" \
          "  getWindow: function(id) {\n" \
          "    return this.windows[id] || null;\n" \
          "  },\n" \
          "\n" \
          "  getComponentById: function(componentId, windowId) {\n" \
          "    if (windowId) {\n" \
          "      var window = this.windows[windowId];\n" \
          "      return window ? (window.components[componentId] || null) : null;\n" \
          "    }\n" \
          "    for (var key in this.windows) {\n" \
          "      var window = this.windows[key];\n" \
          "      if (window.components && window.components[componentId]) {\n" \
          "        return window.components[componentId];\n" \
          "      }\n" \
          "    }\n" \
          "    return null;\n" \
          "  },\n" \
          "\n" \
          "  findComponentById: function(componentId) {\n" \
          "    for (var key in this.windows) {\n" \
          "      var window = this.windows[key];\n" \
          "      if (window.components && window.components[componentId]) {\n" \
          "        return window.components[componentId];\n" \
          "      }\n" \
          "    }\n" \
          "    return null;\n" \
          "  },\n" \
          "\n" \
          "  get componentIds() {\n" \
          "    var ids = [];\n" \
          "    for (var key in this.windows) {\n" \
          "      var window = this.windows[key];\n" \
          "      if (window.components) {\n" \
          "        ids = ids.concat(Object.keys(window.components));\n" \
          "      }\n" \
          "    }\n" \
          "    return ids;\n" \
          "  },\n" \
          "\n" \
          "  get windowIds() {\n" \
          "    return Object.keys(this.windows);\n" \
          "  },\n" \
          "\n" \
          "  _readyCallbacks: [],\n" \
          "  _exitCallbacks: [],\n" \
          "  _isReady: false,\n" \
          "\n" \
          "  onReady: function(callback) {\n" \
          "    if (this._isReady) {\n" \
          "      callback();\n" \
          "    } else {\n" \
          "      this._readyCallbacks.push(callback);\n" \
          "    }\n" \
          "  },\n" \
          "\n" \
          "  _flushReady: function() {\n" \
          "    this._isReady = true;\n" \
          "    for (var i = 0; i < this._readyCallbacks.length; i++) {\n" \
          "      this._readyCallbacks[i]();\n" \
          "    }\n" \
          "    this._readyCallbacks = [];\n" \
          "  },\n" \
          "\n" \
          "  onExit: function(callback) {\n" \
          "    this._exitCallbacks.push(callback);\n" \
          "  },\n" \
          "\n" \
          "  _flushExit: function() {\n" \
          "    for (var i = 0; i < this._exitCallbacks.length; i++) {\n" \
          "      this._exitCallbacks[i]();\n" \
          "    }\n" \
          "  }\n" \
          "};\n"
        )
      end

      # Called by the builder after window.show — flushes all $.onReady callbacks.
      def flush_ready : Nil
        Log.debug { "Flushing onReady callbacks" }
        @sandbox.eval_mutex!("$._flushReady();")
      end

      # Called by the builder after exit — flushes all $.onExit callbacks.
      def flush_exit : Nil
        Log.debug { "Flushing onExit callbacks" }
        @sandbox.eval_mutex!("$._flushExit();")
      end

      private def register_core_bindings : Nil
        Log.debug { "Registering core bindings" }

        # Core modules
        StandardLibrary::Console.new.register(@sandbox, self)
        StandardLibrary::Dispatch.new.register(@sandbox, self)
        StandardLibrary::State.new.register(@sandbox, self)
        StandardLibrary::Promise.new.register(@sandbox, self)

        # Standard library
        StandardLibrary::FileSystem.new.register(@sandbox, self)
        StandardLibrary::HTTP.new.register(@sandbox, self)
        StandardLibrary::Widget.new.register(@sandbox, self)

        # Game engine
        StandardLibrary::Canvas.new.register(@sandbox, self)

        ModuleLoader.install(@sandbox.engine.runtime)

        # Seed (JSX runtime)
        register_seed_bindings
      end

      # Queues a JS promise for resolution with a value. The job drain timer
      # will call __resolvePromise on the next tick.
      #
      # The value is JSON-escaped for safe injection into eval. Pass any of:
      #   resolve_promise(id)                    # resolves with true
      #   resolve_promise(id, "hello")           # resolves with "hello" string
      #   resolve_promise(id, data.to_json)      # resolves with parsed object
      #   resolve_promise(id, "42")              # resolves with "42" string
      def resolve_promise(id : String, value : String = "true") : Nil
        @@resolve_mutex.synchronize do
          @@pending_resolves << {id, value}
        end
      end

      # Starts a GLib timer that drains the QuickJS job queue every 16ms.
      # Must be called after the GTK main loop is running (after window.show).
      # Without this, Promises never resolve.
      def job_drain : Nil
        Log.debug { "Starting job drain timer (16ms)" }

        LibGLib.g_timeout_add_full(
          0,
          16_u32,
          ->(data : Pointer(Void)) {
            Fiber.yield

            resolves = [] of {String, String}
            @@resolve_mutex.synchronize do
              resolves = @@pending_resolves.dup
              @@pending_resolves.clear
            end

            resolves.each do |promise_id, promise_value|
              begin
                safe_value = promise_value.to_json
                @@instance.sandbox.eval_mutex!(
                  "__resolvePromise(\"#{promise_id}\", #{safe_value});"
                )
              rescue
              end
            end

            @@instance.sandbox.drain_jobs
            1
          }.pointer,
          Pointer(Void).null,
          Pointer(Void).null
        )
      end

      private def register_seed_bindings : Nil
        Log.debug { "Registering Seed runtime bindings" }

        @sandbox.bind("__create_widget", 3) do |args|
          parent_id = args[0].as_s
          kind = args[1].as_s
          props_json = args[2].as_s

          props = JSON.parse(props_json)
          id = props["id"]?.try(&.as_s) || Random::Secure.hex(8)
          class_name = props["className"]?.try(&.as_s) || ""
          window_id = "Main"

          parent_component = Registry.instance.registered_components[parent_id]?
          unless parent_component
            Log.error { "Seed: parent #{parent_id} not found" }
            next id
          end

          parent_widget = parent_component.widget

          widget = case kind
                   when "Box"
                     orientation = case props["orientation"]?.try(&.as_s)
                                   when "horizontal" then Gtk::Orientation::Horizontal
                                   else                   Gtk::Orientation::Vertical
                                   end
                     spacing = (props["spacing"]?.try(&.as_i?) || props["spacing"]?.try(&.as_s.to_i?)) || 0
                     homogeneous = (props["homogeneous"]?.try(&.as_bool?) || props["homogeneous"]?.try(&.as_s) == "true")
                     expand = (props["expand"]?.try(&.as_bool?) || props["expand"]?.try(&.as_s) == "true")
                     Gtk::Box.new(orientation: orientation, spacing: spacing, homogeneous: homogeneous)
                   when "Label"
                     text = props["text"]?.try(&.as_s) || ""
                     label = Gtk::Label.new(str: text)
                     wrap = (props["wrap"]?.try(&.as_bool?) || props["wrap"]?.try(&.as_s) == "true")

                     label.wrap = wrap
                     label.wrap_mode = Pango::WrapMode::WordChar
                     label.hexpand = true
                     label.max_width_chars = 1

                     label
                   when "Button"
                     text = props["text"]?.try(&.as_s) || ""
                     Gtk::Button.new_with_label(text)
                   when "Entry"
                     entry = Gtk::Entry.new
                     if text = props["text"]?.try(&.as_s)
                       entry.text = text
                     end
                     if placeholder = props["placeHolder"]?.try(&.as_s)
                       entry.placeholder_text = placeholder
                     end
                     if props["inputType"]?.try(&.as_s) == "password"
                       entry.visibility = false
                     end
                     entry
                   when "Image"
                     Gtk::Picture.new
                   when "ScrolledWindow"
                     sw = Gtk::ScrolledWindow.new

                     sw.hscrollbar_policy = Gtk::PolicyType::Never
                     sw.vscrollbar_policy = Gtk::PolicyType::Automatic

                     sw.propagate_natural_width = false
                     sw.propagate_natural_height = false

                     if (props["expand"]?.try(&.as_bool?) || props["expand"]?.try(&.as_s) == "true")
                       sw.vexpand = true
                       sw.hexpand = true
                     end
                     sw
                   when "HorizontalSeparator"
                     Gtk::Separator.new(orientation: Gtk::Orientation::Horizontal)
                   when "VerticalSeparator"
                     Gtk::Separator.new(orientation: Gtk::Orientation::Vertical)
                   when "Switch"
                     Gtk::Switch.new
                   when "Canvas"
                     StandardLibrary::Canvas.create_widget(id, props)
                   else
                     Log.warn { "Seed: unknown widget type '#{kind}', creating Box" }
                     Gtk::Box.new(orientation: Gtk::Orientation::Vertical)
                   end

          # Apply common properties
          widget.name = id

          if (props["expand"]?.try(&.as_bool?) || props["expand"]?.try(&.as_s) == "true")
            widget.vexpand = true
            widget.hexpand = true
          end

          if halign = props["horizontalAlignment"]?.try(&.as_s)
            widget.halign = case halign.downcase
                            when "center" then Gtk::Align::Center
                            when "start"  then Gtk::Align::Start
                            when "end"    then Gtk::Align::End
                            when "fill"   then Gtk::Align::Fill
                            else               Gtk::Align::Fill
                            end
          end

          if valign = props["verticalAlignment"]?.try(&.as_s)
            widget.valign = case valign.downcase
                            when "center" then Gtk::Align::Center
                            when "start"  then Gtk::Align::Start
                            when "end"    then Gtk::Align::End
                            when "fill"   then Gtk::Align::Fill
                            else               Gtk::Align::Fill
                            end
          end

          # Add CSS class
          unless class_name.empty?
            widget.add_css_class(class_name)
          end

          # Connect widget-specific signals
          captured_id = id
          case widget
          when Gtk::Button
            widget.clicked_signal.connect do
              component = Registry.instance.registered_components[captured_id]?
              component.try(&.dispatch_event("press"))
            end
          when Gtk::Entry
            widget.buffer.inserted_text_signal.connect do
              component = Registry.instance.registered_components[captured_id]?
              component.try(&.dispatch_event("change", "\"#{widget.text}\""))
            end
            widget.buffer.deleted_text_signal.connect do
              component = Registry.instance.registered_components[captured_id]?
              component.try(&.dispatch_event("change", "\"#{widget.text}\""))
            end
          when Gtk::Switch
            widget.notify_signal["active"].connect do
              component = Registry.instance.registered_components[captured_id]?
              component.try(&.dispatch_event("change", widget.active?.to_s))
            end
          end

          # Append to parent
          case parent_widget
          when Gtk::Box
            parent_widget.append(widget)
          when Gtk::ScrolledWindow
            parent_widget.child = widget
          when Gtk::ListBox
            parent_widget.append(widget)
          else
            Log.warn { "Seed: cannot append to #{parent_widget.class}" }
          end

          # Register as a component so JS can interact with it
          component = Component.new(
            id: id,
            class_name: class_name,
            kind: kind,
            widget: widget,
            window_id: window_id
          )
          Registry.instance.register(component)

          Log.debug { "Seed: created #{kind}##{id} in #{parent_id}" }
          id
        end

        @sandbox.bind("__destroy_widget", 1) do |args|
          widget_id = args[0].as_s

          if component = Registry.instance.registered_components[widget_id]?
            widget = component.widget
            widget.unparent if widget.parent
            Registry.instance.unregister(widget_id)
            Log.debug { "Seed: destroyed #{widget_id}" }
          end

          nil
        end

        @sandbox.bind("__unregister_widget", 1) do |args|
          widget_id = args[0].as_s
          Registry.instance.unregister(widget_id)
          nil
        end

        # Load the Seed runtime JS
        runtime_path = File.join(__DIR__, "..", "..", "runtime", "seed.js")
        if File.exists?(runtime_path)
          Log.debug { "Seed: loading runtime from #{runtime_path}" }
          @sandbox.eval_mutex!(File.read(runtime_path))
        else
          Log.warn { "Seed: runtime not found at #{runtime_path}" }
        end
      end

      # IPC
      private def accept_connections : Nil
        Log.debug { "IPC: Listening for connections" }
        loop do
          if client = @server.accept?
            Log.debug { "IPC: Client connected" }
            spawn handle_client(client)
          end
        end
      rescue ex : IO::Error
        Log.debug { "IPC: Server closed (#{ex.message})" }
      end

      private def handle_client(client : UNIXSocket) : Nil
        loop do
          raw = client.gets
          break unless raw

          request = Message::Request.from_json(raw)

          @mutex.synchronize do
            if source_code = request.source_code
              Log.debug { "IPC: Evaluating #{source_code.bytesize} bytes" }
              @sandbox.eval!(source_code)
            end
          end
        end
      rescue ex : Medusa::Exceptions::InternalException
        Log.error(exception: ex) { ex.message }
      rescue ex : JSON::ParseException
        Log.error { "IPC: Invalid request — #{ex.message}" }
      rescue ex : IO::Error
        Log.debug { "IPC: Client disconnected (#{ex.message})" }
      end
    end
  end
end
