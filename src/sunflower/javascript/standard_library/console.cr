module Sunflower
  module JavaScript
    module StandardLibrary
      class Console < Module
        def register(sandbox : Medusa::Sandbox, engine : Engine) : Nil
          sandbox.bind("__console_log", 1) do |args|
            STDOUT.puts args[0].as_s
            nil
          end

          sandbox.bind("__console_warn", 1) do |args|
            STDERR.puts "[WARN] #{args[0].as_s}"
            nil
          end

          sandbox.bind("__console_error", 1) do |args|
            STDERR.puts "[ERROR] #{args[0].as_s}"
            nil
          end

          sandbox.eval_mutex!(
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
      end
    end
  end
end
