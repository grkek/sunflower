module Sunflower
  module JavaScript
    class Engine
      Log = ::Log.for(self)

      @@pending_resolves = [] of {String, String}
      @@resolve_mutex = Mutex.new

      @@instance : Engine = Engine.new

      @mutex : Mutex

      getter server : UNIXServer
      getter sandbox : Medusa::Sandbox

      property paths : Helpers::Synchronized(Array(String)) = Helpers::Synchronized(Array(String)).new

      getter scene_view : Sunflower::SceneView = Sunflower::SceneView.new
      property last_module_namespace : Medusa::Binding::QuickJS::JSValue? = nil

      def self.instance : Engine
        @@instance
      end

      def initialize
        @mutex = Mutex.new(:reentrant)
        @server = UNIXServer.new("/tmp/#{UUID.random}.sock")
        @sandbox = Medusa::Sandbox.new

        Log.info { "Engine initialized (socket: #{@server.path})" }

        register_core_bindings
        register_tachyon_module

        spawn accept_connections
      end

      private def register_tachyon_module : Nil
        context = @sandbox.engine.context

        Tachyon::Scripting::LibTachyonBridge.TachyonBridge_InitClasses(context.runtime)
        Tachyon::Scripting::LibTachyonBridge.TachyonBridge_RegisterModule(context.to_unsafe)
      end

      def load!(path : String) : Nil
        Log.info { "Loading file: #{path}" }
        @mutex.synchronize { @sandbox.load_auto!(path) }
      end

      def load_bytecode!(path : String) : Nil
        Log.info { "Loading bytecode: #{path}" }
        @mutex.synchronize do
          @sandbox.load_bytecode(File.read(path).to_slice)
        end
      end

      def bind(name : String, arg_count : Int32 = 0, &block : Array(Medusa::ValueWrapper) -> _) : Nil
        Log.debug { "Binding function: #{name} (#{arg_count} args)" }
        @mutex.synchronize { @sandbox.bind(name, arg_count, &block) }
      end

      def eval_module!(source : String, tag : String) : Nil
        context = @sandbox.engine.context.to_unsafe

        result = Medusa::Binding::QuickJS.JS_Eval(
          context, source, source.bytesize, tag,
          (Medusa::Binding::QuickJS::EvalFlag::MODULE | Medusa::Binding::QuickJS::EvalFlag::COMPILE_ONLY).value
        )

        game_module = result.u.ptr.as(Medusa::Binding::QuickJS::JSModuleDef)
        Medusa::Binding::QuickJS.JS_EvalFunction(context, result)

        @last_module_namespace = Medusa::Binding::QuickJS.JS_GetModuleNamespace(context, game_module)
      end

      def set_global(name : String, value) : Nil
        Log.debug { "Setting global: #{name}" }
        @sandbox.set_global(name, value)
      end

      def register_window(window_id : String) : Nil
        Log.info { "Registering window: #{window_id}" }
        @sandbox.eval_mutex!(<<-JS)
          Runtime.windows["#{window_id}"] = {
            id: "#{window_id}",
            components: {},
            isMounted: true,
            properties: {}
          };
        JS
      end

      def flush_ready : Nil
        Log.debug { "Flushing onReady callbacks" }
        @sandbox.eval_mutex!("Runtime.flushReady();")
      end

      def flush_exit : Nil
        Log.debug { "Flushing onExit callbacks" }
        @sandbox.eval_mutex!("Runtime.flushExit();")
      end

      def close : Nil
        Log.info { "Shutting down engine" }
        @server.close rescue nil
        @sandbox.close
      end

      def resolve_promise(id : String, value : String = "true") : Nil
        @@resolve_mutex.synchronize { @@pending_resolves << {id, value} }
      end

      def job_drain : Nil
        Log.debug { "Starting job drain timer (16ms)" }

        LibGLib.g_timeout_add_full(
          0, 16_u32,
          ->(data : Pointer(Void)) {
            Fiber.yield
            Engine.drain_pending_resolves
            @@instance.sandbox.drain_jobs
            1
          }.pointer,
          Pointer(Void).null,
          Pointer(Void).null
        )
      end

      def self.drain_pending_resolves : Nil
        resolves = @@resolve_mutex.synchronize do
          batch = @@pending_resolves.dup
          @@pending_resolves.clear
          batch
        end

        resolves.each do |promise_id, promise_value|
          safe_value = promise_value.to_json
          @@instance.sandbox.eval_mutex!(
            "__resolvePromise(\"#{promise_id}\", #{safe_value});"
          )
        rescue
        end
      end

      private def register_core_bindings : Nil
        Log.debug { "Registering core bindings" }

        # Core modules
        StandardLibrary::Console.new.register(@sandbox, self)
        StandardLibrary::State.new.register(@sandbox, self)
        StandardLibrary::Promise.new.register(@sandbox, self)

        # Standard library
        StandardLibrary::FileSystem.new.register(@sandbox, self)
        StandardLibrary::HTTP.new.register(@sandbox, self)
        StandardLibrary::Widget.new.register(@sandbox, self)

        # Module loader
        ModuleLoader.install(@sandbox.engine.runtime)

        # Stigma runtime
        Stigma.install(@sandbox, self)
      end

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
