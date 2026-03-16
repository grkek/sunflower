module Sunflower
  module JavaScript
    module StandardLibrary
      class Dispatch < Module
        def register(sandbox : Medusa::Sandbox, engine : Engine) : Nil
          sandbox.eval_mutex!(
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
      end
    end
  end
end
