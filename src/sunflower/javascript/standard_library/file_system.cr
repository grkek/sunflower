# Async filesystem access for the Medusa/QuickJS sandbox.
#
# JS API:
#   import { read, write, exists, mkdir, readdir, stat, append, remove, writeBytes, readBytes } from "fs";
#
#   const content = await read("/path/to/file");
#   await write("/path/to/file", "hello world");
#   const items = await readdir("/some/dir");
#   const info = await stat("/some/file");

module Sunflower
  module JavaScript
    module StandardLibrary
      class FileSystem < Module
        def register(sandbox : Medusa::Sandbox, engine : Engine) : Nil
          register_native_bindings(sandbox, engine)
          install_js_module(sandbox)
        end

        private def register_native_bindings(sandbox, engine) : Nil
          sandbox.bind("__fs_read", 1) do |args|
            path = args[0].as_s
            promise_id = Random::Secure.hex(8)
            spawn do
              begin
                content = File.read(path)
                engine.resolve_promise(promise_id, content)
              rescue ex
                engine.resolve_promise(promise_id, {error: ex.message}.to_json)
              end
            end
            promise_id
          end

          sandbox.bind("__fs_write", 2) do |args|
            path = args[0].as_s
            content = args[1].as_s
            promise_id = Random::Secure.hex(8)
            spawn do
              begin
                File.write(path, content)
                engine.resolve_promise(promise_id)
              rescue ex
                engine.resolve_promise(promise_id, {error: ex.message}.to_json)
              end
            end
            promise_id
          end

          sandbox.bind("__fs_write_bytes", 2) do |args|
            path = args[0].as_s
            json_bytes = args[1].as_s
            promise_id = Random::Secure.hex(8)
            spawn do
              begin
                bytes = Array(UInt8).from_json(json_bytes)
                File.write(path, Slice.new(bytes.to_unsafe, bytes.size))
                engine.resolve_promise(promise_id, {ok: true, bytes: bytes.size}.to_json)
              rescue ex
                engine.resolve_promise(promise_id, {error: ex.message}.to_json)
              end
            end
            promise_id
          end

          sandbox.bind("__fs_read_bytes", 1) do |args|
            path = args[0].as_s
            promise_id = Random::Secure.hex(8)
            spawn do
              begin
                bytes = File.read(path).to_slice
                engine.resolve_promise(promise_id, bytes.to_a.to_json)
              rescue ex
                engine.resolve_promise(promise_id, {error: ex.message}.to_json)
              end
            end
            promise_id
          end

          sandbox.bind("__fs_append", 2) do |args|
            path = args[0].as_s
            content = args[1].as_s
            promise_id = Random::Secure.hex(8)
            spawn do
              begin
                File.open(path, "a") { |f| f.print(content) }
                engine.resolve_promise(promise_id)
              rescue ex
                engine.resolve_promise(promise_id, {error: ex.message}.to_json)
              end
            end
            promise_id
          end

          sandbox.bind("__fs_exists", 1) do |args|
            path = args[0].as_s
            promise_id = Random::Secure.hex(8)
            spawn { engine.resolve_promise(promise_id, File.exists?(path).to_s) }
            promise_id
          end

          sandbox.bind("__fs_delete", 1) do |args|
            path = args[0].as_s
            promise_id = Random::Secure.hex(8)
            spawn do
              begin
                File.delete(path)
                engine.resolve_promise(promise_id)
              rescue ex
                engine.resolve_promise(promise_id, {error: ex.message}.to_json)
              end
            end
            promise_id
          end

          sandbox.bind("__fs_mkdir", 1) do |args|
            path = args[0].as_s
            promise_id = Random::Secure.hex(8)
            spawn do
              begin
                Dir.mkdir_p(path)
                engine.resolve_promise(promise_id)
              rescue ex
                engine.resolve_promise(promise_id, {error: ex.message}.to_json)
              end
            end
            promise_id
          end

          sandbox.bind("__fs_readdir", 1) do |args|
            path = args[0].as_s
            promise_id = Random::Secure.hex(8)
            spawn do
              begin
                entries = Dir.children(path)
                engine.resolve_promise(promise_id, entries.to_json)
              rescue ex
                engine.resolve_promise(promise_id, {error: ex.message}.to_json)
              end
            end
            promise_id
          end

          sandbox.bind("__fs_stat", 1) do |args|
            path = args[0].as_s
            promise_id = Random::Secure.hex(8)
            spawn do
              begin
                info = File.info(path)
                engine.resolve_promise(promise_id, {
                  size: info.size, isFile: info.file?, isDirectory: info.directory?,
                  isSymlink: info.symlink?, modifiedAt: info.modification_time.to_unix,
                  permissions: info.permissions.value,
                }.to_json)
              rescue ex
                engine.resolve_promise(promise_id, {error: ex.message}.to_json)
              end
            end
            promise_id
          end
        end

        private def install_js_module(sandbox) : Nil
          ModuleLoader.register("fs", <<-JS)
            export function read(p) {
              return __createPromise(__fs_read(p));
            }

            export function write(p, c) {
              return __createPromise(__fs_write(p, c));
            }

            export function writeBytes(p, b) {
              var a = b instanceof Uint8Array ? Array.from(b) : b;
              return __createPromise(__fs_write_bytes(p, JSON.stringify(a)));
            }

            export function readBytes(p) {
              return __createPromise(__fs_read_bytes(p)).then(function(a) {
                return new Uint8Array(a);
              });
            }

            export function append(p, c) {
              return __createPromise(__fs_append(p, c));
            }

            export function exists(p) {
              return __createPromise(__fs_exists(p));
            }

            export function remove(p) {
              return __createPromise(__fs_delete(p));
            }

            export function mkdir(p) {
              return __createPromise(__fs_mkdir(p));
            }

            export function readdir(p) {
              return __createPromise(__fs_readdir(p));
            }

            export function stat(p) {
              return __createPromise(__fs_stat(p));
            }
          JS
        end
      end
    end
  end
end
