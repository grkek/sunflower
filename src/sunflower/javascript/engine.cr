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
          "  // Shortcut to the main ApplicationWindow\n" \
          "  get mainWindow() {\n" \
          "    return this.windows['Main'] || null;\n" \
          "  },\n" \
          "\n" \
          "  // Get a window by id\n" \
          "  getWindow: function(id) {\n" \
          "    return this.windows[id] || null;\n" \
          "  },\n" \
          "\n" \
          "  // Get a component from a all or specific window(s)\n" \
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
          "  // Search all windows for a component\n" \
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
          "  // Get all component ids across all windows\n" \
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
          "  // Get all window ids\n" \
          "  get windowIds() {\n" \
          "    return Object.keys(this.windows);\n" \
          "  },\n" \
          "\n" \
          "  // Ready state\n" \
          "  _readyCallbacks: [],\n" \
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
          "  }\n" \
          "};\n"
        )
      end

      # Called by the builder after window.show — flushes all $.onReady callbacks.
      def flush_ready : Nil
        Log.debug { "Flushing onReady callbacks" }
        @sandbox.eval_mutex!("$._flushReady();")
      end

      private def register_core_bindings : Nil
        Log.debug { "Registering core bindings" }

        register_console
        register_dispatch
        register_state_getter
        register_promises
        register_fs_bindings
        register_http_bindings
      end

      private def register_console : Nil
        @sandbox.bind("__console_log", 1) do |args|
          STDOUT.puts args[0].as_s
          nil
        end

        @sandbox.bind("__console_warn", 1) do |args|
          STDERR.puts "[WARN] #{args[0].as_s}"
          nil
        end

        @sandbox.bind("__console_error", 1) do |args|
          STDERR.puts "[ERROR] #{args[0].as_s}"
          nil
        end

        @sandbox.eval_mutex!(
          "globalThis.console = {\n" \
          "  log: function() {\n" \
          "    __console_log(Array.prototype.map.call(arguments, function(a) {\n" \
          "      return typeof a === 'object' ? JSON.stringify(a) : String(a);\n" \
          "    }).join(' '));\n" \
          "  },\n" \
          "  info: function() { this.log.apply(this, arguments); },\n" \
          "  debug: function() { this.log.apply(this, arguments); },\n" \
          "  warn: function() {\n" \
          "    __console_warn(Array.prototype.map.call(arguments, function(a) {\n" \
          "      return typeof a === 'object' ? JSON.stringify(a) : String(a);\n" \
          "    }).join(' '));\n" \
          "  },\n" \
          "  error: function() {\n" \
          "    __console_error(Array.prototype.map.call(arguments, function(a) {\n" \
          "      return typeof a === 'object' ? JSON.stringify(a) : String(a);\n" \
          "    }).join(' '));\n" \
          "  }\n" \
          "};\n"
        )
      end

      private def register_dispatch : Nil
        @sandbox.eval_mutex!(
          "globalThis.__dispatch = function(componentId, eventName, eventData) {\n" \
          "  var component = $.findComponentById(componentId);\n" \
          "  if (!component || !component.on) return;\n" \
          "  var handler = component.on[eventName];\n" \
          "  if (typeof handler === 'function') {\n" \
          "    handler.call(component, eventData);\n" \
          "  }\n" \
          "};\n"
        )
      end

      private def register_state_getter : Nil
        @sandbox.bind("__getState", 1) do |args|
          id = args[0].as_s

          Registry.instance.collect_state(id)
        end

        @sandbox.eval_mutex!(
          "globalThis.__installStateGetter = function(comp) {\n" \
          "  Object.defineProperty(comp, 'state', {\n" \
          "    get: function() {\n" \
          "      return JSON.parse(__getState(this.id));\n" \
          "    },\n" \
          "    configurable: true\n" \
          "  });\n" \
          "};\n"
        )
      end

      # Promise infrastructure for async/await support.
      # Crystal bindings can return a promise_id, spawn a fiber for async work,
      # then call resolve_promise(id, value) when done. JS awaits the promise.
      #
      # Values are automatically parsed on the JS side:
      #   - Objects/arrays (starting with { or [) → parsed as JSON
      #   - Quoted strings (starting with ") → parsed as JSON string
      #   - Numbers → parsed as numbers
      #   - "true"/"false" → booleans
      #   - "null" → null
      #   - Everything else → kept as string
      private def register_promises : Nil
        Log.debug { "Registering promise infrastructure" }

        @sandbox.eval_mutex!(
          "globalThis.__pendingPromises = {};\n" \
          "\n" \
          "globalThis.__createPromise = function(id) {\n" \
          "  return new Promise(function(resolve) {\n" \
          "    __pendingPromises[id] = resolve;\n" \
          "  });\n" \
          "};\n" \
          "\n" \
          "globalThis.__resolvePromise = function(id, value) {\n" \
          "  if (__pendingPromises[id]) {\n" \
          "    var parsed = value;\n" \
          "    if (typeof value === 'string' && value.length > 0) {\n" \
          "      var c = value[0];\n" \
          "      if (c === '{' || c === '[' || c === '\"') {\n" \
          "        try { parsed = JSON.parse(value); } catch(e) {}\n" \
          "      }\n" \
          "    }\n" \
          "    __pendingPromises[id](parsed);\n" \
          "    delete __pendingPromises[id];\n" \
          "  }\n" \
          "};\n"
        )
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

      private def register_fs_bindings : Nil
        @sandbox.bind("__fs_read", 1) do |args|
          path = args[0].as_s
          promise_id = Random::Secure.hex(8)

          spawn do
            begin
              content = File.read(path)
              resolve_promise(promise_id, content)
            rescue ex
              resolve_promise(promise_id, {error: ex.message}.to_json)
            end
          end

          promise_id
        end

        @sandbox.bind("__fs_write", 2) do |args|
          path = args[0].as_s
          content = args[1].as_s
          promise_id = Random::Secure.hex(8)

          spawn do
            begin
              File.write(path, content)
              resolve_promise(promise_id)
            rescue ex
              resolve_promise(promise_id, {error: ex.message}.to_json)
            end
          end

          promise_id
        end


        @sandbox.bind("__fs_write_bytes", 2) do |args|
          path = args[0].as_s
          json_bytes = args[1].as_s
          promise_id = Random::Secure.hex(8)

          spawn do
            begin
              bytes = Array(UInt8).from_json(json_bytes)
              File.write(path, Slice.new(bytes.to_unsafe, bytes.size))
              resolve_promise(promise_id, {ok: true, bytes: bytes.size}.to_json)
            rescue ex
              resolve_promise(promise_id, {error: ex.message}.to_json)
            end
          end

          promise_id
        end

        @sandbox.bind("__fs_read_bytes", 1) do |args|
          path = args[0].as_s
          promise_id = Random::Secure.hex(8)

          spawn do
            begin
              bytes = File.read(path).to_slice
              resolve_promise(promise_id, bytes.to_a.to_json)
            rescue ex
              resolve_promise(promise_id, {error: ex.message}.to_json)
            end
          end

          promise_id
        end

        @sandbox.bind("__fs_append", 2) do |args|
          path = args[0].as_s
          content = args[1].as_s
          promise_id = Random::Secure.hex(8)

          spawn do
            begin
              File.open(path, "a") { |f| f.print(content) }
              resolve_promise(promise_id)
            rescue ex
              resolve_promise(promise_id, {error: ex.message}.to_json)
            end
          end

          promise_id
        end

        @sandbox.bind("__fs_exists", 1) do |args|
          path = args[0].as_s
          promise_id = Random::Secure.hex(8)

          spawn do
            resolve_promise(promise_id, File.exists?(path).to_s)
          end

          promise_id
        end

        @sandbox.bind("__fs_delete", 1) do |args|
          path = args[0].as_s
          promise_id = Random::Secure.hex(8)

          spawn do
            begin
              File.delete(path)
              resolve_promise(promise_id)
            rescue ex
              resolve_promise(promise_id, {error: ex.message}.to_json)
            end
          end

          promise_id
        end

        @sandbox.bind("__fs_mkdir", 1) do |args|
          path = args[0].as_s
          promise_id = Random::Secure.hex(8)

          spawn do
            begin
              Dir.mkdir_p(path)
              resolve_promise(promise_id)
            rescue ex
              resolve_promise(promise_id, {error: ex.message}.to_json)
            end
          end

          promise_id
        end

        @sandbox.bind("__fs_readdir", 1) do |args|
          path = args[0].as_s
          promise_id = Random::Secure.hex(8)

          spawn do
            begin
              entries = Dir.children(path)
              resolve_promise(promise_id, entries.to_json)
            rescue ex
              resolve_promise(promise_id, {error: ex.message}.to_json)
            end
          end

          promise_id
        end

        @sandbox.bind("__fs_stat", 1) do |args|
          path = args[0].as_s
          promise_id = Random::Secure.hex(8)

          spawn do
            begin
              info = File.info(path)
              resolve_promise(promise_id, {
                size:        info.size,
                isFile:      info.file?,
                isDirectory: info.directory?,
                isSymlink:   info.symlink?,
                modifiedAt:  info.modification_time.to_unix,
                permissions: info.permissions.value,
              }.to_json)
            rescue ex
              resolve_promise(promise_id, {error: ex.message}.to_json)
            end
          end

          promise_id
        end

        @sandbox.eval_mutex!(
          "globalThis.$.fs = {\n" \
          "  read: function(path) {\n" \
          "    return __createPromise(__fs_read(path));\n" \
          "  },\n" \
          "  write: function(path, content) {\n" \
          "    return __createPromise(__fs_write(path, content));\n" \
          "  },\n" \
          "  writeBytes: function(path, bytes) {\n" \
          "    var arr = bytes instanceof Uint8Array ? Array.from(bytes) : bytes;\n" \
          "    return __createPromise(__fs_write_bytes(path, JSON.stringify(arr)));\n" \
          "  },\n" \
          "  readBytes: function(path) {\n" \
          "    return __createPromise(__fs_read_bytes(path)).then(function(arr) {\n" \
          "      return new Uint8Array(arr);\n" \
          "    });\n" \
          "  },\n" \
          "  append: function(path, content) {\n" \
          "    return __createPromise(__fs_append(path, content));\n" \
          "  },\n" \
          "  exists: function(path) {\n" \
          "    return __createPromise(__fs_exists(path));\n" \
          "  },\n" \
          "  delete: function(path) {\n" \
          "    return __createPromise(__fs_delete(path));\n" \
          "  },\n" \
          "  mkdir: function(path) {\n" \
          "    return __createPromise(__fs_mkdir(path));\n" \
          "  },\n" \
          "  readdir: function(path) {\n" \
          "    return __createPromise(__fs_readdir(path));\n" \
          "  },\n" \
          "  statistics: function(path) {\n" \
          "    return __createPromise(__fs_statistics(path));\n" \
          "  }\n" \
          "};\n"
        )
      end

      private def register_http_bindings : Nil
        @sandbox.bind("__http_request", 1) do |args|
          opts = JSON.parse(args[0].as_s)
          promise_id = Random::Secure.hex(8)

          spawn do
            begin
              url = opts["url"].as_s
              method = (opts["method"]?.try(&.as_s) || "GET").upcase
              body = opts["body"]?.try(&.as_s)
              headers = HTTP::Headers.new

              if h = opts["headers"]?.try(&.as_h)
                h.each { |k, v| headers[k] = v.as_s }
              end

              response = case method
                         when "POST"   then HTTP::Client.exec("POST", url, headers: headers, body: body)
                         when "PUT"    then HTTP::Client.exec("PUT", url, headers: headers, body: body)
                         when "PATCH"  then HTTP::Client.exec("PATCH", url, headers: headers, body: body)
                         when "DELETE" then HTTP::Client.exec("DELETE", url, headers: headers)
                         when "HEAD"   then HTTP::Client.exec("HEAD", url, headers: headers)
                         else               HTTP::Client.exec("GET", url, headers: headers)
                         end

              response_headers = {} of String => String
              response.headers.each { |k, v| response_headers[k] = v.join(", ") }

              resolve_promise(promise_id, {
                status:        response.status_code,
                statusMessage: response.status_message,
                headers:       response_headers,
                body:          response.body,
              }.to_json)
            rescue ex
              resolve_promise(promise_id, {error: ex.message}.to_json)
            end
          end

          promise_id
        end

        @sandbox.bind("__http_download", 2) do |args|
          url = args[0].as_s
          path = args[1].as_s
          promise_id = Random::Secure.hex(8)

          spawn do
            begin
              response = HTTP::Client.get(url)

              if response.success?
                File.write(path, response.body)
                resolve_promise(promise_id, {
                  okay:    true,
                  bytes: response.body.bytesize,
                  path:  path,
                }.to_json)
              else
                resolve_promise(promise_id, {
                  error:  "HTTP #{response.status_code}",
                  status: response.status_code,
                }.to_json)
              end
            rescue ex
              resolve_promise(promise_id, {error: ex.message}.to_json)
            end
          end

          promise_id
        end

        @sandbox.eval_mutex!(
          "globalThis.$.http = {\n" \
          "  request: function(opts) {\n" \
          "    if (typeof opts === 'string') opts = { url: opts };\n" \
          "    return __createPromise(__http_request(JSON.stringify(opts)));\n" \
          "  },\n" \
          "  get: function(url, headers) {\n" \
          "    return this.request({ url: url, method: 'GET', headers: headers });\n" \
          "  },\n" \
          "  post: function(url, body, headers) {\n" \
          "    return this.request({ url: url, method: 'POST', body: typeof body === 'object' ? JSON.stringify(body) : body, headers: headers });\n" \
          "  },\n" \
          "  put: function(url, body, headers) {\n" \
          "    return this.request({ url: url, method: 'PUT', body: typeof body === 'object' ? JSON.stringify(body) : body, headers: headers });\n" \
          "  },\n" \
          "  patch: function(url, body, headers) {\n" \
          "    return this.request({ url: url, method: 'PATCH', body: typeof body === 'object' ? JSON.stringify(body) : body, headers: headers });\n" \
          "  },\n" \
          "  delete: function(url, headers) {\n" \
          "    return this.request({ url: url, method: 'DELETE', headers: headers });\n" \
          "  },\n" \
          "  download: function(url, path) {\n" \
          "    return __createPromise(__http_download(url, path));\n" \
          "  }\n" \
          "};\n"
        )
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
