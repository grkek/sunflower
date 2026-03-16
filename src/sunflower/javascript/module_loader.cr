# ES Module loader for Sunflower.
#
# Uses a C++ bridge (src/ext/module_loader.cpp) compiled into Sunflower's
# own object file. Does NOT modify Medusa.
#
# Built-in modules register their JS source at startup:
#   ModuleLoader.register("canvas", "export class Canvas { ... }")
#
# User JS then imports normally:
#   import { Canvas } from "canvas";
#   import { read, write } from "fs";

module Sunflower
  module JavaScript
    # Compile the C++ module loader bridge at Crystal compile time.
    # This mirrors how Medusa builds medusa.a — the {% system %} macro
    # runs during compilation, before linking.
    #
    # Paths are relative to this file's directory:
    #   __DIR__ = src/sunflower/javascript/
    #   ext/    = src/ext/
    #   bin/    = bin/ (project root)
    {% begin %}
      {% ext_dir = "#{__DIR__}/../../../src/ext" %}
      {% quickjs_include = "#{__DIR__}/../../../lib/medusa/src/ext" %}
      {% output = "#{__DIR__}/../../../bin/module_loader.o" %}

      {% result = `c++ -c -std=c++17 -O2 #{ext_dir.id}/module_loader.cpp -o #{output.id} -I#{quickjs_include.id} 2>&1` %}
      {% if result.includes?("error") %}
        {% raise "Failed to compile module_loader.cpp:\n#{result}" %}
      {% end %}
    {% end %}

    {% if flag?(:darwin) %}
      @[Link(ldflags: "#{__DIR__}/../../../bin/module_loader.o -lc++")]
    {% else %}
      @[Link(ldflags: "#{__DIR__}/../../../bin/module_loader.o -lstdc++")]
    {% end %}
    lib ModuleLoaderBridge
      fun SetupCustomModuleLoader(
        rt : Medusa::Binding::QuickJS::JSRuntime,
        normalize_cb : (LibC::Char*, LibC::Char*) -> LibC::Char*,
        load_cb : (LibC::Char*, LibC::SizeT*) -> LibC::Char*,
      ) : Void
    end

    class ModuleLoader
      @@modules = {} of String => String

      def self.register(name : String, source : String) : Nil
        @@modules[name] = source
      end

      def self.get(name : String) : String?
        @@modules[name]?
      end

      def self.registered?(name : String) : Bool
        @@modules.has_key?(name)
      end

      def self.all_modules : Hash(String, String)
        @@modules
      end

      # Install the custom module loader on a runtime.
      # Call AFTER Engine.new and after all modules have been registered.
      def self.install(runtime : Medusa::Runtime) : Nil
        ModuleLoaderBridge.SetupCustomModuleLoader(
          runtime.to_unsafe,
          @@normalize_cb,
          @@load_cb
        )
      end

      # Plain C function pointer callbacks (no closures)

      # Called by the C++ bridge normalizer.
      # Returns a malloc'd string if the module is built-in, or null to
      # let the C++ side handle file resolution.
      @@normalize_cb = ->(base_name : LibC::Char*, name : LibC::Char*) : LibC::Char* {
        module_name = String.new(name)

        if @@modules.has_key?(module_name)
          ptr = LibC.malloc(module_name.bytesize + 1).as(LibC::Char*)
          ptr.copy_from(module_name.to_unsafe, module_name.bytesize)
          (ptr + module_name.bytesize).value = 0_u8
          return ptr
        end

        Pointer(LibC::Char).null
      }

      # Called by the C++ bridge loader.
      # Returns a malloc'd source string if the module is in the registry,
      # or null to let the C++ side load from disk.
      @@load_cb = ->(name : LibC::Char*, out_len : LibC::SizeT*) : LibC::Char* {
        module_name = String.new(name)

        if source = @@modules[module_name]?
          out_len.value = LibC::SizeT.new(source.bytesize)
          ptr = LibC.malloc(source.bytesize + 1).as(LibC::Char*)
          ptr.copy_from(source.to_unsafe, source.bytesize)
          (ptr + source.bytesize).value = 0_u8
          return ptr
        end

        Pointer(LibC::Char).null
      }
    end
  end
end
