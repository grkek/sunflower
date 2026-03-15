require "./node"
require "./generic"

module Sunflower
  module Elements
    module Attributes
      class Script < Sunflower::Attributes::Base
        include JSON::Serializable

        @[JSON::Field(key: "src")]
        property src : String? = nil

        @[JSON::Field(key: "type")]
        property type : String? = nil
      end
    end

    class Script < Generic
      Log = ::Log.for(self)

      getter kind : String = "Script"
      getter attributes : Hash(String, JSON::Any)

      # Base directory for resolving relative src paths.
      # Set by the builder to the directory of the HTML file being parsed.
      property base_dir : String = Dir.current

      def initialize(@attributes, @children = [] of Node)
        super(@kind, @attributes, @children)
      end

      def execute : Nil
        engine = JavaScript::Engine.instance
        script_attrs = Attributes::Script.from_json(attributes.to_json)

        if src_path = script_attrs.src
          load_file(engine, src_path, script_attrs.type)
        else
          load_inline(engine, script_attrs.type)
        end
      end

      private def resolve_path(path : String) : String
        if path.starts_with?("/")
          path
        else
          File.expand_path(path, base_dir)
        end
      end

      private def load_file(engine : JavaScript::Engine, path : String, type : String?) : Nil
        resolved = resolve_path(path)

        Log.info { "Loading script: #{path} (resolved: #{resolved})" }

        unless File.exists?(resolved)
          Log.error { "Script not found: #{resolved}" }
          return
        end

        if type == "module"
          engine.sandbox.eval_mutex!(
            File.read(resolved),
            flag: Medusa::Binding::QuickJS::EvalFlag::MODULE,
            tag: resolved
          )
        else
          if path.ends_with?(".jsx")
            source = File.read(resolved)
            transpiled = JavaScript::XML::Transpiler.transform(source)
            engine.sandbox.eval_mutex!(transpiled, tag: resolved)
          else
            engine.load!(resolved)
          end
        end
      end

      private def load_inline(engine : JavaScript::Engine, type : String?) : Nil
        source = children
          .select(&.is_a?(Text))
          .map(&.as(Text).content)
          .join("\n")
          .strip

        if source.empty?
          Log.debug { "Empty inline script, skipping" }
          return
        end

        Log.info { "Executing inline script (#{source.bytesize} bytes)" }

        if type == "module"
          engine.sandbox.eval_mutex!(
            source,
            flag: Medusa::Binding::QuickJS::EvalFlag::MODULE,
            tag: "<inline-module>"
          )
        else
          engine.sandbox.eval_mutex!(source)
        end
      end
    end
  end
end
