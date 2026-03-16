module Sunflower
  module JavaScript
    module StandardLibrary
      class State < Module
        def register(sandbox : Medusa::Sandbox, engine : Engine) : Nil
          sandbox.bind("__getState", 1) do |args|
            id = args[0].as_s
            Registry.instance.collect_state(id)
          end

          sandbox.eval_mutex!(
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
      end
    end
  end
end
