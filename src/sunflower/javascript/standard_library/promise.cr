module Sunflower
  module JavaScript
    module StandardLibrary
      class Promise < Module
        def register(sandbox : Medusa::Sandbox, engine : Engine) : Nil
          sandbox.eval_mutex!(
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
      end
    end
  end
end
